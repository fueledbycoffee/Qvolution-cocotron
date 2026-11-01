#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Onyx2D/O2Context.h>
#import <Onyx2D/O2GraphicsState.h>
#import <Onyx2D/O2ClipState.h>
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSArray *clipPhases(CGContextRef context) {
    return [O2GStateClipState(O2ContextCurrentGState((O2ContextRef)context)) clipPhases];
}

static void layers(CGContextRef context) {
    CGRect parent = CGRectMake(0, 0, 16, 16);
    CGContextClipToRect(context, parent);
    NSArray *initial = [clipPhases(context) copy];
    CHECK(initial.count > 0);
    CGContextBeginTransparencyLayerWithRect(context, CGRectMake(0, 0, 8, 8), NULL);
    NSArray *outer = [clipPhases(context) copy];
    CHECK(outer.count == initial.count + 1);
    CGContextBeginTransparencyLayerWithRect(context, CGRectMake(0, 0, 4, 4), NULL);
    CGContextSetRGBFillColor(context, 1, 0, 0, 1);
    CGContextFillRect(context, CGRectMake(0, 0, 16, 16));
    CGContextEndTransparencyLayer(context);
    CHECK([clipPhases(context) isEqualToArray:outer]);
    CGContextEndTransparencyLayer(context);
    CHECK([clipPhases(context) isEqualToArray:initial]);
    [outer release];
    [initial release];
    CGContextSetRGBFillColor(context, 0, 1, 0, 1);
    CGContextFillRect(context, CGRectMake(12, 12, 2, 2));
}

int main(void) {
    @autoreleasepool {
        CFMutableDataRef data = CFDataCreateMutable(NULL, 0);
        CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData(data);
        CGRect media = CGRectMake(0, 0, 16, 16);
        CGContextRef pdf = CGPDFContextCreate(consumer, &media, NULL);
        CHECK(pdf != NULL);
        if (pdf) {
            CGPDFContextBeginPage(pdf, NULL);
            layers(pdf);
            CGPDFContextEndPage(pdf);
            CGPDFContextClose(pdf);
            CGContextRelease(pdf);
            CHECK(CFDataGetLength(data) > 0);
        }
        CGDataConsumerRelease(consumer);
        CFRelease(data);
        unsigned char pixels[16 * 16 * 4] = {0};
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGContextRef bitmap = CGBitmapContextCreate(pixels, 16, 16, 8, 64, space,
            kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
        CHECK(bitmap != NULL);
        if (bitmap) {
            layers(bitmap);
            // The successful nested layers must composite red, and drawing on
            // the parent after end must paint green outside both layer bounds.
            int red = 0, green = 0;
            for (int i = 0; i < 256; i++) {
                red += pixels[4*i] > 200 && pixels[4*i+1] < 20 && pixels[4*i+3] > 200;
                green += pixels[4*i] < 20 && pixels[4*i+1] > 200 && pixels[4*i+3] > 200;
            }
            CHECK(red == 16);
            CHECK(green == 4);
            CGContextRelease(bitmap);
        }
        CGColorSpaceRelease(space);
    }
    printf("RESULT layer-clip failures=%d\n", failures);
    return failures != 0;
}
