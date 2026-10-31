#import <Onyx2D/O2Encoder_PNG.h>

#if !defined(__APPLE__) || defined(DARLING)
#import <Onyx2D/O2Defines_libpng.h>
#endif

#include <limits.h>
#include <stdlib.h>
#include <string.h>

// PNG stores unassociated samples; preserve straight-alpha zero-color bytes.
static unsigned char *O2PNGCopyPixels(const unsigned char *bytes, size_t length,
        size_t width, size_t height, size_t bitsPerComponent, size_t bitsPerPixel,
        size_t stride, O2BitmapInfo info, size_t *channelsOut) {
    O2ImageAlphaInfo alpha = info & kO2BitmapAlphaInfoMask;
    O2BitmapInfo order = info & kO2BitmapByteOrderMask;
    BOOL first = alpha == kO2ImageAlphaFirst || alpha == kO2ImageAlphaPremultipliedFirst || alpha == kO2ImageAlphaNoneSkipFirst;
    BOOL premultiplied = alpha == kO2ImageAlphaPremultipliedFirst || alpha == kO2ImageAlphaPremultipliedLast;
    BOOL hasAlpha = premultiplied || alpha == kO2ImageAlphaFirst || alpha == kO2ImageAlphaLast;
    size_t sourceChannels = bitsPerPixel / 8, channels = hasAlpha ? 4 : 3;
    if (!bytes || !width || !height || width > INT_MAX || height > INT_MAX || bitsPerComponent != 8 ||
            (info & ~(kO2BitmapAlphaInfoMask | kO2BitmapByteOrderMask)) ||
            !((bitsPerPixel == 24 && alpha == kO2ImageAlphaNone && order == kO2BitmapByteOrderDefault) ||
              (bitsPerPixel == 32 && (hasAlpha || alpha == kO2ImageAlphaNoneSkipFirst || alpha == kO2ImageAlphaNoneSkipLast))))
        return NULL;
    if (order == kO2BitmapByteOrderDefault && bitsPerPixel == 32) {
        if (!first) order = kO2BitmapByteOrder32Big;
        else {
#ifdef __LITTLE_ENDIAN__
            order = kO2BitmapByteOrder32Little;
#else
            order = kO2BitmapByteOrder32Big;
#endif
        }
    }
    if (bitsPerPixel == 32 && order != kO2BitmapByteOrder32Big && order != kO2BitmapByteOrder32Little)
        return NULL;
    if (width > SIZE_MAX / sourceChannels || stride < width * sourceChannels ||
            height - 1 > (SIZE_MAX - width * sourceChannels) / stride ||
            length < (height - 1) * stride + width * sourceChannels ||
            width > SIZE_MAX / channels || height > SIZE_MAX / (width * channels))
        return NULL;
    unsigned char *out = malloc(width * height * channels);
    if (!out) return NULL;
    for (size_t y = 0; y < height; y++) {
        const unsigned char *row = bytes + y * stride;
        for (size_t x = 0; x < width; x++) {
            const unsigned char *pixel = row + x * sourceChannels;
            unsigned char *dest = out + (y * width + x) * channels;
            unsigned indices[4] = {first ? 1 : 0, first ? 2 : 1, first ? 3 : 2, first ? 0 : 3};
            if (order == kO2BitmapByteOrder32Little)
                for (unsigned i = 0; i < 4; i++) indices[i] = 3 - indices[i];
            unsigned a = hasAlpha ? pixel[indices[3]] : 255;
            for (unsigned c = 0; c < 3; c++) {
                unsigned value = pixel[indices[c]];
                if (premultiplied) value = a ? (value * 255 + a / 2) / a : 0;
                dest[c] = value > 255 ? 255 : value;
            }
            if (hasAlpha) dest[3] = a;
        }
    }
    *channelsOut = channels;
    return out;
}

static unsigned char *O2PNGCopyImagePixels(O2ImageRef image, size_t *channels) {
    if (!image || O2ImageIsMask(image) || O2ImageGetMask(image) || O2ImageGetDecode(image) ||
            O2ColorSpaceGetModel(O2ImageGetColorSpace(image)) != kO2ColorSpaceModelRGB)
        return NULL;
    NSData *data = [image directData];
    return O2PNGCopyPixels([data bytes], [data length], O2ImageGetWidth(image), O2ImageGetHeight(image),
            O2ImageGetBitsPerComponent(image), O2ImageGetBitsPerPixel(image),
            O2ImageGetBytesPerRow(image), O2ImageGetBitmapInfo(image), channels);
}

O2PNGEncoderRef O2PNGEncoderCreate(O2DataConsumerRef consumer) {
    if (!consumer) return NULL;
    O2PNGEncoderRef self = NSZoneCalloc(NULL, 1, sizeof(struct O2PNGEncoder));
    if (self) self->_consumer = (id) CFRetain(consumer);
    return self;
}

void O2PNGEncoderDealloc(O2PNGEncoderRef self) {
    if (!self) return;
    if (self->_consumer != NULL) CFRelease(self->_consumer);
    NSZoneFree(NULL, self);
}

bool O2PNGEncoderIsComplete(O2PNGEncoderRef self) {
    return self && self->_complete && !self->_failed;
}

#ifdef LIBPNG_PRESENT
#include <png.h>
#include <zlib.h>

static void o2png_write_data(png_structp png_ptr, png_bytep data, png_size_t length) {
    O2PNGEncoderRef self = (O2PNGEncoderRef)png_get_io_ptr(png_ptr);
    if (O2DataConsumerPutBytes(self->_consumer, data, length) != length) {
        self->_failed = YES;
        png_error(png_ptr, "short PNG consumer write");
    }
}

void O2PNGEncoderWriteImage(O2PNGEncoderRef self, O2ImageRef image, CFDictionaryRef props) {
    if (!self) return;
    if (self->_complete || self->_failed) { self->_failed = YES; return; }
    self->_failed = YES;
    size_t channels = 0, width = O2ImageGetWidth(image), height = O2ImageGetHeight(image);
    unsigned char *pixels = O2PNGCopyImagePixels(image, &channels);
    if (!pixels) return;
    png_structp png = png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
    png_infop info = png ? png_create_info_struct(png) : NULL;
    if (!info) {
        if (png) png_destroy_write_struct(&png, NULL);
        free(pixels);
        return;
    }
    @try {
        if (!setjmp(png_jmpbuf(png))) {
            png_set_write_fn(png, self, o2png_write_data, NULL);
            png_set_filter(png, PNG_FILTER_TYPE_BASE, PNG_FILTER_SUB);
            png_set_compression_level(png, 3);
            png_set_IHDR(png, info, width, height, 8, channels == 4 ? PNG_COLOR_TYPE_RGB_ALPHA : PNG_COLOR_TYPE_RGB,
                    PNG_INTERLACE_NONE, PNG_COMPRESSION_TYPE_BASE, PNG_FILTER_TYPE_BASE);
            png_write_info(png, info);
            for (size_t y = 0; y < height; y++) png_write_row(png, pixels + y * width * channels);
            png_write_end(png, NULL);
            self->_complete = YES;
            self->_failed = NO;
        }
    } @catch (NSException *exception) {
        self->_failed = YES;
    } @finally {
        png_destroy_write_struct(&png, &info);
        free(pixels);
    }
}
#else
/* stbiw-0.92 - public domain - http://nothings.org/stb/stb_image_write.h
   writes out PNG/BMP/TGA images to C stdio - Sean Barrett 2010
                            no warranty implied; use at your own risk


Before including,

    #define STB_IMAGE_WRITE_IMPLEMENTATION

in the file that you want to have the implementation.


ABOUT:

   This header file is a library for writing images to C stdio. It could be
   adapted to write to memory or a general streaming interface; let me know.

   The PNG output is not optimal; it is 20-50% larger than the file
   written by a decent optimizing implementation. This library is designed
   for source code compactness and simplicitly, not optimal image file size
   or run-time performance.

USAGE:

   There are three functions, one for each image file format:

     int stbi_write_png(char const *filename, int w, int h, int comp, const void
*data, int stride_in_bytes); int stbi_write_bmp(char const *filename, int w, int
h, int comp, const void *data); int stbi_write_tga(char const *filename, int w,
int h, int comp, const void *data);

   Each function returns 0 on failure and non-0 on success.

   The functions create an image file defined by the parameters. The image
   is a rectangle of pixels stored from left-to-right, top-to-bottom.
   Each pixel contains 'comp' channels of data stored interleaved with 8-bits
   per channel, in the following order: 1=Y, 2=YA, 3=RGB, 4=RGBA. (Y is
   monochrome color.) The rectangle is 'w' pixels wide and 'h' pixels tall.
   The *data pointer points to the first byte of the top-left-most pixel.
   For PNG, "stride_in_bytes" is the distance in bytes from the first byte of
   a row of pixels to the first byte of the next row of pixels.

   PNG creates output files with the same number of components as the input.
   The BMP and TGA formats expand Y to RGB in the file format. BMP does not
   output alpha.

   PNG supports writing rectangles of data even when the bytes storing rows of
   data are not consecutive in memory (e.g. sub-rectangles of a larger image),
   by supplying the stride between the beginning of adjacent rows. The other
   formats do not. (Thus you cannot write a native-format BMP through the BMP
   writer, both because it is in BGR order and because it may have padding
   at the end of the line.)
*/

#include <assert.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef unsigned int stbiw_uint32;
typedef int stb_image_write_test[sizeof(stbiw_uint32) == 4 ? 1 : -1];

// stretchy buffer; stbi__sbpush() == vector<>::push_back() -- stbi__sbcount()
// == vector<>::size()
#define stbi__sbraw(a) ((int *) (a) -2)
#define stbi__sbm(a) stbi__sbraw(a)[0]
#define stbi__sbn(a) stbi__sbraw(a)[1]

#define stbi__sbneedgrow(a, n) ((a) == 0 || stbi__sbn(a) + n >= stbi__sbm(a))
#define stbi__sbgrow(a, n) stbi__sbgrowf((void **) &(a), (n), sizeof(*(a)))

#define stbi__sbpush(a, v) \
    ((!stbi__sbneedgrow(a, 1) || stbi__sbgrow(a, 1)) ? ((a)[stbi__sbn(a)++] = (v), 1) : 0)
#define stbi__sbcount(a) ((a) ? stbi__sbn(a) : 0)
#define stbi__sbfree(a) ((a) ? free(stbi__sbraw(a)), 0 : 0)

static void *stbi__sbgrowf(void **arr, int increment, int itemsize) {
    int old = *arr ? stbi__sbm(*arr) : 0;
    if (old > (INT_MAX - increment) / 2) return NULL;
    int m = old ? 2 * old + increment : increment + 1;
    if ((size_t)m > (SIZE_MAX - sizeof(int) * 2) / itemsize) return NULL;
    void *p = realloc(*arr ? stbi__sbraw(*arr) : 0, (size_t)itemsize * m + sizeof(int) * 2);
    if (!p) return NULL;
    if (!*arr) ((int *)p)[1] = 0;
    *arr = (void *)((int *)p + 2);
    stbi__sbm(*arr) = m;
    return *arr;
}

static int stbi__zlib_flushf(unsigned char **data,
                               unsigned int *bitbuffer, int *bitcount) {
    while (*bitcount >= 8) {
        if (!stbi__sbpush(*data, (unsigned char)*bitbuffer)) return 0;
        *bitbuffer >>= 8;
        *bitcount -= 8;
    }
    return 1;
}

static int stbi__zlib_bitrev(int code, int codebits) {
    int res = 0;
    while (codebits--) {
        res = (res << 1) | (code & 1);
        code >>= 1;
    }
    return res;
}

static unsigned int stbi__zlib_countm(unsigned char *a, unsigned char *b,
                                      int limit)
{
    int i;
    for (i = 0; i < limit && i < 258; ++i)
        if (a[i] != b[i])
            break;
    return i;
}

static unsigned int stbi__zhash(unsigned char *data) {
    stbiw_uint32 hash = data[0] + (data[1] << 8) + (data[2] << 16);
    hash ^= hash << 3;
    hash += hash >> 5;
    hash ^= hash << 4;
    hash += hash >> 17;
    hash ^= hash << 25;
    hash += hash >> 6;
    return hash;
}

#define stbi__zlib_flush() do { if (!stbi__zlib_flushf(&out, &bitbuf, &bitcount)) goto fail; } while (0)
#define stbi__zlib_add(code, codebits) do { \
    bitbuf |= (unsigned)(code) << bitcount; bitcount += (codebits); stbi__zlib_flush(); \
} while (0)
#define stbi__zlib_huffa(b, c) stbi__zlib_add(stbi__zlib_bitrev(b, c), c)
// default huffman tables
#define stbi__zlib_huff1(n) stbi__zlib_huffa(0x30 + (n), 8)
#define stbi__zlib_huff2(n) stbi__zlib_huffa(0x190 + (n) -144, 9)
#define stbi__zlib_huff3(n) stbi__zlib_huffa(0 + (n) -256, 7)
#define stbi__zlib_huff4(n) stbi__zlib_huffa(0xc0 + (n) -280, 8)
#define stbi__zlib_huff(n) do { \
    if ((n) <= 143) { stbi__zlib_huff1(n); } \
    else if ((n) <= 255) { stbi__zlib_huff2(n); } \
    else if ((n) <= 279) { stbi__zlib_huff3(n); } \
    else { stbi__zlib_huff4(n); } \
} while (0)
#define stbi__zlib_huffb(n) do { \
    if ((n) <= 143) { stbi__zlib_huff1(n); } else { stbi__zlib_huff2(n); } \
} while (0)

#define stbi__ZHASH 16384

unsigned char *stbi_zlib_compress(unsigned char *data, int data_len,
                                  int *out_len, int quality)
{
    static unsigned short lengthc[] = {
            3,  4,  5,  6,  7,  8,  9,  10, 11,  13,  15,  17,  19,  23,  27,
            31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258, 259};
    static unsigned char lengtheb[] = {0, 0, 0, 0, 0, 0, 0, 0, 1, 1,
                                       1, 1, 2, 2, 2, 2, 3, 3, 3, 3,
                                       4, 4, 4, 4, 5, 5, 5, 5, 0};
    static unsigned short distc[] = {
            1,    2,    3,    4,    5,    7,     9,     13,    17,   25,   33,
            49,   65,   97,   129,  193,  257,   385,   513,   769,  1025, 1537,
            2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577, 32768};
    static unsigned char disteb[] = {0, 0, 0,  0,  1,  1,  2,  2,  3,  3,
                                     4, 4, 5,  5,  6,  6,  7,  7,  8,  8,
                                     9, 9, 10, 10, 11, 11, 12, 12, 13, 13};
    unsigned int bitbuf = 0;
    int i, j, bitcount = 0;
    unsigned char *out = NULL;
    unsigned char **hash_table[stbi__ZHASH] = {0};
    if (quality < 5)
        quality = 5;

    if (!stbi__sbpush(out, 0x78) || !stbi__sbpush(out, 0x5e)) goto fail;
    stbi__zlib_add(1, 1);    // BFINAL = 1
    stbi__zlib_add(1, 2);    // BTYPE = 1 -- fixed huffman

    for (i = 0; i < stbi__ZHASH; ++i)
        hash_table[i] = NULL;

    i = 0;
    while (i < data_len - 3) {
        // hash next 3 bytes of data to be compressed
        int h = stbi__zhash(data + i) & (stbi__ZHASH - 1), best = 3;
        unsigned char *bestloc = 0;
        unsigned char **hlist = hash_table[h];
        int n = stbi__sbcount(hlist);
        for (j = 0; j < n; ++j) {
            if (hlist[j] - data > i - 32768) { // if entry lies within window
                int d = stbi__zlib_countm(hlist[j], data + i, data_len - i);
                if (d >= best)
                    best = d, bestloc = hlist[j];
            }
        }
        // when hash table entry is too long, delete half the entries
        if (hash_table[h] && stbi__sbn(hash_table[h]) == 2 * quality) {
            memcpy(hash_table[h], hash_table[h] + quality,
                   sizeof(hash_table[h][0]) * quality);
            stbi__sbn(hash_table[h]) = quality;
        }
        if (!stbi__sbpush(hash_table[h], data + i)) goto fail;

        if (bestloc) {
            // "lazy matching" - check match at *next* byte, and if it's better,
            // do cur byte as literal
            h = stbi__zhash(data + i + 1) & (stbi__ZHASH - 1);
            hlist = hash_table[h];
            n = stbi__sbcount(hlist);
            for (j = 0; j < n; ++j) {
                if (hlist[j] - data > i - 32767) {
                    int e = stbi__zlib_countm(hlist[j], data + i + 1,
                                              data_len - i - 1);
                    if (e > best) { // if next match is better, bail on current
                                    // match
                        bestloc = NULL;
                        break;
                    }
                }
            }
        }

        if (bestloc) {
            int d = data + i - bestloc; // distance back
            assert(d <= 32767 && best <= 258);
            for (j = 0; best > lengthc[j + 1] - 1; ++j)
                ;
            stbi__zlib_huff(j + 257);
            if (lengtheb[j])
                stbi__zlib_add(best - lengthc[j], lengtheb[j]);
            for (j = 0; d > distc[j + 1] - 1; ++j)
                ;
            stbi__zlib_add(stbi__zlib_bitrev(j, 5), 5);
            if (disteb[j])
                stbi__zlib_add(d - distc[j], disteb[j]);
            i += best;
        } else {
            stbi__zlib_huffb(data[i]);
            ++i;
        }
    }
    // write out final bytes
    for (; i < data_len; ++i)
        stbi__zlib_huffb(data[i]);
    stbi__zlib_huff(256); // end of block
    // pad with 0 bits to byte boundary
    while (bitcount)
        stbi__zlib_add(0, 1);

    for (i = 0; i < stbi__ZHASH; ++i) {
        (void)stbi__sbfree(hash_table[i]);
        hash_table[i] = NULL;
    } {
        // compute adler32 on input
        unsigned int i = 0, s1 = 1, s2 = 0, blocklen = data_len % 5552;
        int j = 0;
        while (j < data_len) {
            for (i = 0; i < blocklen; ++i)
                s1 += data[j + i], s2 += s1;
            s1 %= 65521, s2 %= 65521;
            j += blocklen;
            blocklen = 5552;
        }
        if (!stbi__sbpush(out, (unsigned char)(s2 >> 8)) ||
                !stbi__sbpush(out, (unsigned char)s2) ||
                !stbi__sbpush(out, (unsigned char)(s1 >> 8)) ||
                !stbi__sbpush(out, (unsigned char)s1)) goto fail;
    }
    *out_len = stbi__sbn(out);
    // make returned pointer freeable
    memmove(stbi__sbraw(out), out, *out_len);
    return (unsigned char *) stbi__sbraw(out);
fail:
    for (i = 0; i < stbi__ZHASH; i++) (void)stbi__sbfree(hash_table[i]);
    (void)stbi__sbfree(out);
    return NULL;
}

unsigned int stbi__crc32(unsigned char *buffer, int len) {
    unsigned int crc_table[256];
    unsigned int crc = ~0u;
    int i, j;
    for (i = 0; i < 256; i++)
        for (crc_table[i] = i, j = 0; j < 8; ++j)
            crc_table[i] = (crc_table[i] >> 1) ^
                           (crc_table[i] & 1 ? 0xedb88320 : 0);
    for (i = 0; i < len; ++i)
        crc = (crc >> 8) ^ crc_table[buffer[i] ^ (crc & 0xff)];
    return ~crc;
}

#define stbi__wpng4(o, a, b, c, d)                                             \
    ((o)[0] = (unsigned char) (a), (o)[1] = (unsigned char) (b),               \
     (o)[2] = (unsigned char) (c), (o)[3] = (unsigned char) (d), (o) += 4)
#define stbi__wp32(data, v)                                                    \
    stbi__wpng4(data, (v) >> 24, (v) >> 16, (v) >> 8, (v));
#define stbi__wptag(data, s) stbi__wpng4(data, s[0], s[1], s[2], s[3])

static void stbi__wpcrc(unsigned char **data, int len) {
    unsigned int crc = stbi__crc32(*data - len - 4, len + 4);
    stbi__wp32(*data, crc);
}

static unsigned char stbi__paeth(int a, int b, int c) {
    int p = a + b - c, pa = abs(p - a), pb = abs(p - b), pc = abs(p - c);
    if (pa <= pb && pa <= pc)
        return (unsigned char) a;
    if (pb <= pc)
        return (unsigned char) b;
    return (unsigned char) c;
}

unsigned char *stbi_write_png_to_mem(const unsigned char *pixels, int x, int y, int n,
                                     int *out_len)
{
    int ctype[5] = {-1, 0, 4, 2, 6};
    unsigned char sig[8] = {137, 80, 78, 71, 13, 10, 26, 10};
    unsigned char *out, *o, *filt, *zlib;
    signed char *line_buffer;
    int i, j, k, p, zlen;


    filt = (unsigned char *) malloc((x * n + 1) * y);
    if (!filt)
        return 0;
    line_buffer = (signed char *) malloc(x * n);
    if (!line_buffer) {
        free(filt);
        return 0;
    }

    unsigned char *lastZ = calloc(1, x * n);
    unsigned char *z = calloc(1, x * n);
    if (!lastZ || !z) { free(lastZ); free(z); free(line_buffer); free(filt); return NULL; }

    for (j = 0; j < y; ++j) {
        static int mapping[] = {0, 1, 2, 3, 4};
        static int firstmap[] = {0, 1, 0, 5, 6};
        int *mymap = j ? mapping : firstmap;
        int best = 0, bestval = 0x7fffffff;

        memcpy(z, pixels + j * x * n, x * n);

        for (p = 0; p < 2; ++p) {
            for (k = p ? best : 0; k < 5; ++k) {
                int type = mymap[k], est = 0;

                for (i = 0; i < n; ++i)
                    switch (type) {
                    case 0:
                        line_buffer[i] = z[i];
                        break;
                    case 1:
                        line_buffer[i] = z[i];
                        break;
                    case 2:
                        line_buffer[i] = z[i] - lastZ[i];
                        break;
                    case 3:
                        line_buffer[i] = z[i] - (lastZ[i] >> 1);
                        break;
                    case 4:
                        line_buffer[i] =
                                (signed char) (z[i] -
                                               stbi__paeth(0, lastZ[i], 0));
                        break;
                    case 5:
                        line_buffer[i] = z[i];
                        break;
                    case 6:
                        line_buffer[i] = z[i];
                        break;
                    }
                for (i = n; i < x * n; ++i) {
                    switch (type) {
                    case 0:
                        line_buffer[i] = z[i];
                        break;
                    case 1:
                        line_buffer[i] = z[i] - z[i - n];
                        break;
                    case 2:
                        line_buffer[i] = z[i] - lastZ[i];
                        break;
                    case 3:
                        line_buffer[i] = z[i] - ((z[i - n] + lastZ[i]) >> 1);
                        break;
                    case 4:
                        line_buffer[i] = z[i] - stbi__paeth(z[i - n], lastZ[i],
                                                            lastZ[i - n]);
                        break;
                    case 5:
                        line_buffer[i] = z[i] - (z[i - n] >> 1);
                        break;
                    case 6:
                        line_buffer[i] = z[i] - stbi__paeth(z[i - n], 0, 0);
                        break;
                    }
                }
                if (p)
                    break;
                for (i = 0; i < x * n; ++i)
                    est += abs((signed char) line_buffer[i]);
                if (est < bestval) {
                    bestval = est;
                    best = k;
                }
            }
        }
        // when we get here, best contains the filter type, and line_buffer
        // contains the data
        filt[j * (x * n + 1)] = (unsigned char) best;
        memcpy(filt + j * (x * n + 1) + 1, line_buffer, x * n);

        unsigned char *tmp = lastZ;
        lastZ = z;
        z = tmp;
    }
    free(z);
    free(lastZ);
    free(line_buffer);

    zlib = stbi_zlib_compress(
            filt, y * (x * n + 1), &zlen,
            8); // increase 8 to get smaller but use more memory
    free(filt);
    if (!zlib)
        return 0;

    // each tag requires 12 bytes of overhead
    out = (unsigned char *) malloc(8 + 12 + 13 + 12 + zlen + 12);
    if (!out) { free(zlib); return 0; }
    *out_len = 8 + 12 + 13 + 12 + zlen + 12;

    o = out;
    memcpy(o, sig, 8);
    o += 8;
    stbi__wp32(o, 13); // header length
    stbi__wptag(o, "IHDR");
    stbi__wp32(o, x);
    stbi__wp32(o, y);
    *o++ = 8;
    *o++ = (unsigned char) ctype[n];
    *o++ = 0;
    *o++ = 0;
    *o++ = 0;
    stbi__wpcrc(&o, 13);

    stbi__wp32(o, zlen);
    stbi__wptag(o, "IDAT");
    memcpy(o, zlib, zlen);
    o += zlen;
    free(zlib);
    stbi__wpcrc(&o, zlen);

    stbi__wp32(o, 0);
    stbi__wptag(o, "IEND");
    stbi__wpcrc(&o, 0);

    assert(o == out + *out_len);

    return out;
}
/* Revision history

      0.92 (2010-08-01)
             casts to unsigned char to fix warnings
      0.91 (2010-07-17)
             first public release
      0.90   first internal release
*/

void O2PNGEncoderWriteImage(O2PNGEncoderRef self, O2ImageRef image, CFDictionaryRef properties) {
    if (!self) return;
    if (self->_complete || self->_failed) { self->_failed = YES; return; }
    self->_failed = YES;
    size_t channels = 0, width = O2ImageGetWidth(image), height = O2ImageGetHeight(image);
    unsigned char *pixels = O2PNGCopyImagePixels(image, &channels);
    if (!pixels) return;
    // The legacy fallback uses signed int offsets and filter-cost sums.
    if (width > INT_MAX / (128 * channels) || height > (INT_MAX - 256) / (2 * (width * channels + 1))) {
        free(pixels);
        return;
    }
    int length = 0;
    unsigned char *png = stbi_write_png_to_mem(pixels, width, height, channels, &length);
    free(pixels);
    if (!png) return;
    @try {
        if (O2DataConsumerPutBytes(self->_consumer, png, length) == (size_t)length) {
            self->_complete = YES;
            self->_failed = NO;
        }
    } @catch (NSException *exception) {
        self->_failed = YES;
    } @finally { free(png); }
}
#endif
