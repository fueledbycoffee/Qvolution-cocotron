/* Copyright (c) 2026 darling-cocotron contributors. MIT licensed.
 * Internal byte paths. Keep their guards free of stores: a refusal must leave
 * the original rasterizer's input and destination intact.
 */
#ifndef O2_PIXEL_FAST_PATHS_H
#define O2_PIXEL_FAST_PATHS_H
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <math.h>
#include <limits.h>

typedef struct {
    uint8_t *bytes;
    size_t width, height, stride;
    int format; /* 1: RGBA premultiplied, 2: BGRA premultiplied */
} O2FastPixelBuffer;

typedef struct { int x, y, width, height; } O2FastPixelRect;

static inline int O2FastPixelBufferIsValid(O2FastPixelBuffer b) {
    return b.bytes != NULL && (b.format == 1 || b.format == 2) &&
            b.width > 0 && b.width <= INT_MAX / 4 &&
            b.height > 0 && b.height <= INT_MAX &&
            b.stride >= b.width * 4 && b.stride <= INT_MAX &&
            b.height <= SIZE_MAX / b.stride &&
            b.height * b.stride <= UINTPTR_MAX - (uintptr_t)b.bytes;
}

static inline int O2FastPixelClipIsValid(O2FastPixelBuffer b, O2FastPixelRect c) {
    return c.x >= 0 && c.y >= 0 && c.width >= 0 && c.height >= 0 &&
            (size_t)c.x <= b.width && (size_t)c.y <= b.height &&
            (size_t)c.width <= b.width - c.x &&
            (size_t)c.height <= b.height - c.y;
}

static inline int O2FastPixelCoordinate(double v) {
    /* Bound the old sweep's int conversions and float coordinate precision. */
    return isfinite(v) && v >= -1048576 && v <= 1048576 && floor(v) == v;
}

static inline int O2FastPixelBounds(O2FastPixelBuffer b, O2FastPixelRect clip,
        double x0, double y0, double x1, double y1, O2FastPixelRect *r) {
    if (!O2FastPixelBufferIsValid(b) || !O2FastPixelClipIsValid(b, clip) ||
            !O2FastPixelCoordinate(x0) || !O2FastPixelCoordinate(y0) ||
            !O2FastPixelCoordinate(x1) || !O2FastPixelCoordinate(y1))
        return 0;
    double left = fmin(x0, x1), top = fmin(y0, y1);
    double right = fmax(x0, x1), bottom = fmax(y0, y1);
    int x = (int)fmin(clip.x + clip.width, fmax(clip.x, left));
    int y = (int)fmin(clip.y + clip.height, fmax(clip.y, top));
    int endX = (int)fmax(x, fmin(clip.x + clip.width, right));
    int endY = (int)fmax(y, fmin(clip.y + clip.height, bottom));
    *r = (O2FastPixelRect){x, y, endX - x, endY - y};
    return 1;
}

static inline int O2FastFillPixels(O2FastPixelBuffer b, O2FastPixelRect clip,
        double x0, double y0, double x1, double y1, const uint8_t pixel[4],
        O2FastPixelRect *written) {
    O2FastPixelRect r;
    if (!O2FastPixelBounds(b, clip, x0, y0, x1, y1, &r))
        return 0;
    if (r.width == 0 || r.height == 0) {
        if (written) *written = r;
        return 1;
    }
    uint8_t *row = b.bytes + (size_t)r.y * b.stride + (size_t)r.x * 4;
    uint32_t packed;
    memcpy(&packed, pixel, 4);
    int sameByte = pixel[0] == pixel[1] && pixel[0] == pixel[2] && pixel[0] == pixel[3];
    size_t rowBytes = (size_t)r.width * 4;
    int contiguous = rowBytes == b.stride;
    uint8_t repeatedByte = pixel[0];
    if (sameByte) {
        if (contiguous)
            memset(row, repeatedByte, rowBytes * r.height);
        else for (int y = 0; y < r.height; y++)
            memset(row + (size_t)y * b.stride, repeatedByte, rowBytes);
    } else {
        size_t count = (size_t)r.width;
        // memcpy keeps unaligned stores defined and lets the compiler broadcast
        // the packed pixel to vector registers, without reading a template row.
        for (size_t x = 0; x < count; x++)
            memcpy(row + x * 4, &packed, 4);
        // Keep row copies even for contiguous storage: debug builds must not
        // execute a scalar pixel loop over the entire backing store.
        for (int y = 1; y < r.height; y++)
            memcpy(row + (size_t)y * b.stride, row, rowBytes);
    }
    if (written) *written = r;
    return 1;
}

static inline uint32_t O2FastPixelSwapRB(uint32_t p) {
    return (p & 0xff00ff00u) | ((p & 0xffu) << 16) | ((p >> 16) & 0xffu);
}

static inline uint32_t O2FastPixelMulPair(uint32_t pair, uint32_t alpha) {
    uint32_t product = alpha * (pair & 0x00ff00ffu) + 0x800080u;
    return (product + ((product >> 8) & 0x00ff00ffu)) >> 8 & 0x00ff00ffu;
}

static inline int O2FastBlitPixels(O2FastPixelBuffer dst, O2FastPixelBuffer src,
        O2FastPixelRect clip, double tx, double ty, int flipY,
        int normal, int floatPipeline, O2FastPixelRect *written) {
#if !defined(__LITTLE_ENDIAN__) && (!defined(__BYTE_ORDER__) || __BYTE_ORDER__ != __ORDER_LITTLE_ENDIAN__)
    return 0;
#else
    if (!O2FastPixelBufferIsValid(src) || src.format != dst.format)
        return 0;
    O2FastPixelRect r;
    if (!O2FastPixelBounds(dst, clip, tx, ty,
            tx + src.width, ty + src.height, &r))
        return 0;
    /* The old sampler sees live pixels. Overlaps must retain its traversal,
     * chunk boundaries and interpolation reads; memmove is not equivalent. */
    uintptr_t s0 = (uintptr_t)src.bytes, d0 = (uintptr_t)dst.bytes;
    if (s0 < d0 + dst.height * dst.stride &&
            d0 < s0 + src.height * src.stride)
        return 0;
    if (r.width == 0 || r.height == 0) {
        if (written) *written = r;
        return 1;
    }
    int sx = r.x - (int)tx;
    int sy = r.y - (int)ty;
    /* Source-over in the float pipeline has different rounding. An opaque
     * source is still an exact copy; reject all other float blends. */
    if (normal && floatPipeline) {
        for (int y = 0; y < r.height; y++) {
            int sourceY = flipY ? (int)src.height - 1 - (sy + y) : sy + y;
            const uint8_t *s = src.bytes + (size_t)sourceY * src.stride + (size_t)sx * 4;
            for (int x = 0; x < r.width; x++)
                if (s[x * 4 + 3] != 255)
                    return 0;
        }
    }
    for (int y = 0; y < r.height; y++) {
        int sourceY = flipY ? (int)src.height - 1 - (sy + y) : sy + y;
        const uint8_t *s = src.bytes + (size_t)sourceY * src.stride + (size_t)sx * 4;
        uint8_t *d = dst.bytes + (size_t)(r.y + y) * dst.stride + (size_t)r.x * 4;
        int opaque = !normal || floatPipeline;
        if (!opaque) {
            opaque = 1;
            for (int x = 0; x < r.width; x++)
                if (s[x * 4 + 3] != 255) { opaque = 0; break; }
        }
        if (opaque)
            memcpy(d, s, (size_t)r.width * 4);
        else for (int x = 0; x < r.width; x++, s += 4, d += 4) {
            uint32_t source, dest;
            memcpy(&source, s, 4);
            if (s[3] == 255) { memcpy(d, s, 4); continue; }
            if (s[3] == 0) continue;
            memcpy(&dest, d, 4);
            /* Match the old packed BGRA loop even for malformed premultiplied
             * pixels: its lane carries are observable. No aligned casts. */
            if (src.format == 1) {
                source = O2FastPixelSwapRB(source);
                dest = O2FastPixelSwapRB(dest);
            }
            uint32_t sa = 255 - (source >> 24);
            uint32_t rb = (source & 0x00ff00ffu) + O2FastPixelMulPair(dest, sa);
            uint32_t ag = ((source >> 8) & 0x00ff00ffu) + O2FastPixelMulPair(dest >> 8, sa);
            uint32_t result = (ag << 8) | rb;
            if (src.format == 1) result = O2FastPixelSwapRB(result);
            memcpy(d, &result, 4);
        }
    }
    if (written) *written = r;
    return 1;
#endif
}
#endif
