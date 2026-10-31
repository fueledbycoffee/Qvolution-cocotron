#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "failed line %d: %s\n", __LINE__, #c); return 1; } } while (0)
int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    const CFStringRef *symbol = dlsym(RTLD_DEFAULT, "kCGColorSpaceITUR_2100_HLG");
    if (!symbol) { puts("ABSENT_DATA_SYMBOL"); [pool drain]; return 77; }
    CGColorSpaceRef hlg = CGColorSpaceCreateWithName(*symbol);
    CHECK(hlg);
    unsigned char pixels[16] = {128,64,192,255,128,64,192,255,128,64,192,255,128,64,192,255};
    CHECK(!CGBitmapContextCreate(pixels, 2, 2, 8, 8, hlg, kCGImageAlphaPremultipliedLast));
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, pixels, sizeof(pixels), NULL);
    CHECK(provider);
    CHECK(!CGImageCreate(2, 2, 8, 32, 8, hlg, kCGImageAlphaPremultipliedLast, provider, NULL, false, kCGRenderingIntentDefault));
    CGFloat colors[] = {0.5,0.25,0.75,1, 1,1,1,1};
    CHECK(!CGGradientCreateWithColorComponents(hlg, colors, NULL, 2));
    CGColorSpaceRef sdr = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    unsigned char target[16]; memset(target, 0, sizeof(target));
    CGContextRef context = CGBitmapContextCreate(target, 2, 2, 8, 8, sdr, kCGImageAlphaPremultipliedLast);
    CHECK(context);
    CGColorRef color = CGColorCreate(hlg, colors);
    CHECK(color);
    CGContextSetFillColorWithColor(context, color);
    BOOL rejected = NO;
    @try { CGContextFillRect(context, CGRectMake(0,0,2,2)); }
    @catch (NSException *exception) { rejected = [[exception name] isEqual:NSInvalidArgumentException]; }
    CHECK(rejected);
    for (int i = 0; i < sizeof(target); i++) CHECK(target[i] == 0);
    CGColorRelease(color); CGContextRelease(context); CGColorSpaceRelease(sdr);
    CGDataProviderRelease(provider); CGColorSpaceRelease(hlg); [pool drain];
    puts("HLG_RENDER_EXPLICIT_LIMITATION_PASS_NOT_CONVERSION");
    return 0;
}
