#ifndef O2_BITMAP_FORMAT_H
#define O2_BITMAP_FORMAT_H

#import <Onyx2D/O2Image.h>
#include <limits.h>
#include <stdint.h>

/* Existing raw float readers/writers implement explicit premultiplied RGBA.
 * Keep their dispatch in agreement and bound their signed x*16 coordinates. */
static inline BOOL O2BitmapFormatSupportsFloatRGBA(size_t width, size_t height,
        size_t bitsPerComponent, size_t bitsPerPixel, size_t bytesPerRow,
        O2ColorSpaceRef colorSpace, O2BitmapInfo bitmapInfo) {
    if (bitsPerComponent != 32 || bitsPerPixel != 128 ||
        !(bitmapInfo & kO2BitmapFloatComponents) || colorSpace == nil ||
        [colorSpace type] != kO2ColorSpaceModelRGB ||
        (bitmapInfo & kO2BitmapAlphaInfoMask) != kO2ImageAlphaPremultipliedLast)
        return NO;
    O2BitmapInfo order = bitmapInfo & kO2BitmapByteOrderMask;
    if (order != kO2BitmapByteOrder32Little && order != kO2BitmapByteOrder32Big)
        return NO;
    if (bitmapInfo & ~(kO2BitmapAlphaInfoMask | kO2BitmapFloatComponents | kO2BitmapByteOrderMask))
        return NO;
    if (width == 0 || height == 0 || width > INT_MAX / 16 || height > INT_MAX)
        return NO;
    /* scanlineAtY still uses signed int byte offsets, so accepted float
     * storage must fit that reader as well as size_t allocation arithmetic. */
    return bytesPerRow >= width * 16 && bytesPerRow <= INT_MAX &&
           bytesPerRow != 0 && height <= (size_t)INT_MAX / bytesPerRow;
}

#endif
