#import <Onyx2D/O2Context_builtin_FT.h>
#import <Onyx2D/O2Font_freetype.h>
#import <Onyx2D/O2GraphicsState.h>
#import <Onyx2D/O2Paint_color.h>
#import <Onyx2D/O2ColorSpace.h>
#include <stdint.h>
#include <stdlib.h>

@implementation O2Context (O2BitmapContext)

+ (O2Context *) createWithBytes: (void *) bytes
                          width: (size_t) width
                         height: (size_t) height
               bitsPerComponent: (size_t) bitsPerComponent
                    bytesPerRow: (size_t) bytesPerRow
                     colorSpace: (O2ColorSpaceRef) colorSpace
                     bitmapInfo: (O2BitmapInfo) bitmapInfo
                releaseCallback:
                        (O2BitmapContextReleaseDataCallback) releaseCallback
                    releaseInfo: (void *) releaseInfo
{

    return [[O2Context_builtin_FT alloc] initWithBytes: bytes
                                                 width: width
                                                height: height
                                      bitsPerComponent: bitsPerComponent
                                           bytesPerRow: bytesPerRow
                                            colorSpace: colorSpace
                                            bitmapInfo: bitmapInfo
                                       releaseCallback: releaseCallback
                                           releaseInfo: releaseInfo];
}

@end

@implementation O2Context_builtin_FT

- initWithSurface: (O2Surface *) surface flipped: (BOOL) flipped {
    if ([super initWithSurface: surface flipped: flipped] == nil)
        return nil;

    return self;
}

- (void) dealloc {
    [super dealloc];
}

- (void) establishFontStateInDeviceIfDirty {
    O2GState *gState = O2ContextCurrentGState(self);

    if (gState->_fontIsDirty) {
        O2GStateClearFontIsDirty(gState);
    }
}

static O2Paint *paintFromColor(O2ColorRef color) {
    O2ColorSpaceRequireSupportedRendering(O2ColorGetColorSpace(color));
    size_t count = O2ColorGetNumberOfComponents(color);
    const O2Float *components = O2ColorGetComponents(color);

    if (count == 2)
        return [[O2Paint_color alloc] initWithGray: components[0]
                                             alpha: components[1]
                           surfaceToPaintTransform: O2AffineTransformIdentity];
    if (count == 4)
        return [[O2Paint_color alloc] initWithRed: components[0]
                                            green: components[1]
                                             blue: components[2]
                                            alpha: components[3]
                          surfaceToPaintTransform: O2AffineTransformIdentity];

    return [[O2Paint_color alloc] initWithGray: 0
                                         alpha: 1
                       surfaceToPaintTransform: O2AffineTransformIdentity];
}

static void applyCoverageToSpan_lRGBA8888_PRE(O2argb8u *dst,
                                              unsigned char *coverageSpan,
                                              O2argb8u *src, int length)
{
    int i;

    for (i = 0; i < length; i++, src++, dst++) {
        int coverage = coverageSpan[i];
        int oneMinusCoverage = inverseCoverage(coverage);
        O2argb8u r = *src;
        O2argb8u d = *dst;

        *dst = O2argb8uAdd(O2argb8uMultiplyByCoverage(r, coverage),
                           O2argb8uMultiplyByCoverage(d, oneMinusCoverage));
    }
}

static void renderFreeTypeBitmap(O2Context_builtin_FT *self, O2Surface *surface,
                                 FT_Bitmap *bitmap, NSInteger x, NSInteger y,
                                 O2Paint *paint)
{
    if (bitmap == NULL || bitmap->buffer == NULL || surface == NULL || paint == NULL)
        return;

    // Size of the bitmap.
    NSInteger fullWidth = bitmap->width;
    NSInteger fullHeight = bitmap->rows;
    NSInteger pitch = bitmap->pitch;

    if (fullWidth <= 0 || fullHeight <= 0 || pitch == 0)
        return;

    // What we're going to render, taking clippig into account.
    NSInteger minX = MAX(x, self->_vpx);
    NSInteger maxX = MIN(x + fullWidth, self->_vpx + self->_vpwidth);
    NSInteger minY = MAX(y, self->_vpy);
    NSInteger maxY = MIN(y + fullHeight, self->_vpy + self->_vpheight);

    if (maxX <= minX || maxY <= minY)
        return;
    NSInteger renderWidth = maxX - minX;
    NSInteger renderHeight = maxY - minY;

    if (self->_clipContext != nil || self->_blend_argb8u_PRE == NULL ||
        !O2SurfaceCanReadWriteARGB8u(surface) ||
        paint->_paint_largb8u_PRE == NULL) {
        for (NSInteger row = 0; row < renderHeight; row++) {
            NSInteger curY = minY + row;
            NSInteger rowInBitmap = curY - y;
            NSInteger rowOffset = pitch >= 0 ? rowInBitmap * pitch
                    : (fullHeight - 1 - rowInBitmap) * (-pitch);
            unsigned char *coverage = bitmap->buffer + rowOffset + (minX - x);
            O2ContextWriteGlyphCoverageSpanFloat(self, surface, paint,
                    minX, curY, coverage, renderWidth);
        }
        return;
    }

    O2argb8u *dstBuffer = __builtin_alloca(renderWidth * sizeof(O2argb8u));
    O2argb8u *srcBuffer = __builtin_alloca(renderWidth * sizeof(O2argb8u));

    for (NSInteger row = 0; row < renderHeight; row++) {
        // Geometry of this row.
        // We're going to change curX & remainingLength as we move along this
        // row.
        NSInteger curX = minX;
        NSInteger curY = minY + row;
        NSInteger remainingLength = renderWidth;

        // We're going to advance these pointers as we move along this row.
        NSInteger rowInBitmap = curY - y;
        NSInteger rowOffset = (pitch >= 0) ? (rowInBitmap * pitch) : ((fullHeight - 1 - rowInBitmap) * (-pitch));
        unsigned char *coverage = bitmap->buffer + rowOffset + (curX - x);
        O2argb8u *src = srcBuffer;
        O2argb8u *dst = dstBuffer;

        // Try to get direct access to the surface data.
        O2argb8u *direct = surface->_read_argb8u(surface, curX, curY, dst,
                                                 remainingLength);
        // If that succeeded, write there directly with no temporary buffer.
        if (direct != NULL)
            dst = direct;

        while (remainingLength > 0) {
            // Read next chunk into src.
            int chunk = O2PaintReadSpan_argb8u_PRE(paint, curX, curY, src,
                                                   remainingLength);

            if (chunk < 0) {
                chunk = -chunk;
                // Skip this much pixels.
            } else {
                if (self->_blend_argb8u_PRE != NULL) {
                    self->_blend_argb8u_PRE(src, dst, chunk);
                } else {
                    O2BlendSpanNormal_8888(src, dst, chunk);
                }

                applyCoverageToSpan_lRGBA8888_PRE(dst, coverage, src, chunk);

                if (direct == NULL) {
                    // When direct is NULL, dst is a temporary buffer, not the
                    // surface itself, so we have to write it out to the surface
                    // explicitly.
                    O2SurfaceWriteSpan_argb8u_PRE(surface, curX, curY, dst,
                                                  chunk);
                }
            }

            coverage += chunk;
            remainingLength -= chunk;
            curX += chunk;
            src += chunk;
            dst += chunk;
        }
    }
}

// FreeType delta precision is 26.6; retain the integer carry at phase wrap.
static BOOL splitGlyphOrigin(O2Float value, NSInteger *anchor, uint8_t *phase) {
    if (!isfinite(value))
        return NO;
    double integral = floor((double)value);
    long fraction = lround(((double)value - integral) * 64);
    if (fraction == 64) { integral += 1; fraction = 0; }
    if ((long double)integral < (long double)NSIntegerMin ||
        (long double)integral >= (long double)NSIntegerMax + 1.0L)
        return NO;
    *anchor = (NSInteger)integral;
    *phase = (uint8_t)fraction;
    return YES;
}

static BOOL glyphBitmapPosition(NSInteger anchorX, NSInteger anchorY,
        NSInteger left, NSInteger top, size_t width, size_t height,
        NSInteger *x, NSInteger *y) {
    if (width > (size_t)NSIntegerMax || height > (size_t)NSIntegerMax)
        return NO;
    NSInteger right, bottom;
    return !__builtin_add_overflow(anchorX, left, x) &&
            !__builtin_sub_overflow(anchorY, top, y) &&
            !__builtin_add_overflow(*x, (NSInteger)width, &right) &&
            !__builtin_add_overflow(*y, (NSInteger)height, &bottom);
}

- (void) showGlyphs: (const O2Glyph *) glyphs
           advances: (const O2Size *) advances
              count: (NSUInteger) count
{
    if (count == 0 || glyphs == NULL || _surface == NULL)
        return;

    O2GState *gState = O2ContextCurrentGState(self);
    O2ColorSpaceRequireSupportedRendering(O2ColorGetColorSpace(gState->_fillColor));
    O2Size *defaultAdvances = NULL;
    if (advances == NULL) {
        if (count > SIZE_MAX / sizeof(*defaultAdvances))
            return;
        defaultAdvances = malloc(count * sizeof(*defaultAdvances));
        if (defaultAdvances == NULL)
            return;
    }

    O2Surface *surface = [_layerStack count] > 0
            ? O2LayerGetSurface([_layerStack lastObject]) : _surface;
    O2SurfaceLock(surface);

    O2Paint *paint = nil;
    @try {
        paint = paintFromColor(gState->_fillColor);
        O2ContextSetupPaintAndBlendMode(self, paint, O2GStateBlendMode(gState));
        O2AffineTransform Trm = O2ContextGetTextRenderingMatrix(self);

        NSPoint point = O2PointApplyAffineTransform(NSMakePoint(0, 0), Trm);

        // Only use the scaling part of the current transform to scale the font size
        O2Float scaleX = sqrt((Trm.a * Trm.a) + (Trm.c * Trm.c));
        O2Float scaleY = sqrt((Trm.b * Trm.b) + (Trm.d * Trm.d));
        O2AffineTransform scalingTransform =
                O2AffineTransformMakeScale(scaleX, scaleY);
        O2Size fontSize = O2SizeApplyAffineTransform(
                O2SizeMake(0, O2GStatePointSize(gState)), scalingTransform);

        [self establishFontStateInDeviceIfDirty];

        O2Font_freetype *font = (O2Font_freetype *) gState->_font;
        FT_Face face = [font face];

        NSUInteger i;
        FT_Error ftError;

        if (face == NULL) {
            NSLog(@"face is NULL");
            return;
        }

        if ((ftError =
                     FT_Set_Char_Size(face, 0, fontSize.height * 64, 72.0, 72.0))) {
            NSLog(@"FT_Set_Char_Size returned %d", ftError);
            return;
        }

        if (advances == NULL)
            O2ContextGetDefaultAdvances(self, glyphs, defaultAdvances, count);

        const O2Size *useAdvances = (advances != NULL) ? advances : defaultAdvances;

        BOOL position = _allowsAntialiasing && gState->_shouldAntialias &&
                _allowsFontSubpixelPositioning && gState->_shouldSubpixelPositionFonts && FT_IS_SCALABLE(face) &&
                !(_allowsFontSubpixelQuantization && gState->_shouldSubpixelQuantizeFonts);
        for (i = 0; i < count; i++) {
            uint8_t phaseX = 0, phaseY = 0;
            NSInteger anchorX = 0, anchorY = 0;
            BOOL valid = !position ||
                    (splitGlyphOrigin(point.x, &anchorX, &phaseX) &&
                     splitGlyphOrigin(point.y, &anchorY, &phaseY));
            O2FreeTypeCachedGlyph *cached = valid
                    ? [font rasterizeGlyph: glyphs[i] pointSize: fontSize.height
                                    phaseX: phaseX phaseY: phaseY] : nil;

            if (cached != nil && (!position || glyphBitmapPosition(anchorX, anchorY,
                    cached->left, cached->top, cached->bitmap.width, cached->bitmap.rows,
                    &anchorX, &anchorY)))
                renderFreeTypeBitmap(self, surface, &cached->bitmap,
                        position ? anchorX : point.x + cached->left,
                        position ? anchorY : point.y - cached->top, paint);

            if (advances != NULL) {
                // Advances are in text space, so only the linear part of Trm
                // applies; that is also what carries the device y-flip.
                O2Size step = O2SizeApplyAffineTransform(advances[i], Trm);

                point.x += step.width;
                point.y += step.height;
            } else if (cached != nil) {
                // Keep FreeType's hinted advance here; defaultAdvances would
                // change what this path renders today. Cost: the draw step and
                // the text-position update below then come from different
                // sources, so chained runs drift by the hinting delta.
                point.x += cached->advance >> 6;
            }
        }

        O2ContextConcatAdvancesToTextMatrix(self, useAdvances, count);
    } @finally {
        O2PaintRelease(paint);
        free(defaultAdvances);
        O2SurfaceUnlock(surface);
    }
}

@end
