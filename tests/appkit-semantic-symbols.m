#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>
#define SIDE 64
static unsigned failures;
static void expectResult(BOOL ok,const char *what){printf("%s: %s\n",ok?"PASS":"FAIL",what);if(!ok)failures++;}
static void raster(NSImage *image,unsigned char *out){
    memset(out,0,SIDE*SIDE*4);CGColorSpaceRef rgb=CGColorSpaceCreateDeviceRGB();
    CGContextRef c=CGBitmapContextCreate(out,SIDE,SIDE,8,SIDE*4,rgb,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    if(!c)exit(2);[NSGraphicsContext saveGraphicsState];
    @try{[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithGraphicsPort:c flipped:NO]];[image drawInRect:NSMakeRect(0,0,SIDE,SIDE) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1];}
    @finally{[NSGraphicsContext restoreGraphicsState];CGContextRelease(c);CGColorSpaceRelease(rgb);}
}
static unsigned difference(const unsigned char *a,const unsigned char *b){unsigned n=0;for(unsigned i=0;i<SIDE*SIDE;i++)if(memcmp(a+i*4,b+i*4,4))n++;return n;}
int main(void){
    setbuf(stdout,NULL);puts("ENTER: original semantic symbol raster");NSAutoreleasePool *pool=[NSAutoreleasePool new];[NSApplication sharedApplication];
    expectResult([NSImage imageWithSystemSymbolName:@"" accessibilityDescription:nil]==nil,"empty symbol unavailable");
    expectResult([NSImage imageWithSystemSymbolName:@"qvolution.original.unknown.symbol.9271" accessibilityDescription:nil]==nil,"unknown nonempty symbol unavailable");
    NSMutableString *name=[[NSMutableString alloc]initWithString:@"plus"];
    NSImage *plus=[[NSImage imageWithSystemSymbolName:name accessibilityDescription:@"Add"]retain];[name setString:@"minus"];[name release];
    NSImage *minus=[[NSImage imageWithSystemSymbolName:@"minus" accessibilityDescription:@"Remove"]retain];
    NSImage *gear=[[NSImage imageWithSystemSymbolName:@"gearshape" accessibilityDescription:@"Settings"]retain];
    expectResult(plus&&minus&&gear,"documented symbols return images");
    unsigned char a[SIDE*SIDE*4],b[SIDE*SIDE*4],c[SIDE*SIDE*4],copyPixels[SIDE*SIDE*4];raster(plus,a);raster(minus,b);raster(gear,c);
    unsigned ink=0;for(unsigned i=0;i<SIDE*SIDE;i++)if(a[i*4+3])ink++;
    expectResult(ink>20,"known symbol actually draws nonempty pixels");
    unsigned pm=difference(a,b),pg=difference(a,c),mg=difference(b,c);printf("MEASURE: ink=%u plus-minus=%u plus-gear=%u minus-gear=%u\n",ink,pm,pg,mg);
    expectResult(pm>20&&pg>20&&mg>20,"plus minus gear have distinct actual artwork; constant-glyph negative control rejected");
    NSImage *copy=[plus copy];raster(copy,copyPixels);expectResult(difference(a,copyPixels)==0,"copy preserves requested image artwork after mutable input changed");
    expectResult([[copy accessibilityDescription]isEqualToString:@"Add"],"copy preserves accessibility metadata");
    NSImageSymbolConfiguration *small=[NSImageSymbolConfiguration configurationWithPointSize:18 weight:NSFontWeightBold scale:NSImageSymbolScaleSmall];
    NSImageSymbolConfiguration *large=[NSImageSymbolConfiguration configurationWithScale:NSImageSymbolScaleLarge];
    NSImage *configured=[[plus imageWithSymbolConfiguration:small]retain];NSImage *scaled=[[configured imageWithSymbolConfiguration:large]retain];
    expectResult(configured!=nil&&scaled!=nil&&scaled!=configured,"configuration makes independent image");
    expectResult([[scaled symbolConfiguration]isEqual:[small configurationByApplyingConfiguration:large]],"scale configuration preserves prior attributes by immutable merge");
    NSImage *sameConfiguredMinus=[[[minus imageWithSymbolConfiguration:small] imageWithSymbolConfiguration:large]retain];
    unsigned char matchingMinus[SIDE*SIDE*4];raster(sameConfiguredMinus,matchingMinus);
    raster(scaled,copyPixels);expectResult(difference(copyPixels,matchingMinus)>20,"reconfiguration preserves plus identity versus identically configured minus");
    NSAutoreleasePool *nested=[NSAutoreleasePool new];NSImage *survivor=[[gear imageWithSymbolConfiguration:large]retain];NSImage *matchingLifetimeMinus=[[minus imageWithSymbolConfiguration:large]retain];[nested drain];raster(survivor,copyPixels);raster(matchingLifetimeMinus,matchingMinus);expectResult(difference(copyPixels,matchingMinus)>20,"configured retained image survives nested pool with identity versus same configured minus");[matchingLifetimeMinus release];
    [sameConfiguredMinus release];[survivor release];[scaled release];[configured release];[copy release];[plus release];[minus release];[gear release];[pool drain];printf("RESULT: %u failures\n",failures);return failures?1:0;
}
