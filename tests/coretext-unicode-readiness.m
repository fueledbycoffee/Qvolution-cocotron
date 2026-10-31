#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#import <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#import <objc/runtime.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#define REQUIRE(c,m) do { if (!(c)) { fprintf(stderr,"INPUT FAIL: %s\n",m); return 2; } } while(0)
static unsigned failures;
static void expectReadiness(BOOL c,const char *m) { printf("%s: %s\n",c?"PASS":"FAIL",m);failures+=!c; }
static NSDictionary *scalarRecord(NSDictionary *font,unsigned scalar) {
 for(NSDictionary *r in [font objectForKey:@"glyphs"])if([[r objectForKey:@"scalar"]unsignedIntValue]==scalar)return r;return nil;
}
static CTFontRef loadFont(const char *path) {
 NSData *data=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:path]];
 if(!data)return NULL;CGDataProviderRef provider=CGDataProviderCreateWithCFData((CFDataRef)data);
 CGFontRef graphics=CGFontCreateWithDataProvider(provider);CGDataProviderRelease(provider);if(!graphics)return NULL;
 CTFontRef font=CTFontCreateWithGraphicsFont(graphics,17.5,NULL,NULL);CGFontRelease(graphics);return font;
}
int main(int argc,const char **argv) {
 setbuf(stdout,NULL);REQUIRE(argc==5||argc==6,"mode(cmap|advance|fallback|clusters), exactMono.ttf, exactSans.ttf, independent reference.json, optional appkit");
 NSAutoreleasePool *pool=[NSAutoreleasePool new];
 if(argc==6){REQUIRE(!strcmp(argv[5],"appkit"),"only optional mode appkit");REQUIRE(dlopen("/System/Library/Frameworks/AppKit.framework/AppKit",RTLD_LAZY|RTLD_LOCAL),"actual AppKit loads before fonts");}
 NSData *bytes=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[4]]];
 NSDictionary *reference=bytes?[NSJSONSerialization JSONObjectWithData:bytes options:0 error:NULL]:nil;
 NSArray *expected=[reference objectForKey:@"fonts"];REQUIRE([expected count]==2,"independent original native-reference font records");
 CTFontRef fonts[]={loadFont(argv[2]),loadFont(argv[3])};
 for(int i=0;i<2;i++){
  REQUIRE(fonts[i],"explicit open provider font creates");CFStringRef ps=CTFontCopyPostScriptName(fonts[i]);
  REQUIRE(ps&&[(id)ps isEqual:[[expected objectAtIndex:i]objectForKey:@"postscript"]],"reject substituted font identity");CFRelease(ps);
  CGFontRef graphics=CTFontCopyGraphicsFont(fonts[i],NULL);REQUIRE(graphics&&CGFontGetUnitsPerEm(graphics)==[[[expected objectAtIndex:i]objectForKey:@"units"]unsignedIntValue],"actual font design units agree with independent input");CGFontRelease(graphics);
  REQUIRE(CTFontGetAscent(fonts[i])>0,"real metric control");printf("MEASURE: fontClass=%s\n",class_getName([(id)fonts[i] class]));
 }
 if(!strcmp(argv[1],"cmap")){
  for(int i=0;i<2;i++)for(NSDictionary *r in [[expected objectAtIndex:i]objectForKey:@"glyphs"]){
   unsigned scalar=[[r objectForKey:@"scalar"]unsignedIntValue];if(scalar>0xffff)continue;
   UniChar c=scalar;CGGlyph glyph=0xffff;BOOL mapped=CTFontGetGlyphsForCharacters(fonts[i],&c,&glyph,1);unsigned wanted=[[r objectForKey:@"glyph"]unsignedIntValue];
   expectReadiness(glyph==wanted&&mapped==(wanted!=0),"actual basic BMP/combining cmap matches independent open-font reference");
  }
  UniChar pair[]={0xd835,0xdd38};struct {unsigned before;CGGlyph glyphs[2];unsigned after;} output={0x13579bdf,{0xffff,0xffff},0x2468ace0};
  BOOL mapped=CTFontGetGlyphsForCharacters(fonts[1],pair,output.glyphs,2);unsigned wanted=[[scalarRecord([expected objectAtIndex:1],0x1d538)objectForKey:@"glyph"]unsignedIntValue];
  printf("MEASURE: supplementary mapped=%d glyphs=%u,%u\n",mapped,output.glyphs[0],output.glyphs[1]);
  expectReadiness(mapped&&(output.glyphs[0]==wanted||output.glyphs[1]==wanted),"covered supplementary scalar maps to its actual glyph without imposing padding order");
  expectReadiness(output.before==0x13579bdf&&output.after==0x2468ace0&&pair[0]==0xd835&&pair[1]==0xdd38,"UTF16 mapping respects declared output capacity and const input");
 }else if(!strcmp(argv[1],"advance")){
  CGFloat sizes[]={20,17.5};for(int i=0;i<2;i++)for(int s=0;s<2;s++){
   CTFontRef sized=CTFontCreateCopyWithAttributes(fonts[i],sizes[s],NULL,NULL);REQUIRE(sized,"real sized font copy");
   double sum=0,actualSum=0;unsigned count=0;CGGlyph batchGlyphs[8];double batchExpected[8];CGSize batchAdvances[8];
   for(NSDictionary *r in [[expected objectAtIndex:i]objectForKey:@"glyphs"]){unsigned g=[[r objectForKey:@"glyph"]unsignedIntValue];if(!g)continue;CGGlyph glyph=g;CGSize advance={0,0};
    double wanted=[[r objectForKey:@"advance"]doubleValue]*sizes[s]/[[[expected objectAtIndex:i]objectForKey:@"units"]doubleValue];
    double actual=CTFontGetAdvancesForGlyphs(sized,kCTFontOrientationHorizontal,&glyph,&advance,1);
    printf("MEASURE: font=%d size=%.3f glyph=%u ideal=%.9f actual=%.9f\n",i,(double)sizes[s],g,wanted,(double)advance.width);
    expectReadiness(fabs(advance.width-wanted)<0.0001&&fabs(advance.height)<0.0001&&fabs(actual-wanted)<0.0001,"public ideal advances scale unhinted design metrics at integer/fractional sizes");REQUIRE(count<8,"bounded independent reference batch");batchGlyphs[count]=glyph;batchExpected[count]=wanted;sum+=wanted;actualSum+=actual;count++;
   }expectReadiness(count>0&&fabs(sum-actualSum)<0.0001,"independent ideal advance sum");
   double batchSum=CTFontGetAdvancesForGlyphs(sized,kCTFontOrientationHorizontal,batchGlyphs,batchAdvances,count);
   double nullSum=CTFontGetAdvancesForGlyphs(sized,kCTFontOrientationHorizontal,batchGlyphs,NULL,count);
   expectReadiness(fabs(batchSum-sum)<0.0001&&fabs(nullSum-sum)<0.0001,"actual batch and NULL-output summed advances match independent design-unit sum");
   for(unsigned j=0;j<count;j++)expectReadiness(fabs(batchAdvances[j].width-batchExpected[j])<0.0001&&fabs(batchAdvances[j].height)<0.0001,"actual batch output preserves each independent glyph advance");
   CFRelease(sized);
  }
 }else if(!strcmp(argv[1],"fallback")){
  REQUIRE([[scalarRecord([expected objectAtIndex:0],0x1d538)objectForKey:@"glyph"]unsignedIntValue]==0&&[[scalarRecord([expected objectAtIndex:1],0x1d538)objectForKey:@"glyph"]unsignedIntValue]!=0,"independent base-absent/fallback-present scalar control");
  CTFontDescriptorRef fallback=CTFontCopyFontDescriptor(fonts[1]);REQUIRE(fallback,"real fallback descriptor");
  NSDictionary *attributes=@{(id)kCTFontCascadeListAttribute:@[(id)fallback]};CTFontDescriptorRef descriptor=CTFontDescriptorCreateWithAttributes((CFDictionaryRef)attributes);
  CGFontRef graphics=CTFontCopyGraphicsFont(fonts[0],NULL);CTFontRef base=CTFontCreateWithGraphicsFont(graphics,17.5,NULL,descriptor);CGFontRelease(graphics);CFRelease(descriptor);CFRelease(fallback);REQUIRE(base,"font owns explicit public cascade");
  CTFontRef same=CTFontCreateForString(base,CFSTR("A"),CFRangeMake(0,1));expectReadiness(same==base,"covered range retains original font per public contract");if(same)CFRelease(same);
  CTFontRef chosen=CTFontCreateForString(base,CFSTR("\U0001d538"),CFRangeMake(0,2));expectReadiness(chosen!=NULL,"explicit cascade supplies supplementary coverage");
  if(chosen){CFStringRef ps=CTFontCopyPostScriptName(chosen);expectReadiness(ps&&[(id)ps isEqual:@"DejaVuSans"]&&CTFontGetSize(chosen)==17.5,"fallback actual face and point size preserved");if(ps)CFRelease(ps);CFRelease(base);CFCharacterSetRef set=CTFontCopyCharacterSet(chosen);expectReadiness(set&&CFCharacterSetIsLongCharacterMember(set,0x1d538),"returned owned fallback outlives original and really covers scalar");if(set)CFRelease(set);CFRelease(chosen);}else CFRelease(base);
 }else if(!strcmp(argv[1],"clusters")){
  CFStringRef texts[]={CFSTR("\u00e9"),CFSTR("e\u0301"),CFSTR("\U0001d538")};double widths[3];
  for(int i=0;i<3;i++){
   NSDictionary *attrs=@{(id)kCTFontAttributeName:(id)fonts[1]};CFAttributedStringRef string=CFAttributedStringCreate(NULL,texts[i],(CFDictionaryRef)attrs);CTLineRef line=CTLineCreateWithAttributedString(string);REQUIRE(line,"actual CoreText line creates");
   widths[i]=CTLineGetTypographicBounds(line,NULL,NULL,NULL);expectReadiness(isfinite(widths[i])&&widths[i]>0,"Unicode line has finite nonzero advance");
   CFArrayRef runs=CTLineGetGlyphRuns(line);REQUIRE(runs,"public glyph-run array exists");expectReadiness(CFArrayGetCount(runs)>0,"actual glyph runs exist");
   for(CFIndex j=0;j<CFArrayGetCount(runs);j++){CTRunRef run=(CTRunRef)CFArrayGetValueAtIndex(runs,j);CFRange range=CTRunGetStringRange(run);CFIndex n=CTRunGetGlyphCount(run);REQUIRE(n>0&&n<16,"bounded real glyph count for tiny test cluster");expectReadiness(range.location>=0&&range.length>0&&range.location+range.length<=CFStringGetLength(texts[i]),"run source range stays within original UTF16 text");CGGlyph *glyphs=calloc(n,sizeof(*glyphs));CFIndex *indices=calloc(n,sizeof(*indices));REQUIRE(glyphs&&indices,"bounded run output arrays");CTRunGetGlyphs(run,CFRangeMake(0,0),glyphs);CTRunGetStringIndices(run,CFRangeMake(0,0),indices);for(CFIndex k=0;k<n;k++)expectReadiness(glyphs[k]!=0&&indices[k]>=0&&indices[k]<CFStringGetLength(texts[i]),"covered cluster has real glyph and original UTF16 index");free(glyphs);free(indices);}
   expectReadiness(CFEqual(CFAttributedStringGetString(string),texts[i]),"layout preserves exact original Unicode text");CFRelease(line);CFRelease(string);
  }printf("MEASURE: exact-open-font canonical widths NFC=%.9f NFD=%.9f delta=%.9f (diagnostic, not native parity)\n",widths[0],widths[1],widths[0]-widths[1]);
 }else REQUIRE(NO,"known explicit mode");
 for(int i=0;i<2;i++)CFRelease(fonts[i]);[pool drain];printf("RESULT: %u failures\n",failures);return failures?1:0;
}
