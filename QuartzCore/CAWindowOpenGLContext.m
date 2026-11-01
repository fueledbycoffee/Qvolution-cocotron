#define GL_GLEXT_PROTOTYPES 1
#import <Onyx2D/O2Surface.h>
#import <OpenGL/gl.h>
#import <OpenGL/glext.h>
#include <limits.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#import <OpenGL/OpenGL.h>
#import <QuartzCore/CAWindowOpenGLContext.h>

@implementation CAWindowOpenGLContext

- initWithCGLContext: (CGLContextObj) cglContext {
    _cglContext = CGLRetainContext(cglContext);
    return self;
}

- (void) dealloc {
    CGLReleaseContext(_cglContext);
    [super dealloc];
}

- (void) prepareViewportWidth: (int) width height: (int) height {
    // prepare
    CGLError error;

    if ((error = CGLSetCurrentContext(_cglContext)) != kCGLNoError)
        NSLog(@"CGLSetCurrentContext failed with %d in %s %d", error, __FILE__,
              __LINE__);

    glEnable(GL_DEPTH_TEST);
    glShadeModel(GL_SMOOTH);

    // reshape
    glViewport(0, 0, width, height);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrtho(0, width, 0, height, -1, 1);
}

- (void) renderSurface: (O2Surface *) surface {
    size_t width = O2ImageGetWidth(surface);
    size_t height = O2ImageGetHeight(surface);

    // prepare
    glEnable(GL_DEPTH_TEST);
    glShadeModel(GL_SMOOTH);

    // reshape
    glViewport(0, 0, width, height);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrtho(0, width, 0, height, -1, 1);

    // render
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    glEnable(GL_TEXTURE_2D);
    glEnableClientState(GL_VERTEX_ARRAY);
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);

    glDisable(GL_BLEND);
    glDisable(GL_DEPTH_TEST);

    width = O2ImageGetWidth(surface);
    height = O2ImageGetHeight(surface);

    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_BGRA,
                 GL_UNSIGNED_INT_8_8_8_8_REV, [surface pixelBytes]);

    glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);

    GLfloat vertices[4 * 2];
    GLfloat texture[4 * 2];

    vertices[0] = 0;
    vertices[1] = 0;
    vertices[2] = width;
    vertices[3] = 0;
    vertices[4] = 0;
    vertices[5] = height;
    vertices[6] = width;
    vertices[7] = height;

    texture[0] = 0;
    texture[1] = 1;
    texture[2] = 1;
    texture[3] = 1;
    texture[4] = 0;
    texture[5] = 0;
    texture[6] = 1;
    texture[7] = 0;

    glPushMatrix();
    //  glTranslatef(width/2,height/2,0);
    glTexCoordPointer(2, GL_FLOAT, 0, texture);
    glVertexPointer(2, GL_FLOAT, 0, vertices);
    //  glTranslatef(center.x,center.y,0);
    //  glRotatef(1,0,0,1);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    glPopMatrix();

    glFinish();
}

// Integer pixel bounds of a damage rectangle inside a width x height surface.
static BOOL clampDamage(CGRect rect, size_t width, size_t height, size_t box[4]) {
    if (!isfinite(rect.origin.x) || !isfinite(rect.origin.y) ||
        !isfinite(rect.size.width) || !isfinite(rect.size.height))
        return NO;
    double x0 = floor(MAX(rect.origin.x, 0)), y0 = floor(MAX(rect.origin.y, 0));
    double x1 = ceil(MIN(rect.origin.x + rect.size.width, (double)width));
    double y1 = ceil(MIN(rect.origin.y + rect.size.height, (double)height));
    if (x1 <= x0 || y1 <= y0)
        return NO;
    box[0] = (size_t)x0; box[1] = (size_t)y0; box[2] = (size_t)(x1 - x0); box[3] = (size_t)(y1 - y0);
    return YES;
}

- (uint64_t) lastUploadBytes {
    return _lastUploadBytes;
}

- (unsigned) lastUploadRects {
    return _lastUploadRects;
}

- (BOOL) presentSurface: (O2Surface *) surface opaque: (BOOL) opaque
                 damage: (const CGRect *) damage count: (unsigned) count
                 verify: (BOOL) verify corrupt: (BOOL) corrupt {
    size_t width = O2SurfaceGetWidth(surface), height = O2SurfaceGetHeight(surface);
    size_t stride = O2SurfaceGetBytesPerRow(surface);
    const uint8_t *source = O2SurfaceGetPixelBytes(surface);
    // Onyx2D window surfaces are 32-bit premultiplied ARGB, little-endian: BGRA
    // bytes, which GL_BGRA/GL_UNSIGNED_INT_8_8_8_8_REV reads directly.
    if (!source || !width || !height || width > INT_MAX || height > INT_MAX ||
        width > SIZE_MAX / 4 || stride < width * 4 || stride % 4 || stride / 4 > INT_MAX ||
        height > SIZE_MAX / stride || O2ImageGetBitsPerPixel((O2ImageRef)surface) != 32)
        return NO;
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glDrawBuffer(GL_BACK); glReadBuffer(GL_BACK);
    glViewport(0, 0, (GLsizei)width, (GLsizei)height);
    glDisable(GL_SCISSOR_TEST); glDisable(GL_BLEND); glDisable(GL_DEPTH_TEST);
    glDisable(GL_DITHER); glDisable(GL_FRAMEBUFFER_SRGB);
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glClearColor(0, 0, 0, opaque ? 1 : 0); glClear(GL_COLOR_BUFFER_BIT);
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, opaque ? GL_FALSE : GL_TRUE);
    glMatrixMode(GL_PROJECTION); glLoadIdentity(); glOrtho(0, width, 0, height, -1, 1);
    glMatrixMode(GL_MODELVIEW); glLoadIdentity();
    glEnable(GL_TEXTURE_2D);
    if (!_presentTexture)
        glGenTextures(1, &_presentTexture);
    glBindTexture(GL_TEXTURE_2D, _presentTexture);
    BOOL whole = count == 0 || width != _presentWidth || height != _presentHeight;
    if (width != _presentWidth || height != _presentHeight) {
        _presentWidth = _presentHeight = 0;
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, (GLsizei)width, (GLsizei)height, 0,
                     GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, NULL);
        GLint allocatedWidth = 0, allocatedHeight = 0;
        glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_WIDTH, &allocatedWidth);
        glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_HEIGHT, &allocatedHeight);
        if (allocatedWidth != (GLint)width || allocatedHeight != (GLint)height)
            return NO;
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        _presentWidth = width; _presentHeight = height;
    }
    // Texture row 0 is the surface's top row, as in the CPU storage.
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
    glPixelStorei(GL_UNPACK_ROW_LENGTH, (GLint)(stride / 4));
    glPixelStorei(GL_UNPACK_SWAP_BYTES, GL_FALSE);
    CGRect all = CGRectMake(0, 0, width, height);
    const CGRect *rects = whole ? &all : damage;
    unsigned rectCount = whole ? 1 : count, uploaded = 0;
    uint64_t bytes = 0;
    for (unsigned i = 0; i < rectCount; ++i) {
        size_t box[4];
        if (!clampDamage(rects[i], width, height, box))
            continue;
        glPixelStorei(GL_UNPACK_SKIP_PIXELS, (GLint)box[0]);
        glPixelStorei(GL_UNPACK_SKIP_ROWS, (GLint)box[1]);
        glTexSubImage2D(GL_TEXTURE_2D, 0, (GLint)box[0], (GLint)box[1], (GLsizei)box[2], (GLsizei)box[3],
                        GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, source);
        bytes += (uint64_t)box[2] * box[3] * 4; ++uploaded;
    }
    glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
    glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0);
    glPixelStorei(GL_UNPACK_SKIP_ROWS, 0);
    if (corrupt) {
        // Explicit diagnostic negative control: alter uploaded data, never its CPU oracle.
        uint8_t pixel[4]; memcpy(pixel, source, 4); pixel[0] ^= 0xff;
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 1, 1, GL_BGRA, GL_UNSIGNED_BYTE, pixel);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
    }
    glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);
    const GLfloat vertices[] = {0, 0, width, 0, 0, height, width, height};
    const GLfloat coords[] = {0, 1, 1, 1, 0, 0, 1, 0};
    glEnableClientState(GL_VERTEX_ARRAY); glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    glVertexPointer(2, GL_FLOAT, 0, vertices); glTexCoordPointer(2, GL_FLOAT, 0, coords);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    glDisableClientState(GL_VERTEX_ARRAY); glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    glBindTexture(GL_TEXTURE_2D, 0);
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    BOOL valid = YES;
    if (verify) {
        uint8_t *actual = malloc(width * 4 * height);
        if (!actual) valid = NO;
        else {
            glPixelStorei(GL_PACK_ALIGNMENT, 1); glPixelStorei(GL_PACK_ROW_LENGTH, 0);
            glPixelStorei(GL_PACK_SKIP_ROWS, 0); glPixelStorei(GL_PACK_SKIP_PIXELS, 0);
            glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
            glReadPixels(0, 0, width, height, GL_BGRA, GL_UNSIGNED_BYTE, actual);
            size_t mismatches = 0;
            for (size_t y = 0; y < height; ++y) {
                const uint8_t *expected = source + y * stride;
                const uint8_t *row = actual + (height - 1 - y) * width * 4;
                for (size_t x = 0; x < width; ++x)
                    if (memcmp(row + x * 4, expected + x * 4, 3) ||
                        row[x * 4 + 3] != (opaque ? 255 : expected[x * 4 + 3]))
                        ++mismatches;
            }
            if (mismatches) NSLog(@"AppKit EGL: reference mismatch %lu/%lu pixels", (unsigned long)mismatches, (unsigned long)(width * height));
            valid = mismatches == 0;
            free(actual);
        }
    }
    if (glGetError() != GL_NO_ERROR || !valid) {
        // The texture no longer matches any known surface state.
        _presentWidth = _presentHeight = 0;
        return NO;
    }
    _lastUploadBytes = bytes; _lastUploadRects = uploaded;
    return YES;
}

@end
