#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#define CHECK(c,m) do { if (!(c)) { fprintf(stderr,"FAIL: %s\n",m); return 1; } } while(0)
int main(int argc,const char **argv) {
 CHECK(argc==4,"provide DejaVuSans.ttf, DejaVuSans-BoldOblique.ttf, DejaVuSansMono.ttf");
 NSAutoreleasePool *pool=[NSAutoreleasePool new];
 NSString *names[]={@"DejaVuSans",@"DejaVuSans-BoldOblique",@"DejaVuSansMono"};
 CTFontSymbolicTraits expected[]={0,kCTFontTraitBold|kCTFontTraitItalic,kCTFontTraitMonoSpace};
 CTFontSymbolicTraits tested=kCTFontTraitBold|kCTFontTraitItalic|kCTFontTraitMonoSpace;
 for(int i=0;i<3;i++) {
  NSData *data=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[i+1]]];CHECK(data,"read explicit open font");
  CGDataProviderRef provider=CGDataProviderCreateWithCFData((CFDataRef)data);CGFontRef graphics=CGFontCreateWithDataProvider(provider);CHECK(graphics,"explicit graphics font creates");
  CTFontRef font=CTFontCreateWithGraphicsFont(graphics,17.5,NULL,NULL);CHECK(font,"real font creates");
  CFStringRef ps=CTFontCopyPostScriptName(font);CHECK(ps&&[(id)ps isEqual:names[i]],"reject substitute provider font");
  CHECK(CTFontGetSize(font)==17.5&&CTFontGetAscent(font)>0&&CTFontGetGlyphCount(font)>100,"real size and metrics controls");
  CHECK((CTFontGetSymbolicTraits(font)&tested)==expected[i],"symbolic traits reflect actual regular/bolditalic/mono face");
  CFDictionaryRef traits=CTFontCopyTraits(font);CHECK(traits&&CFGetTypeID(traits)==CFDictionaryGetTypeID(),"owned real traits dictionary");
  id symbolic=[(id)traits objectForKey:(id)kCTFontSymbolicTrait];CHECK([symbolic isKindOfClass:[NSNumber class]]&&([symbolic unsignedIntValue]&tested)==expected[i],"traits dictionary agrees with actual face");
  CFTypeRef attribute=CTFontCopyAttribute(font,kCTFontNameAttribute);CHECK(attribute&&CFEqual(attribute,ps),"public name attribute is actual PostScript name");
  CFRelease(attribute);CFRelease(traits);CFRelease(ps);CFRelease(font);CGFontRelease(graphics);CGDataProviderRelease(provider);
 }
 CHECK(CTFontGetSymbolicTraits(NULL)==0&&CTFontCopyTraits(NULL)==NULL,"invalid font metadata is absent");
 [pool drain];puts("PASS: actual provider symbolic traits and public PostScript-name attribute");return 0;
}
