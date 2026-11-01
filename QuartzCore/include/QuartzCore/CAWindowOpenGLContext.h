#import <OpenGL/OpenGL.h>
#import <QuartzCore/CARenderer.h>

@interface CAWindowOpenGLContext : NSObject {
    CGLContextObj _cglContext;
    // Persistent copy of the presented surface; owned by _cglContext.
    GLuint _presentTexture;
    size_t _presentWidth, _presentHeight;
    uint64_t _lastUploadBytes;
    unsigned _lastUploadRects;
    // Staging ring for uploads: the CPU copies into one while the GPU may still
    // be reading the others, so glTexSubImage2D does not wait on the copy.
    GLuint _uploadBuffers[3];
    size_t _uploadBufferSize;
    unsigned _uploadNext;
}

- initWithCGLContext: (CGLContextObj) cglContext;

- (void) prepareViewportWidth: (int) width height: (int) height;

- (void) renderSurface: (O2Surface *) surface;
// Dedicated presentation context; verification reads the real default framebuffer.
// The surface is kept in a texture between frames: only the damage rectangles
// (surface pixels, origin at the top row) are uploaded, and count == 0 uploads
// the whole surface. A new size always uploads the whole surface.
- (BOOL) presentSurface: (O2Surface *) surface opaque: (BOOL) opaque
                 damage: (const CGRect *) damage count: (unsigned) count
                 verify: (BOOL) verify corrupt: (BOOL) corrupt;
// Bytes and rectangles uploaded by the last successful present.
- (uint64_t) lastUploadBytes;
- (unsigned) lastUploadRects;

@end
