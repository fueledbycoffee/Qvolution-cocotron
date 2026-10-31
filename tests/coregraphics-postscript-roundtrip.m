// Original name/metric contract using explicit open provider fonts.
#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdio.h>
#define CHECK(c,m) do{if(!(c)){fprintf(stderr,"FAIL %s\n",m);return 1;}}while(0)
static CGFontRef provider(const char *path){NSData *bytes=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:path]];if(!bytes)return NULL;CGDataProviderRef data=CGDataProviderCreateWithCFData((CFDataRef)bytes);if(!data)return NULL;CGFontRef font=CGFontCreateWithDataProvider(data);CGDataProviderRelease(data);return font;}
struct metrics{CGSize advance[6];};
static int measure(CTFontRef font,struct metrics *m){UniChar chars[]={'A','i','W','m','0','f'};CGGlyph glyph[6];if(!font||!CTFontGetGlyphsForCharacters(font,chars,glyph,6))return 0;double total=CTFontGetAdvancesForGlyphs(font,kCTFontOrientationHorizontal,glyph,m->advance,6);if(!isfinite(total)||total<=0)return 0;for(int i=0;i<6;i++)if(!glyph[i]||!isfinite(m->advance[i].width)||!isfinite(m->advance[i].height)||m->advance[i].width<=0)return 0;return 1;}
static int same(struct metrics *a,struct metrics *b){for(int i=0;i<6;i++)if(fabs(a->advance[i].width-b->advance[i].width)>0.00001||fabs(a->advance[i].height-b->advance[i].height)>0.00001)return 0;return 1;}
int main(int argc,char**argv){@autoreleasepool{
 CHECK(argc==3||argc==4,"explicit DejaVuSans-BoldOblique.ttf then DejaVuSans.ttf");
 fprintf(stderr,"PHASE enter explicit providers\n");CGFontRef bold=provider(argv[1]),regular=provider(argv[2]);CHECK(bold&&regular,"actual explicit open font providers");CFStringRef ps=CGFontCopyPostScriptName(bold),regularPS=CGFontCopyPostScriptName(regular);CHECK(ps&&regularPS&&CFEqual(ps,CFSTR("DejaVuSans-BoldOblique"))&&CFEqual(regularPS,CFSTR("DejaVuSans")),"real provider-name prerequisite rejects substitutes/request labels");
 CTFontRef expected=CTFontCreateWithGraphicsFont(bold,17.25,NULL,NULL),plain=CTFontCreateWithGraphicsFont(regular,17.25,NULL,NULL);struct metrics reference,plainMetrics;CHECK(measure(expected,&reference)&&measure(plain,&plainMetrics),"real finite provider glyph metric controls");CHECK(!same(&reference,&plainMetrics),"boldoblique actual metrics distinguish regular substitute");fprintf(stderr,"PHASE return explicit providers\n");
 fprintf(stderr,"PHASE enter named graphics\n");CGFontRef named=CGFontCreateWithFontName(ps);CHECK(named,"named graphics creation");CFStringRef actualPS=CGFontCopyPostScriptName(named);CHECK(actualPS&&CFEqual(actualPS,ps),"available exact PostScript name resolves same actual face");CTFontRef fromCG=CTFontCreateWithGraphicsFont(named,17.25,NULL,NULL);struct metrics cgMetrics;CHECK(measure(fromCG,&cgMetrics)&&same(&reference,&cgMetrics),"named graphics actual glyph metrics equal explicit bold provider");fprintf(stderr,"PHASE return named graphics\n");
 fprintf(stderr,"PHASE enter named CoreText\n");CTFontRef fromName=CTFontCreateWithName(ps,17.25,NULL);CHECK(fromName,"named CoreText creation");CFStringRef ctPS=CTFontCopyPostScriptName(fromName);CHECK(ctPS&&CFEqual(ctPS,ps),"CoreText exact available PostScript identity preserved");struct metrics ctMetrics;CHECK(measure(fromName,&ctMetrics)&&same(&reference,&ctMetrics),"named CoreText actual glyph metrics equal explicit bold provider");fprintf(stderr,"PHASE return named CoreText\n");
 const CFStringRef legacy[]={CFSTR("sans-serif"),CFSTR("DejaVu Sans:weight=bold"),CFSTR("")};
 for(unsigned i=0;i<3;i++){CGFontRef g=CGFontCreateWithFontName(legacy[i]);CHECK(g&&CGFontGetNumberOfGlyphs(g)>0,"legacy generic/family-pattern/default remains real font");CGFontRelease(g);}
 UniChar invalidName[]={'D','e','j','a','V','u',0,'X'};CFStringRef invalid=CFStringCreateWithCharacters(NULL,invalidName,8);CHECK(invalid&&!CGFontCreateWithFontName(invalid),"embedded NUL request never selects truncated name");CFRelease(invalid);
 if(argc==4){CGFontRef nonunicode=provider(argv[3]);CHECK(nonunicode&&CGFontGetNumberOfGlyphs(nonunicode)>0,"original non-Unicode provider remains valid graphics font");CGFontRelease(nonunicode);}
 CFRelease(ctPS);CFRelease(fromName);CFRelease(fromCG);CFRelease(actualPS);CGFontRelease(named);CFRelease(expected);CFRelease(plain);CFRelease(ps);CFRelease(regularPS);CGFontRelease(bold);CGFontRelease(regular);
 puts("PASS actual available PostScript-name identity and bold-provider glyph metrics; no descriptor/app qualification");return 0;
}}
