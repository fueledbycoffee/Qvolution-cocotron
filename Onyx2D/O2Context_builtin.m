/*
 * Copyright (c) 2007 The Khronos Group Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and /or associated documentation files
 * (the "Materials "), to deal in the Materials without restriction,
 * including without limitation the rights to use, copy, modify, merge,
 * publish, distribute, sublicense, and/or sell copies of the Materials,
 * and to permit persons to whom the Materials are furnished to do so,
 * subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Materials.
 *
 * THE MATERIALS ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
 * DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
 * OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE MATERIALS OR
 * THE USE OR OTHER DEALINGS IN THE MATERIALS.
 */
#import <Onyx2D/O2ClipPhase.h>
#import <Onyx2D/O2ClipState.h>
#import <Onyx2D/O2Color.h>
#import <Onyx2D/O2Context_builtin.h>
#import <Onyx2D/O2Exceptions.h>
#import <Onyx2D/O2GraphicsState.h>
#import <Onyx2D/O2Image.h>
#import <Onyx2D/O2MutablePath.h>
#import <Onyx2D/O2Paint_axialGradient.h>
#import <Onyx2D/O2Paint_color.h>
#import <Onyx2D/O2Paint_image.h>
#import <Onyx2D/O2Paint_pattern.h>
#import <Onyx2D/O2Paint_radialGradient.h>
#import <Onyx2D/O2Shading.h>
#import <Onyx2D/O2Surface.h>
#import <Onyx2D/VGPath.h>

#define MAX_SAMPLES COVERAGE_MULTIPLIER

void O2DContextClipAndFillEdges(O2Context_builtin *self, int fillRuleMask);
static inline O2AffineTransform createImageToSurfaceTransform(O2ImageRef image,
        O2Rect rect, O2AffineTransform deviceTransform);

@implementation O2Context_builtin

+ (BOOL) canInitBitmap {
    return YES;
}

- (void) reallocateForSurface {
    size_t width = O2ImageGetWidth(_surface);

    if (self->_winding != NULL)
        free(self->_winding);
    // +1 is so we can modify the the next winding value without a bounds check
    self->_winding = calloc((width * MAX_SAMPLES) + 1, sizeof(int));
    free(self->_rowIncrease);
    self->_rowIncrease = calloc((width * MAX_SAMPLES) + 1, sizeof(int));
    if (self->_increase != NULL)
        free(self->_increase);
    self->_increase = malloc(width * sizeof(int));
    int i;
    for (i = 0; i < width; i++)
        self->_increase[i] = INT_MAX;
}

- initWithSurface: (O2Surface *) surface flipped: (BOOL) flipped {
    if ((self = [super initWithSurface: surface flipped: flipped]) == nil)
        return nil;

    _clipContext = nil;
    _layerClipPhases = [[NSMutableArray alloc] init];

    O2PaintRef paint =
            [[O2Paint_color alloc] initWithGray: 0
                                          alpha: 1
                        surfaceToPaintTransform: O2AffineTransformIdentity];

    O2ContextSetupPaintAndBlendMode(self, paint, kO2BlendModeNormal);

    O2PaintRelease(paint);

    if (surface != nil) {
        _vpx = 0;
        _vpy = 0;
        _vpwidth = O2SurfaceGetWidth(surface);
        _vpheight = O2SurfaceGetHeight(surface);
    } else {
        _vpwidth = self->_vpheight = 0;
    }

    _edgeCount = 0;
    _edgeCapacity = 256;
    _edges = NSZoneMalloc(NULL, self->_edgeCapacity * sizeof(Edge *));
    _sortCache =
            NSZoneMalloc(NULL, (self->_edgeCapacity / 2 + 1) * sizeof(Edge *));

    sampleSizeShift = 0;
    numSamples = 0;
    samplesWeight = 0;
    samplesX = NSZoneMalloc(NULL, MAX_SAMPLES * sizeof(O2Float));

    O2RasterizerSetViewport(self, 0, 0, O2ImageGetWidth(_surface),
                            O2ImageGetHeight(_surface));
    [self reallocateForSurface];
    return self;
}

- (void) dealloc {
    [_clipContext release];
    [_viewportClipPhases release];
    [_layerClipPhases release];
    free(_clipSamples);
    [_paint release];

    if (_edges != NULL) {
        int i;
        for (i = 0; i < _edgeAllocated; i++)
            NSZoneFree(NULL, _edges[i]);

        NSZoneFree(NULL, _edges);
    }
    if (_sortCache != NULL)
        NSZoneFree(NULL, _sortCache);

    if (_winding != NULL)
        free(_winding);
    if (_increase != NULL)
        free(_increase);
    free(_rowIncrease);
    if (samplesX != NULL)
        NSZoneFree(NULL, samplesX);

    [super dealloc];
}

- (O2Surface *) surface {
    return _surface;
}

- (void) setWidth: (size_t) width
                          height: (size_t) height
        reallocateOnlyIfRequired: (BOOL) roir
{
    [_surface setWidth: width height: height reallocateOnlyIfRequired: roir];
    [self reallocateForSurface];
    O2AffineTransform flip = {1, 0, 0, -1, 0, O2ImageGetHeight(_surface)};
    O2GStateSetDeviceSpaceCTM(O2ContextCurrentGState(self), flip);
    [self clipToState: O2GStateClipState(O2ContextCurrentGState(self))];
}

- (O2Surface *) createSurfaceWithWidth: (size_t) width height: (size_t) height {
    return [[[self surfaceClass] alloc]
               initWithBytes: NULL
                       width: width
                      height: height
            bitsPerComponent: O2ImageGetBitsPerComponent(_surface)
                 bytesPerRow: 0
                  colorSpace: O2ImageGetColorSpace(_surface)
                  bitmapInfo: O2ImageGetBitmapInfo(_surface)];
}

- (O2Size) size {
    return O2SizeMake(O2ImageGetWidth(_surface), O2ImageGetHeight(_surface));
}

- (O2ContextRef) createCompatibleContextWithSize: (O2Size) size
                                          unused: (NSDictionary *) unused
{
    O2Surface *surface = [self createSurfaceWithWidth: ceil(size.width)
                                               height: ceil(size.height)];
    O2ContextRef result = [[[self class] alloc] initWithSurface: surface
                                                        flipped: NO];
    [surface release];
    return result;
}

- (void) beginTransparencyLayerWithInfo: (NSDictionary *) unused {
    O2LayerRef layer = O2LayerCreateWithContext(self, [self size], unused);

    if (layer == nil)
        return;
    NSArray *phases = [O2GStateClipState(O2ContextCurrentGState(self)) clipPhases];
    [_layerClipPhases addObject: phases != nil ?
            [[phases copy] autorelease] : [NSArray array]];
    [self->_layerStack addObject: layer];
    O2LayerRelease(layer);
    O2ContextSaveGState(self);

    /**
     * From Cocoa doc :
     * graphics state parameters remain unchanged except for alpha (which is set
     * to 1), shadow (which is turned off), blend mode (which is set to normal),
     * and other parameters that affect the final composite.
     */
    O2GStateSetBlendMode(O2ContextCurrentGState(self), kO2BlendModeNormal);
    [O2ContextCurrentGState(self) setShadowOffset: O2SizeZero
                                             blur: 0.
                                            color: nil];
    O2GStateSetAlpha(O2ContextCurrentGState(self), 1.);
    [self clipToState: O2GStateClipState(O2ContextCurrentGState(self))];
}

- (void) endTransparencyLayer {
    if ([_stateStack count] > 1) {
        O2GState *restored = [_stateStack objectAtIndex:[_stateStack count] - 2];
        if (restored->_shadowKernel)
            O2ColorSpaceRequireSupportedRendering(O2ColorGetColorSpace(restored->_shadowColor));
    }
    O2LayerRef layer = O2LayerRetain([self->_layerStack lastObject]);

    if (layer == nil)
        return;
    [self->_layerStack removeLastObject];
    [_layerClipPhases removeLastObject];
    O2ContextRestoreGState(self);

    O2Size size = [self size];

    // The layer holds device pixels: composite it without the current user CTM.
    O2GState *gState = O2ContextCurrentGState(self);
    O2AffineTransform base = O2AffineTransformConcat(
            O2AffineTransformInvert(gState->_userSpaceTransform),
            gState->_deviceSpaceTransform);
    O2ContextSaveGState(self);
    O2GStateSetUserSpaceCTM(O2ContextCurrentGState(self),
                            O2AffineTransformIdentity);
    O2GStateSetDeviceSpaceCTM(O2ContextCurrentGState(self), base);

    if (O2ContextCurrentGState(self)->_shadowKernel) {
        O2Surface *shadow =
                [self createSurfaceWithWidth: O2ImageGetWidth(_surface)
                                      height: O2ImageGetHeight(_surface)];

        O2SurfaceGaussianBlur(shadow, O2LayerGetSurface(layer),
                              O2ContextCurrentGState(self)->_shadowKernel,
                              O2ContextCurrentGState(self)->_shadowColor);
        O2ContextDrawImage(
                self,
                O2RectMake(O2ContextCurrentGState(self)->_shadowOffset.width,
                           O2ContextCurrentGState(self)->_shadowOffset.height,
                           size.width, size.height),
                shadow);
        [shadow release];
    }

    O2ContextDrawLayerInRect(self, O2RectMake(0, 0, size.width, size.height),
                             layer);
    O2ContextRestoreGState(self);
    O2LayerRelease(layer);
}

void O2ContextDeviceClipReset_builtin(O2Context_builtin *self) {
    [self->_viewportClipPhases release];
    self->_viewportClipPhases = nil;
    [self->_clipContext release];
    self->_clipContext = nil;
    O2RasterizerSetViewport(self, 0, 0, O2ImageGetWidth(self->_surface),
                            O2ImageGetHeight(self->_surface));
}

static O2Context_builtin *createClipContext(size_t width, size_t height) {
    if (width == 0 || height == 0 || width > INT_MAX || height > INT_MAX ||
            width > SIZE_MAX / sizeof(O2argb32f) ||
            height > SIZE_MAX / (width * sizeof(O2argb32f)))
        return nil;
    O2ColorSpaceRef space = O2ColorSpaceCreateDeviceRGB();
    O2Surface *surface = [[O2Surface alloc] initWithBytes: NULL width: width
            height: height bitsPerComponent: 32 bytesPerRow: 0 colorSpace: space
            bitmapInfo: kO2BitmapFloatComponents | kO2BitmapByteOrder32Little |
                    kO2ImageAlphaPremultipliedLast];
    O2ColorSpaceRelease(space);
    O2Context_builtin *result = surface != nil ? [[O2Context_builtin alloc]
            initWithSurface: surface flipped: YES] : nil;
    [surface release];
    return result;
}

static BOOL allocateClipSamples(O2Context_builtin *context) {
    size_t width = O2ImageGetWidth(context->_surface);
    size_t height = O2ImageGetHeight(context->_surface);
    if (width == 0 || height == 0 || width > SIZE_MAX / (8 * sizeof(uint32_t)) ||
            height > SIZE_MAX / (width * 8 * sizeof(uint32_t)))
        return NO;
    context->_clipSamples = calloc(width * height, 8 * sizeof(uint32_t));
    return context->_clipSamples != NULL;
}

static unsigned clipSampleCount(const uint32_t *samples) {
    unsigned count = 0;
    for (int word = 0; word < 8; word++)
        count += __builtin_popcount(samples[word]);
    return count;
}

static void intersectClipContext(O2Context_builtin *self,
        O2Context_builtin *phase) {
    O2Context_builtin *old = self->_clipContext;
    if (phase != nil && old != nil && old->_clipSamples != NULL &&
            phase->_clipSamples == NULL) {
        if (!allocateClipSamples(phase))
            phase = nil;
        else
            memcpy(phase->_clipSamples, old->_clipSamples,
                    O2ImageGetWidth(self->_surface) * O2ImageGetHeight(self->_surface) *
                    8 * sizeof(uint32_t));
    }
    if (phase == nil) {
        O2ContextDeviceClipReset_builtin(self);
        O2RasterizerSetViewport(self, 0, 0, 0, 0);
        return;
    }
    if (old != nil) {
        size_t width = O2ImageGetWidth(self->_surface);
        size_t height = O2ImageGetHeight(self->_surface);
        O2argb32f pixels[256], previous[256];
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width;) {
                int length = MIN(width - x, 256);
                O2Image_read_argb32f(phase->_surface, x, y, pixels, length);
                O2Image_read_argb32f(old->_surface, x, y, previous, length);
                for (int i = 0; i < length; i++) {
                    if (old->_clipSamples != NULL && phase->_clipSamples != NULL) {
                        size_t offset = ((size_t)y * width + x + i) * 8;
                        uint32_t *bits = phase->_clipSamples + offset;
                        const uint32_t *oldBits = old->_clipSamples + offset;
                        unsigned before = clipSampleCount(oldBits);
                        for (int word = 0; word < 8; word++)
                            bits[word] &= oldBits[word];
                        O2Float ratio = before != 0 ?
                                (O2Float)clipSampleCount(bits) / before : 0;
                        // A copied sample mask denotes a soft phase, whose
                        // scalar value still multiplies the prior coverage.
                        if (phase->_clipIsSoftPhase)
                            ratio *= pixels[i].a;
                        pixels[i] = O2argb32fMultiplyByFloat(previous[i], ratio);
                    } else
                        pixels[i] = O2argb32fMultiplyByFloat(pixels[i], previous[i].a);
                }
                O2SurfaceWriteSpan_largb32f_PRE(phase->_surface, x, y,
                        pixels, length);
                x += length;
            }
    }
    [self->_clipContext release];
    self->_clipContext = [phase retain];
}

// Check device-space corners, including vertical-first and implicitly closed paths.
static BOOL integralRectBounds(O2Path *path, double *x0, double *y0,
        double *x1, double *y1) {
    size_t elements = O2PathNumberOfElements(path);
    const unsigned char *types = O2PathElements(path);
    if (O2PathNumberOfPoints(path) != 4 || (elements != 4 && elements != 5) ||
            types[0] != kO2PathElementMoveToPoint ||
            types[1] != kO2PathElementAddLineToPoint ||
            types[2] != kO2PathElementAddLineToPoint ||
            types[3] != kO2PathElementAddLineToPoint ||
            (elements == 5 && types[4] != kO2PathElementCloseSubpath))
        return NO;
    const O2Point *p = O2PathPoints(path);
    if (!((p[0].y == p[1].y && p[1].x == p[2].x &&
                    p[2].y == p[3].y && p[3].x == p[0].x) ||
            (p[0].x == p[1].x && p[1].y == p[2].y &&
                    p[2].x == p[3].x && p[3].y == p[0].y)))
        return NO;
    *x0 = p[0].x; *y0 = p[0].y;
    *x1 = p[2].x; *y1 = p[2].y;
    return isfinite(*x0) && isfinite(*y0) && isfinite(*x1) && isfinite(*y1) &&
            floor(*x0) == *x0 && floor(*y0) == *y0 &&
            floor(*x1) == *x1 && floor(*y1) == *y1;
}

static BOOL clipToIntegralRect(O2Context_builtin *self, O2Path *path) {
    double x0, y0, x1, y1;
    if (!integralRectBounds(path, &x0, &y0, &x1, &y1))
        return NO;
    // Clamp before converting; huge finite corners need not fit an integer.
    int x = MIN((double)self->_vpx + self->_vpwidth,
            MAX(self->_vpx, MIN(x0, x1)));
    int y = MIN((double)self->_vpy + self->_vpheight,
            MAX(self->_vpy, MIN(y0, y1)));
    int endX = MAX((double)self->_vpx,
            MIN((double)self->_vpx + self->_vpwidth, MAX(x0, x1)));
    int endY = MAX((double)self->_vpy,
            MIN((double)self->_vpy + self->_vpheight, MAX(y0, y1)));
    O2RasterizerSetViewport(self, x, y, MAX(0, endX - x), MAX(0, endY - y));
    return YES;
}

static void clipToPath(O2Context_builtin *self, O2Path *path, int fillRule,
        BOOL antialias) {
    // Binary coverage commutes with path samples and soft masks, including
    // inherited layer domains. Keep their normalization and draw sampling intact.
    if (clipToIntegralRect(self, path))
        return;
    O2Context_builtin *phase = createClipContext(O2ImageGetWidth(self->_surface),
            O2ImageGetHeight(self->_surface));
    if (phase != nil && !allocateClipSamples(phase)) {
        [phase release];
        phase = nil;
    }
    if (phase != nil) {
        O2RasterizerSetShouldAntialias(phase, antialias, antialias ? MAX_SAMPLES : 1);
        O2Paint *paint = [[O2Paint_color alloc] initWithGray: 1 alpha: 1
                surfaceToPaintTransform: O2AffineTransformIdentity];
        O2ContextSetupPaintAndBlendMode(phase, paint, kO2BlendModeCopy);
        [paint release];
        VGPath *vgPath = [[VGPath alloc] initWithKGPath: path];
        VGPathFill(vgPath, O2AffineTransformIdentity, phase);
        O2DContextClipAndFillEdges(phase, fillRule);
        [vgPath release];
    }
    intersectClipContext(self, phase);
    [phase release];
}

void O2ContextDeviceClipToNonZeroPath_builtin(O2Context_builtin *self,
        O2Path *path) {
    clipToPath(self, path, VG_NON_ZERO,
            O2ContextCurrentGState(self)->_shouldAntialias);
}

void O2ContextDeviceClipToEvenOddPath_builtin(O2Context_builtin *self,
        O2Path *path) {
    clipToPath(self, path, VG_EVEN_ODD,
            O2ContextCurrentGState(self)->_shouldAntialias);
}

static O2Surface *createClipMaskImage(O2Image *image) {
    size_t width = O2ImageGetWidth(image), height = O2ImageGetHeight(image);
    size_t bpc = O2ImageGetBitsPerComponent(image);
    size_t bpp = O2ImageGetBitsPerPixel(image);
    size_t row = O2ImageGetBytesPerRow(image);
    O2ColorSpaceRef space = O2ImageGetColorSpace(image);
    if (space == nil || O2ColorSpaceGetModel(space) != kO2ColorSpaceModelMonochrome ||
            O2ColorSpaceGetName(space) != NULL ||
            O2ImageGetAlphaInfo(image) != kO2ImageAlphaNone || O2ImageGetMask(image) != nil)
        return nil;
    if (width == 0 || height == 0 || width > INT_MAX || height > INT_MAX ||
            O2ColorSpaceGetNumberOfComponents(O2ImageGetColorSpace(image)) != 1 ||
            (bpc != 1 && bpc != 8) || bpp != bpc ||
            width > (SIZE_MAX - 7) / bpc || row < (width * bpc + 7) / 8 ||
            row == 0 || height > SIZE_MAX / row)
        return nil;
    NSData *data = [image directData];
    if ([data bytes] == NULL || [data length] < row * height)
        return nil;
    const O2Float *decode = O2ImageGetDecode(image);
    if (decode != NULL && (!isfinite(decode[0]) || !isfinite(decode[1])))
        return nil;
    O2Context_builtin *context = createClipContext(width, height);
    if (context == nil)
        return nil;
    O2Surface *surface = [context->_surface retain];
    O2argb32f pixels[256];
    const uint8_t *bytes = [data bytes];
    for (int y = 0; y < height; y++)
        for (int x = 0; x < width;) {
            int length = MIN(width - x, 256);
            for (int i = 0; i < length; i++) {
                size_t bit = (size_t)(x + i) * bpc;
                O2Float value = bpc == 8 ? bytes[y * row + x + i] / 255.0f :
                        ((bytes[y * row + bit / 8] >> (7 - bit % 8)) & 1);
                if (decode != NULL)
                    value = (1 - value) * decode[0] + value * decode[1];
                value = RI_CLAMP(value, 0, 1);
                if (O2ImageIsMask(image))
                    value = 1 - value;
                pixels[i] = O2argb32fInit(value, value, value, value);
            }
            O2SurfaceWriteSpan_largb32f_PRE(surface, x, y, pixels, length);
            x += length;
        }
    [context release];
    return surface;
}

static BOOL clipMaskTransformIsSafe(O2Image *image, O2Rect rect,
        O2AffineTransform transform, size_t width, size_t height) {
    O2AffineTransform forward = createImageToSurfaceTransform(image, rect, transform);
    O2Float determinant = forward.a * forward.d - forward.b * forward.c;
    if (!isfinite(determinant) || determinant == 0)
        return NO;
    O2AffineTransform inverse = O2AffineTransformInvert(forward);
    O2Float values[] = {forward.a, forward.b, forward.c, forward.d,
            forward.tx, forward.ty, inverse.a, inverse.b, inverse.c, inverse.d,
            inverse.tx, inverse.ty};
    for (int i = 0; i < 12; i++)
        if (!isfinite(values[i]))
            return NO;
    O2Point source[] = {{0, 0}, {O2ImageGetWidth(image), 0},
            {0, O2ImageGetHeight(image)},
            {O2ImageGetWidth(image), O2ImageGetHeight(image)}};
    O2Point destination[] = {{0, 0}, {width, 0}, {0, height}, {width, height}};
    for (int i = 0; i < 4; i++) {
        O2Point p = O2PointApplyAffineTransform(source[i], forward);
        O2Point q = O2PointApplyAffineTransform(destination[i], inverse);
        O2Float coordinates[] = {p.x, p.y, q.x, q.y};
        for (int j = 0; j < 4; j++)
            if (!isfinite(coordinates[j]) || coordinates[j] < INT_MIN + 2.0 ||
                    coordinates[j] > INT_MAX - 2.0)
                return NO;
    }
    return YES;
}

static void clipToMask(O2Context_builtin *self, O2ClipPhase *clipPhase) {
    O2Surface *image = createClipMaskImage(O2ClipPhaseObject(clipPhase));
    O2Context_builtin *phase = image != nil ?
            createClipContext(O2ImageGetWidth(self->_surface),
                    O2ImageGetHeight(self->_surface)) : nil;
    O2Rect rect = O2ClipPhaseRect(clipPhase);
    O2AffineTransform transform = O2ClipPhaseTransform(clipPhase);
    O2Float determinant = transform.a * transform.d - transform.b * transform.c;
    if (!isfinite(rect.origin.x) || !isfinite(rect.origin.y) ||
            !isfinite(rect.size.width) || !isfinite(rect.size.height) ||
            rect.size.width == 0 || rect.size.height == 0 ||
            !isfinite(transform.a) || !isfinite(transform.b) ||
            !isfinite(transform.c) || !isfinite(transform.d) ||
            !isfinite(transform.tx) || !isfinite(transform.ty) ||
            !isfinite(determinant) || determinant == 0) {
        [phase release];
        phase = nil;
    }
    if (phase != nil && !clipMaskTransformIsSafe(image, rect, transform,
            O2ImageGetWidth(self->_surface), O2ImageGetHeight(self->_surface))) {
        [phase release];
        phase = nil;
    }
    if (phase != nil) {
        phase->_clipIsSoftPhase = YES;
        O2GState *target = O2ContextCurrentGState(phase);
        O2GStateSetDeviceSpaceCTM(target, transform);
        target->_interpolationQuality = O2ImageGetShouldInterpolate(
                O2ClipPhaseObject(clipPhase)) ? kO2InterpolationLow : kO2InterpolationNone;
        target->_shouldAntialias = O2ClipPhaseShouldAntialias(clipPhase);
        target->_antialiasingQuality = target->_shouldAntialias ?
                O2ClipPhaseAntialiasingQuality(clipPhase) : 1;
        target->_blendMode = kO2BlendModeCopy;
        [phase drawImage: image inRect: rect];
    }
    intersectClipContext(self, phase);
    [phase release];
    [image release];
}

static void applyClipPhase(O2Context_builtin *self, O2ClipPhase *phase) {
    switch (O2ClipPhasePhaseType(phase)) {
    case O2ClipPhaseNonZeroPath:
        clipToPath(self, O2ClipPhaseObject(phase), VG_NON_ZERO,
                O2ClipPhaseShouldAntialias(phase));
        break;
    case O2ClipPhaseEOPath:
        clipToPath(self, O2ClipPhaseObject(phase), VG_EVEN_ODD,
                O2ClipPhaseShouldAntialias(phase));
        break;
    case O2ClipPhaseMask:
        clipToMask(self, phase);
        break;
    }
}

static void normalizeClipToLayerDomain(O2Context_builtin *self,
        O2Context_builtin *domain) {
    if (self->_clipContext == nil || domain == nil || domain->_clipSamples == NULL)
        return;
    size_t width = O2ImageGetWidth(self->_surface);
    size_t height = O2ImageGetHeight(self->_surface);
    O2argb32f pixels[256];
    for (int y = 0; y < height; y++)
        for (int x = 0; x < width;) {
            int length = MIN(width - x, 256);
            O2Image_read_argb32f(self->_clipContext->_surface, x, y, pixels, length);
            for (int i = 0; i < length; i++) {
                unsigned count = clipSampleCount(domain->_clipSamples +
                        ((size_t)y * width + x + i) * 8);
                O2Float factor = count != 0 ? (O2Float)MAX_SAMPLES / count : 0;
                pixels[i] = O2argb32fMultiplyByFloat(pixels[i], factor);
            }
            O2SurfaceWriteSpan_largb32f_PRE(self->_clipContext->_surface,
                    x, y, pixels, length);
            x += length;
        }
}

static BOOL clipToIntegralRects(O2Context_builtin *self, NSArray *phases) {
    size_t width = O2ImageGetWidth(self->_surface);
    size_t height = O2ImageGetHeight(self->_surface);
    if (width > INT_MAX || height > INT_MAX)
        return NO;
    double minX = 0, minY = 0, maxX = width, maxY = height;
    for (O2ClipPhase *phase in phases) {
        O2ClipPhaseType type = O2ClipPhasePhaseType(phase);
        if (type != O2ClipPhaseNonZeroPath && type != O2ClipPhaseEOPath)
            return NO;
        double x0, y0, x1, y1;
        if (!integralRectBounds(O2ClipPhaseObject(phase), &x0, &y0, &x1, &y1))
            return NO;
        minX = MAX(minX, MIN(x0, x1));
        minY = MAX(minY, MIN(y0, y1));
        maxX = MIN(maxX, MAX(x0, x1));
        maxY = MIN(maxY, MAX(y0, y1));
    }
    int x = MIN((double)width, MAX(0, minX));
    int y = MIN((double)height, MAX(0, minY));
    int endX = MIN((double)width, MAX(0, maxX));
    int endY = MIN((double)height, MAX(0, maxY));
    O2RasterizerSetViewport(self, x, y, MAX(0, endX - x), MAX(0, endY - y));
    return YES;
}

static BOOL hasViewportClip(O2Context_builtin *self) {
    NSArray *phases = [O2GStateClipState(O2ContextCurrentGState(self)) clipPhases];
    if (self->_clipContext == nil && [phases count] != 0)
        return YES;
    // Omitted rectangle samples still require clipped drawing quality, even
    // beside a scalar mask or after resetting the current clip inside a layer.
    for (O2ClipPhase *phase in phases)
        if (O2ClipPhasePhaseType(phase) != O2ClipPhaseMask)
            return YES;
    for (O2ClipPhase *phase in [self->_layerClipPhases lastObject])
        if (O2ClipPhasePhaseType(phase) != O2ClipPhaseMask)
            return YES;
    return NO;
}

- (void) clipToState: (O2ClipState *) clipState {
    NSArray *phases = [clipState clipPhases];
    size_t width = O2ImageGetWidth(_surface), height = O2ImageGetHeight(_surface);
    // Saved states share immutable phases. Only reuse exact integral viewports;
    // masks and transparency domains still replay their coverage operations.
    if (_viewportClipPhases != nil && [_layerClipPhases count] == 0 &&
            _clipContext == nil && width == _viewportClipWidth &&
            height == _viewportClipHeight &&
            _vpx == _viewportClipX && _vpy == _viewportClipY &&
            _vpwidth == _viewportClipW && _vpheight == _viewportClipH &&
            (phases == nil ? [_viewportClipPhases count] == 0 :
                    [phases isEqualToArray: _viewportClipPhases]))
        return;
    NSArray *inherited = [_layerClipPhases lastObject];
    O2ContextDeviceClipReset_builtin(self);
    // Integral device rectangles cover whole pixels; the viewport is exact.
    if ([_layerClipPhases count] == 0 && clipToIntegralRects(self, phases)) {
        _viewportClipPhases = phases != nil ? [phases copy] : [[NSArray alloc] init];
        _viewportClipWidth = width;
        _viewportClipHeight = height;
        _viewportClipX = _vpx;
        _viewportClipY = _vpy;
        _viewportClipW = _vpwidth;
        _viewportClipH = _vpheight;
        return;
    }
    // Layer drawing uses conditional coverage within inherited path samples.
    // The parent applies that domain and inherited soft masks once at composite.
    for (O2ClipPhase *phase in inherited) {
        if (O2ClipPhasePhaseType(phase) != O2ClipPhaseMask)
            applyClipPhase(self, phase);
        if (_vpwidth == 0 || _vpheight == 0)
            return;
    }
    O2Context_builtin *domain = [_clipContext retain];
    for (O2ClipPhase *phase in phases) {
        if (inherited != nil && [inherited indexOfObjectIdenticalTo: phase] != NSNotFound)
            continue;
        applyClipPhase(self, phase);
        if (_vpwidth == 0 || _vpheight == 0)
            break;
    }
    normalizeClipToLayerDomain(self, domain);
    [domain release];
}

ONYX2D_STATIC O2Paint *paintFromColor(O2Context_builtin *self, O2ColorRef color,
                                      O2AffineTransform surfaceToPaintMatrix)
{
    O2Paint *result = nil;
    O2ColorSpaceRequireSupportedRendering(O2ColorGetColorSpace(color));
    O2PatternRef pattern = O2ColorGetPattern(color);

    if (pattern != NULL) {
        O2GState *gState = O2ContextCurrentGState(self);
        O2Size size = [pattern bounds].size;
        O2Surface *surface = [self createSurfaceWithWidth: size.width
                                                   height: size.height];
        O2BitmapContext *context =
                [[[self class] alloc] initWithSurface: surface flipped: NO];

        @try {
            O2ContextClearRect(context, O2RectMake(0, 0, size.width, size.height));
            [pattern drawInContext: context];
            result = [[O2Paint_pattern alloc]
                              initWithImage: surface
                    surfaceToPaintTransform: surfaceToPaintMatrix
                                      phase: O2GStatePatternPhase(gState)];
        } @finally {
            O2ContextRelease(context);
            [surface release];
        }
    } else {
        size_t count = O2ColorGetNumberOfComponents(color);
        const O2Float *components = O2ColorGetComponents(color);

        if (count == 2)
            result = [[O2Paint_color alloc] initWithGray: components[0]
                                                   alpha: components[1]
                                 surfaceToPaintTransform: surfaceToPaintMatrix];
        else if (count == 4)
            result = [[O2Paint_color alloc] initWithRed: components[0]
                                                  green: components[1]
                                                   blue: components[2]
                                                  alpha: components[3]
                                surfaceToPaintTransform: surfaceToPaintMatrix];
        else
            result = [[O2Paint_color alloc] initWithGray: 0
                                                   alpha: 1
                                 surfaceToPaintTransform: surfaceToPaintMatrix];
    }

    return result;
}

- (void) drawPath: (O2PathDrawingMode) drawingMode {
    O2GState *gState = O2ContextCurrentGState(self);

    BOOL usesFill = drawingMode != kO2PathStroke;
    BOOL usesStroke = drawingMode >= kO2PathStroke && gState->_lineWidth > 0;
    if (usesFill)
        O2ColorSpaceRequireSupportedRendering(O2ColorGetColorSpace(gState->_fillColor));
    if (usesStroke)
        O2ColorSpaceRequireSupportedRendering(O2ColorGetColorSpace(gState->_strokeColor));
    O2AffineTransform paintMatrix = O2AffineTransformInvert(gState->_deviceSpaceTransform);
    O2Paint *fillPaint = nil, *strokePaint = nil;
    VGPath *vgPath = nil;
    @try {
        if (usesFill) fillPaint = paintFromColor(self, gState->_fillColor, paintMatrix);
        if (usesStroke) strokePaint = paintFromColor(self, gState->_strokeColor, paintMatrix);

        O2RasterizerSetShouldAntialias(self, gState->_shouldAntialias,
                                       gState->_antialiasingQuality);

        /* Path construction is affected by the CTM, and the stroke pen is affected
         * by the CTM , this means path points and the stroke can be affected by
         * different transforms as the CTM can change during path construction and
         * before stroking. For example, creation of transformed shapes which are
         * drawn using an untransformed pen. The current tesselator expects
         * everything to be in user coordinates and it tesselates from there into
         * device space, but the path points are already in base coordinates. So,
         * path points are brought from base coordinates into the active coordinate
         * space using an inverted transform and then everything is tesselated using
         * the CTM into device space.  */

        O2AffineTransform userToSurfaceMatrix = gState->_deviceSpaceTransform;

        O2PathApplyTransform(_path,
                             O2AffineTransformInvert(gState->_userSpaceTransform));
        vgPath = [[VGPath alloc] initWithKGPath: _path];

        if (drawingMode != kO2PathStroke) {
            O2ContextSetupPaintAndBlendMode(self, fillPaint, gState->_blendMode);

            VGPathFill(vgPath, userToSurfaceMatrix, self);

            VGFillRuleMask fillRule =
                    (drawingMode == kO2PathFill || drawingMode == kO2PathFillStroke)
                            ? VG_NON_ZERO
                            : VG_EVEN_ODD;

            O2DContextClipAndFillEdges(self, fillRule);
        }

        if (drawingMode >= kO2PathStroke) {
            if (gState->_lineWidth > 0.0f) {
                O2ContextSetupPaintAndBlendMode(self, strokePaint, gState->_blendMode);

                O2RasterizerClear(self);

                VGPathStroke(vgPath, userToSurfaceMatrix, self,
                             gState->_dashLengths, gState->_dashLengthsCount,
                             gState->_dashPhase,
                             YES /* context->m_strokeDashPhaseReset ? YES : NO*/,
                             gState->_lineWidth, gState->_lineCap,
                             gState->_lineJoin, RI_MAX(gState->_miterLimit, 1.0f));

                O2DContextClipAndFillEdges(self, VG_NON_ZERO);
            }
        }

        O2RasterizerClear(self);
        O2PathReset(_path);
    } @finally {
        O2ContextSetPaint(self, nil);
        [vgPath release];
        O2PaintRelease(fillPaint);
        O2PaintRelease(strokePaint);
    }
}

- (void) showGlyphs: (const O2Glyph *) glyphs
           advances: (const O2Size *) advances
              count: (NSUInteger) count
{
#if 0
   O2FontRef font=O2ContextCurrentGState(self)->_font;
   int i;
   
   for(i=0;i<count;i++){
    O2Glyph    glyph=glyphs[i];
    O2ImageRef stencil;
   }
#endif
}

- (void) drawShading: (O2Shading *) shading {
    O2ColorSpaceRequireSupportedRendering(O2ShadingColorSpace(shading));
    O2GState *gState = O2ContextCurrentGState(self);
    O2Paint *paint;

    O2RasterizerSetShouldAntialias(self, gState->_shouldAntialias,
                                   gState->_antialiasingQuality);

    if ([shading isAxial])
        paint = [[O2Paint_axialGradient alloc]
                initWithShading: shading
                deviceTransform: gState->_deviceSpaceTransform];
    else
        paint = [[O2Paint_radialGradient alloc]
                initWithShading: shading
                deviceTransform: gState->_deviceSpaceTransform];

    O2ContextSetupPaintAndBlendMode(self, paint, gState->_blendMode);
    O2PaintRelease(paint);

    O2DContextAddEdge(self, O2PointMake(0, 0),
            O2PointMake(0, O2ImageGetHeight(_surface)));
    O2DContextAddEdge(self, O2PointMake(O2ImageGetWidth(_surface), 0),
            O2PointMake(O2ImageGetWidth(_surface), O2ImageGetHeight(_surface)));

    O2DContextClipAndFillEdges(self, VG_NON_ZERO);
    O2ContextSetPaint(self, nil);
    O2RasterizerClear(self);
}

static inline O2AffineTransform
createImageToSurfaceTransform(O2ImageRef image, O2Rect rect,
                              O2AffineTransform deviceTransform)
{
    O2AffineTransform result =
            O2AffineTransformMakeTranslation(rect.origin.x, rect.origin.y);

    result = O2AffineTransformScale(
            result, rect.size.width / (O2Float) O2ImageGetWidth(image),
            rect.size.height / (O2Float) O2ImageGetHeight(image));
    result = O2AffineTransformConcat(result, deviceTransform);

    O2AffineTransform i2u =
            O2AffineTransformMakeTranslation(0, O2ImageGetHeight(image));
    i2u = O2AffineTransformScale(i2u, 1, -1);

    result = O2AffineTransformConcat(i2u, result);

    return result;
}

- (void) drawImage: (O2Image *) image inRect: (O2Rect) rect {
    O2ColorSpaceRequireSupportedRendering(O2ImageGetColorSpace(image));
    O2GState *gState = O2ContextCurrentGState(self);
    O2ImageRef softMask = O2ImageGetMask(image);

    O2AffineTransform imageToSurface = createImageToSurfaceTransform(
            image, rect, gState->_deviceSpaceTransform);
    O2AffineTransform maskToSurface;

    if (softMask == NULL)
        maskToSurface = O2AffineTransformIdentity;
    else
        maskToSurface = createImageToSurfaceTransform(
                softMask, rect, gState->_deviceSpaceTransform);

    // transform image corners into the surface space
    O2Point p0 = O2PointMake(0, 0);
    O2Point p1 = O2PointMake(0, (O2Float) O2ImageGetHeight(image));
    O2Point p2 = O2PointMake((O2Float) O2ImageGetWidth(image),
                             (O2Float) O2ImageGetHeight(image));
    O2Point p3 = O2PointMake((O2Float) O2ImageGetWidth(image), 0);
    p0 = O2PointApplyAffineTransform(p0, imageToSurface);
    p1 = O2PointApplyAffineTransform(p1, imageToSurface);
    p2 = O2PointApplyAffineTransform(p2, imageToSurface);
    p3 = O2PointApplyAffineTransform(p3, imageToSurface);

    O2RasterizerSetShouldAntialias(self, gState->_shouldAntialias,
                                   gState->_antialiasingQuality);

    O2InterpolationQuality iq;
    if (gState->_interpolationQuality == kO2InterpolationDefault)
        iq = kO2InterpolationLow;
    else
        iq = gState->_interpolationQuality;

    O2Paint *imagePaint = [[O2Paint_image allocWithZone: NULL]
                   initWithImage: image
                            mask: softMask
                            mode: VG_DRAW_IMAGE_NORMAL
                           paint: nil
            interpolationQuality: iq
                  surfaceToImage: O2AffineTransformInvert(imageToSurface)
                   surfaceToMask: O2AffineTransformInvert(maskToSurface)];

    O2ContextSetupPaintAndBlendMode(self, imagePaint, gState->_blendMode);

    O2PaintRelease(imagePaint);

    O2DContextAddEdge(self, p0, p1);
    O2DContextAddEdge(self, p1, p2);
    O2DContextAddEdge(self, p2, p3);
    O2DContextAddEdge(self, p3, p0);
    O2DContextClipAndFillEdges(self, VG_EVEN_ODD);

    O2ContextSetPaint(self, nil);

    O2RasterizerClear(self);
}

- (void) drawLayer: (O2LayerRef) layer inRect: (O2Rect) rect {
    O2ImageRef image = O2LayerGetSurface(layer);

    [self drawImage: image inRect: rect];
}

void O2RasterizerSetViewport(O2Context_builtin *self, int x, int y, int width,
                             int height)
{
    RI_ASSERT(vpwidth >= 0 && vpheight >= 0);
    self->_vpx = x;
    self->_vpy = y;
    self->_vpwidth = width;
    self->_vpheight = height;
}

void O2RasterizerClear(O2Context_builtin *self) {
    // Spare edges kept for the next path; a rounded control face is ~3,000.
    // (Inside the function: the native harnesses copy only its body.)
    enum { maxSpareEdges = 65536 };
    // Sorting permutes only _edges[0, _edgeCount), so every allocated edge is
    // still listed once in _edges[0, _edgeAllocated).
    int i;
    for (i = maxSpareEdges; i < self->_edgeAllocated; i++)
        NSZoneFree(NULL, self->_edges[i]);
    self->_edgeAllocated = MIN(self->_edgeAllocated, maxSpareEdges);

    self->_edgeCount = 0;
}

void O2DContextAddEdge(O2Context_builtin *self, const O2Point v0,
                       const O2Point v1)
{

    if (v0.y == v1.y)
        return; // skip horizontal edges (they don't affect rasterization since
                // we scan horizontally)

    if (v0.y < self->_vpy && v1.y < self->_vpy) // ignore below miny
        return;

    int MaxY = self->_vpy + self->_vpheight;

    if (v0.y >= MaxY && v1.y >= MaxY) // ignore above maxy
        return;

    if (self->_edgeCount + 1 >= self->_edgeCapacity) {
        self->_edgeCapacity *= 2;
        self->_edges = NSZoneRealloc(NULL, self->_edges,
                                     self->_edgeCapacity * sizeof(Edge *));
        self->_sortCache =
                NSZoneRealloc(NULL, self->_sortCache,
                              (self->_edgeCapacity / 2 + 1) * sizeof(Edge *));
    }
    // A path's curves become thousands of edges; reuse the previous path's
    // instead of a malloc and free for each.
    if (self->_edgeCount == self->_edgeAllocated)
        self->_edges[self->_edgeAllocated++] = NSZoneMalloc(NULL, sizeof(Edge));
    Edge *edge = self->_edges[self->_edgeCount];
    self->_edgeCount++;

    if (v0.y < v1.y) { // edge is going upward
        edge->v0 = v0;
        edge->v1 = v1;
        edge->direction = 1;
    } else { // edge is going downward
        edge->v0 = v1;
        edge->v1 = v0;
        edge->direction = -1;
    }

    edge->next = NULL;
}

// Returns a radical inverse of a given integer for Hammersley point set.
ONYX2D_STATIC double radicalInverseBase2(unsigned int i) {
    if (i == 0)
        return 0.0;
    double p = 0.0;
    double f = 0.5f;
    double ff = f;
    unsigned int j;
    for (j = 0; j < 32; j++) {
        if (i & (1U << j))
            p += f;
        f *= ff;
    }
    return p;
}

void O2RasterizerSetShouldAntialias(O2Context_builtin *self, BOOL antialias,
                                    int quality)
{
    quality = RI_INT_CLAMP(quality, 1, MAX_SAMPLES);

    self->alias = (!antialias || quality == 1) ? YES : NO;

#if 0
   {
    self->numSamples=1;
			self->samplesX[0] = 0.5;
			self->samplesInitialY = 0.5;
			self->samplesDeltaY = 0;
			self->samplesWeight = MAX_SAMPLES;
   }
   else
#endif

    if (self->numSamples == quality)
        return;

    int shift;
    int numberOfSamples = 1;

    for (shift = 0; numberOfSamples < quality; shift++)
        numberOfSamples <<= 1;

    // quality is a hint and may not match the number of samples, recheck for
    // optimization
    if (self->numSamples == numberOfSamples)
        return;

    self->sampleSizeShift = shift;
    self->numSamples = numberOfSamples;

    self->samplesInitialY = ((O2Float)(0.5f)) / (O2Float) numberOfSamples;
    self->samplesDeltaY = ((O2Float)(1.0f)) / (O2Float) numberOfSamples;

    int i;
    for (i = 0; i < numberOfSamples; i++) {
        // Complementary interior samples avoid a directional bias at pixel centers.
        self->samplesX[i] = numberOfSamples == 1 ? 0.5f :
                (O2Float) radicalInverseBase2(i) +
                ((i & 1) ? 0.75f : 0.25f) / numberOfSamples;
        self->samplesWeight = MAX_SAMPLES / numberOfSamples;
    }
}

ONYX2D_STATIC void O2ApplyCoverageAndMaskToSpan_largb32f_PRE(O2argb32f *dst,
                                                             int icoverage,
                                                             O2Float *mask,
                                                             O2argb32f *src,
                                                             int length)
{
    int i;

    for (i = 0; i < length; i++) {
        O2argb32f r = src[i];
        O2argb32f d = dst[i];
        O2Float coverage = zeroToOneFromCoverage(icoverage);
        O2Float cov = mask[i] * coverage;

        dst[i] = O2argb32fAdd(O2argb32fMultiplyByFloat(r, cov),
                              O2argb32fMultiplyByFloat(d, (1.0f - cov)));
    }
}

ONYX2D_STATIC void O2ApplyCoverageToSpan_largb32f_PRE(O2argb32f *dst,
                                                      int icoverage,
                                                      O2argb32f *src,
                                                      int length)
{
    int i;
    O2Float coverage = zeroToOneFromCoverage(icoverage);

    for (i = 0; i < length; i++) {
        O2argb32f r = src[i];
        O2argb32f d = dst[i];

        dst[i] = O2argb32fAdd(O2argb32fMultiplyByFloat(r, coverage),
                              O2argb32fMultiplyByFloat(d, (1.0f - coverage)));
    }
}

/* Paint functions can selectively paint or not paint at all, e.g. gradients
 * with extend turned off, they do this by returning a negative chunk for a
 * pixels which aren't generated and positive chunk for pixels that are. We need
 * to make sure we cover the entire span so we loop until the span is complete.
 */
ONYX2D_STATIC_INLINE void O2RasterizeWriteCoverageSpan8888_Normal(
        O2Surface *surface, O2Surface *mask, O2Paint *paint, int x, int y,
        int coverage, int length, O2BlendSpan_argb8u blendFunction)
{
    O2argb8u *dst = __builtin_alloca(length * sizeof(O2argb8u));
    O2argb8u *direct = surface->_read_argb8u(surface, x, y, dst, length);

    if (direct != NULL)
        dst = direct;

    O2argb8u *src = __builtin_alloca(length * sizeof(O2argb8u));

    while (YES) {
        int chunk = O2PaintReadSpan_argb8u_PRE(paint, x, y, src, length);

        if (chunk < 0) // skip
            chunk = -chunk;
        else {
            O2argb8u_sover_by_coverage(src, dst, coverage, chunk);
            // FIXME: doesnt handle mask if present

            if (direct == NULL) {
                // write result to the destination surface
                O2SurfaceWriteSpan_argb8u_PRE(surface, x, y, dst, chunk);
            }
        }
        length -= chunk;
        if (length == 0)
            break;

        x += chunk;
        src += chunk;
        dst += chunk;
    }
}

ONYX2D_STATIC_INLINE void O2RasterizeWriteCoverageSpan8888_Copy(
        O2Surface *surface, O2Surface *mask, O2Paint *paint, int x, int y,
        int coverage, int length, O2BlendSpan_argb8u blendFunction)
{
    O2argb8u *dst = __builtin_alloca(length * sizeof(O2argb8u));
    O2argb8u *direct = surface->_read_argb8u(surface, x, y, dst, length);

    if (direct != NULL)
        dst = direct;

    O2argb8u *src = __builtin_alloca(length * sizeof(O2argb8u));

    while (YES) {
        int chunk = O2PaintReadSpan_argb8u_PRE(paint, x, y, src, length);

        if (chunk < 0) // skip
            chunk = -chunk;
        else {
            O2argb8u_copy_by_coverage(src, dst, coverage, chunk);
            // FIXME: doesnt handle mask if present

            if (direct == NULL) {
                // write result to the destination surface
                O2SurfaceWriteSpan_argb8u_PRE(surface, x, y, dst, chunk);
            }
        }

        length -= chunk;
        if (length == 0)
            break;

        x += chunk;
        src += chunk;
        dst += chunk;
    }
}

ONYX2D_STATIC_INLINE void
O2RasterizeWriteCoverageSpan8888(O2Surface *surface, O2Surface *mask,
                                 O2Paint *paint, int x, int y, int coverage,
                                 int length, O2BlendSpan_argb8u blendFunction)
{
    O2argb8u *dst = __builtin_alloca(length * sizeof(O2argb8u));
    O2argb8u *direct = surface->_read_argb8u(surface, x, y, dst, length);

    if (direct != NULL)
        dst = direct;

    O2argb8u *src = __builtin_alloca(length * sizeof(O2argb8u));

    while (YES) {
        int chunk = O2PaintReadSpan_argb8u_PRE(paint, x, y, src, length);

        if (chunk < 0) // skip
            chunk = -chunk;
        else {
            blendFunction(src, dst, chunk);

            // apply masking
            if (mask == NULL)
                O2ApplyCoverageToSpan_largb8u_PRE(dst, coverage, src, chunk);
            else {
                uint8_t maskSpan[chunk];

                O2Image_read_a8u(mask, x, y, maskSpan, chunk);
                O2ApplyCoverageAndMaskToSpan_largb8u_PRE(dst, coverage,
                                                         maskSpan, src, chunk);
            }

            if (direct == NULL) {
                // write result to the destination surface
                O2SurfaceWriteSpan_argb8u_PRE(surface, x, y, dst, chunk);
            }
        }

        length -= chunk;
        if (length == 0)
            break;

        x += chunk;
        src += chunk;
        dst += chunk;
    }
}

ONYX2D_STATIC_INLINE void
O2RasterizeWriteCoverageSpanffff(O2Surface *surface, O2Surface *mask,
                                 O2Paint *paint, int x, int y, int coverage,
                                 int length, O2BlendSpan_argb32f blendFunction)
{
    O2argb32f dst[256], src[256];
    O2Float maskSpan[256];
    BOOL fullCopy = coverage == COVERAGE_MULTIPLIER && mask == nil &&
            blendFunction == O2BlendSpanCopy_ffff &&
            O2SurfaceCanReadWriteARGB8u(surface);
    O2argb32f color;
    if (fullCopy && O2PaintGetConstantColor(paint, &color) &&
            O2SurfaceWriteRepeatedColor(surface, x, y, color, length))
        return;
    while (length > 0) {
        int requested = MIN(length, 256);
        int chunk = O2PaintReadSpan_largb32f_PRE(paint, x, y, src, requested);
        if (chunk == 0 || chunk > requested || chunk < -requested)
            return;
        if (chunk < 0)
            chunk = -chunk;
        else if (fullCopy)
            O2SurfaceWriteSpan_largb32f_PRE(surface, x, y, src, chunk);
        else {
            O2Image_read_argb32f(surface, x, y, dst, chunk);
            blendFunction(src, dst, chunk);
            if (mask == NULL)
                O2ApplyCoverageToSpan_largb32f_PRE(dst, coverage, src, chunk);
            else {
                O2ImageReadSpan_Af_MASK(mask, x, y, maskSpan, chunk);
                O2ApplyCoverageAndMaskToSpan_largb32f_PRE(dst, coverage,
                                                          maskSpan, src, chunk);
            }
            O2SurfaceWriteSpan_largb32f_PRE(surface, x, y, dst, chunk);
        }
        length -= chunk;
        x += chunk;
    }
}

// Both text backends use byte glyph coverage, including on float destinations.
// Keep destination pixels intact until the selected blend and both coverages
// have been combined. Paint may return negative spans to skip pixels.
void O2ContextWriteGlyphCoverageSpanFloat(O2Context_builtin *self,
        O2Surface *surface, O2Paint *paint, int x, int y,
        const uint8_t *coverage, int length) {
    O2argb32f dst[256], src[256];
    O2Float maskSpan[256];
    O2Surface *mask = self->_clipContext != nil
            ? self->_clipContext->_surface : nil;
    while (length > 0) {
        int requested = MIN(length, 256);
        int chunk = O2PaintReadSpan_largb32f_PRE(paint, x, y, src, requested);
        if (chunk == 0 || chunk > requested || chunk < -requested)
            return;
        if (chunk < 0)
            chunk = -chunk;
        else {
            O2Image_read_argb32f(surface, x, y, dst, chunk);
            self->_blend_argb32f_PRE(src, dst, chunk);
            if (mask != nil)
                O2ImageReadSpan_Af_MASK(mask, x, y, maskSpan, chunk);
            for (int i = 0; i < chunk; i++) {
                O2Float factor = coverage[i] / 255.0f;
                if (mask != nil)
                    factor *= maskSpan[i];
                dst[i] = O2argb32fAdd(O2argb32fMultiplyByFloat(src[i], factor),
                        O2argb32fMultiplyByFloat(dst[i], 1.0f - factor));
            }
            O2SurfaceWriteSpan_largb32f_PRE(surface, x, y, dst, chunk);
        }
        length -= chunk;
        x += chunk;
        coverage += chunk;
    }
}

ONYX2D_STATIC_INLINE void sortEdgesByMinY(Edge **edges, int count, Edge **B) {
    int h, i, j, k, l, m, n = count;
    Edge *A;

    for (h = 1; h < n; h += h) {
        for (m = n - 1 - h; m >= 0; m -= h + h) {
            l = m - h + 1;
            if (l < 0)
                l = 0;

            for (i = 0, j = l; j <= m; i++, j++)
                B[i] = edges[j];

            for (i = 0, k = l; k < j && j <= m + h; k++) {
                A = edges[j];
                if (A->v0.y > B[i]->v0.y)
                    edges[k] = B[i++];
                else {
                    edges[k] = A;
                    j++;
                }
            }

            while (k < j)
                edges[k++] = B[i++];
        }
    }
}

// One edge's value at one sample; compared against the pixel's pcxnormal.
ONYX2D_STATIC_INLINE O2Float edgeSampleValue(O2Float sampleY, O2Float sampleX,
                                             O2Float normalX, O2Float normalY)
{
    return sampleY * normalY - sampleX * normalX;
}

// An edge shorter than half a pixel never covers every sample row of a
// scanline, so only the rows it crosses are ever compared; those are computed
// per scanline in FillEdgesOnSurface instead of all numSamples here.
ONYX2D_STATIC_INLINE BOOL edgeUsesRowSamples(O2Context_builtin *self, Edge *edge) {
    return self->numSamples > 1 && edge->v1.y - edge->v0.y < 0.5f;
}

ONYX2D_STATIC_INLINE void initEdgeForAET(O2Context_builtin *self, Edge *edge,
                                         int scany)
{
    // compute edge min and max x-coordinates for this scanline

    O2Point vd = Vector2Subtract(edge->v1, edge->v0);
    O2Float wl = 1.0f / vd.y;
    edge->vdxwl = vd.x * wl;

    if (edge->v0.x < edge->v1.x) {
        edge->isVertical = 0;
        edge->bminx = edge->v0.x;
        edge->bmaxx = edge->v1.x;
    } else {
        edge->isVertical = (edge->v0.x == edge->v1.x) ? 1 : 0;
        edge->bminx = edge->v1.x;
        edge->bmaxx = edge->v0.x;
    }

    edge->sxPre = edge->v0.x - (edge->v0.y * edge->vdxwl);
    edge->exPre = edge->sxPre;
    edge->sxPre += (scany - 1) * edge->vdxwl;
    edge->exPre += (scany + 1) * edge->vdxwl;

    O2Float autosx = RI_CLAMP(edge->sxPre, edge->bminx, edge->bmaxx);
    O2Float autoex = RI_CLAMP(edge->exPre, edge->bminx, edge->bmaxx);
    O2Float minx = RI_MIN(autosx, autoex);

    edge->minx = MAX(self->_vpx, minx);
    if (edgeUsesRowSamples(self, edge)) {
        edge->samples = NULL;
        return;
    }
    edge->samples = NSZoneMalloc(NULL, sizeof(O2Float) * self->numSamples);

    O2Float *pre = edge->samples;
    int i, numberOfSamples = self->numSamples;
    O2Float sampleY = self->samplesInitialY;
    O2Float deltaY = self->samplesDeltaY;
    O2Float *samplesX = self->samplesX;

    O2Float normalX = edge->v0.y - edge->v1.y;
    O2Float normalY = edge->v0.x - edge->v1.x;
    O2Float min = 0, max = 0;

    for (i = 0; i < numberOfSamples; sampleY += deltaY, samplesX++, i++) {
        O2Float value = edgeSampleValue(sampleY, *samplesX, normalX, normalY);

        *pre++ = value;

        if (i == 0)
            min = max = value;
        else {
            min = MIN(min, value);
            max = MAX(max, value);
        }
    }
    edge->minSample = min;
    edge->maxSample = max;
}

ONYX2D_STATIC_INLINE void incrementEdgeForAET(Edge *edge, int vpx) {
    edge->sxPre += edge->vdxwl;
    edge->exPre += edge->vdxwl;

    O2Float autosx = RI_CLAMP(edge->sxPre, edge->bminx, edge->bmaxx);
    O2Float autoex = RI_CLAMP(edge->exPre, edge->bminx, edge->bmaxx);
    O2Float minx = RI_MIN(autosx, autoex);

    edge->minx = MAX(vpx, minx);
}

ONYX2D_STATIC_INLINE void removeEdgeFromAET(Edge *edge) {
    if (edge->samples != NULL)
        NSZoneFree(NULL, edge->samples);
}

// The first index in [low, high) whose sample row is not below y, or high:
// the count the original linear walk (row < y, row += deltaY) reached.
ONYX2D_STATIC_INLINE int firstSampleRowNotBelow(const O2Float *rows, int low,
                                                int high, O2Float y)
{
    while (low < high) {
        int middle = low + (high - low) / 2;
        if (rows[middle] < y)
            low = middle + 1;
        else
            high = middle;
    }
    return low;
}

typedef struct CoverageNode {
    struct CoverageNode *next;
    int scanx;
    int coverage;
    int length;
    uint32_t samples[8];
} CoverageNode;

static void writeCoverageNode(O2Context_builtin *self, O2Surface *surface,
        O2Surface *mask, O2Paint *paint, CoverageNode *node, int y) {
    size_t width = O2ImageGetWidth(self->_surface);
    O2Context_builtin *clip = self->_clipContext;
    if (self->_clipSamples != NULL)
        for (int x = node->scanx; x < node->scanx + node->length; x++)
            memcpy(self->_clipSamples + ((size_t)y * width + x) * 8,
                    node->samples, sizeof(node->samples));
    if (clip != nil && clip->_clipSamples != NULL) {
        for (int x = node->scanx; x < node->scanx + node->length; x++) {
            const uint32_t *bits = clip->_clipSamples + ((size_t)y * width + x) * 8;
            unsigned before = clipSampleCount(bits), after = 0;
            for (int word = 0; word < 8; word++)
                after += __builtin_popcount(bits[word] & node->samples[word]);
            if (before != 0 && after != 0) {
                int coverage = (after * COVERAGE_MULTIPLIER + before / 2) / before;
                self->_writeCoverageFunction(surface, mask, paint, x, y,
                        coverage, 1, self->_blendFunction);
            }
        }
    } else
        self->_writeCoverageFunction(surface, mask, paint, node->scanx, y,
                node->coverage, node->length, self->_blendFunction);
}

void O2DContextFillEdgesOnSurface(O2Context_builtin *self, O2Surface *surface,
                                  O2Image *mask, O2Paint *paint,
                                  int fillRuleMask)
{
    int edgeCount = self->_edgeCount;
    Edge **edges = self->_edges;

    CoverageNode *freeCoverage = NULL;
    CoverageNode *currentCoverage = NULL;

    sortEdgesByMinY(edges, edgeCount, self->_sortCache);

    int ylimit = self->_vpy + self->_vpheight;
    int xlimit = self->_vpx + self->_vpwidth;
    int firstY = self->_vpy;

    // Partial-row edges otherwise propagate winding to the viewport's right
    // edge, even for a one-pixel ruler tick. Closed geometry has no coverage
    // beyond its last edge. Keep the original pixel sample coordinates.
    double minY = ylimit, maxY = firstY, minX = xlimit, maxX = self->_vpx;
    BOOL finiteBounds = YES;
    for (int i = 0; i < edgeCount; i++) {
        Edge *edge = edges[i];
        if (!isfinite(edge->v0.x) || !isfinite(edge->v1.x) ||
                !isfinite(edge->v0.y) || !isfinite(edge->v1.y)) {
            finiteBounds = NO;
            break;
        }
        minY = MIN(minY, edge->v0.y);
        maxY = MAX(maxY, edge->v1.y);
        minX = MIN(minX, MIN(edge->v0.x, edge->v1.x));
        maxX = MAX(maxX, MAX(edge->v0.x, edge->v1.x));
    }
    if (finiteBounds) {
        firstY = MAX(firstY, floor(MAX((double)firstY, minY)));
        ylimit = MIN(ylimit, ceil(MIN((double)ylimit, maxY)));
        xlimit = MIN(xlimit, ceil(MIN((double)xlimit, maxX)));
    }
    // Report what the sweep can write before writing it: rows [firstY,
    // ylimit) and, coverage being zero left of every edge, columns from the
    // leftmost edge's pixel up to xlimit.
    int firstX = finiteBounds
            ? (int)MIN((double)xlimit, MAX((double)self->_vpx, floor(minX)))
            : self->_vpx;
    O2SurfaceAddDamage(surface, firstX, firstY, xlimit - firstX, ylimit - firstY);

    Edge *activeRoot = NULL;
    int nextAvailableEdge = 0;

    int scany;

    int *winding = self->_winding;
    int *rowIncrease = self->_rowIncrease;
    // Sample row offsets as initEdgeForAET accumulates them, and this
    // scanline's sample rows as the original below/above walk accumulated them.
    O2Float sampleRowY[MAX_SAMPLES], scanRowY[MAX_SAMPLES], rowPre[MAX_SAMPLES];
    sampleRowY[0] = self->samplesInitialY;
    for (int row = 1; row < self->numSamples; row++)
        sampleRowY[row] = sampleRowY[row - 1] + self->samplesDeltaY;
    int numberOfSamples = self->numSamples;
    int shiftNumberOfSamples = self->sampleSizeShift;
    int totalActiveEdges = 0;
    int totalActiveVerticalEdgesFullCoverage = 0;

    for (scany = firstY; scany < ylimit; scany++) {
        Edge *edge, *previous = NULL;
        int unchangedActiveEdges = 1;

        // increment and remove edges out of range
        for (edge = activeRoot; edge != NULL; edge = edge->next) {
            if (edge->v1.y > scany) {
                incrementEdgeForAET(edge, self->_vpx);
                previous = edge;

                if (edge->isVertical) {
                    if (edge->v0.y < scany && edge->v1.y >= (scany + 1)) {
                        if (!edge->isFullCoverage) {
                            edge->isFullCoverage = 1;
                            unchangedActiveEdges = 0;
                            totalActiveVerticalEdgesFullCoverage++;
                        }
                    } else {
                        if (edge->isFullCoverage) {
                            edge->isFullCoverage = 0;
                            unchangedActiveEdges = 0;
                            totalActiveVerticalEdgesFullCoverage--;
                        }
                    }
                }
            } else {
                unchangedActiveEdges = 0;

                totalActiveEdges--;
                if (edge->isVertical && edge->isFullCoverage)
                    totalActiveVerticalEdgesFullCoverage--;

                removeEdgeFromAET(edge);
                if (previous == NULL)
                    activeRoot = edge->next;
                else
                    previous->next = edge->next;
            }
        }

        // load more available edges
        for (; nextAvailableEdge < edgeCount; nextAvailableEdge++) {
            edge = edges[nextAvailableEdge];

            if (edge->v0.y >= (scany + 1))
                break;

            unchangedActiveEdges = 0;
            edge->next = activeRoot;
            activeRoot = edge;
            initEdgeForAET(self, edge, scany);
            totalActiveEdges++;

            if (edge->isVertical) {
                if (edge->v0.y < scany && edge->v1.y >= (scany + 1)) {
                    edge->isFullCoverage = 1;
                    totalActiveVerticalEdgesFullCoverage++;
                } else {
                    edge->isFullCoverage = 0;
                }
            }
        }

        if (unchangedActiveEdges) {
            if (activeRoot == NULL && nextAvailableEdge == edgeCount)
                break;

            if (totalActiveVerticalEdgesFullCoverage == totalActiveEdges) {
                CoverageNode *node;

                for (node = currentCoverage; node != NULL; node = node->next) {
#if 0
       if(node->scanx<self->_vpx || node->scanx+node->length>xlimit || scany>=ylimit || scany<self->_vpy){
        NSLog(@"drawing out of viewport, node %d %d %d",node->scanx,scany,node->length);
        NSLog(@"viewport=%d %d %d %d",self->_vpx,self->_vpy,self->_vpwidth,self->_vpheight);
        NSLog(@"xlimit=%d,ylimit=%d",xlimit,ylimit);
        }
#endif
                    writeCoverageNode(self, surface, mask, paint, node, scany);
                }
                continue;
            }
        }

        int minx = xlimit, maxx = 0;
        int *increase = self->_increase;
        scanRowY[0] = scany + self->samplesInitialY;
        for (int row = 1; row < numberOfSamples; row++)
            scanRowY[row] = scanRowY[row - 1] + self->samplesDeltaY;
        // From this pixel on, every pixel is its own coverage span, as when
        // edges ending inside the row wrote each pixel up to xlimit.
        int splitFrom = xlimit;

        for (edge = activeRoot; edge != NULL; edge = edge->next) {
            if (edge->minx >= xlimit) {
                maxx = MAX(maxx, xlimit);
                continue;
            }

            O2Float v0y = edge->v0.y;
            O2Float v1y = edge->v1.y;

            int belowY = firstSampleRowNotBelow(scanRowY, 0, numberOfSamples, v0y);
            int aboveY;

            if (scany + 1 < v1y)
                aboveY = numberOfSamples;
            else
                aboveY = firstSampleRowNotBelow(scanRowY, belowY, numberOfSamples, v1y);

            // it is possible for the edge to be inside the scanline a tiny bit
            // and below/above first/last sample, skip it
            if (aboveY - belowY == 0)
                continue;

            int direction = edge->direction;
            int scanx = edge->minx;

            minx = MIN(minx, scanx);

            O2Float normalX = edge->v0.y - edge->v1.y;
            O2Float normalY = edge->v0.x - edge->v1.x;
            O2Float pcxnormal = (scanx - edge->v0.x) * normalX -
                                (scany - edge->v0.y) * normalY;

            int *windptr = winding + (scanx << shiftNumberOfSamples);

            O2Float *pre = edge->samples;
            O2Float minSample = pre != NULL ? edge->minSample : 0;
            if (pre == NULL) {
                // A short edge always ends inside the row; its rows decide
                // when every later pixel takes the carried contribution.
                pre = rowPre;
                for (int row = belowY; row < aboveY; row++) {
                    pre[row] = edgeSampleValue(sampleRowY[row], self->samplesX[row],
                                               normalX, normalY);
                    minSample = row == belowY ? pre[row] : MIN(minSample, pre[row]);
                }
            }

            for (;; pcxnormal += normalX, windptr += numberOfSamples) {
                /*
                  Some edges do have pcxnormal>edge->maxSample when the normalX
                  is less than zero we should be able to eliminate that
                  condition prior to the loop to avoid an iteration.

                  For now they just end up in the general loop
                 */

                if (increase[scanx] == INT_MAX)
                    increase[scanx] = 0;

                if (pcxnormal <= minSample) {
                    windptr[belowY] += direction;

                    if (aboveY != numberOfSamples)
                        windptr[aboveY] -= direction;
                    else if (belowY == 0) {
                        increase[scanx] += direction;
                        break;
                    }
                    // Every sample of every later pixel is right of this
                    // edge too, so each would get the same rows. Carry them
                    // instead of writing every pixel up to xlimit, which
                    // made filling short curve segments cost O(width).
                    int *carry = rowIncrease + (scanx << shiftNumberOfSamples);
                    carry[belowY] += direction;
                    if (aboveY != numberOfSamples)
                        carry[aboveY] -= direction;
                    splitFrom = MIN(splitFrom, scanx + 1);
                    // The walk used to end at xlimit, so the coverage loop
                    // still runs that far: an unclosed edge set leaves
                    // winding past the last edge, and it must stay painted.
                    maxx = xlimit;
                    break;
                } else {
                    int idx = belowY;

                    while (idx < aboveY) {
                        if (pcxnormal <= pre[idx]) {
                            windptr[idx] += direction;
                            windptr[idx + 1] -= direction;
                        }

                        idx++;
                    }

                    if (aboveY == numberOfSamples) {
                        // if we overwrote past the last value, undo it, this is
                        // cheaper than not writing it
                        if (pcxnormal <= pre[idx - 1])
                            windptr[idx] += direction;
                    }
                }

                scanx++;
                if (scanx == xlimit)
                    break;
            }

            maxx = MAX(maxx, scanx);
        }
        minx = MAX(self->_vpx, minx);
        maxx = MIN(xlimit, maxx + 1);

        int *maxAdvance = increase + maxx;
        int *splitAdvance = increase + splitFrom;
        int carried[MAX_SAMPLES] = {0};

        increase += minx;
        for (; increase < maxAdvance; increase++)
            if (*increase != INT_MAX) {
                break;
            }

        int accum = 0;

        int *windptr = winding +
                       ((increase - self->_increase) << shiftNumberOfSamples);
        int *windend = windptr + numberOfSamples;

        CoverageNode *node;
        for (node = currentCoverage; node != NULL;) {
            CoverageNode *next = node->next;
            node->next = freeCoverage;
            freeCoverage = node;
            node = next;
        }
        currentCoverage = NULL;

        // An untouched pixel (only past splitFrom) has no winding of its
        // own, so it repeats the last untouched pixel until accum or the
        // carried rows change, which only a touched pixel does.
        BOOL reusable = NO;
        int reusedCoverage = 0;
        uint32_t reusedBits[8];

        for (; increase < maxAdvance;) {
            int total = accum;
            int coverage = 0;
            uint32_t sampleBits[8] = {0};
            unsigned sampleIndex = 0;
            int *carriedRow = carried;
            BOOL untouched = *increase == INT_MAX;

            if (untouched && reusable) {
                coverage = reusedCoverage;
                memcpy(sampleBits, reusedBits, sizeof(sampleBits));
                windptr = windend;
            } else if (fillRuleMask == 1) {
                do {
                    total += *windptr + *carriedRow++;

                    if (total & 0x01) {
                        coverage++;
                        sampleBits[sampleIndex / 32] |= 1U << (sampleIndex % 32);
                    }
                    sampleIndex++;
                    *windptr++ = 0;
                } while (windptr < windend);
            } else {
                do {
                    total += *windptr + *carriedRow++;

                    if (total) {
                        coverage++;
                        sampleBits[sampleIndex / 32] |= 1U << (sampleIndex % 32);
                    }
                    sampleIndex++;
                    *windptr++ = 0;
                } while (windptr < windend);
            }
            if (untouched && !reusable) {
                reusable = YES;
                reusedCoverage = coverage;
                memcpy(reusedBits, sampleBits, sizeof(sampleBits));
            } else if (!untouched)
                reusable = NO;

            int *advance = increase + 1;
            for (; advance < maxAdvance && advance < splitAdvance; advance++)
                if (*advance != INT_MAX) {
                    break;
                }

            if (coverage > 0) {

                if (self->alias) {
                    coverage = 256;
                    for (int word = 0; word < 8; word++)
                        sampleBits[word] = UINT32_MAX;
                } else
                    coverage *= self->samplesWeight;

                int scanx = increase - self->_increase;

                CoverageNode *node;

                if (freeCoverage == NULL)
                    node = NSZoneMalloc(NULL, sizeof(CoverageNode));
                else {
                    node = freeCoverage;
                    freeCoverage = freeCoverage->next;
                }
                node->next = currentCoverage;
                currentCoverage = node;
                node->scanx = scanx;
                node->coverage = coverage;
                node->length = (advance - increase);
                memcpy(node->samples, sampleBits, sizeof(sampleBits));
            }

            windend += (advance - increase) << shiftNumberOfSamples;
            windptr = windend - numberOfSamples;

            // Pixels from splitFrom on may be untouched (INT_MAX): no change,
            // and only a touched pixel can hold carried rows.
            if (!untouched) {
                accum += *increase;
                int *rowCarry = rowIncrease +
                        ((increase - self->_increase) << shiftNumberOfSamples);
                for (int row = 0; row < numberOfSamples; row++) {
                    carried[row] += rowCarry[row];
                    rowCarry[row] = 0;
                }
            }
            *increase = INT_MAX;
            increase = advance;
        }

        for (node = currentCoverage; node != NULL; node = node->next) {
#if 0
#warning viewport assert enabled
       if(node->scanx<self->_vpx || node->scanx+node->length>xlimit || scany>=ylimit || scany<self->_vpy){
        NSLog(@"drawing out of viewport, node %d %d %d",node->scanx,scany,node->length);
        NSLog(@"viewport=%d %d %d %d",self->_vpx,self->_vpy,self->_vpwidth,self->_vpheight);
        NSLog(@"xlimit=%d,ylimit=%d",xlimit,ylimit);
        }
#endif
            writeCoverageNode(self, surface, mask, paint, node, scany);
        }
    }

    for (; activeRoot != NULL; activeRoot = activeRoot->next)
        removeEdgeFromAET(activeRoot);

    CoverageNode *node, *next;
    for (node = freeCoverage; node != NULL; node = next) {
        next = node->next;
        NSZoneFree(NULL, node);
    }
    for (node = currentCoverage; node != NULL; node = next) {
        next = node->next;
        NSZoneFree(NULL, node);
    }
}

void O2DContextClipAndFillEdges(O2Context_builtin *self, int fillRuleMask) {
    O2Image *mask =
            (self->_clipContext != nil) ? self->_clipContext->_surface : nil;
    O2Surface *surface;

    if ([self->_layerStack count] > 0)
        surface = O2LayerGetSurface([self->_layerStack lastObject]);
    else
        surface = self->_surface;

    if ((self->_clipContext != nil && self->_clipContext->_clipSamples != NULL) ||
            hasViewportClip(self)) {
        O2GState *state = O2ContextCurrentGState(self);
        O2RasterizerSetShouldAntialias(self, state->_shouldAntialias,
                state->_shouldAntialias ? MAX_SAMPLES : 1);
    }
    O2DContextFillEdgesOnSurface(self, surface, mask, self->_paint,
                                 fillRuleMask);
}

void O2ContextSetupPaintAndBlendMode(O2Context_builtin *self, O2PaintRef paint,
                                     O2BlendMode blendMode)
{
    RI_ASSERT(blendMode >= kO2BlendModeNormal &&
              blendMode <= kO2BlendModePlusLighter);

    self->_blend_argb8u_PRE = NULL;
    self->_writeCoverage_argb8u_PRE = NULL;

    O2Float alpha = O2ContextCurrentGState(self)->_alpha;
    if (alpha == 1)
        O2ContextSetPaint(self, paint);
    else {
        O2PaintRef source = O2PaintCreateWithAlpha(paint, alpha);
        O2ContextSetPaint(self, source);
        O2PaintRelease(source);
    }
    paint = self->_paint;

    if (O2PaintIsOpaque(self->_paint) && (blendMode == kO2BlendModeNormal))
        blendMode = kO2BlendModeCopy;

    switch (blendMode) {

    case kO2BlendModeNormal:
        self->_blend_argb8u_PRE = O2BlendSpanNormal_8888;
        self->_blend_argb32f_PRE = O2BlendSpanNormal_ffff;
        self->_writeCoverage_argb8u_PRE =
                O2RasterizeWriteCoverageSpan8888_Normal;
        break;

    case kO2BlendModeMultiply:
        self->_blend_argb32f_PRE = O2BlendSpanMultiply_ffff;
        break;

    case kO2BlendModeScreen:
        self->_blend_argb32f_PRE = O2BlendSpanScreen_ffff;
        break;

    case kO2BlendModeOverlay:
        self->_blend_argb32f_PRE = O2BlendSpanOverlay_ffff;
        break;

    case kO2BlendModeDarken:
        self->_blend_argb32f_PRE = O2BlendSpanDarken_ffff;
        break;

    case kO2BlendModeLighten:
        self->_blend_argb32f_PRE = O2BlendSpanLighten_ffff;
        break;

    case kO2BlendModeColorDodge:
        self->_blend_argb32f_PRE = O2BlendSpanColorDodge_ffff;
        break;

    case kO2BlendModeColorBurn:
        self->_blend_argb32f_PRE = O2BlendSpanColorBurn_ffff;
        break;

    case kO2BlendModeHardLight:
        self->_blend_argb32f_PRE = O2BlendSpanHardLight_ffff;
        break;

    case kO2BlendModeSoftLight:
        self->_blend_argb32f_PRE = O2BlendSpanSoftLight_ffff;
        break;

    case kO2BlendModeDifference:
        self->_blend_argb32f_PRE = O2BlendSpanDifference_ffff;
        break;

    case kO2BlendModeExclusion:
        self->_blend_argb32f_PRE = O2BlendSpanExclusion_ffff;
        break;

    case kO2BlendModeHue:
        self->_blend_argb32f_PRE = O2BlendSpanHue_ffff;
        break;

    case kO2BlendModeSaturation:
        self->_blend_argb32f_PRE = O2BlendSpanSaturation_ffff;
        break;

    case kO2BlendModeColor:
        self->_blend_argb32f_PRE = O2BlendSpanColor_ffff;
        break;

    case kO2BlendModeLuminosity:
        self->_blend_argb32f_PRE = O2BlendSpanLuminosity_ffff;
        break;

    case kO2BlendModeClear:
        self->_blend_argb8u_PRE = O2BlendSpanClear_8888;
        self->_blend_argb32f_PRE = O2BlendSpanClear_ffff;
        break;

    case kO2BlendModeCopy:
        self->_blend_argb8u_PRE = O2BlendSpanCopy_8888;
        self->_blend_argb32f_PRE = O2BlendSpanCopy_ffff;
        self->_writeCoverage_argb8u_PRE = O2RasterizeWriteCoverageSpan8888_Copy;
        break;

    case kO2BlendModeSourceIn:
        self->_blend_argb8u_PRE = O2BlendSpanSourceIn_8888;
        self->_blend_argb32f_PRE = O2BlendSpanSourceIn_ffff;
        break;

    case kO2BlendModeSourceOut:
        self->_blend_argb32f_PRE = O2BlendSpanSourceOut_ffff;
        break;

    case kO2BlendModeSourceAtop:
        self->_blend_argb32f_PRE = O2BlendSpanSourceAtop_ffff;
        break;

    case kO2BlendModeDestinationOver:
        self->_blend_argb32f_PRE = O2BlendSpanDestinationOver_ffff;
        break;

    case kO2BlendModeDestinationIn:
        self->_blend_argb32f_PRE = O2BlendSpanDestinationIn_ffff;
        break;

    case kO2BlendModeDestinationOut:
        self->_blend_argb32f_PRE = O2BlendSpanDestinationOut_ffff;
        break;

    case kO2BlendModeDestinationAtop:
        self->_blend_argb32f_PRE = O2BlendSpanDestinationAtop_ffff;
        break;

    case kO2BlendModeXOR:
        self->_blend_argb8u_PRE = O2BlendSpanXOR_8888;
        self->_blend_argb32f_PRE = O2BlendSpanXOR_ffff;
        break;

    case kO2BlendModePlusDarker:
        self->_blend_argb32f_PRE = O2BlendSpanPlusDarker_ffff;
        break;

    case kO2BlendModePlusLighter:
        self->_blend_argb8u_PRE = O2BlendSpanPlusLighter_8888;
        self->_blend_argb32f_PRE = O2BlendSpanPlusLighter_ffff;
        break;
    }

    O2Surface *surface = [self->_layerStack count] > 0
            ? O2LayerGetSurface([self->_layerStack lastObject]) : self->_surface;
    if (self->_clipContext != nil || hasViewportClip(self) ||
        !O2SurfaceCanReadWriteARGB8u(surface) ||
        paint->_paint_largb8u_PRE == NULL) {
        self->_writeCoverage_argb8u_PRE = NULL;
        self->_blend_argb8u_PRE = NULL;
    }

    if (self->_writeCoverage_argb8u_PRE != NULL) {
        self->_blendFunction = NULL;
        self->_writeCoverageFunction = self->_writeCoverage_argb8u_PRE;
    } else {
        if (self->_blend_argb8u_PRE != NULL) {
            self->_blendFunction = self->_blend_argb8u_PRE;
            self->_writeCoverageFunction = O2RasterizeWriteCoverageSpan8888;
        } else {
            self->_blendFunction = self->_blend_argb32f_PRE;
            self->_writeCoverageFunction = O2RasterizeWriteCoverageSpanffff;
        }
    }
}

void O2ContextSetPaint(O2Context_builtin *self, O2PaintRef paint) {
    paint = O2PaintRetain(paint);
    O2PaintRelease(self->_paint);
    self->_paint = paint;
}

@end
