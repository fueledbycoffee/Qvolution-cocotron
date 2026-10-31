#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <math.h>
#define CHECK(c,m) do { if (!(c)) { fprintf(stderr,"FAIL: %s\n",m); return 1; } } while(0)
int main(int argc,const char **argv) {
 CHECK(argc==2,"provide exact DejaVuSans-BoldOblique.ttf");
 NSAutoreleasePool *outer=[NSAutoreleasePool new],*creation=[NSAutoreleasePool new];
 NSData *data=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];CHECK(data,"read explicit open font");
 CGDataProviderRef provider=CGDataProviderCreateWithCFData((CFDataRef)data);CGFontRef graphics=CGFontCreateWithDataProvider(provider);CHECK(graphics,"explicit provider graphics font");
 CTFontDescriptorRef fallback=CTFontDescriptorCreateWithNameAndSize(CFSTR("DejaVuSansMono"),11);
 NSMutableArray *cascade=[NSMutableArray arrayWithObject:(id)fallback];
 NSDictionary *settings=[NSDictionary dictionaryWithObject:cascade forKey:(id)kCTFontCascadeListAttribute];
 CTFontDescriptorRef construction=CTFontDescriptorCreateWithAttributes((CFDictionaryRef)settings);CHECK(construction,"public descriptor constructor owns input settings");
 CTFontRef font=CTFontCreateWithGraphicsFont(graphics,17.5,NULL,construction);CFRelease(construction);CHECK(font,"provider CoreText font");
 [cascade removeAllObjects];CFRelease(fallback);
 CFStringRef ps=CTFontCopyPostScriptName(font),family=CTFontCopyFamilyName(font),display=CTFontCopyDisplayName(font);
 CHECK(ps&&[(id)ps isEqual:@"DejaVuSans-BoldOblique"]&&[(id)family isEqual:@"DejaVu Sans"],"reject fallback font and verify actual family");
 CGFloat ascent=CTFontGetAscent(font);UniChar text='A';CGGlyph glyph=0;
 CHECK(ascent>0&&CTFontGetGlyphsForCharacters(font,&text,&glyph,1)&&glyph!=0,"actual metrics and glyph independent controls");
 CTFontDescriptorRef descriptor=CTFontCopyFontDescriptor(font);
 CHECK(descriptor,"actual font produces owned normalized descriptor");
 CHECK(CFGetTypeID(descriptor)==CTFontDescriptorGetTypeID(),"descriptor uses framework registered representation");
 CFDictionaryRef attrs=CTFontDescriptorCopyAttributes(descriptor);CHECK(attrs&&[(id)attrs count]>0,"nonempty immutable attribute snapshot");
 CHECK([[(id)attrs objectForKey:(id)kCTFontNameAttribute] isEqual:(id)ps]&&[[(id)attrs objectForKey:(id)kCTFontPostScriptNameAttribute] isEqual:(id)ps],"descriptor names actual PostScript face");
 CHECK([[(id)attrs objectForKey:(id)kCTFontFamilyNameAttribute] isEqual:(id)family]&&[[(id)attrs objectForKey:(id)kCTFontDisplayNameAttribute] isEqual:(id)display],"descriptor preserves actual family and display name");
 id size=[(id)attrs objectForKey:(id)kCTFontSizeAttribute];CHECK([size isKindOfClass:[NSNumber class]]&&[size doubleValue]==17.5,"size remains numeric and precise");
 CTFontSymbolicTraits mask=kCTFontTraitBold|kCTFontTraitItalic|kCTFontTraitMonoSpace;
 CHECK((CTFontDescriptorGetSymbolicTraits(descriptor)&mask)==(kCTFontTraitBold|kCTFontTraitItalic),"descriptor traits reflect bolditalic face");
 NSArray *saved=[(id)attrs objectForKey:(id)kCTFontCascadeListAttribute];CHECK([saved count]==1,"copied explicit cascade survives source array mutation");
 NSMutableDictionary *changed=[(id)attrs mutableCopy];[changed setObject:@99 forKey:(id)kCTFontSizeAttribute];
 CFTypeRef originalSize=CTFontDescriptorCopyAttribute(descriptor,kCTFontSizeAttribute);CHECK([(id)originalSize doubleValue]==17.5,"mutable attribute copy cannot alter descriptor");
 CFRelease(originalSize);[changed release];CFRelease(attrs);CFRelease(ps);CFRelease(family);CFRelease(display);CFRelease(font);CGFontRelease(graphics);CGDataProviderRelease(provider);[creation drain];
 CTFontRef recreated=CTFontCreateWithFontDescriptor(descriptor,0,NULL);CHECK(recreated,"descriptor recreates after original font and pool release");
 CFStringRef recreatedPS=CTFontCopyPostScriptName(recreated);CHECK(recreatedPS&&[(id)recreatedPS isEqual:@"DejaVuSans-BoldOblique"]&&CTFontGetSize(recreated)==17.5,"recreated font identity and inherited size");
 CHECK(fabs(CTFontGetAscent(recreated)-ascent)<0.0001,"recreated actual metrics unchanged");
 CGGlyph reproduced=0;CHECK(CTFontGetGlyphsForCharacters(recreated,&text,&reproduced,1)&&reproduced==glyph,"recreated glyph identity unchanged");
 CFArrayRef recreatedCascade=CTFontCopyAttribute(recreated,kCTFontCascadeListAttribute);CHECK(recreatedCascade&&CFArrayGetCount(recreatedCascade)==1,"descriptor cascade survives recreation");
 CFRelease(recreatedCascade);CFRelease(recreatedPS);CFRelease(recreated);CFRelease(descriptor);
 CHECK(CTFontCopyFontDescriptor(NULL)==NULL,"invalid font has no descriptor");
 [outer drain];puts("PASS: normalized real-font descriptor metadata, copy/lifetime and recreation");return 0;
}
