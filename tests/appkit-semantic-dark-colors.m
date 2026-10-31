#import <AppKit/AppKit.h>
#import <AppKit/NSDisplay.h>
#include <stdio.h>
#include <string.h>
#define CHECK(c,message) do {if(!(c)){fprintf(stderr,"FAIL: %s\n",message);return 1;}}while(0)
static void paint(NSColor *color, BOOL convert, unsigned char result[4]) {
    unsigned char bytes[4]={0,0,0,255};
    CGColorSpaceRef rgb=CGColorSpaceCreateDeviceRGB();
    CGContextRef c=CGBitmapContextCreate(bytes,1,1,8,4,rgb,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    if(!c){fputs("FAIL: bitmap allocation\n",stderr);exit(1);}
    [NSGraphicsContext saveGraphicsState];
    @try {
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithGraphicsPort:c flipped:NO]];
        if(convert) {
            NSColor *resolved=[color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
            if(!resolved){fputs("FAIL: semantic conversion unavailable\n",stderr);exit(1);}
            CGContextSetFillColorWithColor(c,[resolved CGColor]);
        } else [color setFill];
        CGContextFillRect(c,CGRectMake(0,0,1,1));
        memcpy(result,bytes,4);
    } @finally {[NSGraphicsContext restoreGraphicsState];CGContextRelease(c);CGColorSpaceRelease(rgb);}
}
static BOOL near(const unsigned char *a,const unsigned char *b) {
    for(unsigned i=0;i<4;i++){int d=(int)a[i]-b[i];if(d < -1 || d > 1)return NO;}return YES;
}
static double lightness(const unsigned char *p){return(p[0]+p[1]+p[2])/(3.0*255.0);}
int main(void){
    NSAutoreleasePool *pool=[NSAutoreleasePool new];
    static const char *keys[]={"textBackgroundColor","textColor","controlColor","controlTextColor","labelColor"};
    NSAutoreleasePool *creation=[NSAutoreleasePool new];
    NSArray *colors=[[NSArray alloc] initWithObjects:[NSColor textBackgroundColor],[NSColor textColor],
        [NSColor controlColor],[NSColor controlTextColor],[NSColor labelColor],nil];
    [creation drain];
    NSAppearance *aqua=[NSAppearance appearanceNamed:NSAppearanceNameAqua],*dark=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    __block struct { unsigned char light[5][4],night[5][4],again[5][4],fixedLight[4],fixedDark[4]; } samples;
    __block BOOL agrees=YES,metadata=YES;
    [aqua performAsCurrentDrawingAppearance:^{
        for(unsigned i=0;i<5;i++) {
            NSColor *color=[colors objectAtIndex:i];
            metadata &= [[color catalogNameComponent] isEqual:@"System"] &&
                [[color colorNameComponent] isEqual:[NSString stringWithUTF8String:keys[i]]];
            paint(color,NO,samples.light[i]); unsigned char backend[4],converted[4];
            paint([[NSDisplay currentDisplay] colorWithName:[NSString stringWithUTF8String:keys[i]]],NO,backend);
            paint(color,YES,converted);agrees &= near(samples.light[i],backend)&&near(samples.light[i],converted);
        }
    }];
    CHECK(metadata,"retained semantic catalog identity");
    CHECK(agrees,"Aqua values match existing backend and converted representation");
    [dark performAsCurrentDrawingAppearance:^{
        for(unsigned i=0;i<5;i++) {unsigned char converted[4];paint([colors objectAtIndex:i],NO,samples.night[i]);
            paint([colors objectAtIndex:i],YES,converted);agrees &= near(samples.night[i],converted);}
        [aqua performAsCurrentDrawingAppearance:^{for(unsigned i=0;i<5;i++)paint([colors objectAtIndex:i],NO,samples.again[i]);}];
        unsigned char restored[4];paint([colors objectAtIndex:0],NO,restored);agrees &= near(restored,samples.night[0]);
    }];
    CHECK(agrees,"dark conversion and nested scope restoration agree");
    for(unsigned i=0;i<5;i++) CHECK(near(samples.light[i],samples.again[i]),"Aqua cached colors restored without recreation");
    CHECK(lightness(samples.night[0]) < lightness(samples.light[0])-.4,"cached semantic text surface adapts darker");
    CHECK(lightness(samples.night[2]) < lightness(samples.light[2])-.4,"cached semantic control/window surface adapts darker");
    for(unsigned i=1;i<5;i++) if(i!=2)
        CHECK(lightness(samples.night[i]) > lightness(samples.light[i])+.4,"cached semantic foreground adapts brighter");
    CHECK(lightness(samples.night[1])-lightness(samples.night[0])>.5,"dark text foreground remains distinct from surface");
    CHECK(lightness(samples.night[3])-lightness(samples.night[2])>.5,"dark control foreground remains distinct from surface");
    NSColor *fixed=[NSColor colorWithCalibratedRed:.2 green:.4 blue:.7 alpha:1];
    [aqua performAsCurrentDrawingAppearance:^{paint(fixed,NO,samples.fixedLight);}];
    [dark performAsCurrentDrawingAppearance:^{paint(fixed,NO,samples.fixedDark);}];
    CHECK(near(samples.fixedLight,samples.fixedDark),"explicit content color unchanged");
    NSColor *custom=[NSColor colorWithCatalogName:@"QvolutionUser" colorName:@"textColor"];
    [aqua performAsCurrentDrawingAppearance:^{paint(custom,NO,samples.fixedLight);}];
    [dark performAsCurrentDrawingAppearance:^{paint(custom,NO,samples.fixedDark);}];
    CHECK(near(samples.fixedLight,samples.fixedDark),"non-System role-named catalog remains unchanged");
    [colors release];[pool drain];puts("PASS: retained semantic colors adapt and preserve Aqua/backend values");return 0;
}
