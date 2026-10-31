/* Original public metadata regression: skipped alpha still occupies storage. */
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <string.h>
int main(void) { @autoreleasepool {
    CGColorSpaceRef space=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    if(!space) return 2;
    const CGBitmapInfo flags[]={
        kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little,
        kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big,
        kCGImageAlphaNoneSkipFirst|kCGBitmapByteOrder32Little,
        kCGImageAlphaNoneSkipLast|kCGBitmapByteOrder32Big};
    unsigned failures=0;
    for(unsigned i=0;i<4;i++) {
        unsigned char bytes[32],saved[32];memset(bytes,0x63,sizeof(bytes));memcpy(saved,bytes,sizeof(bytes));
        CGContextRef context=CGBitmapContextCreate(bytes,2,2,8,16,space,flags[i]);
        if(!context) return 2;
        CGImageRef image=CGBitmapContextCreateImage(context);if(!image) return 2;
        size_t actual=CGBitmapContextGetBitsPerPixel(context),snapshot=CGImageGetBitsPerPixel(image);
        printf("layout=%u contextBpp=%zu imageBpp=%zu\n",i,actual,snapshot);
        failures+=actual!=32 || snapshot!=32 || CGBitmapContextGetBitsPerComponent(context)!=8 ||
            CGBitmapContextGetBytesPerRow(context)!=16 || memcmp(bytes,saved,sizeof(bytes));
        CGImageRelease(image);CGContextRelease(context);
    }
    CGColorSpaceRelease(space);return failures?1:0;
} }
