// Original bounded construction/cache-payload/advance workload; no native performance claim.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>
#import <Onyx2D/O2Font.h>
#include <stdio.h>
#include <time.h>
#include <math.h>
@interface O2Font (QVCostObservation)
- (NSUInteger)qvAdvancePayload;
@end
@implementation O2Font (QVCostObservation)
- (NSUInteger)qvAdvancePayload { return _advances ? (NSUInteger)_numberOfGlyphs*sizeof(NSInteger) : 0; }
@end
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
int main(int argc,char **argv){@autoreleasepool{
 setbuf(stdout,NULL);if(argc!=4){fprintf(stderr,"usage: probe Mono.ttf Sans.ttf large-CJK.ttc\n");return 2;}
 for(int input=1;input<4;input++){
  NSData *data=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[input]]];if(!data)return 2;
  CGDataProviderRef provider=CGDataProviderCreateWithCFData((CFDataRef)data);if(!provider)return 2;
  double begin=now();CGFontRef graphics=NULL;NSUInteger bytes=0;size_t glyphCount=0;
  for(unsigned n=0;n<10;n++){@autoreleasepool{
   CGFontRef font=CGFontCreateWithDataProvider(provider);if(!font)return 2;
   CFStringRef name=CGFontCopyPostScriptName(font);glyphCount=CGFontGetNumberOfGlyphs(font);
   if(!name||glyphCount==0||CGFontGetUnitsPerEm(font)<=0)return 2;
   bytes=[(O2Font *)font qvAdvancePayload];
   if(n==9){graphics=font;printf("INPUT %d PS=%s glyphs=%zu cache_payload_bytes=%lu\n",input,[(id)name UTF8String],glyphCount,(unsigned long)bytes);}else CGFontRelease(font);
   CFRelease(name);
  }}
  double construction=now()-begin;
  CTFontRef font=CTFontCreateWithGraphicsFont(graphics,17.5,NULL,NULL);if(!font)return 2;
  UniChar text[]={'A','W','e'};CGGlyph glyphs[3]={0};CGSize widths[3];
  if(!CTFontGetGlyphsForCharacters(font,text,glyphs,3))return 2;
  begin=now();volatile double sum=0;
  for(unsigned repeat=0;repeat<10000;repeat++)sum+=CTFontGetAdvancesForGlyphs(font,kCTFontOrientationHorizontal,glyphs,widths,3);
  double query=now()-begin;if(!isfinite(sum)||sum<=0)return 1;
  printf("MEASURE input=%d construction10_seconds=%.9f query30000glyph_seconds=%.9f checksum=%.9f\n",input,construction,query,(double)sum);
  CFRelease(font);CGFontRelease(graphics);CGDataProviderRelease(provider);
 }
 puts("PASS: bounded font cost workload completed");return 0;
}}
