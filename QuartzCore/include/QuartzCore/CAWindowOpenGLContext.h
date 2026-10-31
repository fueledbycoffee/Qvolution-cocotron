#import <OpenGL/OpenGL.h>
#import <QuartzCore/CARenderer.h>

@interface CAWindowOpenGLContext : NSObject {
    CGLContextObj _cglContext;
}

- initWithCGLContext: (CGLContextObj) cglContext;

- (void) prepareViewportWidth: (int) width height: (int) height;

- (void) renderSurface: (O2Surface *) surface;
// Dedicated presentation context; verification reads the real default framebuffer.
- (BOOL) presentSurface: (O2Surface *) surface opaque: (BOOL) opaque
                verify: (BOOL) verify corrupt: (BOOL) corrupt;

@end
