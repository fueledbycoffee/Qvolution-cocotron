#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Onyx2D/O2PDFContext.h>
#import <Onyx2D/O2PDFStream.h>
#import <Onyx2D/O2Paint_ramp.h>
#import <Onyx2D/O2Shading.h>
#import <Onyx2D/O2Context_builtin.h>
#import <Onyx2D/O2GraphicsState.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#define CHECK(c) do { if (!(c)) { fprintf(stderr,"line %d: %s\n",__LINE__,#c); return 1; } } while(0)
#define REJECT(operation) do { BOOL rejected=NO; @try { operation; } @catch(NSException *e) { rejected=[[e name] isEqual:NSInvalidArgumentException]; } CHECK(rejected); } while(0)
@interface TransactionPDF : O2PDFContext
- (NSData *)pendingBytes;
@end
@implementation TransactionPDF
- (NSData *)pendingBytes { return [[[[_contentStreamStack lastObject] mutableData] copy] autorelease]; }
@end
static unsigned rampDeaths, liveSurfaces, liveContexts;
@interface RampLifetimeProbe : O2Paint_ramp @end
@implementation RampLifetimeProbe
- (void)dealloc { rampDeaths++; [super dealloc]; }
@end
@interface PatternSurfaceProbe : O2Surface { BOOL _counted; } @end
@implementation PatternSurfaceProbe
- initWithBytes:(void *)bytes width:(size_t)width height:(size_t)height bitsPerComponent:(size_t)bpc bytesPerRow:(size_t)row colorSpace:(O2ColorSpaceRef)space bitmapInfo:(O2BitmapInfo)info {
    if ((self=[super initWithBytes:bytes width:width height:height bitsPerComponent:bpc bytesPerRow:row colorSpace:space bitmapInfo:info])) { _counted=YES; liveSurfaces++; }
    return self;
}
- (void)dealloc { if (_counted) liveSurfaces--; [super dealloc]; }
@end
@interface PatternContextProbe : O2Context_builtin { BOOL _counted; }
- (NSUInteger)stateDepth;
- (NSUInteger)layerDepth;
- (id)currentStateIdentity;
- (void)replacePendingShadowWithColor:(O2ColorRef)color;
@end
@implementation PatternContextProbe
- (NSUInteger)stateDepth { return [_stateStack count]; }
- (NSUInteger)layerDepth { return [_layerStack count]; }
- (id)currentStateIdentity { return _currentState; }
/* Test-only repair of an explicit pending parent parameter after verifying the
 * failed end operation preserved both stacks. No production bypass is added. */
- (void)replacePendingShadowWithColor:(O2ColorRef)color {
    O2GState *parent=[_stateStack objectAtIndex:[_stateStack count]-2];
    [parent setShadowOffset:O2SizeMake(1,1) blur:2 color:color];
}
- (Class)surfaceClass { return [PatternSurfaceProbe class]; }
- initWithSurface:(O2Surface *)surface flipped:(BOOL)flipped {
    if ((self=[super initWithSurface:surface flipped:flipped])) { _counted=YES; liveContexts++; }
    return self;
}
- (void)dealloc { if (_counted) liveContexts--; [super dealloc]; }
@end
static void rejectPattern(void *info, CGContextRef context) {
    CGContextSetFillColorWithColor(context,(CGColorRef)info);
    CGContextFillRect(context,CGRectMake(0,0,4,4));
}
static void shadingValues(void *info,const CGFloat *input,CGFloat *out) { out[0]=out[1]=out[2]=input[0]; }
static BOOL nonzero(const unsigned char *p, size_t n) { for(size_t i=0;i<n;i++) if(p[i]) return YES; return NO; }
int main(void) { @autoreleasepool {
    const CFStringRef *symbol=dlsym(RTLD_DEFAULT,"kCGColorSpaceITUR_2100_HLG");
    if(!symbol) { puts("ABSENT_DATA_SYMBOL"); return 77; }
    CGColorSpaceRef hlg=CGColorSpaceCreateWithName(*symbol), sdr=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CHECK(hlg && sdr);
    CGFloat values[]={0.5,0.25,0.75,1};
    CGColorRef hdr=CGColorCreate(hlg,values), rgb=CGColorCreate(sdr,values);
    CHECK(hdr && rgb);
    unsigned char target[64*64*4]={0}, before[sizeof(target)];
    CGContextRef context=CGBitmapContextCreate(target,64,64,8,64*4,sdr,kCGImageAlphaPremultipliedLast);
    CHECK(context);
    CGContextTranslateCTM(context,3,4);
    CGContextSetFillColorWithColor(context,rgb); CGContextSetStrokeColorWithColor(context,hdr);
    CGContextAddRect(context,CGRectMake(4,4,20,20));
    CGPathRef path=CGContextCopyPath(context);
    memcpy(before,target,sizeof(target));
    REJECT(CGContextDrawPath(context,kCGPathFillStroke));
    CGPathRef after=CGContextCopyPath(context);
    CHECK(CGPathEqualToPath(path,after) && !memcmp(before,target,sizeof(target)));
    CGPathRelease(after); CGPathRelease(path);
    /* Unused HLG stroke must not reject a fill-only operation. */
    CGContextDrawPath(context,kCGPathFill);
    CHECK(nonzero(target,sizeof(target)) && CGContextIsPathEmpty(context));
    CGContextSetFillColorWithColor(context,hdr); CGContextSetStrokeColorWithColor(context,rgb);
    memset(target,0,sizeof(target));
    CGContextAddRect(context,CGRectMake(4,4,20,20));
    CGContextDrawPath(context,kCGPathStroke);
    CHECK(nonzero(target,sizeof(target)));
    /* Normal image paint does not consume the current fill color. */
    unsigned char pixels[]={20,100,200,255,20,100,200,255,20,100,200,255,20,100,200,255};
    CGDataProviderRef provider=CGDataProviderCreateWithData(NULL,pixels,sizeof(pixels),NULL);
    CGImageRef image=CGImageCreate(2,2,8,32,8,sdr,kCGImageAlphaPremultipliedLast,provider,NULL,false,kCGRenderingIntentDefault);
    CHECK(image); memset(target,0,sizeof(target));
    CGContextDrawImage(context,CGRectMake(2,2,8,8),image);
    CHECK(nonzero(target,sizeof(target)));
    /* Reject before advances allocation and surface lock; retry must complete. */
    CGFontRef font=CGFontCreateWithFontName(CFSTR("DejaVuSans")); CHECK(font);
    CGContextSetFont(context,font); CGContextSetFontSize(context,14); CGContextSetTextPosition(context,4,24);
    CGGlyph glyph=CGFontGetGlyphWithGlyphName(font,CFSTR("A")); CHECK(glyph);
    memcpy(before,target,sizeof(target)); CGAffineTransform textMatrix=CGContextGetTextMatrix(context);
    REJECT(CGContextShowGlyphs(context,&glyph,1));
    CHECK(!memcmp(before,target,sizeof(target)) && CGAffineTransformEqualToTransform(textMatrix,CGContextGetTextMatrix(context)));
    CGContextSetFillColorWithColor(context,rgb);
    CGContextShowGlyphs(context,&glyph,1); /* A leaked surface lock hangs here. */
    CHECK(memcmp(before,target,sizeof(target)));
    CGFunctionCallbacks functionCallbacks={0,shadingValues,NULL};
    CGFloat domain[]={0,1}, range[]={0,1,0,1,0,1};
    CGFunctionRef function=CGFunctionCreate(NULL,1,domain,3,range,&functionCallbacks); CHECK(function);
    CGShadingRef shading=CGShadingCreateAxial(hlg,CGPointMake(0,0),CGPointMake(32,32),function,true,true); CHECK(shading);
    memcpy(before,target,sizeof(target));
    REJECT(CGContextDrawShading(context,shading));
    CHECK(!memcmp(before,target,sizeof(target)));
    REJECT([[RampLifetimeProbe alloc] initWithShading:(O2Shading *)shading deviceTransform:O2AffineTransformIdentity numberOfSamples:4]);
    CHECK(rampDeaths==1);
    PatternContextProbe *patternContext=[[PatternContextProbe alloc] initWithBytes:target width:64 height:64 bitsPerComponent:8 bytesPerRow:64*4 colorSpace:(O2ColorSpaceRef)sdr bitmapInfo:kCGImageAlphaPremultipliedLast releaseCallback:NULL releaseInfo:NULL];
    CHECK(patternContext && liveContexts==1 && liveSurfaces==1);
    CGPatternCallbacks patternCallbacks={0,rejectPattern,NULL};
    CGPatternRef pattern=CGPatternCreate((void *)hdr,CGRectMake(0,0,4,4),CGAffineTransformIdentity,4,4,kCGPatternTilingConstantSpacing,true,&patternCallbacks); CHECK(pattern);
    CGColorSpaceRef patternSpace=CGColorSpaceCreatePattern(NULL); CGFloat alpha=1;
    CGColorRef patternColor=CGColorCreateWithPattern(patternSpace,pattern,&alpha); CHECK(patternColor);
    CGContextRef patternCG=(CGContextRef)patternContext;
    CGContextSetFillColorWithColor(patternCG,patternColor); CGContextAddRect(patternCG,CGRectMake(1,1,20,20));
    path=CGContextCopyPath(patternCG); memcpy(before,target,sizeof(target));
    REJECT(CGContextDrawPath(patternCG,kCGPathFill));
    after=CGContextCopyPath(patternCG);
    CHECK(CGPathEqualToPath(path,after) && !memcmp(before,target,sizeof(target)) && liveContexts==1 && liveSurfaces==1);
    CGPathRelease(path); CGPathRelease(after);
    CGContextSetFillColorWithColor(patternCG,rgb); CGContextDrawPath(patternCG,kCGPathFill);
    CGContextSetShadowWithColor(patternCG,CGSizeMake(1,1),2,hdr);
    CGContextBeginTransparencyLayer(patternCG,NULL);
    CGContextSetFillColorWithColor(patternCG,rgb);
    CGContextFillRect(patternCG,CGRectMake(2,2,8,8));
    CGContextAddRect(patternCG,CGRectMake(3,3,10,10));
    NSUInteger stateDepth=[patternContext stateDepth], layerDepth=[patternContext layerDepth];
    id stateIdentity=[patternContext currentStateIdentity];
    unsigned shadowContexts=liveContexts, shadowSurfaces=liveSurfaces;
    CGAffineTransform shadowCTM=CGContextGetCTM(patternCG);
    path=CGContextCopyPath(patternCG); memcpy(before,target,sizeof(target));
    REJECT(CGContextEndTransparencyLayer(patternCG));
    after=CGContextCopyPath(patternCG);
    CHECK([patternContext stateDepth]==stateDepth && [patternContext layerDepth]==layerDepth &&
          [patternContext currentStateIdentity]==stateIdentity && liveContexts==shadowContexts && liveSurfaces==shadowSurfaces &&
          CGAffineTransformEqualToTransform(shadowCTM,CGContextGetCTM(patternCG)) &&
          CGPathEqualToPath(path,after) && !memcmp(before,target,sizeof(target)));
    CGPathRelease(path); CGPathRelease(after);
    [patternContext replacePendingShadowWithColor:(O2ColorRef)rgb];
    CGContextEndTransparencyLayer(patternCG);
    CHECK([patternContext stateDepth]==stateDepth-1 && [patternContext layerDepth]==layerDepth-1 && liveContexts==1 && liveSurfaces==1);
    CGContextSetShadowWithColor(patternCG,CGSizeMake(0,0),0,NULL);
    CGContextSetFillColorWithColor(patternCG,rgb);
    memset(target,0,sizeof(target));
    CGContextFillRect(patternCG,CGRectMake(2,2,8,8));
    CHECK(nonzero(target,sizeof(target)));
    [patternContext release]; CHECK(liveContexts==0 && liveSurfaces==0);
    CGColorRelease(patternColor); CGColorSpaceRelease(patternSpace); CGPatternRelease(pattern);
    NSMutableData *pdfData=[NSMutableData data];
    CGDataConsumerRef consumer=CGDataConsumerCreateWithCFData((CFMutableDataRef)pdfData); CHECK(consumer);
    CGRect box=CGRectMake(0,0,64,64);
    TransactionPDF *pdf=[[TransactionPDF alloc] initWithConsumer:(O2DataConsumer *)consumer mediaBox:&box auxiliaryInfo:nil]; CHECK(pdf);
    [pdf beginPage:&box]; CGContextRef pdfContext=(CGContextRef)pdf;
    CGContextSetFillColorWithColor(pdfContext,rgb); CGContextSetStrokeColorWithColor(pdfContext,hdr);
    CGContextAddRect(pdfContext,CGRectMake(4,4,20,20));
    NSData *pending=[[pdf pendingBytes] copy], *written=[pdfData copy]; NSUInteger length=[pdf length];
    path=CGContextCopyPath(pdfContext);
    REJECT(CGContextDrawPath(pdfContext,kCGPathFillStroke));
    after=CGContextCopyPath(pdfContext);
    CHECK(CGPathEqualToPath(path,after) && [pending isEqual:[pdf pendingBytes]] && [written isEqual:pdfData] && length==[pdf length]);
    CGPathRelease(path); CGPathRelease(after); [pending release]; [written release];
    CGContextDrawPath(pdfContext,kCGPathFill); /* HLG stroke unused. */
    CGContextSetFillColorWithColor(pdfContext,hdr); CGContextSetStrokeColorWithColor(pdfContext,rgb);
    CGContextAddRect(pdfContext,CGRectMake(4,4,20,20));
    pending=[[pdf pendingBytes]copy]; written=[pdfData copy]; length=[pdf length];
    REJECT(CGContextDrawPath(pdfContext,kCGPathFillStroke));
    CHECK([pending isEqual:[pdf pendingBytes]] && [written isEqual:pdfData] && length==[pdf length]);
    [pending release]; [written release];
    CGContextDrawPath(pdfContext,kCGPathStroke); /* HLG fill unused. */
    CGContextDrawImage(pdfContext,CGRectMake(0,0,8,8),image); /* HLG fill unused for RGB image. */
    pending=[[pdf pendingBytes]copy]; written=[pdfData copy]; length=[pdf length];
    REJECT(CGContextDrawShading(pdfContext,shading));
    CHECK([pending isEqual:[pdf pendingBytes]] && [written isEqual:pdfData] && length==[pdf length]);
    [pending release]; [written release];
    CGShadingRelease(shading); CGFunctionRelease(function);
    [pdf endPage]; [pdf close]; [pdf release]; CGDataConsumerRelease(consumer);
    CGFontRelease(font); CGImageRelease(image); CGDataProviderRelease(provider); CGContextRelease(context);
    CGColorRelease(hdr); CGColorRelease(rgb); CGColorSpaceRelease(hlg); CGColorSpaceRelease(sdr);
    puts("HLG_REJECTION_TRANSACTION_PASS_NO_RENDER_SUPPORT"); return 0;
} }
