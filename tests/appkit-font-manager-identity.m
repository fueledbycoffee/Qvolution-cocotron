// Original public font-manager identity/trait/conversion baseline over exact open fonts.
#import <AppKit/AppKit.h>
#import <CoreText/CoreText.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#import <objc/runtime.h>
#include <time.h>
static NSUInteger catalogConstructions;
static IMP actualInitWithFace;
static id observeFontConstruction(id receiver,SEL selector,void *face){
 ++catalogConstructions;return ((id(*)(id,SEL,void *))actualInitWithFace)(receiver,selector,face);
}
static double seconds(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
static unsigned failures;
#define INPUT(c,m) do{if(!(c)){fprintf(stderr,"INPUT FAIL: %s\n",m);return 2;}}while(0)
static void expectManager(BOOL value,const char *message){printf("%s: %s\n",value?"PASS":"FAIL",message);failures+=!value;}
static NSFontTraitMask actualTraits(NSFont *font){
 CTFontSymbolicTraits ct=CTFontGetSymbolicTraits((CTFontRef)font);NSFontTraitMask m=0;
 if(ct&kCTFontTraitBold)m|=NSBoldFontMask;if(ct&kCTFontTraitItalic)m|=NSItalicFontMask;if(ct&kCTFontTraitMonoSpace)m|=NSFixedPitchFontMask;return m;
}
static NSFont *providerFont(NSString *dir,NSString *name){
 NSData *data=[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:[name stringByAppendingString:@".ttf"]]];
 if(!data)return nil;CGDataProviderRef provider=CGDataProviderCreateWithCFData((CFDataRef)data);if(!provider)return nil;
 CGFontRef graphics=CGFontCreateWithDataProvider(provider);CGDataProviderRelease(provider);if(!graphics)return nil;
 CTFontRef font=CTFontCreateWithGraphicsFont(graphics,17.5,NULL,NULL);CGFontRelease(graphics);return (NSFont *)font;
}
static BOOL identity(NSFont *font,NSString *name,NSFontTraitMask traits,CGFloat size){
 if(!font)return NO;CFStringRef ps=CTFontCopyPostScriptName((CTFontRef)font);
 BOOL good=ps&&[(id)ps isEqualToString:name]&&actualTraits(font)==traits&&fabs([font pointSize]-size)<.00001;
 if(ps)CFRelease(ps);return good;
}
static void conversion(NSFont *got,NSFont *reference,const char *message){
 BOOL good=got&&identity(got,[reference fontName],actualTraits(reference),[reference pointSize]);
 if(got)printf("MEASURE converted=%s family=%s actualTraits=%u size=%.4f\n",[[got fontName]UTF8String],[[got familyName]UTF8String],actualTraits(got),(double)[got pointSize]);
 if(good){UniChar chars[]={'W','i','A'};CGGlyph a[3]={0},b[3]={0};CGSize wa[3],wb[3];
  good=CTFontGetGlyphsForCharacters((CTFontRef)got,chars,a,3)&&CTFontGetGlyphsForCharacters((CTFontRef)reference,chars,b,3);
  double sa=CTFontGetAdvancesForGlyphs((CTFontRef)got,kCTFontOrientationHorizontal,a,wa,3),sb=CTFontGetAdvancesForGlyphs((CTFontRef)reference,kCTFontOrientationHorizontal,b,wb,3);
  good=good&&isfinite(sa)&&sa>0&&fabs(sa-sb)<.00001&&memcmp(a,b,sizeof(a))==0;
  for(unsigned i=0;good&&i<3;i++)good=fabs(wa[i].width-wb[i].width)<.00001&&fabs(wa[i].height-wb[i].height)<.00001;
 }
 expectManager(good,message);
}
int main(int argc,char **argv){@autoreleasepool{
 setbuf(stdout,NULL);INPUT(argc==3,"mode traits|family|catalog|convert|catalog-cost and exact open DejaVu font directory");
 NSString *mode=[NSString stringWithUTF8String:argv[1]],*dir=[NSString stringWithUTF8String:argv[2]];
 [NSApplication sharedApplication];NSFontManager *manager=[NSFontManager sharedFontManager];INPUT(manager,"actual shared font manager");
 NSString *names[]={@"DejaVuSans",@"DejaVuSans-Bold",@"DejaVuSans-Oblique",@"DejaVuSans-BoldOblique",@"DejaVuSansMono",@"DejaVuSansMono-BoldOblique"};
 NSFontTraitMask masks[]={0,NSBoldFontMask,NSItalicFontMask,NSBoldFontMask|NSItalicFontMask,NSFixedPitchFontMask,NSFixedPitchFontMask|NSBoldFontMask|NSItalicFontMask};
 NSFont *fonts[6];for(unsigned i=0;i<6;i++){
  fonts[i]=providerFont(dir,names[i]);INPUT(fonts[i]&&[fonts[i]isKindOfClass:[NSFont class]],"exact provider creates real AppKit concrete NSFont");
  INPUT(identity(fonts[i],names[i],masks[i],17.5),"actual provider PS/CT traits/size reject substituted font");
  UniChar w='W';CGGlyph glyph=0;INPUT(CTFontGetGlyphsForCharacters((CTFontRef)fonts[i],&w,&glyph,1)&&glyph&&CTFontGetAscent((CTFontRef)fonts[i])>0,"actual provider glyph and metric positive controls");
 }
 if([mode isEqualToString:@"traits"]){
  for(unsigned pass=0;pass<2;pass++){
   if(pass)[manager availableMembersOfFontFamily:@"DejaVu Sans"];
   for(unsigned i=0;i<6;i++){
    unsigned got=[manager traitsOfFont:fonts[i]];
    printf("MEASURE phase=%s PS=%s actual=%u manager=%u legacyWeight=%d\n",pass?"family-warmed":"cold",[names[i]UTF8String],masks[i],got,[manager weightOfFont:fonts[i]]);
    expectManager((got&(NSBoldFontMask|NSItalicFontMask|NSFixedPitchFontMask))==masks[i],"manager traits reflect actual provider face regardless catalog warmup");
   }
  }
  expectManager([manager fontNamed:@"DejaVuSans-BoldOblique" hasTraits:NSBoldFontMask|NSItalicFontMask],"named font trait predicate uses actual bolditalic face");
 }else if([mode isEqualToString:@"family"]){
  for(unsigned i=0;i<6;i++){
   CFStringRef actualFamily=CTFontCopyFamilyName((CTFontRef)fonts[i]);NSString *wanted=i<4?@"DejaVu Sans":@"DejaVu Sans Mono";
   INPUT(actualFamily&&[(id)actualFamily isEqualToString:wanted],"actual CoreText family positive control");
   printf("MEASURE PS=%s actualFamily=%s AppKitFamily=%s\n",[names[i]UTF8String],[(id)actualFamily UTF8String],[[fonts[i]familyName]UTF8String]);
   expectManager([[fonts[i]familyName]isEqualToString:wanted],"AppKit family name preserves actual face metadata");CFRelease(actualFamily);
  }
 }else if([mode isEqualToString:@"catalog-cost"]){
  Class owned=NSClassFromString(@"O2Font_freetype");Method method=class_getInstanceMethod(owned,NSSelectorFromString(@"initWithFace:"));INPUT(method,"known own render-font initializer observer exists");
  actualInitWithFace=method_getImplementation(method);catalogConstructions=0;double begin=seconds();NSUInteger count=0;
  method_setImplementation(method,(IMP)observeFontConstruction);
  @try{count=[[manager availableFonts]count];}
  @finally{method_setImplementation(method,actualInitWithFace);}
  printf("MEASURE catalogEntries=%lu renderFontConstructions=%lu elapsed_seconds=%.9f\n",(unsigned long)count,(unsigned long)catalogConstructions,seconds()-begin);
  expectManager(count>0,"actual catalog enumerates available entries");
  expectManager(catalogConstructions==0,"catalog metadata discovery constructs no render-font or eager glyph cache objects");
 }else if([mode isEqualToString:@"catalog"]){
  NSArray *members=[manager availableMembersOfFontFamily:@"DejaVu Sans"];INPUT([members count]>0,"actual installed family has catalog members");BOOL seen[4]={0};
  for(id row in members){INPUT([row isKindOfClass:[NSArray class]]&&[row count]==4,"public family member has four fields");
   id name=row[0],style=row[1],weight=row[2],traits=row[3];INPUT([name isKindOfClass:[NSString class]]&&[style isKindOfClass:[NSString class]]&&[weight isKindOfClass:[NSNumber class]]&&[traits isKindOfClass:[NSNumber class]],"public member string/string/numeric/numeric types");
   NSFont *font=[NSFont fontWithName:name size:17.5];INPUT(font&&CTFontGetGlyphCount((CTFontRef)font)>0,"catalog entry loads actual font");CFStringRef ps=CTFontCopyPostScriptName((CTFontRef)font);
   printf("MEASURE catalogName=%s actualPS=%s style=%s legacyWeight=%d flags=%u\n",[name UTF8String],[(id)ps UTF8String],[style UTF8String],[weight intValue],[traits unsignedIntValue]);
   expectManager(ps&&[(id)ps isEqualToString:name],"public catalog member name is actual PostScript identity");
   expectManager(([traits unsignedIntValue]&(NSBoldFontMask|NSItalicFontMask|NSFixedPitchFontMask))==actualTraits(font),"catalog trait field agrees with actual loaded face");
   for(unsigned i=0;i<4;i++)if(ps&&[(id)ps isEqualToString:names[i]])seen[i]=YES;if(ps)CFRelease(ps);
  }
  for(unsigned i=0;i<4;i++)expectManager(seen[i],"catalog enumerates installed exact regular/bold/italic/bolditalic faces");
  NSArray *available=[manager availableFonts];expectManager([available containsObject:@"DejaVuSans-BoldOblique"],"availableFonts exposes actual PostScript names too");
 }else if([mode isEqualToString:@"convert"]){
  conversion([manager fontWithFamily:@"DejaVu Sans" traits:NSBoldFontMask|NSItalicFontMask weight:5 size:17.5],fonts[3],"family/trait loading positive control selects actual bolditalic face");
  conversion([manager convertFont:fonts[0]toFace:@"DejaVuSans-Bold"],fonts[1],"explicit face conversion positive control preserves real bold metrics");
  conversion([manager convertFont:fonts[0]toHaveTrait:NSBoldFontMask],fonts[1],"adding bold converts actual regular face");
  conversion([manager convertFont:fonts[1]toHaveTrait:NSItalicFontMask],fonts[3],"adding italic preserves existing bold trait");
  conversion([manager convertFont:fonts[3]toNotHaveTrait:NSBoldFontMask],fonts[2],"removing bold preserves italic trait");
  conversion([manager convertFont:fonts[3]toNotHaveTrait:NSItalicFontMask],fonts[1],"removing italic preserves bold trait");
  conversion([manager convertFont:fonts[3]toFamily:@"DejaVu Sans Mono"],fonts[5],"family conversion preserves actual bolditalic traits and size");
  NSFont *sized=[manager convertFont:fonts[3]toSize:23.25];expectManager(identity(sized,names[3],masks[3],23.25),"size-only conversion preserves actual PostScript identity/traits");
  expectManager([manager convertFont:fonts[3]toFamily:@"QvolutionDefinitelyUnavailableFamily9271"]==fonts[3],"unavailable family conversion retains original rather than substituting default");
  expectManager([manager convertFont:fonts[0]toHaveTrait:NSPosterFontMask]==fonts[0],"unavailable trait conversion retains original without fabricated style");
 }else INPUT(NO,"known explicit manager mode");
 for(unsigned i=0;i<6;i++)CFRelease((CTFontRef)fonts[i]);printf("RESULT %u failures\n",failures);return failures?1:0;
}}
