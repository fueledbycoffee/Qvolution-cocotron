/* V2 uses the source-declared bitmap initializer and reports existing skip-alpha metadata defects. Original v1 input/binary remain preserved. No HLG/color policy. */
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Onyx2D/O2BitmapContext.h>
#import <Onyx2D/O2DataProvider.h>
#import <Onyx2D/O2Image.h>
#import <Onyx2D/O2Surface.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
static unsigned failures;
#define CHECK(c,m) do { BOOL okay=(c); printf("%s %s\n",okay?"PASS":"FAIL",m); failures+=!okay; } while(0)
#define REQUIRE(c,m) do { if(!(c)) { printf("FAIL %s\n",m); return 1; } } while(0)
static const uint32_t bits[8]={0xbf000000,0x3fc00000,0x3e800000,0x3e800000, 0x80000000,0x3f000000,0x3f800000,0};
static void pack(unsigned char *p,uint32_t value,BOOL big) { for(unsigned i=0;i<4;i++) p[i]=(unsigned char)(value>>(8*(big?3-i:i))); }
static uint32_t floatBits(float value) { uint32_t result; memcpy(&result,&value,4); return result; }
static float fromBits(uint32_t value) { float result; memcpy(&result,&value,4); return result; }
static CGBitmapInfo info(BOOL big) { return kCGBitmapFloatComponents|kCGImageAlphaPremultipliedLast|(big?kCGBitmapByteOrder32Big:kCGBitmapByteOrder32Little); }
static BOOL backed(CGContextRef context) { return context && [(O2BitmapContext *)context surface]!=nil; }
static int storage(CGColorSpaceRef space,BOOL big,BOOL internal) {
    unsigned char buffer[16+3*96+16], saved[sizeof(buffer)]; memset(buffer,0xa7,sizeof(buffer));
    for(unsigned y=0;y<3;y++) for(unsigned x=0;x<5;x++) for(unsigned c=0;c<4;c++) pack(buffer+16+y*96+x*16+c*4,bits[(x%2)*4+c],big);
    memcpy(saved,buffer,sizeof(buffer));
    CGContextRef context=CGBitmapContextCreate(internal?NULL:buffer+16,5,3,32,internal?0:96,space,info(big));
    REQUIRE(context,"float constructor returns context");
    REQUIRE(backed(context),"non-NULL float context has a real backing surface");
    CHECK(CGBitmapContextGetWidth(context)==5&&CGBitmapContextGetHeight(context)==3,"real dimensions");
    CHECK(CGBitmapContextGetBitsPerComponent(context)==32&&CGBitmapContextGetBitsPerPixel(context)==128,"actual RGBA128 packing");
    CHECK(CGBitmapContextGetBytesPerRow(context)==(internal?80:96),"derived or padded row preserved");
    REQUIRE(CGBitmapContextGetData(context),"real writable storage");
    if(internal) { const unsigned char *p=CGBitmapContextGetData(context); BOOL zero=YES;for(unsigned i=0;i<80*3;i++) zero &= p[i]==0; CHECK(zero,"internal storage starts zero"); }
    else CHECK(CGBitmapContextGetData(context)==buffer+16&&!memcmp(saved,buffer,sizeof(buffer)),"borrowed bytes and guards unchanged on construction");
    CGImageRef image=CGBitmapContextCreateImage(context); REQUIRE(image,"snapshot exists");
    CHECK(CGImageGetBitsPerPixel(image)==128&&CGImageGetBitsPerComponent(image)==32&&CGImageGetBytesPerRow(image)==(internal?80:96),"snapshot packing preserved");
    CGDataProviderRef provider=CGImageGetDataProvider(image); CFDataRef copy=CGDataProviderCopyData(provider); REQUIRE(copy,"snapshot owns readable data");
    CHECK(CFDataGetLength(copy)==(internal?80:96)*3,"snapshot capacity matches validated row");
    if(!internal) CHECK(!memcmp(CFDataGetBytePtr(copy),buffer+16,96*3),"snapshot exact samples and padding");
    CFRelease(copy); CGContextRelease(context);
    copy=CGDataProviderCopyData(provider); CHECK(copy&&CFDataGetLength(copy)==(internal?80:96)*3,"snapshot provider survives context release");
    if(copy) CFRelease(copy); CGImageRelease(image);
    return failures?1:0;
}
static int imageSpan(CGColorSpaceRef space,BOOL big) {
    unsigned char buffer[16+3*96+16], saved[sizeof(buffer)]; memset(buffer,0xa7,sizeof(buffer));
    for(unsigned y=0;y<3;y++) for(unsigned x=0;x<5;x++) for(unsigned c=0;c<4;c++) pack(buffer+16+y*96+x*16+c*4,bits[(x%2)*4+c],big);
    memcpy(saved,buffer,sizeof(buffer));
    CGDataProviderRef provider=CGDataProviderCreateWithData(NULL,buffer+16,96*3,NULL); REQUIRE(provider,"raw provider");
    CGImageRef image=CGImageCreate(5,3,32,128,96,space,info(big),provider,NULL,false,kCGRenderingIntentDefault); REQUIRE(image,"supported explicit float image");
    struct { uint32_t before; O2argb32f samples[2]; uint32_t after; } read={0xaabbccdd,{{0}},0xddccbbaa};
    O2Image_read_argb32f((O2Image *)image,1,1,read.samples,2);
    for(unsigned i=0;i<2;i++) {
        const uint32_t *e=bits+((i+1)%2)*4;
        CHECK(floatBits(read.samples[i].r)==e[0]&&floatBits(read.samples[i].g)==e[1]&&floatBits(read.samples[i].b)==e[2]&&floatBits(read.samples[i].a)==e[3],"actual partial float reader preserves exact RGBA bits");
    }
    CHECK(read.before==0xaabbccdd&&read.after==0xddccbbaa&&!memcmp(saved,buffer,sizeof(buffer)),"reader padding/input/output guards preserved");
    CGImageRelease(image); CGDataProviderRelease(provider);
    O2Surface *surface=[[O2Surface alloc] initWithBytes:buffer+16 width:5 height:3 bitsPerComponent:32 bytesPerRow:96 colorSpace:(O2ColorSpaceRef)space bitmapInfo:info(big)]; REQUIRE(surface,"real float writer surface");
    O2argb32f write[2]; for(unsigned i=0;i<2;i++) { write[i].r=fromBits(bits[i*4]);write[i].g=fromBits(bits[i*4+1]);write[i].b=fromBits(bits[i*4+2]);write[i].a=fromBits(bits[i*4+3]); }
    O2SurfaceWriteSpan_largb32f_PRE(surface,1,1,write,2);
    for(unsigned i=0;i<2;i++) for(unsigned c=0;c<4;c++) pack(saved+16+96+(i+1)*16+c*4,bits[i*4+c],big);
    CHECK(!memcmp(saved,buffer,sizeof(buffer)),"actual partial writer changes only requested bytes and preserves padding/guards");
    [surface release]; return failures?1:0;
}
static int reject(CGColorSpaceRef space) {
    unsigned char pixels[128]; memset(pixels,0x5a,sizeof(pixels));
    struct { size_t width,height,bpc,row; CGBitmapInfo flags; } cases[]={
        {2,2,32,31,info(NO)}, {SIZE_MAX/16+1,1,32,0,info(NO)}, {2,SIZE_MAX/32+1,32,32,info(NO)},
        {(size_t)INT_MAX/16+1,1,32,0,info(NO)}, {2,(size_t)INT_MAX+1,32,32,info(NO)}, {1,(size_t)INT_MAX/16+1,32,16,info(NO)},
        {2,2,32,32,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Little},
        {2,2,32,32,kCGBitmapFloatComponents|kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little},
        {2,2,32,32,kCGBitmapFloatComponents|kCGImageAlphaLast|kCGBitmapByteOrder32Little},
        {2,2,32,32,kCGBitmapFloatComponents|kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder16Little},
        {2,2,16,16,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder16Little}
    };
    for(unsigned i=0;i<sizeof(cases)/sizeof(cases[0]);i++) {
        CGContextRef context=CGBitmapContextCreate(pixels,cases[i].width,cases[i].height,cases[i].bpc,cases[i].row,space,cases[i].flags);
        printf("CASE %u\n",i); CHECK(context==NULL,"unsupported packing/row/overflow rejects construction"); if(context) CGContextRelease(context);
    }
    for(unsigned i=0;i<sizeof(pixels);i++) CHECK(pixels[i]==0x5a,"rejection leaves external bytes untouched");
    /* Image dispatch must use the same float format decision. */
    CGDataProviderRef provider=CGDataProviderCreateWithData(NULL,pixels,sizeof(pixels),NULL);
    const CGBitmapInfo bad[]={kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Little,kCGBitmapFloatComponents|kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little,kCGBitmapFloatComponents|kCGImageAlphaLast|kCGBitmapByteOrder32Little,kCGBitmapFloatComponents|kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder16Little};
    for(unsigned i=0;i<4;i++) { CGImageRef image=CGImageCreate(2,2,32,128,32,space,bad[i],provider,NULL,false,kCGRenderingIntentDefault);CHECK(!image,"image and surface reject same unsupported float packing");if(image)CGImageRelease(image); }
    CGDataProviderRelease(provider); return failures?1:0;
}
static unsigned destroyed;
@interface ForcedNilSurface : O2Surface @end
@implementation ForcedNilSurface
- initWithBytes:(void *)bytes width:(size_t)w height:(size_t)h bitsPerComponent:(size_t)bpc bytesPerRow:(size_t)row colorSpace:(O2ColorSpaceRef)space bitmapInfo:(O2BitmapInfo)flags {
    self=[super initWithBytes:bytes width:w height:h bitsPerComponent:bpc bytesPerRow:row colorSpace:space bitmapInfo:flags]; [self release]; return nil;
}
- (void)dealloc { destroyed++; [super dealloc]; }
@end
@interface ForcedNilContext : O2BitmapContext @end
@implementation ForcedNilContext
- (Class)surfaceClass { return [ForcedNilSurface class]; }
@end
static int nilSurface(CGColorSpaceRef space) {
    unsigned char pixels[16]={0};
    id context=[[ForcedNilContext alloc]initWithBytes:pixels width:2 height:2 bitsPerComponent:8 bytesPerRow:8 colorSpace:(O2ColorSpaceRef)space bitmapInfo:kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big releaseCallback:NULL releaseInfo:NULL];
    CHECK(context==nil&&destroyed==1,"nil surface propagates actual constructor failure and balances lifetime"); [context release]; return failures?1:0;
}
static int eightBit(CGColorSpaceRef space) {
    unsigned char pixels[32],saved[32]; memset(pixels,0x63,sizeof(pixels));memcpy(saved,pixels,sizeof(pixels));
    const CGBitmapInfo flags[]={kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big,kCGImageAlphaNoneSkipFirst|kCGBitmapByteOrder32Little,kCGImageAlphaNoneSkipLast|kCGBitmapByteOrder32Big};
    for(unsigned i=0;i<4;i++) { CGContextRef context=CGBitmapContextCreate(pixels,2,2,8,16,space,flags[i]);REQUIRE(backed(context),"existing 8bit context remains backed");printf("EIGHT_BIT layout=%u actualBpp=%zu actualRow=%zu bytesUnchanged=%d\n",i,CGBitmapContextGetBitsPerPixel(context),CGBitmapContextGetBytesPerRow(context),!memcmp(saved,pixels,sizeof(pixels)));CHECK(CGBitmapContextGetBitsPerPixel(context)==32&&CGBitmapContextGetBytesPerRow(context)==16&&!memcmp(saved,pixels,sizeof(pixels)),"existing 8bit packing/storage unchanged");CGContextRelease(context); }
    return failures?1:0;
}
int main(int argc,char **argv) { @autoreleasepool {
    setbuf(stdout,NULL);REQUIRE(argc==2,"mode external-le|external-be|internal|span-le|span-be|reject|nil-surface|eight-bit");
    CGColorSpaceRef space=CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearSRGB);REQUIRE(space,"real named SDR RGB space");
    int result=!strcmp(argv[1],"external-le")?storage(space,NO,NO):!strcmp(argv[1],"external-be")?storage(space,YES,NO):!strcmp(argv[1],"internal")?storage(space,NO,YES):!strcmp(argv[1],"span-le")?imageSpan(space,NO):!strcmp(argv[1],"span-be")?imageSpan(space,YES):!strcmp(argv[1],"reject")?reject(space):!strcmp(argv[1],"nil-surface")?nilSurface(space):!strcmp(argv[1],"eight-bit")?eightBit(space):2;
    CGColorSpaceRelease(space);return result;
} }
