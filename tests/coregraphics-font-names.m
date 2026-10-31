#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#define CHECK(c,m) do { if (!(c)) { fprintf(stderr,"FAIL: %s\n",m); return 1; } } while(0)
int main(int argc,const char **argv) {
 CHECK(argc==3,"provide exact DejaVuSans.ttf and DejaVuSans-BoldOblique.ttf");
 NSAutoreleasePool *outer=[NSAutoreleasePool new];
 NSString *postscript[]={@"DejaVuSans",@"DejaVuSans-BoldOblique"};
 NSString *full[]={@"DejaVu Sans",@"DejaVu Sans Bold Oblique"};
 for(int i=0;i<2;i++) {
  NSAutoreleasePool *creation=[NSAutoreleasePool new];
  NSData *data=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[i+1]]];CHECK(data,"read explicit open provider font");
  CGDataProviderRef provider=CGDataProviderCreateWithCFData((CFDataRef)data);CHECK(provider,"provider owns font data");
  CGFontRef font=CGFontCreateWithDataProvider(provider);CHECK(font&&CGFontGetNumberOfGlyphs(font)>100&&CGFontGetUnitsPerEm(font)>0,"real graphics font metrics controls");
  CFStringRef ps=CGFontCopyPostScriptName(font),name=CGFontCopyFullName(font);
  CHECK(ps&&[(id)ps isEqual:postscript[i]],"provider exposes actual PostScript name rather than absent request label");
  CHECK(name&&[(id)name isEqual:full[i]],"provider exposes distinct actual full font name");
  CHECK(!CFEqual(ps,name),"PostScript and full names stay distinct");
  NSMutableString *changed=[(id)name mutableCopy];[changed appendString:@".fixture"];
  CFStringRef again=CGFontCopyFullName(font);CHECK(again&&CFEqual(again,name),"mutable local copy does not alter font metadata");CFRelease(again);[changed release];
  CGFontRelease(font);CGDataProviderRelease(provider);[creation drain];
  CHECK([(id)ps isEqual:postscript[i]]&&[(id)name isEqual:full[i]],"owned immutable names outlive font, provider and pool");
  CFRelease(ps);CFRelease(name);
 }
 CGFontRef named=CGFontCreateWithFontName(CFSTR("DejaVu Sans"));CHECK(named&&CGFontGetNumberOfGlyphs(named)>100,"named font independent metrics control");
 CFStringRef namedPS=CGFontCopyPostScriptName(named),namedFull=CGFontCopyFullName(named);
 CHECK(namedPS&&[(id)namedPS isEqual:@"DejaVuSans"]&&namedFull&&[(id)namedFull isEqual:@"DejaVu Sans"],"named font exposes provider identity, not input spelling for both names");
 CFRelease(namedPS);CFRelease(namedFull);CGFontRelease(named);
 [outer drain];puts("PASS: actual graphics font PostScript/full metadata, distinction, copy and lifetime");return 0;
}
