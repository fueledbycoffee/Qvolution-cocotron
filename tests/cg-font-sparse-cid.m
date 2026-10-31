// Original CGFont provider contract over locally generated licensed open sparseCID data.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#define REQUIRE(c,m) do{if(!(c)){fprintf(stderr,"FAIL: %s\n",m);return 1;}}while(0)
int main(int argc,char **argv){@autoreleasepool{
 setbuf(stdout,NULL);REQUIRE(argc==2,"original generated sparseCID CFF path");
 NSData *data=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];REQUIRE(data&&[data length]>0,"original fixture data exists");
 CGDataProviderRef provider=CGDataProviderCreateWithCFData((CFDataRef)data);REQUIRE(provider,"actual provider");
 puts("ENTER: actual CGFontCreateWithDataProvider sparseCID");CGFontRef font=CGFontCreateWithDataProvider(provider);CGDataProviderRelease(provider);REQUIRE(font,"valid charmapless sparseCID provider accepted");
 CFStringRef ps=CGFontCopyPostScriptName(font);REQUIRE(ps&&[(id)ps isEqualToString:@"QvolutionSparseCID"],"actual provider PostScript identity");CFRelease(ps);
 REQUIRE(CGFontGetNumberOfGlyphs(font)==1001&&CGFontGetUnitsPerEm(font)==1000,"actual sparseCID bounds/designunits");
 CGGlyph glyphs[]={0,34,1000};int expected[]={1000,608,1000},advances[3]={-1,-1,-1};
 REQUIRE(CGFontGetGlyphAdvances(font,glyphs,3,advances),"actual reachableCID advance query");
 for(unsigned i=0;i<3;i++)REQUIRE(advances[i]==expected[i],"reachableCID advance agrees independent native openfont reference");
 CGGlyph holes[][3]={{0,1,34},{0,33,1000},{0,35,34},{0,999,1000},{0,1001,34}};
 for(unsigned h=0;h<sizeof(holes)/sizeof(*holes);h++){
  advances[0]=advances[1]=advances[2]=-7;
  REQUIRE(!CGFontGetGlyphAdvances(font,holes[h],3,advances),"missingCID rejects whole request");
  REQUIRE(advances[0]==-7&&advances[1]==-7&&advances[2]==-7,"missingCID never partially writes output");
 }
 CGFontRelease(font);puts("PASS: charmapless sparseCID creation and real reachable metrics");return 0;
}}
