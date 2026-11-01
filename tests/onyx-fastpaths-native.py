#!/usr/bin/env python3
"""Generate native differential/benchmark targets; build with ninja -j6.

The oracle is pinned to a360e4d95: the old edge sweep, float/byte spans,
image samplers, blend loops and format conversions are compiled verbatim.
Only object ownership/dispatch and memory allocation have native adapters.
Before the fast-path header exists the candidate deliberately uses the oracle.
No Objective-C dispatch, guest or GPU qualification is claimed.
"""
import argparse
from pathlib import Path
import subprocess
import shlex

ROOT = Path(__file__).resolve().parents[1]
BASE = 'a360e4d95cda25247f9e57d3fbff2c92f0b319f5'
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--prepare', type=Path, required=True)
p.add_argument('--baseline', action='store_true', help='exercise the old path on both sides before enabling candidates')
a = p.parse_args()
out = a.prepare.resolve()
out.mkdir(parents=True, exist_ok=True)

def old(path):
    return subprocess.check_output(['git', '-C', str(ROOT), 'show', BASE + ':' + path], text=True)

def function(text, name):
    start = text.index(name)
    start = text.rfind('\n', 0, start) + 1
    end = text.index('{', start) + 1
    depth = 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end] + '\n'

ctx = old('Onyx2D/O2Context_builtin.m')
image = old('Onyx2D/O2Image.m')
surface = old('Onyx2D/O2Surface.m')
float_header = old('Onyx2D/include/Onyx2D/O2argb32f.h')
byte_header = old('Onyx2D/include/Onyx2D/O2argb8u.h')
edge_header = old('Onyx2D/include/Onyx2D/O2Context_builtin.h')
source = r'''
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include <math.h>
#include <string.h>
#include <assert.h>
#include <time.h>
typedef double O2Float;typedef bool BOOL;
#define YES true
#define NO false
#define nil NULL
#define MAX_SAMPLES 256
#define COVERAGE_MULTIPLIER 256
#define MIN(a,b) ((a)<(b)?(a):(b))
#define MAX(a,b) ((a)>(b)?(a):(b))
#define RI_MIN MIN
#define RI_MAX MAX
#define RI_INT_MIN MIN
#define RI_INT_MAX MAX
#define RI_UINT32_MIN MIN
#define RI_FLOOR_TO_INT(v) ((int)floor(v))
#define RI_CLAMP(v,a,b) (isnan(v)?(a):MAX((a),MIN((v),(b))))
#define RI_INT_CLAMP(v,a,b) MAX((a),MIN((v),(b)))
#define RI_ASSERT(v)
#define ONYX2D_STATIC static
#define ONYX2D_STATIC_INLINE static inline
#define NSZoneMalloc(z,n) malloc(n)
#define NSZoneRealloc(z,p,n) realloc(p,n)
#define NSZoneFree(z,p) free(p)
typedef struct {O2Float x,y;} O2Point;
typedef struct {O2Float a,b,c,d,tx,ty;} O2AffineTransform;
static O2Point O2PointMake(O2Float x,O2Float y){return (O2Point){x,y};}
static O2Point Vector2Subtract(O2Point a,O2Point b){return (O2Point){a.x-b.x,a.y-b.y};}
'''
source += '\n#include <Onyx2D/O2SurfaceDamage.h>\n'
source += byte_header[byte_header.index('typedef struct {'):byte_header.index('void O2ApplyCoverageAndMaskToSpan_largb8u_PRE')]
source += float_header[float_header.index('typedef float O2Float32;'):float_header.index('void O2BlendSpanNormal_ffff(')]
source += edge_header[edge_header.index('typedef struct Edge'):edge_header.index('typedef void (*O2BlendSpan_argb8u)')]
source += r'''
typedef struct O2Surface O2Surface;
typedef O2Surface O2Image;
typedef void(*O2BlendSpan_argb32f)(O2argb32f*,O2argb32f*,int);
typedef void(*O2BlendSpan_argb8u)(O2argb8u*,O2argb8u*,int);
typedef int O2ImageAlphaInfo;
enum {kO2ImageAlphaPremultipliedLast=1,kO2ImageAlphaPremultipliedFirst=2,kO2ImageAlphaLast=3,kO2ImageAlphaFirst=4,kO2ImageAlphaNoneSkipLast=5};
#define kO2BitmapAlphaInfoMask 31
#define kO2BitmapByteOrder32Big 0x4000
#define kO2BitmapByteOrder32Little 0x2000
#define kO2BlendModeNormal 0
#define kO2BlendModeCopy 17
#define kO2PathElementMoveToPoint 0
#define kO2PathElementAddLineToPoint 1
#define kO2PathElementCloseSubpath 4
struct O2Surface {
 size_t _width,_height,_bytesPerRow,_bitsPerComponent,_bitsPerPixel,_directLength;unsigned _bitmapInfo;uint8_t *_pixelBytes;
 O2SurfaceDamage *_damage;int _colorSpace;
 void *_decode,*_decoder;BOOL _clampExternalPixels,_isMask;O2Image *_mask;
 O2argb32f*(*_read_argb32f)(O2Image*,int,int,O2argb32f*,int);
 O2argb8u*(*_read_argb8u)(O2Image*,int,int,O2argb8u*,int);
 void(*_writeargb8u)(O2Surface*,int,int,O2argb8u*,int);
 void(*_writeargb32f)(O2Surface*,int,int,O2argb32f*,int);
};
typedef struct O2Paint {O2argb32f _argb32f_PRE;O2Image *image;O2AffineTransform transform;int interpolation;O2argb8u _argb8u_PRE;} O2Paint;
typedef O2Paint O2Paint_color;
typedef struct {O2AffineTransform _userSpaceTransform,_deviceSpaceTransform;O2Float _alpha;int _blendMode;} O2GState;
typedef struct {size_t _numberOfElements,_numberOfPoints;unsigned char _elements[5];O2Point _points[4];} O2Path;
typedef struct O2Context_builtin {
 int _vpx,_vpy,_vpwidth,_vpheight,_edgeCount,_edgeCapacity,_edgeAllocated;
 Edge **_edges,**_sortCache;int *_winding,*_increase,*_rowIncrease;
 int sampleSizeShift,numSamples,samplesWeight;O2Float *samplesX,samplesInitialY,samplesDeltaY;int alias;
 void (*_writeCoverageFunction)();void *_blendFunction;
 struct O2Context_builtin *_clipContext;O2Surface *_surface;uint32_t *_clipSamples;BOOL _clipIsSoftPhase;
 O2GState _state;O2Path *_path;unsigned _layerStack;BOOL _viewportClip;
} O2Context_builtin;
static size_t O2ImageGetWidth(O2Surface*s){return s->_width;}
static size_t O2ImageGetHeight(O2Surface*s){return s->_height;}
static const uint8_t *scanlineAtY(O2Image*s,int y){assert(y>=0&&(size_t)y<s->_height);return s->_pixelBytes+y*s->_bytesPerRow;}
'''
for name in ['O2argb8u *O2ImageRead_RGBA8888_to_argb8u(', 'O2argb8u *O2ImageRead_BGRA8888_to_argb8u(', 'O2argb32f *O2ImageRead_ANY_to_argb8u_to_argb32f(']:
    source += function(image, name)
source += r'''
static O2argb32f* O2Image_read_argb32f(O2Image*s,int x,int y,O2argb32f*out,int n){return O2ImageRead_ANY_to_argb8u_to_argb32f(s,x,y,out,n);}
static O2argb8u* O2Image_read_argb8u(O2Image*s,int x,int y,O2argb8u*out,int n){return s->_read_argb8u(s,x,y,out,n);}
static void O2ImageReadSpan_Af_MASK(O2Image*s,int x,int y,O2Float*out,int n){O2argb32f f[n];O2Image_read_argb32f(s,x,y,f,n);for(int i=0;i<n;i++)out[i]=f[i].a;}
static void O2Image_read_a8u(O2Image*s,int x,int y,uint8_t*out,int n){O2Float f[n];O2ImageReadSpan_Af_MASK(s,x,y,f,n);for(int i=0;i<n;i++)out[i]=O2ByteFromFloat(f[i]);}
'''
for name in ['static void O2SurfaceWrite_argb32f_to_argb8u(', 'static void O2SurfaceWrite_argb8u_to_argb8u(', 'static void O2SurfaceWrite_argb8u_to_BGRA8888(', 'static void O2SurfaceWrite_argb8u_to_ARGB8888(', 'static void O2SurfaceWrite_argb32f_to_ABGR8888(', 'static void O2SurfaceWrite_argb32f_to_argb8u_to_ANY(', 'static BOOL O2SurfaceCanWriteRepeatedColor(', 'BOOL O2SurfaceWriteRepeatedColor(', 'void O2SurfaceWriteSpan_largb32f_PRE(', 'void O2SurfaceWriteSpan_argb8u_PRE(']:
    source += function(surface, name)
current_surface = (ROOT/'Onyx2D/O2Surface.m').read_text()
for name in ['void O2SurfaceAddDamage(', 'BOOL O2SurfaceTakeDamage(']:
    source += function(current_surface, name)
source += '\n#include "' + str(ROOT/'Onyx2D/O2SurfaceDamage.m') + '"\n'
source += 'static BOOL O2SurfaceCanReadWriteARGB8u(O2Surface*s){return s->_read_argb8u&&s->_writeargb8u;}\n'
for name in ['O2ImageReadTileSpanExtendEdge_largb8u_PRE(', 'void O2ImageReadTileSpanExtendEdge__largb32f_PRE(', 'void O2ImageIntegerTranslate_largb8u_PRE(', 'void O2ImagePointSampling_largb32f_PRE(', 'void O2ImageBilinear_largb32f_PRE(']:
    source += ('void\n' if name.startswith('O2ImageReadTileSpan') else '') + function(image, name)
for name in ['ONYX2D_STATIC int color_largb8u_PRE(', 'ONYX2D_STATIC int color_largb32f_PRE(']:
    source += function(old('Onyx2D/O2Paint_color.m'), name)
source += r'''
static int O2PaintReadSpan_largb32f_PRE(O2Paint*p,int x,int y,O2argb32f*out,int n){
 if(p->image){if(p->interpolation)O2ImageBilinear_largb32f_PRE(p->image,x,y,out,n,p->transform);else O2ImagePointSampling_largb32f_PRE(p->image,x,y,out,n,p->transform);}
 else return color_largb32f_PRE(p,x,y,out,n);return n;}
static int O2PaintReadSpan_argb8u_PRE(O2Paint*p,int x,int y,O2argb8u*out,int n){
 if(p->image)O2ImageIntegerTranslate_largb8u_PRE(p->image,x,y,out,n,p->transform);
 else return color_largb8u_PRE(p,x,y,out,n);return n;}
static BOOL O2PaintGetConstantColor(O2Paint*p,O2argb32f*out){*out=p->_argb32f_PRE;return !p->image;}
'''
for name in ['void O2BlendSpanNormal_ffff(', 'void O2BlendSpanCopy_ffff(']:
    source += function(old('Onyx2D/O2argb32f.m'), name)
for name in ['void O2argb8u_sover_by_coverage(', 'void O2argb8u_copy_by_coverage(']:
    source += function(old('Onyx2D/O2argb8u.m'), name)
for name in ['ONYX2D_STATIC void O2ApplyCoverageAndMaskToSpan_largb32f_PRE(', 'ONYX2D_STATIC void O2ApplyCoverageToSpan_largb32f_PRE(', 'ONYX2D_STATIC_INLINE void O2RasterizeWriteCoverageSpan8888_Normal(', 'ONYX2D_STATIC_INLINE void O2RasterizeWriteCoverageSpan8888_Copy(', 'O2RasterizeWriteCoverageSpanffff(']:
    source += ('static void\n' if name.startswith('O2Rasterize') else '') + function(ctx, name)
for name in ['void O2RasterizerSetViewport(', 'void O2RasterizerClear(', 'void O2DContextAddEdge(', 'ONYX2D_STATIC double radicalInverseBase2(', 'void O2RasterizerSetShouldAntialias(', 'static unsigned clipSampleCount(']:
    source += function(ctx, name)
source += ctx[ctx.index('ONYX2D_STATIC_INLINE void sortEdgesByMinY'):ctx.index('void O2DContextClipAndFillEdges(', ctx.index('ONYX2D_STATIC_INLINE void sortEdgesByMinY'))]
header = ROOT/'Onyx2D/O2PixelFastPaths.h'
if header.exists() and not a.baseline:
    source += '\n#include "' + str(header) + '"\n#define HAVE_FAST_PATHS 1\n'
    source += r'''
static O2GState *O2ContextCurrentGState(O2Context_builtin*c){return &c->_state;}
static size_t O2ImageGetBytesPerRow(O2Image*s){return s->_bytesPerRow;}
static void *O2SurfaceGetPixelBytes(O2Surface*s){return s->_pixelBytes;}
static O2Image *O2ImageGetMask(O2Image*s){return s->_mask;}
static BOOL O2ImageIsMask(O2Image*s){return s->_isMask;}
static const void *directBytes(O2Image*s){return s->_pixelBytes;}
enum {kO2ColorSpaceModelRGB=1};
static int O2ImageGetColorSpace(O2Image*s){return s->_colorSpace;}
static int O2ColorSpaceGetModel(int space){return space;}
static BOOL hasViewportClip(O2Context_builtin*c){return c->_viewportClip;}
static size_t O2PathNumberOfElements(O2Path*p){return p->_numberOfElements;}
static size_t O2PathNumberOfPoints(O2Path*p){return p->_numberOfPoints;}
static const unsigned char *O2PathElements(O2Path*p){return p->_elements;}
static const O2Point *O2PathPoints(O2Path*p){return p->_points;}
'''
    for name in ['O2AffineTransform O2AffineTransformConcat(', 'O2AffineTransform O2AffineTransformInvert(', 'O2Point O2PointApplyAffineTransform(']:
        source += function(old('Onyx2D/O2AffineTransform.m'), name)
    current_image = (ROOT/'Onyx2D/O2Image.m').read_text()
    for name in ['int O2ImageGetFastPixelFormat(', 'const void *O2ImageGetFastPixelBytes(']:
        source += function(current_image, name)
    current_context = (ROOT/'Onyx2D/O2Context_builtin.m').read_text()
    for name in ['static BOOL integralRectBounds(', 'static BOOL fastPixelTransform(', 'static BOOL fastPixelContext(', 'static BOOL tryFastSolidRect(', 'static BOOL tryFastImage(']:
        body = function(current_context, name)
        # Native ownership adapter for the sole Objective-C message in helpers.
        body = body.replace('[self->_layerStack count]', 'self->_layerStack')
        source += body
else:
    source += '\n#define HAVE_FAST_PATHS 0\n'
source += (ROOT/'tests/onyx-fastpaths-native.inc').read_text()
for scalar in ['float', 'double']:
    (out/(scalar+'.c')).write_text(source.replace('typedef double O2Float;', 'typedef '+scalar+' O2Float;'))
(out/'build.ninja').write_text('''rule cc
  command = clang -std=c11 @INCLUDE@ -D_POSIX_C_SOURCE=200809L -D__LITTLE_ENDIAN__ -Wall -Wextra -Werror -Wno-unused-function -Wno-unused-parameter -Wno-sign-compare -Wno-misleading-indentation -Wno-incompatible-function-pointer-types -Wno-strict-prototypes $flags -MMD -MF $out.d $in -lm -o $out
  depfile = $out.d
  deps = gcc
build equivalence-float: cc float.c
  flags = -O2 -g -fsanitize=address,undefined,float-cast-overflow -fno-sanitize-recover=all
build equivalence-double: cc double.c
  flags = -O2 -g -fsanitize=address,undefined,float-cast-overflow -fno-sanitize-recover=all
build equivalence-float-O0: cc float.c
  flags = -O0 -g -fsanitize=address,undefined,float-cast-overflow -fno-sanitize-recover=all
build equivalence-double-O0: cc double.c
  flags = -O0 -g -fsanitize=address,undefined,float-cast-overflow -fno-sanitize-recover=all
build benchmark-O0: cc double.c
  flags = -O0
build benchmark: cc double.c
  flags = -O2
'''.replace('@INCLUDE@', shlex.quote('-I'+str(ROOT/'Onyx2D/include'))))
print('Prepared pinned old general path and current candidate in', out)
