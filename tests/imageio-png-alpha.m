#import <Foundation/Foundation.h>
#import <ImageIO/CGImageSource.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <string.h>

static unsigned failures;
#define CHECK(c, message) do { if (!(c)) { fprintf(stderr,"FAIL: %s (%s:%d)\n", message, name, __LINE__); failures++; } } while (0)
static NSData *readFixture(NSString *dir, const char *name, const char *ext) {
    return [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"%s.%s", name, ext]]];
}
int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 2) return 2;
        NSString *dir = [NSString stringWithUTF8String:argv[1]];
        const char *names[] = {"rgba", "rgb", "gray-alpha", "palette"};
        for (unsigned i=0; i<4; i++) {
            const char *name=names[i];
            NSData *png=readFixture(dir,name,"png"), *pre=readFixture(dir,name,"premul"), *white=readFixture(dir,name,"white");
            CHECK(png && [pre length]==40 && [white length]==40,"original fixtures present");
            if (!png || [pre length]!=40 || [white length]!=40) continue;
            CGImageSourceRef src=CGImageSourceCreateWithData((CFDataRef)png,NULL);
            CHECK(src!=NULL,"public image source"); if (!src) continue;
            CGImageRef image=CGImageSourceCreateImageAtIndex(src,0,NULL);
            CHECK(image!=NULL,"public decoded image"); if (!image) {CFRelease(src);continue;}
            CHECK(CGImageGetWidth(image)==5 && CGImageGetHeight(image)==2,"dimensions");
            CHECK(CGImageGetBitsPerComponent(image)==8 && CGImageGetBitsPerPixel(image)==32,"RGBA decode depth");
            CHECK(CGImageGetAlphaInfo(image)==kCGImageAlphaPremultipliedLast,"advertised premultiplied alpha");
            CHECK((CGImageGetBitmapInfo(image)&kCGBitmapByteOrderMask)==kCGBitmapByteOrder32Big,"advertised RGBA order");
            CFDataRef raw=CGDataProviderCopyData(CGImageGetDataProvider(image));
            size_t stride=CGImageGetBytesPerRow(image);
            CHECK(raw && stride>=20 && CFDataGetLength(raw)>=stride*2,"provider rows");
            if(raw && stride>=20 && CFDataGetLength(raw)>=stride*2)
                for(unsigned y=0;y<2;y++) CHECK(!memcmp(CFDataGetBytePtr(raw)+y*stride,(const unsigned char *)[pre bytes]+y*20,20),"provider bytes match independent premultiplied oracle");
            if(raw) CFRelease(raw);
            CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
            for(unsigned bg=0;bg<2;bg++) for(unsigned order=0;order<2;order++) {
                unsigned char pixels[56]; memset(pixels,0xa5,sizeof pixels);
                for(unsigned y=0;y<2;y++) memset(pixels+y*28,bg?255:0,20);
                CGBitmapInfo info=order ? kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little : kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big;
                CGContextRef c=CGBitmapContextCreate(pixels,5,2,8,28,cs,info);
                CHECK(c!=NULL,"padded bitmap context"); if(!c) continue;
                CGContextSetInterpolationQuality(c,kCGInterpolationNone);
                CGContextDrawImage(c,CGRectMake(0,0,5,2),image);
                const unsigned char *expected=[(bg?white:pre) bytes];
                unsigned bad=0;
                for(unsigned y=0;y<2;y++) for(unsigned x=0;x<5;x++) for(unsigned channel=0;channel<4;channel++) {
                    unsigned mapped=order && channel<3 ? 2-channel : channel;
                    int delta=(int)pixels[y*28+x*4+mapped]-expected[y*20+x*4+channel];
                    if(delta < -1 || delta > 1) bad++;
                }
                CHECK(bad==0,"actual draw matches independent alpha/composite oracle within 1 LSB");
                for(unsigned y=0;y<2;y++) for(unsigned k=20;k<28;k++) CHECK(pixels[y*28+k]==0xa5,"draw preserves row padding");
                CGContextRelease(c);
            }
            CGColorSpaceRelease(cs); CGImageRelease(image); CFRelease(src);
        }
        if(!failures) puts("PASS: PNG provider and RGBA/BGRA padded draw alpha contracts");
        return failures?1:0;
    }
}
