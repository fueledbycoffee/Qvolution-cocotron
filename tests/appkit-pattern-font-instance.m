// Original public legacy-pattern client; run with caller-owned private FONTCONFIG_FILE.
#import <AppKit/AppKit.h>
#import <CoreText/CoreText.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#define INPUT(c,m) do{if(!(c)){fprintf(stderr,"INPUT FAIL: %s\n",m);return 2;}}while(0)
static NSString *ps(NSFont *font){return [(id)CTFontCopyPostScriptName((CTFontRef)font)autorelease];}
static double width(NSFont *font){UniChar w='W';CGGlyph glyph=0;CGSize size=CGSizeZero;if(!font||!CTFontGetGlyphsForCharacters((CTFontRef)font,&w,&glyph,1)||!glyph)return NAN;return CTFontGetAdvancesForGlyphs((CTFontRef)font,kCTFontOrientationHorizontal,&glyph,&size,1);}
int main(void){@autoreleasepool{
 setbuf(stdout,NULL);INPUT(getenv("FONTCONFIG_FILE"),"caller supplies isolated open-font Fontconfig policy");[NSApplication sharedApplication];
 NSString *patterns[]={@"Ubuntu:style=Regular",@"Ubuntu:style=Bold",@"Ubuntu:style=Bold Italic",@"Ubuntu:style=Condensed Bold"};
 NSString *names[]={@"Ubuntu-Regular",@"Ubuntu-Bold",@"UbuntuItalic-BoldItalic",@"Ubuntu-CondensedBold"};double widths[]={924,942,931,721};unsigned failures=0;
 for(unsigned i=0;i<4;i++){
  NSFont *reference=[NSFont fontWithName:names[i]size:1000];INPUT(reference&&[ps(reference)isEqual:names[i]]&&fabs(width(reference)-widths[i])<.001,"exact actual named-instance loading/metrics positive control");
  NSFont *pattern=[NSFont fontWithName:patterns[i]size:1000];BOOL good=pattern&&[ps(pattern)isEqual:names[i]]&&fabs(width(pattern)-widths[i])<.001;
  printf("%s: pattern=%s actualPS=%s W=%.6f expectedPS=%s W=%.6f\n",good?"PASS":"FAIL",[patterns[i]UTF8String],[ps(pattern)UTF8String],width(pattern),[names[i]UTF8String],widths[i]);failures+=!good;
 }
 printf("RESULT %u failures\n",failures);return failures?1:0;
}}
