#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#define CHECK(c,m) do { if (!(c)) { fprintf(stderr,"FAIL: %s\n",m); return 1; } } while(0)
int main(int argc,const char **argv) {
 CHECK(argc==2,"provide exact DejaVuSans-BoldOblique.ttf");
 NSAutoreleasePool *pool=[NSAutoreleasePool new];
 NSData *data=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];CHECK(data,"read explicit open font");
 CGDataProviderRef provider=CGDataProviderCreateWithCFData((CFDataRef)data);CGFontRef graphics=CGFontCreateWithDataProvider(provider);CHECK(graphics,"explicit graphics font creates");
 CTFontRef font=CTFontCreateWithGraphicsFont(graphics,17.5,NULL,NULL);CHECK(font&&CTFontGetAscent(font)>0,"real font and metrics control");
 CFStringRef ps=CTFontCopyPostScriptName(font),full=CTFontCopyFullName(font);CHECK(ps&&[(id)ps isEqual:@"DejaVuSans-BoldOblique"],"reject substituted font");
 CHECK(full&&!CFEqual(full,ps),"independent full-name and PostScript-name controls differ");
 CFTypeRef name=CTFontCopyAttribute(font,kCTFontNameAttribute);CHECK(name&&CFEqual(name,ps),"name attribute is documented PostScript name, not full name");
 CFRelease(font);CGFontRelease(graphics);CGDataProviderRelease(provider);CFRelease(ps);CFRelease(full);
 CHECK([(id)name isEqual:@"DejaVuSans-BoldOblique"],"copied name outlives original font");CFRelease(name);[pool drain];
 puts("PASS: documented PostScript name attribute and ownership");return 0;
}
