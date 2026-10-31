#import <Foundation/Foundation.h>
#import <Onyx2D/O2Font_freetype.h>
#include <stdio.h>
#include <limits.h>
#include <string.h>
#define CHECK(c, message) do { if (!(c)) { fprintf(stderr,"FAIL: %s\n",message); return 1; } } while (0)
@interface O2Font_freetype (QVPhaseTest)
- (NSUInteger)qvPhaseCacheCount;
@end
@implementation O2Font_freetype (QVPhaseTest)
- (NSUInteger)qvPhaseCacheCount { return [_glyphCache count]; }
@end
static O2Font_freetype *load(const char *path) {
    NSData *bytes=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:path]];if(!bytes)return nil;
    O2DataProviderRef data=O2DataProviderCreateWithCFData((CFDataRef)bytes);
    O2Font_freetype *font=[[O2Font_freetype alloc] initWithDataProvider:data];O2DataProviderRelease(data);return font;
}
static NSData *mask(O2FreeTypeCachedGlyph *glyph) {
    if(!glyph)return nil;
    NSMutableData *bytes=[NSMutableData data];
    for(unsigned row=0;row<glyph->bitmap.rows;row++){
        unsigned index=glyph->bitmap.pitch>=0?row:glyph->bitmap.rows-1-row;
        [bytes appendBytes:glyph->bitmap.buffer+index*abs(glyph->bitmap.pitch) length:glyph->bitmap.width];
    }return bytes;
}
static BOOL sameTransform(FT_Face face,FT_Matrix matrix,FT_Vector delta) {
    FT_Matrix current;FT_Vector shift;FT_Get_Transform(face,&current,&shift);
    return current.xx==matrix.xx&&current.xy==matrix.xy&&current.yx==matrix.yx&&current.yy==matrix.yy&&shift.x==delta.x&&shift.y==delta.y;
}
int main(int argc,char **argv) {
    CHECK(argc==3,"provide exact DejaVuSans.ttf and open PCF bitmap paths");NSAutoreleasePool *pool=[NSAutoreleasePool new];
    O2Font_freetype *font=load(argv[1]);CHECK(font,"explicit outline font loads");FT_Face face=[font face];
    CHECK(FT_Get_Postscript_Name(face)&&!strcmp(FT_Get_Postscript_Name(face),"DejaVuSans"),"reject substituted outline font");
    CHECK(FT_Set_Char_Size(face,0,28*64,72,72)==0,"outline size sets");O2Glyph glyph=FT_Get_Char_Index(face,'f');CHECK(glyph,"known glyph exists");
    FT_Matrix matrix={0x10000,0x1000,0,0x10000};FT_Vector delta={7,11};FT_Set_Transform(face,&matrix,&delta);
    CHECK([font rasterizeGlyph:glyph pointSize:28 phaseX:32 phaseY:16]!=nil,"fractional transformed glyph renders");
    CHECK(sameTransform(face,matrix,delta),"transform restored after success");
    CHECK([font qvPhaseCacheCount]==0,"custom transform bypasses incompatible phase cache");
    CHECK([font rasterizeGlyph:UINT16_MAX pointSize:28 phaseX:32 phaseY:16]==nil,"invalid glyph reports failure");
    CHECK(sameTransform(face,matrix,delta),"transform restored after glyph failure");
    FT_Vector extreme={LONG_MAX,0};FT_Set_Transform(face,&matrix,&extreme);
    CHECK([font rasterizeGlyph:glyph pointSize:28 phaseX:32 phaseY:16]==nil,"phase delta overflow is rejected");
    CHECK(sameTransform(face,matrix,extreme),"overflow rejection preserves transform");
    FT_Set_Transform(face,NULL,NULL);
    O2FreeTypeCachedGlyph *first=[font rasterizeGlyph:glyph pointSize:28 phaseX:32 phaseY:16];NSData *expected=[mask(first) copy];CHECK([expected length],"phase mask exists");
    CHECK([font rasterizeGlyph:glyph pointSize:28 phaseX:32 phaseY:16]==first,"same phase hits cache");
    CHECK(![expected isEqual:mask([font rasterizeGlyph:glyph pointSize:28 phaseX:16 phaseY:32])],"different phases keep distinct masks");
    for(unsigned i=0;i<650;i++){
        CHECK([font rasterizeGlyph:glyph pointSize:28 phaseX:i%64 phaseY:i/64]!=nil,"phase cache stress renders");
        CHECK([font qvPhaseCacheCount]<=O2FONT_GLYPH_CACHE_LIMIT,"phase cache stays bounded");
    }
    CHECK([expected isEqual:mask([font rasterizeGlyph:glyph pointSize:28 phaseX:32 phaseY:16])],"evicted phase recreates correct mask");
    CHECK(FT_Set_Char_Size(face,0,29*64,72,72)==0,"another font size sets");
    CHECK(![expected isEqual:mask([font rasterizeGlyph:glyph pointSize:29 phaseX:32 phaseY:16])],"size remains part of phase cache key");
    CHECK(FT_Set_Char_Size(face,0,28*64,72,72)==0,"original font size restored");
    CHECK([expected isEqual:mask([font rasterizeGlyph:glyph pointSize:28 phaseX:32 phaseY:16])],"size and phase revisit correct mask");
    O2FreeTypeCachedGlyph *legacy=[font rasterizeGlyph:glyph pointSize:28];
    CHECK(legacy==[font rasterizeGlyph:glyph pointSize:28 phaseX:0 phaseY:0],"integer phase shares legacy cached output");
    [expected release];[font release];
    font=load(argv[2]);CHECK(font,"explicit bitmap font loads");face=[font face];CHECK(!FT_IS_SCALABLE(face)&&face->num_fixed_sizes>0,"explicit bitmap strike validated");
    CHECK(FT_Select_Size(face,0)==0,"bitmap strike selected");glyph=FT_Get_Char_Index(face,'f');CHECK(glyph,"bitmap glyph exists");
    legacy=[font rasterizeGlyph:glyph pointSize:13];CHECK(legacy,"bitmap glyph renders");
    CHECK(legacy==[font rasterizeGlyph:glyph pointSize:13 phaseX:32 phaseY:16],"bitmap phase explicitly preserves legacy output");
    [font release];[pool drain];puts("PASS: transform success/failure, phase cache/eviction, integer and bitmap compatibility");return 0;
}
