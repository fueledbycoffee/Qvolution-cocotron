#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#define CHECK(c,m) do { if (!(c)) { fprintf(stderr,"FAIL: %s\n",m); return 1; } } while(0)
int main(int argc,const char **argv) {
 CHECK(argc==2,"provide generated name-vector directory");NSAutoreleasePool *pool=[NSAutoreleasePool new];
 NSString *modes[]={@"missing",@"odd-utf16",@"bad-surrogate",@"unsupported",@"empty",@"unicode-unknown",@"unicode-variation",@"unicode",@"macroman",@"english-preference"};
 for(int i=0;i<10;i++) {
  NSString *path=[[NSString stringWithUTF8String:argv[1]] stringByAppendingPathComponent:[modes[i] stringByAppendingString:@".ttf"]];
  NSData *data=[NSData dataWithContentsOfFile:path];CHECK(data,"read generated font vector");CGDataProviderRef provider=CGDataProviderCreateWithCFData((CFDataRef)data);CGFontRef font=CGFontCreateWithDataProvider(provider);
  CHECK(font&&CGFontGetNumberOfGlyphs(font)>100&&CGFontGetUnitsPerEm(font)>0,"glyph/metric data remains real and independent of malformed name");
  CFStringRef ps=CGFontCopyPostScriptName(font);CHECK(ps&&[(id)ps isEqual:@"DejaVuSans-BoldOblique"],"unchanged PostScript identity control");
  CFStringRef full=CGFontCopyFullName(font);
  if(i<7) CHECK(full==NULL,"unavailable, odd, unpaired-surrogate, unsupported or empty full name is absent");
  else CHECK(full&&[(id)full isEqual:(i==7?@"\U0001d11e Full":i==8?@"Fixture Mac Romé":@"English Preferred")],"explicit supplementary Unicode, high-byte MacRoman and English-over-fallback preference");
  CFRelease(ps);if(full)CFRelease(full);CGFontRelease(font);CGDataProviderRelease(provider);
 }
 [pool drain];puts("PASS: real font name absence, malformed rejection and explicit encodings");return 0;
}
