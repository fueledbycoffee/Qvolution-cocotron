#!/usr/bin/env python3
"""Exercise the real image uploader against a native GL API double, without a GPU.

The double interprets glTexImage2D's external pixel format/type, records pixels,
and checks unpack-state restoration. Guest framebuffer checks remain required.
"""
import argparse
from pathlib import Path
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--renderer', type=Path, default=Path(__file__).resolve().parents[1] / 'QuartzCore/CARenderer.m')
p.add_argument('--output-dir', type=Path, required=True)
a = p.parse_args()
a.output_dir.mkdir(parents=True, exist_ok=True)
source = a.renderer.read_text()
upload = source[source.index('void CATexImage2DCGImage('):source.index('// Premultiplied colour (the blend function')]
# The uploader is C apart from these diagnostics.
upload = upload.replace('NSLog(@', 'fprintf(stderr, ')
prelude = r'''
#define GL_GLEXT_PROTOTYPES 1
#include <GL/gl.h>
#include <GL/glext.h>
#include <assert.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef int BOOL;
#define YES 1
#define NO 0
typedef unsigned CGBitmapInfo;
typedef unsigned CGImageAlphaInfo;
enum { kCGImageAlphaNone, kCGImageAlphaPremultipliedLast,
       kCGImageAlphaPremultipliedFirst, kCGImageAlphaLast, kCGImageAlphaFirst,
       kCGImageAlphaNoneSkipLast, kCGImageAlphaNoneSkipFirst, kCGImageAlphaOnly };
enum { kCGBitmapAlphaInfoMask=0x1f, kCGBitmapByteOrderMask=0x7000,
       kCGBitmapByteOrderDefault=0, kCGBitmapByteOrder32Little=0x2000,
       kO2BitmapByteOrder32Big=0x4000, kCGBitmapByteOrder32Big=0x4000 };
typedef struct {
    size_t width, height, stride, length;
    unsigned info;
    uint8_t bytes[64];
} Image;
typedef Image *CGImageRef;
typedef Image *CGDataProviderRef;
typedef Image *CFDataRef;
#define CGImageGetWidth(i) ((i)->width)
#define CGImageGetHeight(i) ((i)->height)
#define CGImageGetBitmapInfo(i) ((i)->info)
#define CGImageGetDataProvider(i) (i)
#define CGImageGetBytesPerRow(i) ((i)->stride)
#define CGImageGetBitsPerPixel(i) 32
#define CGImageGetBitsPerComponent(i) 8
#define CGDataProviderCopyData(i) (i)
#define CFDataGetBytePtr(i) ((i)->bytes)
#define CFDataGetLength(i) ((i)->length)
#define CFRelease(i) ((void)(i))
static BOOL supportsPixelUnpackBuffer(void) { return YES; }
static GLenum names[] = {GL_UNPACK_ALIGNMENT, GL_UNPACK_ROW_LENGTH,
    GL_UNPACK_SKIP_ROWS, GL_UNPACK_SKIP_PIXELS, GL_UNPACK_SWAP_BYTES,
    GL_PIXEL_UNPACK_BUFFER_BINDING};
static GLint state[] = {8, 7, 2, 3, 1, 99};
static unsigned failures, uploads;
static uint8_t captured[16];
void glGetIntegerv(GLenum name, GLint *value) {
    for (unsigned i=0;i<6;i++) if (names[i]==name) { *value=state[i]; return; }
    abort();
}
void glPixelStorei(GLenum name, GLint value) {
    for (unsigned i=0;i<5;i++) if (names[i]==name) { state[i]=value; return; }
    abort();
}
void glBindBuffer(GLenum target, GLuint name) {
    assert(target==GL_PIXEL_UNPACK_BUFFER); state[5]=name;
}
void glTexImage2D(GLenum target, GLint level, GLint internal, GLsizei w, GLsizei h,
                 GLint border, GLenum format, GLenum type, const void *bytes) {
    assert(target==GL_TEXTURE_2D && level==0 && internal==GL_RGBA8 && border==0);
    assert(w==2 && h==2 && !state[2] && !state[3] && !state[4] && !state[5]);
    assert(state[0]==1);
    const uint8_t *data=bytes;
    for (int y=0;y<h;y++) for (int x=0;x<w;x++) {
        const uint8_t *p=data+4*(y*(state[1] ? state[1] : w)+x);
        uint8_t c[4];
        if (type==GL_UNSIGNED_BYTE) memcpy(c,p,4);
        else {
            uint32_t word; memcpy(&word,p,4);
            assert(type==GL_UNSIGNED_INT_8_8_8_8_REV || type==GL_UNSIGNED_INT_8_8_8_8);
            for (unsigned k=0;k<4;k++) c[k]=word >> (type==GL_UNSIGNED_INT_8_8_8_8_REV ? 8*k : 24-8*k);
        }
        uint8_t *out=captured+4*(y*w+x);
        assert(format==GL_RGBA || format==GL_BGRA);
        out[0]=c[format==GL_RGBA ? 0 : 2]; out[1]=c[1];
        out[2]=c[format==GL_RGBA ? 2 : 0]; out[3]=c[3];
    }
    uploads++;
}
'''
checks = r'''
static void check(const char *label, unsigned info, size_t stride, int bgra) {
    // Yellow reproduces the reported cyan; asymmetric colour and alpha prevent
    // red/blue or alpha swaps from passing by coincidence.
    const uint8_t want[16]={255,255,0,255, 64,32,16,128, 0,0,255,255, 9,17,25,64};
    Image image={.width=2,.height=2,.stride=stride,.length=stride+8,.info=info};
    for (unsigned y=0;y<2;y++) for (unsigned x=0;x<2;x++) {
        const uint8_t *p=want+4*(y*2+x); uint8_t *d=image.bytes+y*stride+x*4;
        d[0]=p[bgra ? 2 : 0]; d[1]=p[1]; d[2]=p[bgra ? 0 : 2]; d[3]=p[3];
    }
    GLint before[6]; memcpy(before,state,sizeof state);
    unsigned count=uploads;
    CATexImage2DCGImage(&image);
    BOOL ok=uploads==count+1 && !memcmp(want,captured,sizeof want) && !memcmp(before,state,sizeof state);
    printf("%s %s stride=%zu\n", ok ? "PASS" : "FAIL",label,stride);
    if (!ok) failures++;
}
int main(void) {
    for (size_t stride=8;stride<=12;stride++) {
        check("RGBA default",kCGImageAlphaPremultipliedLast,stride,0);
        check("RGBA big",kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big,stride,0);
        check("BGRA little",kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little,stride,1);
    }
    printf("RESULT texture-upload failures=%u uploads=%u\n",failures,uploads);
    return failures ? 1 : 0;
}
'''
unit = a.output_dir / 'texture-upload.c'
binary = a.output_dir / 'texture-upload'
unit.write_text(prelude + upload + checks)
subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined',
                '-g', str(unit), '-o', str(binary)], check=True)
subprocess.run([str(binary)], check=True)
