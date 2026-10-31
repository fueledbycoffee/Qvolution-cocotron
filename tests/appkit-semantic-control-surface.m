#import <AppKit/AppKit.h>
#include <stdio.h>
static double pixelLightness(NSColor *color) {
    unsigned char pixel[4]={0,0,0,255};
    CGColorSpaceRef rgb=CGColorSpaceCreateDeviceRGB();
    CGContextRef c=CGBitmapContextCreate(pixel,1,1,8,4,rgb,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    if(!c || !color){fputs("FAIL: control surface pixel setup\n",stderr);exit(1);}
    CGContextSetFillColorWithColor(c,[color CGColor]);CGContextFillRect(c,CGRectMake(0,0,1,1));
    CGContextRelease(c);CGColorSpaceRelease(rgb);return(pixel[0]+pixel[1]+pixel[2])/(3.0*255);
}
int main(void){
    NSAutoreleasePool *pool=[NSAutoreleasePool new];
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,32,32)];
    NSArray *surfaces=[[NSArray alloc] initWithObjects:[NSColor controlBackgroundColor],[scroll backgroundColor],[[scroll contentView] backgroundColor],nil];
    NSColor *text=[[NSColor textColor] retain];
    NSAppearance *aqua=[NSAppearance appearanceNamed:NSAppearanceNameAqua],*dark=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    __block struct {double light[3],dark[3],text;} values;
    [aqua performAsCurrentDrawingAppearance:^{for(unsigned i=0;i<3;i++)values.light[i]=pixelLightness([surfaces objectAtIndex:i]);}];
    [dark performAsCurrentDrawingAppearance:^{for(unsigned i=0;i<3;i++)values.dark[i]=pixelLightness([surfaces objectAtIndex:i]);values.text=pixelLightness(text);}];
    for(unsigned i=0;i<3;i++) {
        if(values.dark[i]>=values.light[i]-.4 || values.text-values.dark[i]<=.5) {
            fprintf(stderr,"FAIL: cached control/scroll/clip surface pairs with dark semantic text (index%u)\n",i);return 1;
        }
    }
    [text release];[surfaces release];[scroll release];[pool drain];
    puts("PASS: cached control, scroll and clip surfaces adapt with text foreground");return 0;
}
