#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>
static unsigned failures;
#define CHECK(c,message) do {if(!(c)){fprintf(stderr,"FAIL: %s\n",message);failures++;}}while(0)
static void drawDocument(NSTextView *view,unsigned char output[4]) {
    unsigned char bytes[16*80];memset(bytes,0xa5,sizeof bytes);
    CGColorSpaceRef rgb=CGColorSpaceCreateDeviceRGB();
    CGContextRef c=CGBitmapContextCreate(bytes,16,16,8,80,rgb,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    if(!c){fputs("FAIL: bitmap allocation\n",stderr);exit(1);}
    [NSGraphicsContext saveGraphicsState];
    @try {
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithGraphicsPort:c flipped:NO]];
        [view drawRect:[view bounds]]; // Real empty document path, not a replacement drawRect.
        memcpy(output,bytes+8*80+8*4,4);
    } @finally {[NSGraphicsContext restoreGraphicsState];CGContextRelease(c);CGColorSpaceRelease(rgb);}
    for(unsigned y=0;y<16;y++)for(unsigned x=64;x<80;x++)CHECK(bytes[y*80+x]==0xa5,"document drawing preserves row padding");
}
static void swatch(NSColor *color,unsigned char output[4]) {
    memset(output,0,4);CGColorSpaceRef rgb=CGColorSpaceCreateDeviceRGB();
    CGContextRef c=CGBitmapContextCreate(output,1,1,8,4,rgb,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    if(!c || !color){fputs("FAIL: color setup\n",stderr);exit(1);}
    CGContextSetFillColorWithColor(c,[color CGColor]);CGContextFillRect(c,CGRectMake(0,0,1,1));
    CGContextRelease(c);CGColorSpaceRelease(rgb);
}
static double lightness(const unsigned char *p){return(p[0]+p[1]+p[2])/(3.0*255);}
static BOOL near(const unsigned char*a,const unsigned char*b){for(unsigned i=0;i<4;i++){int d=(int)a[i]-b[i];if(d < -1||d>1)return NO;}return YES;}
int main(void){
    NSAutoreleasePool *pool=[NSAutoreleasePool new];
    NSTextView *view=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,16,16)];
    NSAppearance *aqua=[NSAppearance appearanceNamed:NSAppearanceNameAqua],*dark=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    __block struct {unsigned char lightBG[4],darkBG[4],lightCaret[4],darkCaret[4],expectedBG[4],again[4],explicitBG[4],explicitCaret[4],explicitText[4];} p;
    [aqua performAsCurrentDrawingAppearance:^{drawDocument(view,p.lightBG);swatch([view insertionPointColor],p.lightCaret);}];
    [dark performAsCurrentDrawingAppearance:^{drawDocument(view,p.darkBG);swatch([view insertionPointColor],p.darkCaret);swatch([NSColor textBackgroundColor],p.expectedBG);}];
    CHECK(lightness(p.darkBG)<lightness(p.lightBG)-.4,"default document background adapts darker");
    CHECK(lightness(p.darkCaret)>lightness(p.lightCaret)+.4,"default insertion color adapts brighter");
    CHECK(lightness(p.darkCaret)-lightness(p.darkBG)>.5,"default insertion color remains distinct from document surface");
    CHECK(near(p.darkBG,p.expectedBG),"actual default draw follows semantic text background");
    [aqua performAsCurrentDrawingAppearance:^{drawDocument(view,p.again);}];
    CHECK(near(p.again,p.lightBG),"default Aqua draw restores without rebuilding view");
    NSColor *background=[NSColor colorWithCalibratedRed:.2 green:.4 blue:.7 alpha:1];
    NSColor *caret=[NSColor colorWithCalibratedRed:.8 green:.3 blue:.1 alpha:1];
    NSColor *text=[NSColor colorWithCalibratedRed:.15 green:.6 blue:.25 alpha:1];
    [view setBackgroundColor:background];[view setInsertionPointColor:caret];
    [view setString:@"User"];[view setTextColor:text range:NSMakeRange(0,4)];
    [aqua performAsCurrentDrawingAppearance:^{swatch(background,p.explicitBG);swatch(caret,p.explicitCaret);swatch(text,p.explicitText);}];
    [dark performAsCurrentDrawingAppearance:^{
        swatch([view backgroundColor],p.again);CHECK(near(p.again,p.explicitBG),"explicit document background preserved");
        swatch([view insertionPointColor],p.again);CHECK(near(p.again,p.explicitCaret),"explicit caret color preserved");
        NSColor *stored=[[view textStorage] attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
        swatch(stored,p.again);CHECK(near(p.again,p.explicitText),"explicit attributed document text color preserved");
    }];
    [view release];[pool drain];
    if(!failures)puts("PASS: semantic text defaults draw adaptively and preserve explicit document colors");return failures?1:0;
}
