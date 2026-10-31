#define GL_GLEXT_PROTOTYPES 1
#import <Onyx2D/O2Surface.h>
#import <OpenGL/gl.h>
#import <OpenGL/glext.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#import <OpenGL/OpenGL.h>
#import <QuartzCore/CAWindowOpenGLContext.h>

extern void CATexImage2DCGImage(CGImageRef image);

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

- (BOOL) presentSurface: (O2Surface *) surface opaque: (BOOL) opaque
                verify: (BOOL) verify corrupt: (BOOL) corrupt {
    size_t width = O2SurfaceGetWidth(surface), height = O2SurfaceGetHeight(surface);
    size_t stride = O2SurfaceGetBytesPerRow(surface);
    const uint8_t *source = O2SurfaceGetPixelBytes(surface);
    if (!source || !width || !height || width > INT_MAX || height > INT_MAX ||
        width > SIZE_MAX / 4 || stride < width * 4 || height > SIZE_MAX / stride)
        return NO;
    GLuint texture = 0;
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
    glGenTextures(1, &texture); glBindTexture(GL_TEXTURE_2D, texture);
    CATexImage2DCGImage((CGImageRef)surface);
    GLint uploadedWidth = 0, uploadedHeight = 0;
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_WIDTH, &uploadedWidth);
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_HEIGHT, &uploadedHeight);
    if (uploadedWidth != width || uploadedHeight != height) {
        glDeleteTextures(1, &texture); return NO;
    }
    if (corrupt) {
        // Explicit diagnostic negative control: alter uploaded data, never its CPU oracle.
        uint8_t pixel[4]; memcpy(pixel, source, 4); pixel[0] ^= 0xff;
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 1, 1, GL_BGRA, GL_UNSIGNED_BYTE, pixel);
    }
    glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    const GLfloat vertices[] = {0, 0, width, 0, 0, height, width, height};
    const GLfloat coords[] = {0, 1, 1, 1, 0, 0, 1, 0};
    glEnableClientState(GL_VERTEX_ARRAY); glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    glVertexPointer(2, GL_FLOAT, 0, vertices); glTexCoordPointer(2, GL_FLOAT, 0, coords);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    glDisableClientState(GL_VERTEX_ARRAY); glDisableClientState(GL_TEXTURE_COORD_ARRAY);
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
    glDeleteTextures(1, &texture);
    return glGetError() == GL_NO_ERROR && valid;
}

@end
