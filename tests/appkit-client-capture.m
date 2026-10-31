// Original own-source diagnostic roundtrip; no display/input APIs.
#import <Foundation/Foundation.h>
#import "WaylandClientCapture.h"
#import <Onyx2D/O2Surface.h>
#import <Onyx2D/O2ColorSpace.h>
#import <Onyx2D/O2ImageSource.h>
#include <unistd.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#define CHECK(x) do{if(!(x)){fprintf(stderr,"FAIL line%d: %s\n",__LINE__,#x);exit(1);}}while(0)
int main(int argc,char **argv) { @autoreleasepool {
    CHECK(argc==2); NSString *root=[NSString stringWithUTF8String:argv[1]];
    CHECK([root isAbsolutePath]);
    NSFileManager *fm=[NSFileManager defaultManager];
    NSString *dir=[root stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
    CHECK([fm createDirectoryAtPath:dir withIntermediateDirectories:NO attributes:nil error:NULL]);
    CHECK([[WaylandClientCapture alloc] initWithDirectory:nil]==nil);
    CHECK([[WaylandClientCapture alloc] initWithDirectory:@"relative"]==nil);
    CHECK([[WaylandClientCapture alloc] initWithDirectory:[dir stringByAppendingPathComponent:@"absent"]]==nil);
    NSString *link=[dir stringByAppendingString:@"-link"];
    CHECK(symlink([dir fileSystemRepresentation],[link fileSystemRepresentation])==0);
    CHECK([[WaylandClientCapture alloc] initWithDirectory:link]==nil);
    CHECK([[WaylandClientCapture alloc] initWithDirectory:[link stringByAppendingString:@"/"]]==nil);
    CHECK(unlink([link fileSystemRepresentation])==0);
    O2ColorSpaceRef cs=O2ColorSpaceCreateDeviceRGB();
    // Padded asymmetric rows, includes transparent and half-alpha premultiplied colors.
    unsigned char pixels[]={0,0,255,255, 32,64,96,128, 99,98,97,96,
                            255,0,0,255, 0,0,0,0, 95,94,93,92};
    unsigned char original[sizeof(pixels)];memcpy(original,pixels,sizeof(pixels));
    O2Surface *surface=[[O2Surface alloc] initWithBytes:pixels width:2 height:2 bitsPerComponent:8
        bytesPerRow:12 colorSpace:cs bitmapInfo:kO2ImageAlphaPremultipliedFirst|kO2BitmapByteOrder32Little];
    O2ColorSpaceRelease(cs);CHECK(surface!=nil);
    WaylandClientCapture *capture=[[WaylandClientCapture alloc] initWithDirectory:[dir stringByAppendingString:@"/"]];CHECK(capture!=nil);
    for(int i=0;i<12;i++)[capture captureSurface:surface opaque:NO scale120:150];
    CHECK([capture writtenCount]==8);CHECK(memcmp(original,pixels,sizeof(pixels))==0);
    NSArray *files=[fm contentsOfDirectoryAtPath:dir error:NULL];CHECK([files count]==8);
    for(NSString *file in files) {
        CHECK([file hasPrefix:@"cpu-client-"]&&[file hasSuffix:@"-2x2-s150.png"]);
        NSString *path=[dir stringByAppendingPathComponent:file];struct stat st;CHECK(stat([path fileSystemRepresentation],&st)==0);
        CHECK((st.st_mode&0777)==0600);
        O2ImageSource *source=[O2ImageSource newImageSourceWithData:(CFDataRef)[NSData dataWithContentsOfFile:path] options:NULL];
        CHECK(source!=nil);O2Image *image=[source createImageAtIndex:0 options:NULL];CHECK(image!=nil);
        CHECK(O2ImageGetWidth(image)==2&&O2ImageGetHeight(image)==2);
        // Check decoder dimensions and alpha only: its older color clamp behavior
        // is being fixed independently. Host PNG checker is the color oracle.
        O2argb8u scratch[2];
        for(int y=0;y<2;y++) {
            O2argb8u *row=O2Image_read_argb8u(image,0,y,scratch,2);if(!row)row=scratch;
            for(int x=0;x<2;x++) { unsigned char *p=pixels+y*12+x*4;
                CHECK(row[x].a==p[3]);
            }
        }
        [image release];[source release];
    }
    // A second window has a separate budget and unique names, also opaque alpha.
    WaylandClientCapture *opaque=[[WaylandClientCapture alloc] initWithDirectory:dir];
    [opaque captureSurface:surface opaque:YES scale120:120];CHECK([opaque writtenCount]==1);
    CHECK([[fm contentsOfDirectoryAtPath:dir error:NULL] count]==9);
    NSString *removed=[dir stringByAppendingPathComponent:@"removed"];
    CHECK([fm createDirectoryAtPath:removed withIntermediateDirectories:NO attributes:nil error:NULL]);
    WaylandClientCapture *broken=[[WaylandClientCapture alloc] initWithDirectory:removed];CHECK(broken!=nil);
    CHECK([fm removeItemAtPath:removed error:NULL]);
    [broken captureSurface:surface opaque:NO scale120:120];CHECK([broken writtenCount]==0);CHECK([broken errorCode]==5);
    CHECK(memcmp(original,pixels,sizeof(pixels))==0);[broken release];
    NSString *nilInput=[dir stringByAppendingPathComponent:@"nil-input"];
    CHECK([fm createDirectoryAtPath:nilInput withIntermediateDirectories:NO attributes:nil error:NULL]);
    WaylandClientCapture *invalidSurface=[[WaylandClientCapture alloc] initWithDirectory:nilInput];CHECK(invalidSurface!=nil);
    [invalidSurface captureSurface:nil opaque:NO scale120:120];
    CHECK([invalidSurface writtenCount]==0&&[invalidSurface errorCode]==3);
    [invalidSurface release];CHECK([fm removeItemAtPath:nilInput error:NULL]);
    NSString *collisions=[dir stringByAppendingPathComponent:@"collisions"];
    CHECK([fm createDirectoryAtPath:collisions withIntermediateDirectories:NO attributes:nil error:NULL]);
    NSData *sentinel=[@"unchanged-original" dataUsingEncoding:NSUTF8StringEncoding];
    // Reserve a range of plausible serials, independently of the helper's current
    // counter. A collision must neither overwrite nor unlink an existing file.
    for(unsigned i=1;i<=32;i++) {
        NSString *name=[NSString stringWithFormat:@"cpu-client-%ld-w%u-f1-2x2-s150.png",(long)getpid(),i];
        CHECK([sentinel writeToFile:[collisions stringByAppendingPathComponent:name] atomically:NO]);
    }
    WaylandClientCapture *collision=[[WaylandClientCapture alloc] initWithDirectory:collisions];CHECK(collision!=nil);
    [collision captureSurface:surface opaque:NO scale120:150];CHECK([collision writtenCount]==0);CHECK([collision errorCode]==5);
    NSArray *reserved=[fm contentsOfDirectoryAtPath:collisions error:NULL];CHECK([reserved count]==32);
    for(NSString *name in reserved)CHECK([[NSData dataWithContentsOfFile:[collisions stringByAppendingPathComponent:name]] isEqual:sentinel]);
    [collision release];CHECK([fm removeItemAtPath:collisions error:NULL]);
    [opaque release];[capture release];[surface release];
    // Leave ONLY original synthetic PNGs for independent host pixel verification.
    puts("PASS: CPU client PNG dimensions, padded rows, decoder and source, alpha, scale name, budget, privacy mode, invalid paths and source immutability");
}return 0;}
