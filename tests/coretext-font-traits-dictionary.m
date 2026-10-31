#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#define CHECK(c,m) do { if (!(c)) { fprintf(stderr,"FAIL: %s\n",m); return 1; } } while(0)
int main(int argc,const char **argv) {
 CHECK(argc==2,"provide exact DejaVuSans-BoldOblique.ttf");NSAutoreleasePool *outer=[NSAutoreleasePool new],*creation=[NSAutoreleasePool new];
 NSData *data=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];CHECK(data,"read explicit open font");
 CGDataProviderRef provider=CGDataProviderCreateWithCFData((CFDataRef)data);CGFontRef graphics=CGFontCreateWithDataProvider(provider);CHECK(graphics,"explicit provider font creates");
 CTFontRef font=CTFontCreateWithGraphicsFont(graphics,17.5,NULL,NULL);CHECK(font&&CTFontGetAscent(font)>0,"real font metric controls");
 CFStringRef ps=CTFontCopyPostScriptName(font);CHECK(ps&&[(id)ps isEqual:@"DejaVuSans-BoldOblique"],"reject substituted provider font");
 CFDictionaryRef traits=CTFontCopyTraits(font);CHECK(traits&&CFGetTypeID(traits)==CFDictionaryGetTypeID(),"actual owned font traits dictionary");
 NSNumber *symbolic=[(id)traits objectForKey:(id)kCTFontSymbolicTrait];CTFontSymbolicTraits mask=kCTFontTraitBold|kCTFontTraitItalic|kCTFontTraitMonoSpace;
 CHECK([symbolic isKindOfClass:[NSNumber class]]&&([symbolic unsignedIntValue]&mask)==(kCTFontTraitBold|kCTFontTraitItalic),"real symbolic traits numeric field");
 NSMutableDictionary *changed=[(id)traits mutableCopy];[changed setObject:@0 forKey:(id)kCTFontSymbolicTrait];[changed release];
 CFRelease(ps);CFRelease(font);CGFontRelease(graphics);CGDataProviderRelease(provider);[creation drain];
 CHECK(([[(id)traits objectForKey:(id)kCTFontSymbolicTrait] unsignedIntValue]&mask)==(kCTFontTraitBold|kCTFontTraitItalic),"owned dictionary outlives font/provider/pool and independent mutation");
 CFRelease(traits);CHECK(CTFontCopyTraits(NULL)==NULL,"invalid font has no trait dictionary");[outer drain];puts("PASS: owned actual symbolic traits dictionary independently of getter");return 0;
}
