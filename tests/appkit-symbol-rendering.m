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
static unsigned inkCount(const unsigned char *p){unsigned n=0;for(unsigned i=0;i<SIDE*SIDE;i++)if(p[i*4+3]>128)n++;return n;}
static unsigned regionInk(const unsigned char *p,unsigned x,unsigned y,unsigned w,unsigned h){unsigned n=0;for(unsigned j=y;j<y+h;j++)for(unsigned i=x;i<x+w;i++)if(p[(j*SIDE+i)*4+3]>128)n++;return n;}
int main(void){
 setbuf(stdout,NULL);puts("ENTER: original portable symbol geometry/configuration");NSAutoreleasePool *pool=[NSAutoreleasePool new];[NSApplication sharedApplication];
 NSImage *plus=[NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:nil],*minus=[NSImage imageWithSystemSymbolName:@"minus" accessibilityDescription:nil],*gear=[NSImage imageWithSystemSymbolName:@"gearshape" accessibilityDescription:nil];
 unsigned char a[SIDE*SIDE*4],b[SIDE*SIDE*4],c[SIDE*SIDE*4];raster(plus,a);raster(minus,b);raster(gear,c);
 expectResult(inkCount(a)>20&&inkCount(b)>20&&inkCount(c)>20,"real known images render ink");
 expectResult(regionInk(a,29,17,6,8)>10&&regionInk(b,29,17,6,8)==0,"plus has vertical arm absent from minus");
 expectResult(regionInk(a,17,29,8,6)>10&&regionInk(b,17,29,8,6)>10,"both plus and minus have horizontal arm");
 expectResult(regionInk(c,30,30,4,4)==0&&regionInk(a,30,30,4,4)>0,"gear center hole differs from plus cross");
 NSArray *names=@[@"gearshape",@"gearshape.2",@"folder",@"person",@"list.bullet",@"plus",@"minus",@"xmark",@"checkmark",@"magnifyingglass",@"trash",@"folder.badge.plus",@"multiply.circle.fill",@"chevron.backward"];
 for(NSString *name in names){NSImage *i=[NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];raster(i,a);expectResult(i&&inkCount(a)>10,"allowlisted documented symbol produces actual artwork");}
 expectResult([NSImage imageWithSystemSymbolName:@"plus.thisVariantDoesNotExist" accessibilityDescription:nil]==nil,"unknown variant is unavailable without suffix synthesis");
 NSImageSymbolConfiguration *light=[NSImageSymbolConfiguration configurationWithPointSize:16 weight:NSFontWeightUltraLight],*heavy=[NSImageSymbolConfiguration configurationWithPointSize:16 weight:NSFontWeightHeavy];
 raster([plus imageWithSymbolConfiguration:light],a);raster([plus imageWithSymbolConfiguration:heavy],b);printf("MEASURE: lightInk=%u heavyInk=%u\n",inkCount(a),inkCount(b));expectResult(inkCount(b)>inkCount(a),"requested weight changes actual stroke ink");
 NSMutableArray *colors=[NSMutableArray arrayWithObjects:[NSColor redColor],[NSColor blueColor],nil];
 NSImageSymbolConfiguration *palette=[NSImageSymbolConfiguration configurationWithPaletteColors:colors];[colors replaceObjectAtIndex:0 withObject:[NSColor greenColor]];
 NSImage *two=[[NSImage imageWithSystemSymbolName:@"gearshape.2" accessibilityDescription:nil] imageWithSymbolConfiguration:palette];raster(two,a);
 unsigned red=0,blue=0;for(unsigned i=0;i<SIDE*SIDE;i++){const unsigned char *p=a+i*4;if(p[3]>128&&p[0]>p[2]+40)red++;if(p[3]>128&&p[2]>p[0]+40)blue++;}
 printf("MEASURE: red=%u blue=%u\n",red,blue);expectResult(red>10&&blue>10,"copied palette affects actual primary and secondary semantic layers");expectResult([plus isTemplate]&&![two isTemplate],"monochrome template and explicit palette retain distinct rendering intent");
 NSAppearance *dark=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua],*lightAppearance=[NSAppearance appearanceNamed:NSAppearanceNameAqua];
 __block struct {unsigned char dark[SIDE*SIDE*4],light[SIDE*SIDE*4],repeat[SIDE*SIDE*4];} appearancePixels;
 unsigned char *destinationBytes=calloc(SIDE*SIDE,4);CGColorSpaceRef rgb=CGColorSpaceCreateDeviceRGB();
 CGContextRef destination=CGBitmapContextCreate(destinationBytes,SIDE,SIDE,8,SIDE*4,rgb,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
 if(!destination||!destinationBytes)return 2;
 NSGraphicsContext *graphics=[[NSGraphicsContext graphicsContextWithGraphicsPort:destination flipped:NO]retain];
 [NSGraphicsContext saveGraphicsState];
 @try{
  [NSGraphicsContext setCurrentContext:graphics];
  void (^drawCurrent)(void)=^{CGContextClearRect(destination,CGRectMake(0,0,SIDE,SIDE));[plus drawInRect:NSMakeRect(0,0,SIDE,SIDE) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1];};
  [lightAppearance performAsCurrentDrawingAppearance:^{drawCurrent();memcpy(appearancePixels.light,destinationBytes,SIDE*SIDE*4);}];
  [lightAppearance performAsCurrentDrawingAppearance:^{drawCurrent();memcpy(appearancePixels.repeat,destinationBytes,SIDE*SIDE*4);}];
  expectResult(difference(appearancePixels.light,appearancePixels.repeat)==0,"same destination and appearance repeat preserve artwork");
  [dark performAsCurrentDrawingAppearance:^{drawCurrent();memcpy(appearancePixels.dark,destinationBytes,SIDE*SIDE*4);}];
  [dark performAsCurrentDrawingAppearance:^{drawCurrent();memcpy(appearancePixels.repeat,destinationBytes,SIDE*SIDE*4);}];
  expectResult(difference(appearancePixels.dark,appearancePixels.repeat)==0,"dark repeat on same destination preserves artwork");
  [lightAppearance performAsCurrentDrawingAppearance:^{drawCurrent();memcpy(appearancePixels.repeat,destinationBytes,SIDE*SIDE*4);}];
  expectResult(difference(appearancePixels.light,appearancePixels.repeat)==0,"same destination Aqua-Dark-Aqua restores initial artwork");
 }@finally{[NSGraphicsContext restoreGraphicsState];[graphics release];CGContextRelease(destination);CGColorSpaceRelease(rgb);}
 unsigned long lightSum=0,darkSum=0;for(unsigned i=0;i<SIDE*SIDE;i++){lightSum+=appearancePixels.light[i*4]+appearancePixels.light[i*4+1]+appearancePixels.light[i*4+2];darkSum+=appearancePixels.dark[i*4]+appearancePixels.dark[i*4+1]+appearancePixels.dark[i*4+2];}
 expectResult(darkSum>lightSum,"same-destination monochrome artwork resolves semantic foreground under dark appearance");
 [pool drain];free(destinationBytes);printf("RESULT: %u failures\n",failures);return failures?1:0;
}
