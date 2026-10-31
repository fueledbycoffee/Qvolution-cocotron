#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>
@interface NSColor (QvolutionPlaceholderContract)
+ (NSColor *)placeholderTextColor;
@end
#define CHECK(c,m) do {if(!(c)){fprintf(stderr,"FAIL: %s\n",m);return 1;}}while(0)
static void paint(NSColor *color,BOOL converted,BOOL coloredBackground,unsigned char pixel[4]) {
    memset(pixel,0,4);CGColorSpaceRef rgb=CGColorSpaceCreateDeviceRGB();
    CGContextRef c=CGBitmapContextCreate(pixel,1,1,8,4,rgb,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    if(!c||!color){fputs("FAIL: placeholder bitmap setup\n",stderr);exit(1);}
    [NSGraphicsContext saveGraphicsState];
    @try {
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithGraphicsPort:c flipped:NO]];
        if(coloredBackground){CGContextSetRGBFillColor(c,.2,.4,.8,1);CGContextFillRect(c,CGRectMake(0,0,1,1));}
        if(converted){NSColor *resolved=[color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
            if(!resolved){fputs("FAIL: placeholder color conversion\n",stderr);exit(1);}
            CGContextSetFillColorWithColor(c,[resolved CGColor]);}
        else [color setFill];
        CGContextFillRect(c,CGRectMake(0,0,1,1));
    } @finally {[NSGraphicsContext restoreGraphicsState];CGContextRelease(c);CGColorSpaceRelease(rgb);}
}
static BOOL near(const unsigned char *a,const unsigned char *b){for(unsigned i=0;i<4;i++){int d=(int)a[i]-b[i];if(d < -1||d>1)return NO;}return YES;}
static double lum(const unsigned char *p){return(p[0]+p[1]+p[2])/(3.0*255);}
int main(void){
    NSAutoreleasePool *pool=[NSAutoreleasePool new];
    CHECK([NSColor respondsToSelector:@selector(placeholderTextColor)],"public placeholderTextColor class getter available");
    NSAutoreleasePool *creation=[NSAutoreleasePool new];NSColor *cached=[[NSColor placeholderTextColor] retain];[creation drain];
    CHECK(cached && [cached type]==NSColorTypeCatalog,"placeholder is retained semantic catalog color");
    CHECK([[cached catalogNameComponent] isEqual:@"System"]&&[[cached colorNameComponent] isEqual:@"placeholderTextColor"],"placeholder catalog role identity");
    NSAppearance *aqua=[NSAppearance appearanceNamed:NSAppearanceNameAqua],*dark=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    __block struct{unsigned char light[4],night[4],restored[4],background[4],foreground[4],converted[4],colored[4],fixed[4],other[4];} p;
    __block BOOL consistent=YES;
    [aqua performAsCurrentDrawingAppearance:^{
        paint(cached,NO,NO,p.light);paint(cached,YES,NO,p.converted);consistent &= near(p.light,p.converted);
        paint([NSColor textBackgroundColor],NO,NO,p.background);paint([NSColor textColor],NO,NO,p.foreground);
        consistent &= lum(p.foreground)+.2<lum(p.light)&&lum(p.light)+.2<lum(p.background);
        NSColor *rgb=[cached colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
        consistent &= [cached alphaComponent]==1&&[rgb alphaComponent]==1&&CGColorGetAlpha([cached CGColor])==1;
    }];
    CHECK(consistent,"Aqua placeholder conversion/opaque alpha/subdued surface contrast");
    [dark performAsCurrentDrawingAppearance:^{
        paint(cached,NO,NO,p.night);paint(cached,YES,NO,p.converted);paint(cached,NO,YES,p.colored);
        consistent &= near(p.night,p.converted)&&near(p.night,p.colored)&&p.night[3]==255;
        paint([NSColor textBackgroundColor],NO,NO,p.background);paint([NSColor textColor],NO,NO,p.foreground);
        consistent &= lum(p.background)+.2<lum(p.night)&&lum(p.night)+.2<lum(p.foreground);
        [aqua performAsCurrentDrawingAppearance:^{paint(cached,NO,NO,p.restored);}];
        paint(cached,NO,NO,p.converted);consistent &= near(p.converted,p.night);
    }];
    CHECK(consistent,"dark placeholder converts/draws opaquely with lower emphasis and nested scope restoration");
    CHECK(lum(p.night)>lum(p.light)+.05&&near(p.restored,p.light),"same cached placeholder adapts and restores without recreation");
    NSColor *fixed=[NSColor colorWithCalibratedRed:.2 green:.4 blue:.7 alpha:.5];
    NSColor *custom=[NSColor colorWithCatalogName:@"QvolutionUser" colorName:@"controlColor"];
    [aqua performAsCurrentDrawingAppearance:^{paint(fixed,NO,NO,p.fixed);paint(custom,NO,NO,p.other);}];
    [dark performAsCurrentDrawingAppearance:^{paint(fixed,NO,NO,p.converted);paint(custom,NO,NO,p.colored);}];
    CHECK(near(p.fixed,p.converted)&&near(p.other,p.colored),"explicit translucent content and non-System catalog unchanged");
    CHECK(p.fixed[3]>=127&&p.fixed[3]<=128,"explicit half-alpha drawing remains translucent");
    [cached release];[pool drain];puts("PASS: adaptive placeholder catalog pixels, opaque alpha, contrast and ownership");return 0;
}
