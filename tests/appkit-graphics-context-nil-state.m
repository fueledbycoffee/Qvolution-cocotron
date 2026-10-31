#import <AppKit/AppKit.h>
#include <stdio.h>
#define CHECK(c, message) do { if (!(c)) { fprintf(stderr,"FAIL: %s\n",message); return 1; } } while (0)
int main(void){
    NSAutoreleasePool *pool=[NSAutoreleasePool new];unsigned char aBytes[8*8*4]={0},bBytes[8*8*4]={0};
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef a=CGBitmapContextCreate(aBytes,8,8,8,32,space,kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little);
    CGContextRef b=CGBitmapContextCreate(bBytes,8,8,8,32,space,kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little);CGColorSpaceRelease(space);
    CHECK(a&&b,"own bitmap contexts create");
    NSGraphicsContext *first=[NSGraphicsContext graphicsContextWithGraphicsPort:a flipped:NO],*second=[NSGraphicsContext graphicsContextWithGraphicsPort:b flipped:NO];
    [NSGraphicsContext setCurrentContext:nil];[NSGraphicsContext saveGraphicsState];[NSGraphicsContext setCurrentContext:first];[NSGraphicsContext restoreGraphicsState];
    CHECK([NSGraphicsContext currentContext]==nil,"save/set/restore returns to nil context");
    [NSGraphicsContext setCurrentContext:first];CGAffineTransform aBefore=CGContextGetCTM(a),bBefore=CGContextGetCTM(b);
    [NSGraphicsContext saveGraphicsState];CGContextTranslateCTM(a,3,4);
    [NSGraphicsContext setCurrentContext:nil];[NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:second];[NSGraphicsContext saveGraphicsState];CGContextTranslateCTM(b,7,8);
    [NSGraphicsContext setCurrentContext:nil];[NSGraphicsContext restoreGraphicsState];
    CHECK([NSGraphicsContext currentContext]==second&&CGAffineTransformEqualToTransform(CGContextGetCTM(b),bBefore),"nested nonnil context and CG state restore");
    [NSGraphicsContext restoreGraphicsState];CHECK([NSGraphicsContext currentContext]==nil,"nested nil sentinel restores");
    [NSGraphicsContext restoreGraphicsState];CHECK([NSGraphicsContext currentContext]==first&&CGAffineTransformEqualToTransform(CGContextGetCTM(a),aBefore),"outer context and CG state restore");
    [NSGraphicsContext setCurrentContext:nil];[NSGraphicsContext saveGraphicsState];[NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:first];[NSGraphicsContext restoreGraphicsState];CHECK([NSGraphicsContext currentContext]==nil,"inner repeated nil save restores");
    [NSGraphicsContext setCurrentContext:second];[NSGraphicsContext restoreGraphicsState];CHECK([NSGraphicsContext currentContext]==nil,"outer repeated nil save restores");
    [NSGraphicsContext setCurrentContext:second];[NSGraphicsContext restoreGraphicsState];CHECK([NSGraphicsContext currentContext]==second,"empty restore leaves context unchanged");
    [NSGraphicsContext setCurrentContext:nil];CGContextRelease(a);CGContextRelease(b);[pool drain];
    puts("PASS: nil/nonnil context stack and nested CG state restoration");return 0;
}
