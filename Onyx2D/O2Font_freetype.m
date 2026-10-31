#import <Onyx2D/O2Font_freetype.h>
#ifdef FREETYPE_PRESENT
#import <Onyx2D/O2Encoding.h>
#import <string.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#import FT_TRUETYPE_TABLES_H
#import FT_ADVANCES_H
#import FT_SFNT_NAMES_H
#import FT_TRUETYPE_IDS_H
#import FT_TYPE1_TABLES_H

@implementation O2Font_freetype

#ifdef DARLING

O2FontRef O2FontCreateWithFontName_platform(NSString *name) {
    return [[O2Font_freetype alloc] initWithFontName: name];
}

O2FontRef O2FontCreateWithDataProvider_platform(O2DataProviderRef provider) {
    return [[O2Font_freetype alloc] initWithDataProvider: provider];
}

#endif

FT_Library O2FontSharedFreeTypeLibrary() {
    static FT_Library library = NULL;

    if (library == NULL) {
        if (FT_Init_FreeType(&library) != 0) {
            NSLog(@"FT_Init_FreeType failed");
        }
    }

    return library;
}

static void addAppFont(FcConfig *config, NSString *path) {
    path = [[NSBundle mainBundle] pathForResource: path ofType: nil];
    if (path == nil) {
        NSLog(@"Cannot find font %@ in resources", path);
        return;
    }
    BOOL isDirectory;
    [[NSFileManager defaultManager] fileExistsAtPath: path
                                         isDirectory: &isDirectory];
    if (isDirectory) {
        FcConfigAppFontAddDir(config, (const FcChar8 *) [path UTF8String]);
    } else {
        FcConfigAppFontAddFile(config, (const FcChar8 *) [path UTF8String]);
    }
}

FcConfig *O2FontSharedFontConfig() {
    static FcConfig *fontConfig = NULL;

    if (fontConfig == NULL) {
        fontConfig = FcInitLoadConfigAndFonts();

        id appFontsPath = [[NSBundle mainBundle]
                objectForInfoDictionaryKey: @"ATSApplicationFontsPath"];
        if ([appFontsPath isKindOfClass: [NSString class]]) {
            addAppFont(fontConfig, appFontsPath);
        } else if ([appFontsPath isKindOfClass: [NSArray class]]) {
            for (NSString *path in appFontsPath) {
                addAppFont(fontConfig, path);
            }
        }
    }

    return fontConfig;
}

static FT_Face createFaceForMatch(FcPattern *match, BOOL requireUnicode) {
    FcChar8 *filename = NULL;
    int faceIndex = 0;
    FcResult indexResult = FcPatternGetInteger(match, FC_INDEX, 0, &faceIndex);
    if (FcPatternGetString(match, FC_FILE, 0, &filename) != FcResultMatch ||
        (indexResult != FcResultMatch && indexResult != FcResultNoMatch) ||
        faceIndex < 0)
        return NULL;
    FT_Face face = NULL;
    if (FT_New_Face(O2FontSharedFreeTypeLibrary(), (const char *)filename,
                    faceIndex, &face) != 0)
        return NULL;
    if (requireUnicode && FT_Select_Charmap(face, FT_ENCODING_UNICODE) != 0) {
        FT_Done_Face(face);
        return NULL;
    }
    return face;
}

static FT_Face createMatchingFace(FcPattern *pattern) {
    FcConfig *config = O2FontSharedFontConfig();
    if (config == NULL || !FcConfigSubstitute(config, pattern, FcMatchPattern))
        return NULL;
    FcDefaultSubstitute(pattern);
    FcResult result;
    FcPattern *match = FcFontMatch(config, pattern, &result);
    if (match == NULL)
        return NULL;
    FT_Face face = createFaceForMatch(match, YES);
    FcPatternDestroy(match);
    return face;
}

O2FontRef O2FontCreateWithCodePointCoverage(const uint32_t *codePoints,
                                           size_t count, FT_Face baseFace,
                                           const char *language) {
    if (codePoints == NULL || count == 0)
        return nil;

    FcPattern *pattern = FcPatternCreate();
    FcCharSet *characters = FcCharSetCreate();
    if (pattern == NULL || characters == NULL) {
        if (pattern != NULL)
            FcPatternDestroy(pattern);
        if (characters != NULL)
            FcCharSetDestroy(characters);
        return nil;
    }
    for (size_t index = 0; index < count; ++index) {
        if (codePoints[index] > 0x10FFFF ||
            (codePoints[index] >= 0xD800 && codePoints[index] <= 0xDFFF) ||
            !FcCharSetAddChar(characters, codePoints[index])) {
            FcCharSetDestroy(characters);
            FcPatternDestroy(pattern);
            return nil;
        }
    }
    FcBool added = FcPatternAddCharSet(pattern, FC_CHARSET, characters);
    FcCharSetDestroy(characters);
    if (!added) {
        FcPatternDestroy(pattern);
        return nil;
    }

    // Coverage is mandatory below; these properties rank suitable substitutes.
    // Do not add the base file/index: that would pin selection to the old face.
    if (baseFace != NULL) {
        if (baseFace->family_name != NULL)
            added = FcPatternAddString(pattern, FC_FAMILY,
                    (const FcChar8 *)baseFace->family_name);
        added = added && FcPatternAddInteger(pattern, FC_WEIGHT,
                baseFace->style_flags & FT_STYLE_FLAG_BOLD
                        ? FC_WEIGHT_BOLD : FC_WEIGHT_REGULAR);
        added = added && FcPatternAddInteger(pattern, FC_SLANT,
                baseFace->style_flags & FT_STYLE_FLAG_ITALIC
                        ? FC_SLANT_ITALIC : FC_SLANT_ROMAN);
        if (FT_IS_FIXED_WIDTH(baseFace))
            added = added && FcPatternAddInteger(pattern, FC_SPACING, FC_MONO);
    }
    if (language != NULL && language[0] != '\0')
        added = added && FcPatternAddString(pattern, FC_LANG,
                                            (const FcChar8 *)language);
    if (!added) {
        FcPatternDestroy(pattern);
        return nil;
    }

    FT_Face face = createMatchingFace(pattern);
    FcPatternDestroy(pattern);
    if (face == NULL)
        return nil;
    for (size_t index = 0; index < count; ++index) {
        if (FT_Get_Char_Index(face, codePoints[index]) == 0) {
            FT_Done_Face(face);
            return nil;
        }
    }
    return [[O2Font_freetype alloc] initWithFace: face];
}

static FT_Face createUserInterfaceFace(BOOL fixedPitch, BOOL emphasized,
                                      const char *language) {
    FcPattern *pattern = FcPatternCreate();
    if (pattern == NULL)
        return NULL;
    FcBool added = FcPatternAddString(pattern, FC_FAMILY,
            (const FcChar8 *)(fixedPitch ? "monospace" : "sans-serif")) &&
            FcPatternAddInteger(pattern, FC_WEIGHT,
                    emphasized ? FC_WEIGHT_BOLD : FC_WEIGHT_REGULAR);
    if (fixedPitch)
        added = added && FcPatternAddInteger(pattern, FC_SPACING, FC_MONO);
    if (language != NULL) {
        FcLangSet *languages = FcLangSetCreate();
        if (languages == NULL) {
            FcPatternDestroy(pattern);
            return NULL;
        }
        added = added && FcLangSetAdd(languages, (const FcChar8 *)language) &&
                FcPatternAddLangSet(pattern, FC_LANG, languages);
        FcLangSetDestroy(languages);
    }
    FcConfig *config = O2FontSharedFontConfig();
    if (!added || config == NULL || !FcConfigSubstitute(config, pattern, FcMatchPattern)) {
        FcPatternDestroy(pattern);
        return NULL;
    }
    FcDefaultSubstitute(pattern);
    FcResult result;
    // Do not trim equal-coverage faces: a later one may supply required real traits.
    FcFontSet *candidates = FcFontSort(config, pattern, FcFalse, NULL, &result);
    FcPatternDestroy(pattern);
    if (candidates == NULL)
        return NULL;
    FT_Face face = NULL;
    for (int index = 0; index < candidates->nfont; ++index) {
        face = createFaceForMatch(candidates->fonts[index], YES);
        if (face == NULL)
            continue;
        if (face->units_per_EM > 0 && face->num_glyphs > 0 &&
                (!fixedPitch || FT_IS_FIXED_WIDTH(face)) &&
                (!emphasized || (face->style_flags & FT_STYLE_FLAG_BOLD)))
            break;
        FT_Done_Face(face);
        face = NULL;
    }
    FcFontSetSortDestroy(candidates);
    return face;
}

O2FontRef O2FontCreateForUserInterface(BOOL fixedPitch, BOOL emphasized,
                                      const char *language) {
    FT_Face face = createUserInterfaceFace(fixedPitch, emphasized, language);
    if (face == NULL)
        return nil;
    O2Font_freetype *font = [O2Font_freetype alloc];
    if (font == nil) {
        FT_Done_Face(face);
        return nil;
    }
    return [font initWithFace:face];
}

// 1 is an exact loaded face; 0 permits legacy family/pattern matching; -1 is failure.
static int createExactPostScriptFace(const char *name, FT_Face *face) {
    *face = NULL;
    if (name[0] == '\0')
        return 0; // Empty pattern retains the configured legacy default.
    FcConfig *config = O2FontSharedFontConfig();
    if (config == NULL)
        return -1;
    FcPattern *query = FcPatternCreate();
    FcObjectSet *objects = FcObjectSetBuild(FC_FILE, FC_INDEX, FC_POSTSCRIPT_NAME, NULL);
    if (query == NULL || objects == NULL ||
            !FcPatternAddString(query, FC_POSTSCRIPT_NAME, (const FcChar8 *)name)) {
        if (query != NULL) FcPatternDestroy(query);
        if (objects != NULL) FcObjectSetDestroy(objects);
        return -1;
    }
    FcFontSet *matches = FcFontList(config, query, objects);
    FcPatternDestroy(query);
    FcObjectSetDestroy(objects);
    if (matches == NULL)
        return -1;
    int result = 0;
    for (int index = 0; index < matches->nfont; ++index) {
        FcPattern *entry = matches->fonts[index];
        BOOL exact = NO;
        FcChar8 *advertised;
        for (int nameIndex = 0; FcPatternGetString(entry, FC_POSTSCRIPT_NAME,
                nameIndex, &advertised) == FcResultMatch; ++nameIndex) {
            if (strcmp((const char *)advertised, name) == 0) {
                exact = YES;
                break;
            }
        }
        // Fontconfig normalizes case/spacing; those matches still need legacy routing.
        if (!exact)
            continue;
        result = -1;
        FT_Face candidate = createFaceForMatch(entry, NO);
        if (candidate == NULL)
            continue;
        const char *actual = FT_Get_Postscript_Name(candidate);
        if (actual != NULL && strcmp(actual, name) == 0) {
            *face = candidate;
            result = 1;
            break;
        }
        FT_Done_Face(candidate);
    }
    FcFontSetDestroy(matches);
    return result;
}

static char *copyFontNameUTF8(CFStringRef name) {
    if (name == NULL || CFGetTypeID(name) != CFStringGetTypeID())
        return NULL;
    CFIndex length = CFStringGetLength(name);
    for (CFIndex index = 0; index < length; ++index)
        if (CFStringGetCharacterAtIndex(name, index) == 0)
            return NULL;
    CFIndex maximum = CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8);
    if (maximum < 0 || maximum == LONG_MAX || (uintmax_t)maximum >= SIZE_MAX)
        return NULL;
    char *bytes = malloc((size_t)maximum + 1);
    if (bytes != NULL && !CFStringGetCString(name, bytes, maximum + 1, kCFStringEncodingUTF8)) {
        free(bytes);
        bytes = NULL;
    }
    return bytes;
}

+ (NSString *) filenameForPattern: (NSString *) pattern {
    FcConfig *config = O2FontSharedFontConfig();

    FcPattern *pat = FcNameParse((unsigned char *) [pattern UTF8String]);
    FcConfigSubstitute(config, pat, FcMatchPattern);
    FcDefaultSubstitute(pat);

    FcResult fcResult;
    FcPattern *match = FcFontMatch(config, pat, &fcResult);
    FcPatternDestroy(pat);
    if (match == NULL) {
        return nil;
    }

    FcChar8 *filename = NULL;
    FcPatternGetString(match, FC_FILE, 0, &filename);

    NSString *res = nil;
    if (filename != NULL) {
        res = [NSString stringWithUTF8String: (char *) filename];
    }

    FcPatternDestroy(match);
    return res;
}

- (instancetype) initWithDataProvider: (O2DataProviderRef) provider {
    self = [super initWithDataProvider: provider];
    if (self == nil) {
        return nil;
    }

    const void *bytes = [provider bytes];
    size_t length = [provider length];

    FT_Face face;
    int error = FT_New_Memory_Face(O2FontSharedFreeTypeLibrary(), bytes, length,
                                   0, &face);

    if (error != 0) {
        NSLog(@"FT_New_Memory_Face() = %d", error);
        [self release];
        return nil;
    }

    return [self initWithFace: face];
}

- (instancetype) initWithFontName: (NSString *) name {
    self = [super initWithFontName: name];
    if (self == nil)
        return nil;
    char *requested = copyFontNameUTF8((CFStringRef)_name);
    if (requested == NULL) {
        [self release];
        return nil;
    }
    FT_Face exactFace;
    int exact = createExactPostScriptFace(requested, &exactFace);
    free(requested);
    if (exact > 0)
        return [self initWithFace:exactFace];
    if (exact < 0) {
        [self release];
        return nil;
    }
    NSString *filename = [[self class] filenameForPattern: _name];
    if (filename == nil) {
        filename = [[self class] filenameForPattern: @""];
    }
    if (filename == nil) {
        NSLog(@"No font found for name %@", name);
        [self release];
        return nil;
    }

    // fontconfig reports the host's font path (e.g. /usr/share/fonts/...), which does not
    // exist under the guest's own root, so -fileExistsAtPath: needs it prefixed with
    // /Volumes/SystemRoot. FreeType is reached through the native passthrough, which already
    // resolves those host paths itself: handing it the prefixed path instead makes every
    // FT_New_Face fail with error 1 (FT_Err_Cannot_Open_Resource). So use the prefixed
    // form only to decide *whether* the file is there, and always hand FreeType the raw
    // fontconfig path.
    NSString *freetypePath = filename;
    if (![[NSFileManager defaultManager] fileExistsAtPath: filename]) {
        NSString *rooted = [@"/Volumes/SystemRoot" stringByAppendingPathComponent: filename];
        if (![[NSFileManager defaultManager] fileExistsAtPath: rooted]) {
            NSLog(@"Font file not found: %@", filename);
            [self release];
            return nil;
        }
    }

    FT_Face face;
    FT_Error error = FT_New_Face(O2FontSharedFreeTypeLibrary(),
                                 [freetypePath fileSystemRepresentation], 0, &face);

    if (error != 0) {
        NSLog(@"FT_New_Face() = %d", error);
        [self release];
        return nil;
    }

    return [self initWithFace: face];
}

static NSString *copySFNTName(const FT_SfntName *name) {
    if (name->string == NULL || name->string_len == 0)
        return nil;
    CFStringEncoding encoding;
    if ((name->platform_id == TT_PLATFORM_APPLE_UNICODE &&
         name->encoding_id <= TT_APPLE_ID_UNICODE_32) ||
        (name->platform_id == TT_PLATFORM_MICROSOFT &&
         (name->encoding_id == TT_MS_ID_UNICODE_CS ||
          name->encoding_id == TT_MS_ID_UCS_4 ||
          name->encoding_id == TT_MS_ID_SYMBOL_CS))) {
        if (name->string_len % 2 != 0)
            return nil;
        for (FT_UInt i = 0; i < name->string_len; i += 2) {
            unsigned unit = (name->string[i] << 8) | name->string[i + 1];
            if (unit >= 0xD800 && unit <= 0xDBFF) {
                if (name->string_len - i < 4)
                    return nil;
                unsigned low = (name->string[i + 2] << 8) | name->string[i + 3];
                if (low < 0xDC00 || low > 0xDFFF)
                    return nil;
                i += 2;
            } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
                return nil;
            }
        }
        encoding = kCFStringEncodingUTF16BE;
    } else if (name->platform_id == TT_PLATFORM_MACINTOSH &&
               name->encoding_id == TT_MAC_ID_ROMAN) {
        encoding = kCFStringEncodingMacRoman;
    } else {
        return nil;
    }
    return (NSString *)CFStringCreateWithBytes(kCFAllocatorDefault, name->string,
                                               name->string_len, encoding, false);
}

static NSString *copyPostScriptNameForFace(FT_Face face) {
    const char *name = FT_Get_Postscript_Name(face);
    return name != NULL ? (NSString *)CFStringCreateWithCString(kCFAllocatorDefault,
                                    name, kCFStringEncodingUTF8) : nil;
}

static NSString *copyFullNameForFace(FT_Face face) {
    NSString *fallback = nil;
    FT_UInt count = FT_Get_Sfnt_Name_Count(face);
    for (FT_UInt i = 0; i < count; i++) {
        FT_SfntName name;
        if (FT_Get_Sfnt_Name(face, i, &name) != 0 ||
            name.name_id != TT_NAME_ID_FULL_NAME)
            continue;
        NSString *candidate = copySFNTName(&name);
        if (candidate == nil)
            continue;
        // A deterministic English Unicode preference, not host-locale matching.
        if (name.platform_id == TT_PLATFORM_MICROSOFT &&
            name.language_id == TT_MS_LANGID_ENGLISH_UNITED_STATES) {
            [fallback release];
            return candidate;
        }
        if (fallback == nil)
            fallback = candidate;
        else
            [candidate release];
    }
    if (fallback != nil)
        return fallback;
    if (!FT_IS_SFNT(face)) {
        PS_FontInfoRec info;
        if (FT_Get_PS_Font_Info(face, &info) == 0 && info.full_name != NULL)
            return (NSString *)CFStringCreateWithCString(kCFAllocatorDefault,
                                    info.full_name, kCFStringEncodingUTF8);
    }
    return nil;
}

- (NSString *) copyPostScriptName {
    return [_postScriptName copy];
}

- (NSString *) copyFullName {
    return [_fullName copy];
}

static NSInteger *copyUnscaledAdvances(FT_Face face, NSInteger glyphCount) {
    if (face == NULL || glyphCount <= 0 || (uintmax_t)glyphCount > UINT_MAX ||
        (uintmax_t)glyphCount > SIZE_MAX / sizeof(NSInteger)) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"Font advance cache is not representable"];
        return NULL;
    }
    NSInteger *advances = NSZoneMalloc(NULL, (size_t)glyphCount * sizeof(NSInteger));
    if (advances == NULL) {
        [NSException raise:NSMallocException format:@"Cannot allocate font advance cache"];
        return NULL;
    }
    FT_Fixed batch[256];
    for (FT_UInt first = 0; first < (FT_UInt)glyphCount;) {
        FT_UInt count = MIN(256, (FT_UInt)glyphCount - first);
        FT_Error error = FT_Get_Advances(face, first, count, FT_LOAD_NO_SCALE, batch);
        if (error != 0) {
            NSZoneFree(NULL, advances);
            [NSException raise:NSInternalInconsistencyException
                        format:@"FreeType advance lookup failed: %d", error];
            return NULL;
        }
        for (FT_UInt index = 0; index < count; index++)
            // Bitmap strikes keep 26.6 advances even with FT_LOAD_NO_SCALE.
            advances[first + index] = batch[index] / (FT_IS_SCALABLE(face) ? 1 : 64);
        first += count;
    }
    return advances;
}

- (instancetype) initWithFace: (FT_Face) face {
    _face = face;
    _platformType = O2FontPlatformTypeFreeType;
    _glyphCache = [NSMutableDictionary new];

    int i, numberOfCharMaps = face->num_charmaps;
    BOOL hasUnicode = FALSE;
    BOOL hasMacRoman = FALSE;

    for (i = 0; i < numberOfCharMaps; i++) {

        if (face->charmaps[i]->encoding == FT_ENCODING_UNICODE) {
            hasUnicode = TRUE;
        }
        if (face->charmaps[i]->encoding == FT_ENCODING_APPLE_ROMAN) {
            hasMacRoman = TRUE;
        }
    }
    if (hasUnicode) {
        _ftEncoding = FT_ENCODING_UNICODE;
    } else if (hasMacRoman) {
        _ftEncoding = FT_ENCODING_APPLE_ROMAN;
    } else {
        NSLog(@"encoding = %c %c %c %c", face->charmaps[0]->encoding >> 24,
              face->charmaps[0]->encoding >> 16,
              face->charmaps[0]->encoding >> 8, face->charmaps[0]->encoding);
        _ftEncoding = face->charmaps[0]->encoding;
    }

    if (FT_Select_Charmap(face, _ftEncoding) != 0) {
        NSLog(@"FT_Select_Charmap(%d) failed", _ftEncoding);
    }

    if (!(face->face_flags & FT_FACE_FLAG_SCALABLE)) {
        NSLog(@"FreeType font face is not scalable for family: %s", face->family_name ? face->family_name : "unknown");
    }

    _unitsPerEm = (O2Float) face->units_per_EM;
    _ascent = face->ascender;
    _descent = face->descender;
    _leading = 0;
    _capHeight = face->height;
    _xHeight = face->height;
    _italicAngle = 0;
    _stemV = 0;
    _bbox.origin.x = face->bbox.xMin;
    _bbox.origin.y = face->bbox.yMin;
    _bbox.size.width = face->bbox.xMax - face->bbox.xMin;
    _bbox.size.height = face->bbox.yMax - face->bbox.yMin;
    _numberOfGlyphs = face->num_glyphs;
    _advances = NULL;
    // FreeType name APIs may lazily mutate the face; snapshot before publication.
    _postScriptName = copyPostScriptNameForFace(face);
    _fullName = copyFullNameForFace(face);
    if (FT_IS_SCALABLE(face)) {
        @try {
            // Publish immutable metrics before any renderer can share this face.
            _advances = copyUnscaledAdvances(face, _numberOfGlyphs);
        } @catch (id exception) {
            [self release];
            @throw;
        }
    }
    return self;
}

- (void) dealloc {
    FT_Done_Face(_face);
    [_postScriptName release];
    [_fullName release];
    [_glyphCache release];
    [_macRomanEncoding release];
    [_macExpertEncoding release];
    [_winAnsiEncoding release];
    [super dealloc];
}

- (FT_Face) face {
    return _face;
}

- (CFArrayRef) copyTableTags {
    FT_ULong count = 0;
    if (!_face || FT_Sfnt_Table_Info(_face, 0, NULL, &count) != 0 ||
        count > UINT_MAX || count > LONG_MAX || count > SIZE_MAX / sizeof(void *))
        return NULL;
    const void **tags = count ? malloc((size_t)count * sizeof(*tags)) : NULL;
    if (count && !tags) return NULL;
    CFIndex used = 0;
    for (FT_UInt index = 0; index < count; ++index) {
        FT_ULong tag = 0, length = 0;
        if (FT_Sfnt_Table_Info(_face, index, &tag, &length) != 0 || tag > UINT32_MAX) {
            free(tags);
            return NULL;
        }
        if (length != 0)
            tags[used++] = (const void *)(uintptr_t)tag;
    }
    CFArrayRef result = CFArrayCreate(kCFAllocatorDefault, tags, used, NULL);
    free(tags);
    return result;
}

- (NSData *) copyTableForTag: (uint32_t) requestedTag {
    FT_ULong count = 0, length = 0;
    if (!_face || FT_Sfnt_Table_Info(_face, 0, NULL, &count) != 0 || count > UINT_MAX)
        return nil;
    for (FT_UInt index = 0; index < count; ++index) {
        FT_ULong tag = 0, tableLength = 0;
        if (FT_Sfnt_Table_Info(_face, index, &tag, &tableLength) != 0)
            return nil;
        if (tag == requestedTag) {
            length = tableLength;
            break;
        }
    }
    if (!length || length > SIZE_MAX || length > NSUIntegerMax || length > LONG_MAX ||
        requestedTag == 0 || requestedTag == 1)
        return nil;
    void *bytes = malloc((size_t)length);
    if (!bytes) return nil;
    FT_ULong loaded = length;
    if (FT_Load_Sfnt_Table(_face, requestedTag, 0, bytes, &loaded) != 0 || loaded != length) {
        free(bytes);
        return nil;
    }
    CFDataRef result = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, bytes,
            (CFIndex)length, kCFAllocatorMalloc);
    if (!result) free(bytes);
    return (NSData *)result;
}

- (NSCharacterSet *) coveredCharacterSet {
    if (_coveredCharSet == nil && _face != NULL) {
        @synchronized(self) {
            if (_coveredCharSet == nil && _face != NULL) {
                CFMutableCharacterSetRef set = CFCharacterSetCreateMutable(kCFAllocatorDefault);
                FT_UInt gindex = 0;
                FT_ULong charcode = FT_Get_First_Char(_face, &gindex);
                FT_ULong rangeStart = 0;
                FT_ULong rangeLength = 0;

                while (gindex != 0) {
                    if (charcode <= 0x10FFFF) {
                        if (rangeLength > 0 && charcode == rangeStart + rangeLength) {
                            rangeLength++;
                        } else {
                            if (rangeLength > 0) {
                                CFCharacterSetAddCharactersInRange(set, CFRangeMake(rangeStart, rangeLength));
                            }
                            rangeStart = charcode;
                            rangeLength = 1;
                        }
                    }
                    charcode = FT_Get_Next_Char(_face, charcode, &gindex);
                }
                if (rangeLength > 0) {
                    CFCharacterSetAddCharactersInRange(set, CFRangeMake(rangeStart, rangeLength));
                }
                _coveredCharSet = (NSCharacterSet *) set;
            }
        }
    }
    return _coveredCharSet;
}

FT_Face O2FontFreeTypeFace(O2Font_freetype *self) {
    return self->_face;
}

- (void) fetchAdvances {
    if (_advances == NULL)
        _advances = copyUnscaledAdvances(_face, _numberOfGlyphs);
}

- (O2Glyph) glyphWithGlyphName: (NSString *) name {
    return FT_Get_Name_Index(_face, (char *) [name cString]);
}

- (NSString *) copyGlyphNameForGlyph: (O2Glyph) glyph {
    char initial[100];
    char *buffer = initial;
    FT_UInt capacity = sizeof(initial);
    NSString *result = nil;
    for (;;) {
        if (FT_Get_Glyph_Name(_face, glyph, buffer, capacity) != 0)
            break;
        char *end = memchr(buffer, 0, capacity);
        if (!end) break;
        if ((size_t)(end - buffer) < capacity - 1) {
            result = [[NSString alloc] initWithUTF8String:buffer];
            break;
        }
        if (capacity > UINT_MAX / 2 || capacity > SIZE_MAX / 2 ||
            capacity > PTRDIFF_MAX / 2)
            break;
        char *grown = malloc((size_t)capacity * 2);
        if (!grown) break;
        if (buffer != initial) free(buffer);
        buffer = grown;
        capacity *= 2;
    }
    if (buffer != initial) free(buffer);
    return result;
}

- (void) getGlyphs: (O2Glyph *) glyphs
        forCodePoints: (uint16_t *) codes
               length: (NSInteger) length
{
    for (int i = 0; i < length; i++) {
        glyphs[i] = FT_Get_Char_Index(_face, codes[i]);
    }
}

- (O2Encoding *) unicode_createEncodingForTextEncoding:
        (O2TextEncoding) encoding
{
    unichar unicode[256];
    O2Glyph glyphs[256];

    switch (encoding) {
    case kO2EncodingFontSpecific:
    case kO2EncodingMacRoman:
        if (_macRomanEncoding == nil) {
            O2EncodingGetMacRomanUnicode(unicode);
            [self getGlyphs: glyphs forCodePoints: unicode length: 256];
            _macRomanEncoding = [[O2Encoding alloc] initWithGlyphs: glyphs
                                                           unicode: unicode];
        }
        return [_macRomanEncoding retain];

    case kO2EncodingMacExpert:
        if (_macExpertEncoding == nil) {
            O2EncodingGetMacExpertUnicode(unicode);
            [self getGlyphs: glyphs forCodePoints: unicode length: 256];
            _macExpertEncoding = [[O2Encoding alloc] initWithGlyphs: glyphs
                                                            unicode: unicode];
        }
        return [_macExpertEncoding retain];

    case kO2EncodingWinAnsi:
        if (_winAnsiEncoding == nil) {
            O2EncodingGetWinAnsiUnicode(unicode);
            [self getGlyphs: glyphs forCodePoints: unicode length: 256];
            _winAnsiEncoding = [[O2Encoding alloc] initWithGlyphs: glyphs
                                                          unicode: unicode];
        }
        return [_winAnsiEncoding retain];

    default:
        return nil;
    }
    return nil;
}

- (O2Encoding *) MacRoman_createEncodingForTextEncoding:
        (O2TextEncoding) encoding
{

    uint16_t codes[256];
    O2Glyph glyphs[256];
    unichar unicode[256];

    if (_macRomanEncoding == nil) {

        if (encoding != kO2EncodingMacRoman &&
            encoding != kO2EncodingFontSpecific) {
            NSLog(@"font encoding is MacRoman, requesting encoding %d failed",
                  encoding);
        }

        for (int i = 0; i < 256; i++) {
            codes[i] = i;
        }

        [self getGlyphs: glyphs forCodePoints: codes length: 256];

        O2EncodingGetMacExpertUnicode(unicode);

        _macRomanEncoding = [[O2Encoding alloc] initWithGlyphs: glyphs
                                                       unicode: unicode];
    }

    return [_macRomanEncoding retain];
}

- (O2Encoding *) createEncodingForTextEncoding: (O2TextEncoding) encoding {
    if (_ftEncoding == FT_ENCODING_APPLE_ROMAN) {
        return [self MacRoman_createEncodingForTextEncoding: encoding];
    }

    return [self unicode_createEncodingForTextEncoding: encoding];
}

- (O2FreeTypeCachedGlyph *) rasterizeGlyph: (O2Glyph) glyph
                                  pointSize: (O2Float) pointSize
{
    if (_face == NULL) {
        return nil;
    }

    @synchronized(self) {
        uint64_t keyValue = ((uint64_t)(uint32_t)((long)(pointSize * 64)) << 28) |
                            ((uint64_t)glyph << 12);
        NSNumber *key = [NSNumber numberWithUnsignedLongLong: keyValue];

        O2FreeTypeCachedGlyph *cached = [_glyphCache objectForKey: key];
        if (cached != nil) {
            return [[cached retain] autorelease];
        }

        if (FT_Load_Glyph(_face, glyph, FT_LOAD_DEFAULT) != 0) {
            return nil;
        }

        if (FT_Render_Glyph(_face->glyph, FT_RENDER_MODE_NORMAL) != 0) {
            return nil;
        }

        FT_GlyphSlot slot = _face->glyph;
        cached = [[O2FreeTypeCachedGlyph alloc]
                initWithBitmap: &slot->bitmap
                          left: slot->bitmap_left
                           top: slot->bitmap_top
                       advance: slot->advance.x];

        if ([_glyphCache count] >= O2FONT_GLYPH_CACHE_LIMIT) {
            [_glyphCache removeAllObjects];
        }

        [_glyphCache setObject: cached forKey: key];
        return [cached autorelease];
    }
}

- (O2FreeTypeCachedGlyph *) rasterizeGlyph: (O2Glyph) glyph
                                  pointSize: (O2Float) pointSize
                                    phaseX: (uint8_t) phaseX
                                    phaseY: (uint8_t) phaseY
{
    if (_face == NULL || phaseX >= 64 || phaseY >= 64 ||
        !isfinite(pointSize) || pointSize <= 0 || pointSize * 64 > UINT32_MAX)
        return nil;

    if ((phaseX == 0 && phaseY == 0) || !FT_IS_SCALABLE(_face))
        return [self rasterizeGlyph: glyph pointSize: pointSize];

    @synchronized(self) {
        FT_Matrix matrix;
        FT_Vector delta;
        FT_Get_Transform(_face, &matrix, &delta);
        BOOL cacheable = matrix.xx == 0x10000 && matrix.xy == 0 &&
                matrix.yx == 0 && matrix.yy == 0x10000 && delta.x == 0 && delta.y == 0;
        uint64_t keyValue = ((uint64_t)(uint32_t)(pointSize * 64) << 28) |
                ((uint64_t)glyph << 12) | ((uint64_t)phaseX << 6) | phaseY;
        NSNumber *key = [NSNumber numberWithUnsignedLongLong: keyValue];
        O2FreeTypeCachedGlyph *cached = cacheable ? [_glyphCache objectForKey: key] : nil;
        if (cached != nil)
            return [[cached retain] autorelease];

        if (delta.x > LONG_MAX - phaseX || delta.y < LONG_MIN + phaseY)
            return nil;
        FT_Vector shifted = {delta.x + phaseX, delta.y - phaseY};
        FT_Set_Transform(_face, &matrix, &shifted);
        FT_Error error = FT_Load_Glyph(_face, glyph, FT_LOAD_NO_BITMAP);
        if (error == 0)
            error = FT_Render_Glyph(_face->glyph, FT_RENDER_MODE_NORMAL);
        FT_Set_Transform(_face, &matrix, &delta);
        if (error != 0)
            return nil;

        FT_GlyphSlot slot = _face->glyph;
        cached = [[O2FreeTypeCachedGlyph alloc]
                initWithBitmap: &slot->bitmap left: slot->bitmap_left
                           top: slot->bitmap_top advance: slot->advance.x];
        if (cacheable) {
            if ([_glyphCache count] >= O2FONT_GLYPH_CACHE_LIMIT)
                [_glyphCache removeAllObjects];
            [_glyphCache setObject: cached forKey: key];
        }
        return [cached autorelease];
    }
}

@end

@implementation O2FreeTypeCachedGlyph

- (instancetype) initWithBitmap: (const FT_Bitmap *) srcBitmap
                            left: (NSInteger) left
                             top: (NSInteger) top
                         advance: (FT_Pos) advance
{
    bitmap.rows = srcBitmap->rows;
    bitmap.width = srcBitmap->width;
    bitmap.pitch = srcBitmap->width;
    bitmap.num_grays = 256;
    bitmap.pixel_mode = FT_PIXEL_MODE_GRAY;
    bitmap.palette_mode = 0;
    bitmap.palette = NULL;
    bitmap.buffer = NULL;

    self->left = left;
    self->top = top;
    self->advance = advance;

    if (bitmap.rows > 0 && bitmap.width > 0) {
        size_t bytes = bitmap.rows * bitmap.width;
        unsigned char *data = NSZoneMalloc(NULL, bytes);

        for (FT_Int row = 0; row < bitmap.rows; row++) {
            memcpy(data + row * bitmap.width,
                   srcBitmap->buffer + row * srcBitmap->pitch, bitmap.width);
        }

        bitmap.buffer = data;
    }

    return self;
}

- (void) dealloc {
    if (bitmap.buffer != NULL) {
        NSZoneFree(NULL, bitmap.buffer);
    }
    [super dealloc];
}

@end
#endif
