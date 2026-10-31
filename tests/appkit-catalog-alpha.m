#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>
static unsigned failures;
#define CHECK(c,m) do{if(!(c)){fprintf(stderr,"FAIL: %s\n",m);failures++;}}while(0)
static void pixel(NSColor *color,unsigned char result[4]) {
 memset(result,0,4);CGColorSpaceRef rgb=CGColorSpaceCreateDeviceRGB();
 CGContextRef c=CGBitmapContextCreate(result,1,1,8,4,rgb,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
 CGContextSetFillColorWithColor(c,[color CGColor]);CGContextFillRect(c,CGRectMake(0,0,1,1));CGContextRelease(c);CGColorSpaceRelease(rgb);
}
static BOOL near(const unsigned char*a,const unsigned char*b){for(unsigned i=0;i<4;i++){int d=(int)a[i]-b[i];if(d < -1||d>1)return NO;}return YES;}
int main(void){
 NSAutoreleasePool *pool=[NSAutoreleasePool new];
 NSColor *secondary=[NSColor secondaryLabelColor];CGFloat actual=CGColorGetAlpha([secondary CGColor]);
 CHECK(actual>0&&actual<1,"translucent catalog positive control");
 CHECK([secondary alphaComponent]==actual,"catalog alphaComponent reports actual backing opacity");
 NSAutoreleasePool *creation=[NSAutoreleasePool new];
 NSColor *source=[NSColor textColor];NSColor *variant=[[source colorWithAlphaComponent:.25] retain];
 NSColor *same=[[source colorWithAlphaComponent:.25] retain];
 NSColor *replacement=[[secondary colorWithAlphaComponent:.25] retain];
 CHECK(variant&&same&&replacement,"catalog alpha replacement returns color objects");
 if(variant&&same&&replacement){
  CHECK([[variant colorSpaceName] isEqual:[source colorSpaceName]],"alpha replacement preserves named color space");
  if([[variant colorSpaceName] isEqual:NSNamedColorSpace])
   CHECK([[variant catalogNameComponent] isEqual:[source catalogNameComponent]]&&[[variant colorNameComponent] isEqual:[source colorNameComponent]],"derived catalog role identity retained");
  CHECK(![variant isEqual:source]&&[variant isEqual:same]&&[variant hash]==[same hash],"derived opacity identity and hash are consistent");
  CHECK([source alphaComponent]==1&&[secondary alphaComponent]==actual,"alpha replacement does not mutate source");
 }
 [creation drain];
 if(variant&&same&&replacement){
  NSAppearance *aqua=[NSAppearance appearanceNamed:NSAppearanceNameAqua],*dark=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
  __block struct{unsigned char light[4],night[4],restored[4],replaced[4],more[4];} p;
  [aqua performAsCurrentDrawingAppearance:^{pixel(variant,p.light);pixel(replacement,p.replaced);}];
  CHECK(p.light[3]>=63&&p.light[3]<=64&&p.replaced[3]>=63&&p.replaced[3]<=64,"requested alpha replaces rather than multiplies backing alpha");
  [dark performAsCurrentDrawingAppearance:^{pixel(variant,p.night);
   CHECK([variant alphaComponent]==.25&&CGColorGetAlpha([variant CGColor])==.25,"dynamic opacity getter and CGColor agree");
   [aqua performAsCurrentDrawingAppearance:^{pixel(variant,p.restored);}];
  }];
  CHECK(p.night[0]>p.light[0]+40&&p.night[3]==p.light[3]&&near(p.restored,p.light),"derived catalog remains dynamic through scopes and pool lifetime");
  NSColor *more=[variant colorWithAlphaComponent:.75];pixel(more,p.more);
  CHECK(p.more[3]>=190&&p.more[3]<=192,"replacing derived alpha does not multiply existing override");
  CHECK([variant alphaComponent]==.25,"derived source remains unchanged after second replacement");
 }
 [variant release];[same release];[replacement release];[pool drain];
 if(!failures)puts("PASS: catalog opacity metadata, identity, dynamic drawing and ownership");return failures?1:0;
}
