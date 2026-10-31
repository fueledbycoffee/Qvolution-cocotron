// Original diagnostic implementation; uses repository O2 image/PNG interfaces.
#import "WaylandClientCapture.h"
#import <Onyx2D/O2Surface.h>
#import <Onyx2D/O2ColorSpace.h>
#import <Onyx2D/O2Encoder_PNG.h>
#import <Onyx2D/O2DataConsumer.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

@implementation WaylandClientCapture
- (void)reportFailure:(unsigned)code {
    if(_error)return;
    _error=code;
    NSLog(@"AppKit CPU client capture diagnostic failed (code=%u)",code);
}
- initWithDirectory:(NSString *)directory {
    if (!(self=[super init])) return nil;
    _directory=-1;
    // An explicit existing absolute run directory is required. Never create it,
    // follow a final-component symlink, use a title, or log its path/content.
    if (![directory isAbsolutePath]) { [self reportFailure:1]; [self release]; return nil; }
    // A trailing slash would turn the symlink into an intermediate component
    // before open's O_NOFOLLOW check. Keep that check on the actual last name.
    while([directory length]>1 && [directory hasSuffix:@"/"])
        directory=[directory substringToIndex:[directory length]-1];
    _directory=open([directory fileSystemRepresentation],O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    if (_directory<0) { [self reportFailure:2]; [self release]; return nil; }
    static unsigned long long serial;
    _window=__sync_add_and_fetch(&serial,1);
    return self;
}
- (void)dealloc { if(_directory>=0)close(_directory); [super dealloc]; }
- (unsigned)writtenCount { return _written; }
- (unsigned)errorCode { return _error; }
- (void)captureSurface:(O2Surface *)surface opaque:(BOOL)opaque scale120:(unsigned)scale {
    if (_directory<0 || _attempts>=8) return;
    unsigned sequence=++_attempts;
    O2Surface *copy=nil; O2PNGEncoderRef encoder=NULL; O2DataConsumerRef consumer=nil;
    int fd=-1; char name[160]={0}; BOOL complete=NO, created=NO;
    @try {
        if(!surface){[self reportFailure:3];return;}
        size_t w=O2SurfaceGetWidth(surface),h=O2SurfaceGetHeight(surface),stride=O2SurfaceGetBytesPerRow(surface);
        const unsigned char *source=O2SurfaceGetPixelBytes(surface);
        // Bound synchronous diagnostic work and all products to 64MiB/frame.
        if(!source || !w || !h || w>16384 || h>16384 || w>SIZE_MAX/4 || stride<w*4 ||
           h>SIZE_MAX/stride || h>64*1024*1024/(w*4)) { [self reportFailure:3]; return; }
        O2ColorSpaceRef cs=O2ColorSpaceCreateDeviceRGB();
        copy=[[O2Surface alloc] initWithBytes:NULL width:w height:h bitsPerComponent:8 bytesPerRow:w*4
            colorSpace:cs bitmapInfo:kO2ImageAlphaLast|kO2BitmapByteOrder32Big];
        O2ColorSpaceRelease(cs);
        if(!copy){[self reportFailure:3];return;}
        unsigned char *out=O2SurfaceGetPixelBytes(copy); if(!out){[self reportFailure:3];return;}
        // PNG stores straight alpha; inverse premultiplication retains the source
        // alpha and roundtrips valid 8-bit premultiplied colors with correct decoding.
        for(size_t y=0;y<h;y++)for(size_t x=0;x<w;x++) {
            const unsigned char *p=source+y*stride+x*4; unsigned char *q=out+(y*w+x)*4;
            unsigned a=opaque?255:p[3]; q[3]=a;
            for(int c=0;c<3;c++) q[2-c]=opaque?p[c]:(a?MIN(255,(p[c]*255+a/2)/a):0);
        }
        NSMutableData *data=[NSMutableData data];
        consumer=O2DataConsumerCreateWithCFData((CFMutableDataRef)data);
        encoder=O2PNGEncoderCreate(consumer);
        O2PNGEncoderWriteImage(encoder,copy,NULL);
        // Existing encoder has no status return: require a complete PNG trailer.
        static const unsigned char signature[]={137,80,78,71,13,10,26,10};
        static const unsigned char end[]={0,0,0,0,73,69,78,68,174,66,96,130};
        const unsigned char *bytes=[data bytes];size_t n=[data length];
        if(n<20 || memcmp(bytes,signature,8) || memcmp(bytes+n-12,end,12)){[self reportFailure:4];return;}
        snprintf(name,sizeof(name),"cpu-client-%ld-w%llu-f%u-%zux%zu-s%u.png",(long)getpid(),_window,sequence,w,h,scale);
        fd=openat(_directory,name,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
        if(fd<0){[self reportFailure:5];return;}
        created=YES;
        size_t position=0;
        while(position<n) {
            ssize_t count=write(fd,bytes+position,n-position);
            if(count<0&&errno==EINTR)continue;
            if(count<=0){[self reportFailure:6];return;}
            position+=(size_t)count;
        }
        if(close(fd)!=0){fd=-1;[self reportFailure:7];return;}fd=-1;complete=YES;++_written;
    } @catch(NSException *exception) {
        // Diagnostics must never disrupt rendering or disclose client contents.
        [self reportFailure:8];
    } @finally {
        if(fd>=0)close(fd);
        if(created&&!complete)unlinkat(_directory,name,0);
        if(encoder)O2PNGEncoderDealloc(encoder);
        if(consumer)O2DataConsumerRelease(consumer);
        [copy release];
    }
}
@end
