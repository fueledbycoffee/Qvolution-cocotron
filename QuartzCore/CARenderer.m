#define GL_GLEXT_PROTOTYPES 1
#import <CoreVideo/CoreVideo.h>
#import <Onyx2D/O2Color.h>
#import <Onyx2D/O2Surface.h>
#import <OpenGL/OpenGL.h>
#import <QuartzCore/CAAnimation.h>
#import <QuartzCore/CAMediaTimingFunction.h>
#import <QuartzCore/CARenderer.h>
#import <QuartzCore/CASpringAnimation.h>
#import "CALayerInternal.h"
#include <limits.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

@interface CASpringAnimation (Private)
- (CGFloat) _springProgressAtTime: (CFTimeInterval) t;
@end

NSString *const kCARendererColorSpace = @"kCARendererColorSpace";

@implementation CARenderer

- (CGRect) bounds {
    return _bounds;
}

- (void) setBounds: (CGRect) value {
    _bounds = value;
}

@synthesize layer = _rootLayer;

- initWithCGLContext: (void *) cglContext options: (NSDictionary *) options {
    _cglContext = cglContext;
    _bounds = CGRectZero;
    _rootLayer = nil;
    return self;
}

+ (CARenderer *) rendererWithCGLContext: (void *) cglContext
                                options: (NSDictionary *) options
{
    return [[[self alloc] initWithCGLContext: cglContext
                                     options: options] autorelease];
}

static void startAnimationsInLayer(CALayer *layer, CFTimeInterval currentTime) {
    NSArray *keys = [layer animationKeys];

    for (NSString *key in keys) {
        CAAnimation *check = [layer animationForKey: key];

        if ([check beginTime] == 0.0)
            [check setBeginTime: currentTime];
        if (currentTime > [check beginTime] + [check duration]) {
            [layer removeAnimationForKey: key];
        }
    }

    for (CALayer *child in layer.sublayers)
        startAnimationsInLayer(child, currentTime);
}

- (void) beginFrameAtTime: (CFTimeInterval) currentTime
                timeStamp: (CVTimeStamp *) timeStamp
{
    startAnimationsInLayer(_rootLayer, currentTime);
}

static inline CGFloat cubed(CGFloat value) {
    return value * value * value;
}

static inline CGFloat squared(CGFloat value) {
    return value * value;
}

static CGFloat applyMediaTimingFunction(CAMediaTimingFunction *function,
                                        CGFloat t)
{
    CGFloat result;
    CGFloat cp1[2];
    CGFloat cp2[2];

    [function getControlPointAtIndex: 1 values: cp1];
    [function getControlPointAtIndex: 2 values: cp2];

    double x = cubed(1.0 - t) * 0.0 + 3 * squared(1 - t) * t * cp1[0] +
               3 * (1 - t) * squared(t) * cp2[0] + cubed(t) * 1.0;
    double y = cubed(1.0 - t) * 0.0 + 3 * squared(1 - t) * t * cp1[1] +
               3 * (1 - t) * squared(t) * cp2[1] + cubed(t) * 1.0;

    // this is wrong
    return y;
}

static CGFloat mediaTimingScale(CAAnimation *animation,
                                CFTimeInterval currentTime)
{
    CFTimeInterval begin = [animation beginTime];
    CFTimeInterval duration = [animation duration];
    // beginTime is set by the first animation frame; a render before that
    // (e.g. from a view display) shows the start value. Clamp so a late render
    // can't extrapolate far past the end value.
    if (begin <= 0)
        return 0;
    if (duration <= 0)
        return 1;

    CFTimeInterval delta = currentTime - begin;
    if ([animation isKindOfClass: [CASpringAnimation class]])
        return [(CASpringAnimation *) animation
                _springProgressAtTime: MIN(MAX(delta, 0.0), duration)];

    double zeroToOne = MIN(MAX(delta / duration, 0.0), 1.0);
    CAMediaTimingFunction *function = [animation timingFunction];

    if (function == nil)
        function = [CAMediaTimingFunction
                functionWithName: kCAMediaTimingFunctionDefault];

    return applyMediaTimingFunction(function, zeroToOne);
}

static CGFloat interpolateFloatInLayerKey(CALayer *layer, NSString *key,
                                          CFTimeInterval currentTime)
{
    CAAnimation *animation = [layer animationForKey: key];

    if (animation == nil)
        return [[layer valueForKey: key] floatValue];

    if ([animation isKindOfClass: [CABasicAnimation class]]) {
        CABasicAnimation *basic = (CABasicAnimation *) animation;

        id fromValue = [basic fromValue];
        id toValue = [basic toValue];

        if (toValue == nil)
            toValue = [layer valueForKey: key];

        CGFloat fromFloat = [fromValue floatValue];
        CGFloat toFloat = [toValue floatValue];

        CGFloat resultFloat;
        double timingScale = mediaTimingScale(animation, currentTime);

        resultFloat = fromFloat + (toFloat - fromFloat) * timingScale;

        return resultFloat;
    }

    return 0;
}

static CGPoint interpolatePointInLayerKey(CALayer *layer, NSString *key,
                                          CFTimeInterval currentTime)
{
    CAAnimation *animation = [layer animationForKey: key];

    if (animation == nil)
        return [[layer valueForKey: key] pointValue];

    if ([animation isKindOfClass: [CABasicAnimation class]]) {
        CABasicAnimation *basic = (CABasicAnimation *) animation;

        id fromValue = [basic fromValue];
        id toValue = [basic toValue];

        if (toValue == nil)
            toValue = [layer valueForKey: key];

        CGPoint fromPoint = [fromValue pointValue];
        CGPoint toPoint = [toValue pointValue];

        CGPoint resultPoint;
        double timingScale = mediaTimingScale(animation, currentTime);

        resultPoint.x = fromPoint.x + (toPoint.x - fromPoint.x) * timingScale;
        resultPoint.y = fromPoint.y + (toPoint.y - fromPoint.y) * timingScale;

        return resultPoint;
    }

    return CGPointMake(0, 0);
}

static CGRect interpolateRectInLayerKey(CALayer *layer, NSString *key,
                                        CFTimeInterval currentTime)
{
    CAAnimation *animation = [layer animationForKey: key];

    if (animation == nil) {
        return [[layer valueForKey: key] rectValue];
    }

    if ([animation isKindOfClass: [CABasicAnimation class]]) {
        CABasicAnimation *basic = (CABasicAnimation *) animation;

        id fromValue = [basic fromValue];
        id toValue = [basic toValue];

        if (toValue == nil)
            toValue = [layer valueForKey: key];

        CGRect fromRect = [fromValue rectValue];
        CGRect toRect = [toValue rectValue];

        double timingScale = mediaTimingScale(animation, currentTime);

        CGRect resultRect;

        resultRect.origin.x =
                fromRect.origin.x +
                (toRect.origin.x - fromRect.origin.x) * timingScale;
        resultRect.origin.y =
                fromRect.origin.y +
                (toRect.origin.y - fromRect.origin.y) * timingScale;
        resultRect.size.width =
                fromRect.size.width +
                (toRect.size.width - fromRect.size.width) * timingScale;
        resultRect.size.height =
                fromRect.size.height +
                (toRect.size.height - fromRect.size.height) * timingScale;

        return resultRect;
    }

    return CGRectMake(0, 0, 0, 0);
}

static GLint interpolationFromName(NSString *name) {
    if (name == kCAFilterLinear)
        return GL_LINEAR;
    else if (name == kCAFilterNearest)
        return GL_NEAREST;
    else if ([name isEqualToString: kCAFilterLinear])
        return GL_LINEAR;
    else if ([name isEqualToString: kCAFilterNearest])
        return GL_NEAREST;
    else
        return GL_LINEAR;
}

static void applyLayerTransform(CATransform3D t) {
    // CATransform3D uses row vectors. OpenGL consumes column-major storage,
    // so this field order represents the same point transformation there.
    const GLfloat matrix[16] = {
        t.m11, t.m12, t.m13, t.m14,
        t.m21, t.m22, t.m23, t.m24,
        t.m31, t.m32, t.m33, t.m34,
        t.m41, t.m42, t.m43, t.m44,
    };
    glMultMatrixf(matrix);
}

static BOOL supportsPixelUnpackBuffer(void) {
    const char *version = (const char *)glGetString(GL_VERSION);
    if (version == NULL)
        return NO;
    char *end;
    long major = strtol(version, &end, 10);
    long minor = *end == '.' ? strtol(end + 1, NULL, 10) : 0;
    if (major > 2 || (major == 2 && minor >= 1))
        return YES;
    const char *extensions = (const char *)glGetString(GL_EXTENSIONS);
    if (extensions == NULL)
        return NO;
    const char *names[] = {"GL_ARB_pixel_buffer_object", "GL_EXT_pixel_buffer_object"};
    for (unsigned i = 0; i < 2; ++i) {
        const char *match = extensions;
        size_t length = strlen(names[i]);
        while ((match = strstr(match, names[i])) != NULL) {
            if ((match == extensions || match[-1] == ' ') &&
                (match[length] == ' ' || match[length] == '\0'))
                return YES;
            match += length;
        }
    }
    return NO;
}

void CATexImage2DCGImage(CGImageRef image) {
    if (image == NULL)
        return;

    size_t imageWidth = CGImageGetWidth(image);
    size_t imageHeight = CGImageGetHeight(image);
    if (imageWidth == 0 || imageHeight == 0)
        return;

    CGBitmapInfo bitmapInfo = CGImageGetBitmapInfo(image);

    CGDataProviderRef provider = CGImageGetDataProvider(image);
    if (provider == NULL)
        return;

    CFDataRef data = CGDataProviderCopyData(provider);
    if (data == NULL)
        return;

    const uint8_t *pixelBytes = CFDataGetBytePtr(data);
    if (pixelBytes == NULL) {
        CFRelease(data);
        return;
    }

    GLenum glFormat = GL_BGRA;
    GLenum glType = GL_UNSIGNED_INT_8_8_8_8_REV;

    CGImageAlphaInfo alphaInfo = bitmapInfo & kCGBitmapAlphaInfoMask;
    CGBitmapInfo byteOrder = bitmapInfo & kCGBitmapByteOrderMask;

    switch (alphaInfo) {

    case kCGImageAlphaNone:
        break;

    case kCGImageAlphaPremultipliedLast:
        // Default-order alpha-last bitmaps have R,G,B,A bytes too. In
        // particular app-supplied contents need not use our BGRA backing format.
        if (byteOrder == kCGBitmapByteOrderDefault || byteOrder == kO2BitmapByteOrder32Big) {
            glFormat = GL_RGBA;
            glType = GL_UNSIGNED_BYTE;
        }
        break;

    case kCGImageAlphaPremultipliedFirst: // ARGB
        if (byteOrder == kCGBitmapByteOrder32Little) {
            glFormat = GL_BGRA;
            glType = GL_UNSIGNED_INT_8_8_8_8_REV;
        }
        break;

    case kCGImageAlphaLast:
        break;

    case kCGImageAlphaFirst:
        break;

    case kCGImageAlphaNoneSkipLast:
        break;

    case kCGImageAlphaNoneSkipFirst:
        break;

    case kCGImageAlphaOnly:
        break;
    }

    size_t stride = CGImageGetBytesPerRow(image);
    if (CGImageGetBitsPerPixel(image) != 32 || CGImageGetBitsPerComponent(image) != 8 || imageWidth > INT_MAX ||
        imageHeight > INT_MAX || imageWidth > SIZE_MAX / 4 ||
        stride < imageWidth * 4 ||
        imageHeight - 1 > (SIZE_MAX - imageWidth * 4) / stride ||
        (imageHeight - 1) * stride + imageWidth * 4 > (size_t)CFDataGetLength(data)) {
        NSLog(@"CARenderer: invalid or unsupported image row layout");
        CFRelease(data);
        return;
    }
    uint8_t *packed = NULL;
    GLint rowLength = 0;
    if (stride % 4 == 0 && stride / 4 <= INT_MAX) {
        rowLength = (GLint)(stride / 4);
    } else {
        packed = malloc(imageWidth * 4 * imageHeight);
        if (packed == NULL) {
            NSLog(@"CARenderer: cannot allocate packed image rows");
            CFRelease(data);
            return;
        }
        for (size_t row = 0; row < imageHeight; ++row)
            memcpy(packed + row * imageWidth * 4, pixelBytes + row * stride, imageWidth * 4);
        pixelBytes = packed;
    }
    BOOL hasUnpackBuffer = supportsPixelUnpackBuffer();
    GLint alignment, oldRowLength, skipRows, skipPixels, swapBytes, unpackBuffer = 0;
    glGetIntegerv(GL_UNPACK_ALIGNMENT, &alignment);
    glGetIntegerv(GL_UNPACK_ROW_LENGTH, &oldRowLength);
    glGetIntegerv(GL_UNPACK_SKIP_ROWS, &skipRows);
    glGetIntegerv(GL_UNPACK_SKIP_PIXELS, &skipPixels);
    glGetIntegerv(GL_UNPACK_SWAP_BYTES, &swapBytes);
    if (hasUnpackBuffer) {
        glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &unpackBuffer);
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
    }
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glPixelStorei(GL_UNPACK_ROW_LENGTH, rowLength);
    glPixelStorei(GL_UNPACK_SKIP_ROWS, 0);
    glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0);
    glPixelStorei(GL_UNPACK_SWAP_BYTES, GL_FALSE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, imageWidth, imageHeight, 0,
                 glFormat, glType, pixelBytes);
    glPixelStorei(GL_UNPACK_ALIGNMENT, alignment);
    glPixelStorei(GL_UNPACK_ROW_LENGTH, oldRowLength);
    glPixelStorei(GL_UNPACK_SKIP_ROWS, skipRows);
    glPixelStorei(GL_UNPACK_SKIP_PIXELS, skipPixels);
    glPixelStorei(GL_UNPACK_SWAP_BYTES, swapBytes);
    if (hasUnpackBuffer)
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, unpackBuffer);
    free(packed);
    CFRelease(data);
}

// Premultiplied colour (the blend function is GL_ONE, GL_ONE_MINUS_SRC_ALPHA).
static BOOL setPremultipliedColor(CGColorRef color, CGFloat opacity) {
    if (color == NULL)
        return NO;

    size_t count = CGColorGetNumberOfComponents(color);
    const CGFloat *c = CGColorGetComponents(color);
    CGColorSpaceModel model =
            CGColorSpaceGetModel(CGColorGetColorSpace(color));
    CGFloat r, g, b, a;

    if (c == NULL)
        return NO;
    // Only RGB and grey components can be used as they are; a CMYK colour also
    // has 4+ components, which must not be read as RGBA.
    if (model == kCGColorSpaceModelRGB && count >= 4) {
        r = c[0]; g = c[1]; b = c[2]; a = c[3];
    } else if (model == kCGColorSpaceModelRGB && count == 3) {
        r = c[0]; g = c[1]; b = c[2]; a = 1;
    } else if (model == kCGColorSpaceModelMonochrome && count >= 2) {
        r = g = b = c[0]; a = c[1];
    } else if (model == kCGColorSpaceModelCMYK && count >= 5) {
        // Match Onyx2D's device-CMYK approximation; this is not ICC matching.
        O2Float rgb[4];
        if (!O2ColorConvertComponentsToDeviceRGB(
                (O2ColorSpaceRef)CGColorGetColorSpace(color), c, rgb))
            return NO;
        r = rgb[0]; g = rgb[1]; b = rgb[2]; a = rgb[3];
    } else {
        return NO;
    }

    a *= opacity;
    if (a <= 0)
        return NO;
    glColor4f(r * a, g * a, b * a, a);
    return YES;
}

enum { kCornerSegments = 8, kRoundedRectPoints = 4 * (kCornerSegments + 1) };

// Outline of a rounded rect, counter-clockwise from the bottom-right corner.
// Always kRoundedRectPoints points (a zero radius repeats the corner), so an
// outer and an inner outline can be zipped into a border triangle strip.
static void roundedRectOutline(CGRect r, CGFloat radius, GLfloat *xy) {
    radius = MAX(0, MIN(radius, MIN(r.size.width, r.size.height) / 2));

    const CGFloat cx[4] = {CGRectGetMaxX(r) - radius, CGRectGetMaxX(r) - radius,
                           CGRectGetMinX(r) + radius, CGRectGetMinX(r) + radius};
    const CGFloat cy[4] = {CGRectGetMinY(r) + radius, CGRectGetMaxY(r) - radius,
                           CGRectGetMaxY(r) - radius, CGRectGetMinY(r) + radius};
    int n = 0;

    for (int corner = 0; corner < 4; corner++) {
        CGFloat start = (corner - 1) * M_PI_2;
        for (int i = 0; i <= kCornerSegments; i++) {
            CGFloat angle = start + M_PI_2 * i / kCornerSegments;
            xy[n++] = cx[corner] + radius * cos(angle);
            xy[n++] = cy[corner] + radius * sin(angle);
        }
    }
}

- (void) _drawBackgroundOfLayer: (CALayer *) layer
                         bounds: (CGRect) bounds
                        opacity: (CGFloat) opacity
{
    if (!setPremultipliedColor(layer.backgroundColor, opacity))
        return;

    GLfloat fan[2 * (kRoundedRectPoints + 2)];
    CGRect rect = CGRectMake(0, 0, bounds.size.width, bounds.size.height);

    fan[0] = CGRectGetMidX(rect);
    fan[1] = CGRectGetMidY(rect);
    roundedRectOutline(rect, layer.cornerRadius, fan + 2);
    fan[2 * (kRoundedRectPoints + 1)] = fan[2];
    fan[2 * (kRoundedRectPoints + 1) + 1] = fan[3];

    glVertexPointer(2, GL_FLOAT, 0, fan);
    glDrawArrays(GL_TRIANGLE_FAN, 0, kRoundedRectPoints + 2);
}

- (void) _drawBorderOfLayer: (CALayer *) layer
                     bounds: (CGRect) bounds
                    opacity: (CGFloat) opacity
{
    CGFloat width = layer.borderWidth;

    if (width <= 0 || !setPremultipliedColor(layer.borderColor, opacity))
        return;

    CGRect outerRect = CGRectMake(0, 0, bounds.size.width, bounds.size.height);
    CGRect innerRect = CGRectInset(outerRect, width, width);
    if (innerRect.size.width < 0 || innerRect.size.height < 0)
        innerRect = CGRectMake(CGRectGetMidX(outerRect), CGRectGetMidY(outerRect), 0, 0);

    GLfloat outer[2 * kRoundedRectPoints], inner[2 * kRoundedRectPoints];
    GLfloat strip[2 * 2 * (kRoundedRectPoints + 1)];

    roundedRectOutline(outerRect, layer.cornerRadius, outer);
    roundedRectOutline(innerRect, MAX(0, layer.cornerRadius - width), inner);

    for (int i = 0; i <= kRoundedRectPoints; i++) {
        int j = i % kRoundedRectPoints;
        strip[4 * i] = outer[2 * j];
        strip[4 * i + 1] = outer[2 * j + 1];
        strip[4 * i + 2] = inner[2 * j];
        strip[4 * i + 3] = inner[2 * j + 1];
    }

    glVertexPointer(2, GL_FLOAT, 0, strip);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 2 * (kRoundedRectPoints + 1));
}

- (void) _drawContentsOfLayer: (CALayer *) layer
                       bounds: (CGRect) bounds
                      opacity: (CGFloat) opacity
                      flipped: (BOOL) flipped
{
    CGImageRef image = (CGImageRef) layer.contents;

    if (image == NULL)
        return;

    NSNumber *textureId = [layer _textureId];
    GLuint texture = [textureId unsignedIntValue];

    // Upload when the texture object doesn't exist yet (check before binding:
    // glBindTexture creates it) or when the layer got new contents since the
    // last upload (a layer-backed NSView sets a new image on every display).
    BOOL upload = texture == 0 || glIsTexture(texture) == GL_FALSE ||
                  [layer _textureContents] != layer.contents;

    glEnable(GL_TEXTURE_2D);
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);

    if (texture != 0)
        glBindTexture(GL_TEXTURE_2D, texture);

    if (upload) {
        CATexImage2DCGImage(image);
        [layer _setTextureContents: layer.contents];

        GLint minFilter = interpolationFromName(layer.minificationFilter);
        GLint magFilter = interpolationFromName(layer.magnificationFilter);

        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, minFilter);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, magFilter);

        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    }

    // Texture row 0 is the top of the image. It goes at the top of the screen
    // whether or not the layer's coordinate space is flipped.
    const GLfloat uprightTexture[4 * 2] = {0, 1, 1, 1, 0, 0, 1, 0};
    const GLfloat flippedTexture[4 * 2] = {0, 0, 1, 0, 0, 1, 1, 1};
    const GLfloat *textureVertices = flipped ? flippedTexture : uprightTexture;
    CGRect target = CGRectMake(0, 0, bounds.size.width, bounds.size.height);
    NSString *gravity = layer.contentsGravity;
    CGFloat w = CGImageGetWidth(image) / layer.contentsScale;
    CGFloat h = CGImageGetHeight(image) / layer.contentsScale;
    if (![gravity isEqual:kCAGravityResize] && w > 0 && h > 0) {
        if ([gravity isEqual:kCAGravityResizeAspect] || [gravity isEqual:kCAGravityResizeAspectFill]) {
            CGFloat sx = bounds.size.width / w, sy = bounds.size.height / h;
            CGFloat ratio = [gravity isEqual:kCAGravityResizeAspect] ? MIN(sx, sy) : MAX(sx, sy);
            w *= ratio; h *= ratio;
        }
        target = CGRectMake((bounds.size.width - w) / 2, (bounds.size.height - h) / 2, w, h);
        if ([gravity isEqual:kCAGravityLeft] || [gravity isEqual:kCAGravityTopLeft] || [gravity isEqual:kCAGravityBottomLeft]) target.origin.x = 0;
        if ([gravity isEqual:kCAGravityRight] || [gravity isEqual:kCAGravityTopRight] || [gravity isEqual:kCAGravityBottomRight]) target.origin.x = bounds.size.width - w;
        BOOL top = [gravity isEqual:kCAGravityTop] || [gravity isEqual:kCAGravityTopLeft] || [gravity isEqual:kCAGravityTopRight];
        BOOL bottom = [gravity isEqual:kCAGravityBottom] || [gravity isEqual:kCAGravityBottomLeft] || [gravity isEqual:kCAGravityBottomRight];
        if (top || bottom) target.origin.y = (top != flipped) ? bounds.size.height - h : 0;
    }
    CGRect rasterRect = [layer _contentsRasterRect];
    if (!CGRectIsNull(rasterRect)) {
        target = rasterRect;
        target.origin.x -= bounds.origin.x;
        target.origin.y -= bounds.origin.y;
    }
    const GLfloat vertices[4 * 2] = {CGRectGetMinX(target), CGRectGetMinY(target), CGRectGetMaxX(target), CGRectGetMinY(target),
                                    CGRectGetMinX(target), CGRectGetMaxY(target), CGRectGetMaxX(target), CGRectGetMaxY(target)};

    glTexCoordPointer(2, GL_FLOAT, 0, textureVertices);
    glVertexPointer(2, GL_FLOAT, 0, vertices);
    glColor4f(opacity, opacity, opacity, opacity);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    glDisable(GL_TEXTURE_2D);
}

// Increment/decrement only pixels inside the parent's stencil value. Replaying
// the same transformed outline on exit preserves arbitrary nested/rotated masks.
static void drawLayerMask(CALayer *layer, CGRect bounds, unsigned depth, BOOL entering) {
    GLfloat fan[2 * (kRoundedRectPoints + 2)];
    CGRect rect = CGRectMake(0, 0, bounds.size.width, bounds.size.height);
    fan[0] = CGRectGetMidX(rect); fan[1] = CGRectGetMidY(rect);
    roundedRectOutline(rect, layer.cornerRadius, fan + 2);
    fan[2 * (kRoundedRectPoints + 1)] = fan[2];
    fan[2 * (kRoundedRectPoints + 1) + 1] = fan[3];
    glPushAttrib(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_ENABLE_BIT | GL_STENCIL_BUFFER_BIT);
    glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
    glDisable(GL_ALPHA_TEST); glDisable(GL_DEPTH_TEST); glDisable(GL_TEXTURE_2D);
    glEnable(GL_STENCIL_TEST);
    glStencilMask(0xff);
    glStencilFunc(GL_EQUAL, depth, 0xff);
    glStencilOp(GL_KEEP, GL_KEEP, entering ? GL_INCR : GL_DECR);
    glVertexPointer(2, GL_FLOAT, 0, fan);
    glDrawArrays(GL_TRIANGLE_FAN, 0, kRoundedRectPoints + 2);
    glPopAttrib();
}

// The 16-bit EGL fallback can have no stencil attachment. Use intersected
// window-space bounds there; rounded/rotated masks degrade to their bounding
// rectangles, but nested rectangular view clips remain exact.
static void scissorLayerMask(CGRect bounds) {
    GLdouble model[16], projection[16]; GLint viewport[4], parent[4];
    glGetDoublev(GL_MODELVIEW_MATRIX, model);
    glGetDoublev(GL_PROJECTION_MATRIX, projection);
    glGetIntegerv(GL_VIEWPORT, viewport);
    double x0 = viewport[0] + viewport[2], y0 = viewport[1] + viewport[3];
    double x1 = viewport[0], y1 = viewport[1];
    for (unsigned i = 0; i < 4; ++i) {
        double point[4] = {i & 1 ? bounds.size.width : 0,
                           i & 2 ? bounds.size.height : 0, 0, 1};
        double eye[4] = {0}, clip[4] = {0};
        for (unsigned row = 0; row < 4; ++row)
            for (unsigned col = 0; col < 4; ++col)
                eye[row] += model[col * 4 + row] * point[col];
        for (unsigned row = 0; row < 4; ++row)
            for (unsigned col = 0; col < 4; ++col)
                clip[row] += projection[col * 4 + row] * eye[col];
        if (!isfinite(clip[3]) || clip[3] <= 0) {
            // A near-plane crossing cannot be bounded by projected corners.
            x0 = viewport[0]; y0 = viewport[1];
            x1 = x0 + viewport[2]; y1 = y0 + viewport[3];
            break;
        }
        double x = viewport[0] + (clip[0] / clip[3] + 1) * viewport[2] / 2;
        double y = viewport[1] + (clip[1] / clip[3] + 1) * viewport[3] / 2;
        // Projection arithmetic can put an integral edge a few ulps away.
        if (fabs(x - round(x)) < 1e-7) x = round(x);
        if (fabs(y - round(y)) < 1e-7) y = round(y);
        x0 = MIN(x0, x); y0 = MIN(y0, y); x1 = MAX(x1, x); y1 = MAX(y1, y);
    }
    if (glIsEnabled(GL_SCISSOR_TEST)) glGetIntegerv(GL_SCISSOR_BOX, parent);
    else memcpy(parent, viewport, sizeof(parent));
    x0 = MAX(parent[0], floor(x0)); y0 = MAX(parent[1], floor(y0));
    x1 = MIN(parent[0] + parent[2], ceil(x1)); y1 = MIN(parent[1] + parent[3], ceil(y1));
    glEnable(GL_SCISSOR_TEST);
    glScissor((GLint)x0, (GLint)y0, (GLsizei)MAX(0, x1 - x0), (GLsizei)MAX(0, y1 - y0));
}

// Layers are composited in painter's order: a layer's background, contents and
// border, then its sublayers in array order. Opacity multiplies down the tree.
// parentFlipped says whether the parent's coordinate space is y-flipped on screen.
- (void) _renderLayer: (CALayer *) layer
          currentTime: (CFTimeInterval) currentTime
        parentOpacity: (CGFloat) parentOpacity
        parentFlipped: (BOOL) parentFlipped
            maskDepth: (unsigned) maskDepth
         stencilLimit: (unsigned) stencilLimit
{
    if (layer.hidden)
        return;

    CGPoint anchorPoint =
            interpolatePointInLayerKey(layer, @"anchorPoint", currentTime);
    CGPoint position =
            interpolatePointInLayerKey(layer, @"position", currentTime);
    CGRect bounds = interpolateRectInLayerKey(layer, @"bounds", currentTime);
    CGFloat opacity =
            interpolateFloatInLayerKey(layer, @"opacity", currentTime) *
            parentOpacity;

    if (opacity <= 0)
        return;

    glPushMatrix();
    // Position is the anchor in parent coordinates. Apply the layer transform
    // around it, then move local geometry so its anchor is at the origin.
    glTranslatef(position.x, position.y, 0);
    applyLayerTransform(layer.transform);
    glTranslatef(-bounds.size.width * anchorPoint.x,
                 -bounds.size.height * anchorPoint.y, 0);

    BOOL flipped = parentFlipped;
    if (layer.geometryFlipped) {
        glTranslatef(0, bounds.size.height, 0);
        glScalef(1, -1, 1);
        flipped = !flipped;
    }

    BOOL masked = [layer masksToBounds];
    BOOL stencilMask = masked && maskDepth < stencilLimit;
    BOOL scissorMask = masked && !stencilMask;
    if (stencilMask) {
        drawLayerMask(layer, bounds, maskDepth, YES);
        ++maskDepth;
    } else if (scissorMask) {
        static int warned;
        if (!__sync_lock_test_and_set(&warned, 1))
            NSLog(@"Layer masks: stencil unavailable or exhausted; using rectangular scissor bounds");
        glPushAttrib(GL_SCISSOR_BIT);
        scissorLayerMask(bounds);
    }
    if (stencilLimit) {
        glEnable(GL_STENCIL_TEST);
        glStencilMask(0);
        glStencilFunc(GL_EQUAL, maskDepth, 0xff);
        glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);
    } else glDisable(GL_STENCIL_TEST);

    [self _drawBackgroundOfLayer: layer bounds: bounds opacity: opacity];
    // A layer that draws its own content (CAMetalLayer draws the texture the GPU
    // filled in) opts out of the contents path, which would otherwise upload
    // into the same texture it just drew from.
    if (![layer _drawLayerContents: bounds opacity: opacity])
        [self _drawContentsOfLayer: layer
                            bounds: bounds
                           opacity: opacity
                           flipped: flipped];
    [self _drawBorderOfLayer: layer bounds: bounds opacity: opacity];

    // A child is positioned in this layer's coordinate system, whose origin is
    // bounds.origin, so it belongs that much further left and down than the matrix above
    // puts it. Only the recursion is offset: this layer's own contents already have the
    // origin removed from their image, so translating them too would double-count it.
    glPushMatrix();
    glTranslatef(-bounds.origin.x, -bounds.origin.y, 0);
    for (CALayer *child in layer.sublayers)
        [self _renderLayer: child
                currentTime: currentTime
parentOpacity: opacity
              parentFlipped: flipped
                  maskDepth: maskDepth
               stencilLimit: stencilLimit];
    glPopMatrix();

    if (stencilMask) drawLayerMask(layer, bounds, maskDepth, NO);
    if (scissorMask) glPopAttrib();
    if (stencilLimit) glStencilFunc(GL_EQUAL, stencilMask ? maskDepth - 1 : maskDepth, 0xff);
    glPopMatrix();
}

// Layers that draw their content (-drawInContext:, CATextLayer, CAShapeLayer,
// a drawing delegate) produce it when marked as needing display. This runs
// before any GL drawing: a delegate's -displayLayer: can run arbitrary code (an
// NSView delegate redisplays the view, which renders this layer tree again), and
// doing that in the middle of the traversal would clear the frame and reset the
// matrix stack under it.
static void displayLayerTreeIfNeeded(CALayer *layer) {
    if (layer.hidden)
        return;

    [layer displayIfNeeded];

    // Copied: drawing code may add or remove sublayers.
    NSArray *sublayers = [layer.sublayers copy];
    for (CALayer *child in sublayers)
        displayLayerTreeIfNeeded(child);
    [sublayers release];
}

- (void) render {
    [_rootLayer layoutIfNeeded];
    displayLayerTreeIfNeeded(_rootLayer);

    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    CGColorRef bg = [_rootLayer backgroundColor];
    if (bg != NULL && CGColorGetNumberOfComponents(bg) == 4) {
        const CGFloat *c = CGColorGetComponents(bg);
        glClearColor(c[0], c[1], c[2], c[3]);
    } else {
        glClearColor(0, 0, 0, 0);
    }
    glDisable(GL_SCISSOR_TEST);
    GLint stencilBits = 0;
    glGetIntegerv(GL_STENCIL_BITS, &stencilBits);
    unsigned stencilLimit = stencilBits > 0 ? (1u << MIN(stencilBits, 8)) - 1 : 0;
    if (stencilLimit) {
        glStencilMask(0xff);
        glClearStencil(0);
    }
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT |
            (stencilLimit ? GL_STENCIL_BUFFER_BIT : 0));

    // Painter's order instead of depth testing: every layer used to get z+1,
    // which put layers nested two or more deep outside the [-1, 1] depth range
    // of CALayerContext's glOrtho projection, so they were clipped away.
    glDisable(GL_DEPTH_TEST);

    glEnableClientState(GL_VERTEX_ARRAY);

    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

    glAlphaFunc(GL_GREATER, 0);
    glEnable(GL_ALPHA_TEST);

    [self _renderLayer: _rootLayer
            currentTime: CACurrentMediaTime()
          parentOpacity: 1.0
          parentFlipped: [_rootLayer.superlayer contentsAreFlipped]
              maskDepth: 0
           stencilLimit: stencilLimit];
    glDisable(GL_STENCIL_TEST);

    glFlush();
}

- (void) endFrame {
}

@end
