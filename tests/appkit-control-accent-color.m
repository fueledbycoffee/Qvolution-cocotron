#import <AppKit/AppKit.h>
#include <stdio.h>
@interface NSColor (QvolutionAccentContract)
+ (NSColor *)controlAccentColor;
@end
#define CHECK(c,m) do{if(!(c)){fprintf(stderr,"FAIL: %s\n",m);return 1;}}while(0)
static void pixel(NSColor *color,unsigned char output[4]){
 memset(output,0,4);CGColorSpaceRef rgb=CGColorSpaceCreateDeviceRGB();
 CGContextRef c=CGBitmapContextCreate(output,1,1,8,4,rgb,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
 CGContextSetFillColorWithColor(c,[color CGColor]);CGContextFillRect(c,CGRectMake(0,0,1,1));CGContextRelease(c);CGColorSpaceRelease(rgb);
}
int main(void){
 NSAutoreleasePool *pool=[NSAutoreleasePool new];
 CHECK([NSColor respondsToSelector:@selector(controlAccentColor)],"public controlAccentColor getter available");
 NSAutoreleasePool *creation=[NSAutoreleasePool new];NSColor *accent=[[NSColor controlAccentColor] retain];[creation drain];
 CHECK(accent&&[[accent catalogNameComponent] isEqual:@"System"]&&[[accent colorNameComponent] isEqual:@"controlAccentColor"],"accent retains semantic catalog role");
 NSAppearance *aqua=[NSAppearance appearanceNamed:NSAppearanceNameAqua],*dark=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
 __block struct{unsigned char accent[4],selection[4],night[4],alpha[4];} p;
 [aqua performAsCurrentDrawingAppearance:^{pixel(accent,p.accent);pixel([NSColor selectedControlColor],p.selection);}];
 CHECK(!memcmp(p.accent,p.selection,4),"current fallback uses existing actual backend selection color");
 [dark performAsCurrentDrawingAppearance:^{pixel(accent,p.night);pixel([accent colorWithAlphaComponent:.5],p.alpha);}];
 CHECK(p.night[3]==255&&p.alpha[3]>=127&&p.alpha[3]<=128,"accent has real opaque and derived half-alpha pixels");
 CHECK(p.night[2]>p.night[0]&&p.night[2]>p.night[1],"current backend fallback remains actual blue accent rather than unknown-role red");
 [accent release];[pool drain];puts("PASS: accent catalog, current backend fallback, derived opacity and ownership");return 0;
}
