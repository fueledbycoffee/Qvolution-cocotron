/* Internal fast-path accessors; not an installed framework header. */
#ifndef O2_IMAGE_PRIVATE_H
#define O2_IMAGE_PRIVATE_H
#import <Onyx2D/O2Image.h>

// Internal draw-entry eligibility: 0 unsupported, 1 RGBA, 2 BGRA premultiplied.
__attribute__((visibility("hidden")))
int O2ImageGetFastPixelFormat(O2Image *image);
__attribute__((visibility("hidden")))
const void *O2ImageGetFastPixelBytes(O2Image *image, size_t *length);

#endif
