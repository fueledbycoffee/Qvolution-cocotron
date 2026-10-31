#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#define CHECK(c,m) do { if (!(c)) { fprintf(stderr,"FAIL: %s\n",m); return 1; } } while(0)
int main(int argc,const char **argv) {
 CHECK(argc==3,"provide open NimbusSans-Regular.pfb and generated invalid-UTF8 variant");NSAutoreleasePool *outer=[NSAutoreleasePool new],*creation=[NSAutoreleasePool new];
 NSData *data=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];CHECK(data,"read explicit open Type1 font");CGDataProviderRef provider=CGDataProviderCreateWithCFData((CFDataRef)data);CGFontRef font=CGFontCreateWithDataProvider(provider);
 CHECK(font&&CGFontGetNumberOfGlyphs(font)>100&&CGFontGetUnitsPerEm(font)>0,"actual non-SFNT Type1 metrics");
 CFStringRef ps=CGFontCopyPostScriptName(font),full=CGFontCopyFullName(font);
 CHECK(ps&&[(id)ps isEqual:@"NimbusSans-Regular"]&&full&&[(id)full isEqual:@"Nimbus Sans"],"actual Type1 PostScript and FontInfo full name");
 CGFontRelease(font);CGDataProviderRelease(provider);[creation drain];
 CHECK([(id)ps isEqual:@"NimbusSans-Regular"]&&[(id)full isEqual:@"Nimbus Sans"],"owned Type1 name copies outlive provider/face/pool");CFRelease(ps);CFRelease(full);
 NSAutoreleasePool *negativePool=[NSAutoreleasePool new];
 NSData *invalid=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[2]]];CHECK(invalid,"read original invalid-UTF8 Type1 name vector");
 provider=CGDataProviderCreateWithCFData((CFDataRef)invalid);font=CGFontCreateWithDataProvider(provider);
 CHECK(font&&CGFontGetNumberOfGlyphs(font)>100,"invalid name retains real Type1 glyphs");
 ps=CGFontCopyPostScriptName(font);CHECK(ps&&[(id)ps isEqual:@"NimbusSans-Regular"],"invalid full name preserves independent PS identity");
 full=CGFontCopyFullName(font);CHECK(full==NULL,"unsupported invalid-UTF8 Type1 full name is absent without conversion exception");
 CFRelease(ps);CGFontRelease(font);CGDataProviderRelease(provider);[negativePool drain];[outer drain];
 puts("PASS: actual open Type1 metadata copies, ownership and invalid name conversion");return 0;
}
