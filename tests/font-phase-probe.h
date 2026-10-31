#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#define PHASE_W 256
#define PHASE_H 160
#define REQUIRE(c, message) do { if (!(c)) { fprintf(stderr,"FAIL: %s\n",message); return 1; } } while (0)
typedef struct { double mass,x,y; uint8_t alpha[PHASE_W*PHASE_H]; } PhaseMask;
typedef enum {PhaseDefault,PhaseEnabled,PhaseOff,PhaseAllowOff,PhaseQuantized,PhaseQuantAllowOff,PhaseRestoreShould,PhaseRestoreAllow,PhaseRestoreQuant,PhaseAAOff,PhaseAAAllowOff} PhaseMode;
static void phaseConfigure(CGContextRef c,PhaseMode mode) {
    if(mode==PhaseDefault)return;
    CGContextSetAllowsFontSubpixelPositioning(c,true); CGContextSetShouldSubpixelPositionFonts(c,true);
    CGContextSetAllowsFontSubpixelQuantization(c,true); CGContextSetShouldSubpixelQuantizeFonts(c,false);
    if(mode==PhaseAAOff)CGContextSetShouldAntialias(c,false);
    if(mode==PhaseAAAllowOff)CGContextSetAllowsAntialiasing(c,false);
    if(mode==PhaseOff)CGContextSetShouldSubpixelPositionFonts(c,false);
    if(mode==PhaseAllowOff)CGContextSetAllowsFontSubpixelPositioning(c,false);
    if(mode==PhaseQuantized)CGContextSetShouldSubpixelQuantizeFonts(c,true);
    if(mode==PhaseQuantAllowOff){CGContextSetShouldSubpixelQuantizeFonts(c,true);CGContextSetAllowsFontSubpixelQuantization(c,false);}
    if(mode==PhaseRestoreShould){CGContextSaveGState(c);CGContextSetShouldSubpixelPositionFonts(c,false);CGContextRestoreGState(c);}
    if(mode==PhaseRestoreAllow){CGContextSaveGState(c);CGContextSetAllowsFontSubpixelPositioning(c,false);CGContextRestoreGState(c);}
    if(mode==PhaseRestoreQuant){CGContextSaveGState(c);CGContextSetShouldSubpixelQuantizeFonts(c,true);CGContextRestoreGState(c);}
}
static CGFontRef phaseLoadFont(const char *path,CGGlyph *glyph) {
    NSData *data=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:path]];
    if(!data)return NULL;
    FT_Library lib;FT_Face face;
    if(FT_Init_FreeType(&lib))return NULL;
    if(FT_New_Memory_Face(lib,[data bytes],[data length],0,&face)){FT_Done_FreeType(lib);return NULL;}
    const char *name=FT_Get_Postscript_Name(face);
    if(!name||strcmp(name,"DejaVuSans")||strcmp(face->family_name,"DejaVu Sans")){FT_Done_Face(face);FT_Done_FreeType(lib);return NULL;}
    *glyph=FT_Get_Char_Index(face,'f'); FT_Done_Face(face);FT_Done_FreeType(lib);
    if(!*glyph)return NULL;
    CGDataProviderRef dataProvider=CGDataProviderCreateWithCFData((CFDataRef)data);
    CGFontRef result=CGFontCreateWithDataProvider(dataProvider);CGDataProviderRelease(dataProvider);return result;
}
static CGContextRef phaseContext(uint8_t *bytes,CGFontRef font,double scale,PhaseMode mode) {
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef c=CGBitmapContextCreate(bytes,PHASE_W,PHASE_H,8,PHASE_W*4,space,kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space); if(!c)return NULL;
    CGContextSetAllowsAntialiasing(c,true);CGContextSetShouldAntialias(c,true);
    phaseConfigure(c,mode);CGContextScaleCTM(c,scale,scale);CGContextSetRGBFillColor(c,0,0,0,1);
    CGContextSetFont(c,font);CGContextSetFontSize(c,28);CGContextSetTextMatrix(c,CGAffineTransformIdentity);return c;
}
static int phaseRender(CGFontRef font,CGGlyph glyph,double scale,double x,double y,double tx,PhaseMode mode,PhaseMask *out) {
    uint8_t *bytes=calloc(PHASE_W*PHASE_H,4);if(!bytes)return 0;
    CGContextRef c=phaseContext(bytes,font,scale,mode);if(!c){free(bytes);return 0;}
    CGContextTranslateCTM(c,tx,0);CGContextSetTextPosition(c,x,y);CGSize advance=CGSizeMake(0,0);CGContextShowGlyphsWithAdvances(c,&glyph,&advance,1);
    memset(out,0,sizeof(*out));for(int row=0;row<PHASE_H;row++)for(int col=0;col<PHASE_W;col++) {
        uint8_t a=bytes[(row*PHASE_W+col)*4+3];out->alpha[row*PHASE_W+col]=a;out->mass+=a;out->x+=a*(col+.5);out->y+=a*(row+.5);
    }
    CGContextRelease(c);free(bytes);if(out->mass==0)return 0;out->x/=out->mass;out->y/=out->mass;return 1;
}
static int phaseEqual(const PhaseMask *a,const PhaseMask *b){return !memcmp(a->alpha,b->alpha,sizeof(a->alpha));}
static double phaseNow(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
