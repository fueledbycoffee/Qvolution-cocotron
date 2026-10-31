#import <Onyx2D/O2Defines_FreeType.h>
#import <Onyx2D/O2Font.h>
#import <Foundation/NSDictionary.h>

#ifdef FREETYPE_PRESENT

#ifdef DARLING
#define __linux__
#endif

#import <ft2build.h>
#import FT_FREETYPE_H
#import FT_RENDER_H

#import <fontconfig/fontconfig.h>

#ifdef DARLING
#undef __linux__
#endif

#define O2FONT_GLYPH_CACHE_LIMIT 512

@class O2FreeTypeCachedGlyph;

@interface O2Font_freetype : O2Font {
    FT_Face _face;
    FT_Long _styleFlags;
    NSString *_postScriptName;
    NSString *_fullName;
    FT_Encoding _ftEncoding;
    O2Encoding *_macRomanEncoding;
    O2Encoding *_macExpertEncoding;
    O2Encoding *_winAnsiEncoding;
    NSMutableDictionary *_glyphCache;
}

- (instancetype) initWithFace: (FT_Face) face;
- (instancetype) initWithDataProvider: (O2DataProviderRef) provider;

- (FT_Face) face;

FT_Face O2FontFreeTypeFace(O2Font_freetype *self);
FT_Long O2FontFreeTypeStyleFlags(O2Font_freetype *self);
BOOL O2FontGetFaceStyleFlags(FT_Face face, FT_Long *flags);

FT_Library O2FontSharedFreeTypeLibrary();
FcConfig *O2FontSharedFontConfig();

// Owned metadata-only face/name; no O2Font instance or glyph cache is constructed.
FT_Face O2FontCreateMetadataFaceForMatch(FcPattern *match, FT_Library privateLibrary);
NSString *O2FontCopyMetadataFullName(FT_Face face);

// Returns an owned configured UI face with real requested traits, or nil.
O2FontRef O2FontCreateForUserInterface(BOOL fixedPitch, BOOL emphasized,
                                      const char *language);

// Returns an owned font covering all supplied Unicode scalar values, or nil.
O2FontRef O2FontCreateWithCodePointCoverage(const uint32_t *codePoints,
                                           size_t count, FT_Face baseFace,
                                           const char *language);

- (O2FreeTypeCachedGlyph *) rasterizeGlyph: (O2Glyph) glyph
                                  pointSize: (O2Float) pointSize;
- (O2FreeTypeCachedGlyph *) rasterizeGlyph: (O2Glyph) glyph
                                  pointSize: (O2Float) pointSize
                                    phaseX: (uint8_t) phaseX
                                    phaseY: (uint8_t) phaseY;

@end

@interface O2FreeTypeCachedGlyph : NSObject {
@public
    FT_Bitmap bitmap;
    NSInteger left;
    NSInteger top;
    FT_Pos advance;
}

- (instancetype) initWithBitmap: (const FT_Bitmap *) bitmap
                            left: (NSInteger) left
                             top: (NSInteger) top
                         advance: (FT_Pos) advance;

@end

#endif
