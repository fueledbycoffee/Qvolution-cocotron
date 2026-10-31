#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define WIDTH 256
#define HEIGHT 160
#define CHECK(c, message) do { if (!(c)) { fprintf(stderr,"FAIL: %s\n",message); return 2; } } while (0)
typedef struct { double coverage, x, y; uint8_t alpha[WIDTH*HEIGHT]; } Measurement;
static int render(CGFontRef font, CGGlyph glyph, double scale, double origin, Measurement *result) {
    uint8_t *pixels=calloc(WIDTH*HEIGHT,4);
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(pixels,WIDTH,HEIGHT,8,WIDTH*4,space,kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    if (!context || !pixels) { free(pixels); return 0; }
    CGContextSetAllowsAntialiasing(context,true); CGContextSetShouldAntialias(context,true);
    CGContextSetAllowsFontSubpixelPositioning(context,true); CGContextSetShouldSubpixelPositionFonts(context,true);
    CGContextSetAllowsFontSubpixelQuantization(context,false); CGContextSetShouldSubpixelQuantizeFonts(context,false);
    CGContextSetRGBFillColor(context,0,0,0,1);
    CGContextScaleCTM(context,scale,scale);
    CGContextSetFont(context,font); CGContextSetFontSize(context,28);
    CGContextSetTextMatrix(context,CGAffineTransformIdentity);
    CGContextSetTextPosition(context,origin,40);
    CGSize advance=CGSizeMake(0,0); CGContextShowGlyphsWithAdvances(context,&glyph,&advance,1);
    memset(result,0,sizeof(*result));
    for (size_t y=0;y<HEIGHT;y++) for (size_t x=0;x<WIDTH;x++) {
        uint8_t alpha=pixels[(y*WIDTH+x)*4+3]; result->alpha[y*WIDTH+x]=alpha;
        result->coverage+=alpha; result->x+=alpha*(x+0.5); result->y+=alpha*(y+0.5);
    }
    CGContextRelease(context); free(pixels);
    if (result->coverage==0) return 0;
    result->x/=result->coverage; result->y/=result->coverage;
    return 1;
}
int main(int argc,const char **argv) {
    CHECK(argc==2,"provide exact DejaVuSans.ttf file; no font matching is allowed");
    NSAutoreleasePool *pool=[NSAutoreleasePool new];
    NSData *data=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
    CHECK(data && [data length]>0,"explicit font file loads");
    FT_Library library; FT_Face face;
    CHECK(FT_Init_FreeType(&library)==0,"FreeType validation initializes");
    CHECK(FT_New_Memory_Face(library,[data bytes],[data length],0,&face)==0,"explicit data is a valid font");
    const char *postscript=FT_Get_Postscript_Name(face);
    CHECK(postscript && strcmp(postscript,"DejaVuSans")==0 && strcmp(face->family_name,"DejaVu Sans")==0,"reject any font other than DejaVu Sans regular");
    FT_UInt index=FT_Get_Char_Index(face,'f'); CHECK(index>0 && index<=UINT16_MAX,"known glyph exists without fallback");
    printf("font=%s bytes=%lu glyph=%u file=%s\n",postscript,(unsigned long)[data length],index,argv[1]);
    CGDataProviderRef provider=CGDataProviderCreateWithCFData((CFDataRef)data);
    CGFontRef font=CGFontCreateWithDataProvider(provider); CHECK(font!=NULL,"data-provider graphics font creates");
    int failures=0; const double origins[]={10.25,10.5,11.0};
    for (int scale=1;scale<=2;scale++) {
        Measurement base,shifted;
        CHECK(render(font,index,scale,10,&base),"base glyph renders nonzero coverage");
        for (size_t test=0;test<sizeof(origins)/sizeof(origins[0]);test++) {
            CHECK(render(font,index,scale,origins[test],&shifted),"translated glyph renders");
            size_t different=0; for (size_t pixel=0;pixel<WIDTH*HEIGHT;pixel++) if(base.alpha[pixel]!=shifted.alpha[pixel])different++;
            double expected=(origins[test]-10)*scale, observed=shifted.x-base.x;
            double tolerance=0.15;
            int pass=fabs(observed-expected)<=tolerance && fabs(shifted.y-base.y)<=0.05 && different>0;
            printf("%s scale=%d origin=%.2f expected_dx=%.3f observed_dx=%.6f dy=%.6f changed_pixels=%lu coverage_ratio=%.6f tolerance=%.2f\n",pass?"PASS":"FAIL",scale,origins[test],expected,observed,shifted.y-base.y,(unsigned long)different,shifted.coverage/base.coverage,tolerance);
            if(!pass)failures++;
        }
    }
    CGFontRelease(font); CGDataProviderRelease(provider); FT_Done_Face(face); FT_Done_FreeType(library); [pool drain];
    if(failures) { fprintf(stderr,"FAIL: %d translated glyph cases lost requested device-space placement\n",failures); return 1; }
    puts("PASS: fractional glyph origins preserve requested geometric translation"); return 0;
}
