#import <Foundation/Foundation.h>
#import <Onyx2D/O2Font_freetype.h>
#include <stdio.h>
#include <time.h>
#define CHECK(c, message) do { if (!(c)) { fprintf(stderr,"FAIL: %s\n",message); return 1; } } while (0)
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+t.tv_nsec/1e9; }
int main(void) {
    NSAutoreleasePool *pool=[NSAutoreleasePool new];
    NSArray *names=[NSArray arrayWithObjects:@"DejaVu Serif",@"DejaVu Sans Mono",@"Noto Sans CJK JP",nil];
    for (NSString *name in names) {
        O2Font_freetype *font=[[O2Font_freetype alloc] initWithFontName:name];
        CHECK(font!=nil,"test font resolves");
        FT_Face face=[font face];
        CHECK(face && FT_IS_SCALABLE(face),"test face is scalable");
        CHECK(FT_Set_Char_Size(face,0,16*64,72,72)==0,"initial size set");
        FT_Size_Metrics metrics=face->size->metrics;
        O2Glyph first=0; int value=0;
        double start=now(); CHECK(O2FontGetGlyphAdvances(font,&first,1,&value),"advance request succeeds");
        double elapsed=now()-start;
        CHECK(face->size->metrics.x_ppem==metrics.x_ppem && face->size->metrics.y_ppem==metrics.y_ppem && face->size->metrics.x_scale==metrics.x_scale && face->size->metrics.y_scale==metrics.y_scale,"advance cache preserves live face size");
        for (FT_UInt glyph=0;glyph<(FT_UInt)face->num_glyphs;glyph++) {
            CHECK(glyph<=UINT16_MAX,"test glyph fits public glyph interface");
            O2Glyph requested=(O2Glyph)glyph;
            CHECK(O2FontGetGlyphAdvances(font,&requested,1,&value),"cached advance request succeeds");
            CHECK(FT_Load_Glyph(face,glyph,FT_LOAD_NO_SCALE)==0,"unscaled reference glyph loads");
            CHECK(value==face->glyph->advance.x,"cached advance matches unscaled font units");
        }
        printf("%s glyphs=%ld cache_fill_seconds=%.6f ppem=%u\n",[name UTF8String],face->num_glyphs,elapsed,face->size->metrics.y_ppem);
        [font release];
    }
    [pool drain]; puts("PASS: unscaled advance units and live face preservation"); return 0;
}
