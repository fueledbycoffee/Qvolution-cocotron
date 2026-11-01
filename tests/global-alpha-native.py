#!/usr/bin/env python3
"""Native production paint/alpha/float-composite differential with storage adapters.
No guest dispatch, path tessellation, real font lookup or image resampler claim.
Usage: python3 tests/global-alpha-native.py [--baseline-rev REV]
With --baseline-rev the script succeeds only if the probe FAILS against REV.

With --baseline-rev every Onyx2D source (headers, paints, the shared paint setup,
the FreeType and image-draw call sites) is taken from that git revision instead
of the working tree, so the same assertions run against the pre-fix code.
"""
from pathlib import Path
import argparse, os, re, subprocess, tempfile
p = argparse.ArgumentParser()
p.add_argument('--baseline-rev')
a = p.parse_args()
root = Path(__file__).resolve().parents[1]

def read(rel):
    if a.baseline_rev:
        return subprocess.check_output(['git', 'show', a.baseline_rev + ':Onyx2D/' + rel], cwd=root, text=True)
    return (root / 'Onyx2D' / rel).read_text()

def clean(s):
    return '\n'.join(l for l in s.splitlines() if not l.startswith('#import'))

def balanced(s, start):
    """Text from start through the brace block that opens after it."""
    end = s.index('{', start) + 1; depth = 1
    while depth:
        depth += (s[end] == '{') - (s[end] == '}'); end += 1
    return s[start:end]

def function(rel, name, optional=False):
    s = read(rel)
    if name not in s:
        if optional:
            return ''
        raise SystemExit('missing ' + name + ' in ' + rel)
    start = s.rfind('\n', 0, s.index(name)) + 1
    return balanced(s, start) + '\n'

src = (root / 'tests/global-alpha-native.inc').read_text()
h = read('include/Onyx2D/O2argb32f.h')
src += h[h.index('typedef float O2Float32;'):h.index('#define COVERAGE_MULTIPLIER_FLOAT')]
for name in ['O2Paint', 'O2Paint_color', 'O2Paint_pattern', 'O2Paint_image', 'O2Paint_ramp', 'O2Paint_axialGradient', 'O2Paint_radialGradient']:
    src += clean(read('include/Onyx2D/' + name + '.h')).replace('@protected', '@public').replace(' : O2Paint {', ' : O2Paint {\n@public').replace(' : O2Paint_ramp {', ' : O2Paint_ramp {\n@public') + '\n'
src += clean(read('O2Paint.m')) + '\n' + clean(read('O2Paint_color.m')) + '\n'
# Only the image paint's alpha setter ever existed as a method; take it if this tree has it.
image_setter = function('O2Paint_image.m', '- (void) setAlpha:', optional=True)
src += r'''
@implementation O2Paint_pattern @end
@implementation O2Paint_image
''' + image_setter + r'''@end
@implementation O2Paint_ramp @end
@implementation O2Paint_axialGradient @end
@implementation O2Paint_radialGradient @end
'''
# Only storage/sampling inputs are adapters; all paint span logic is production.
sampling = r'''
static void sample32(O2Image *im,int x,int y,O2argb32f *out,int n,O2AffineTransform t){
 (void)y;(void)t;for(int i=0;i<n;i++)out[i]=O2argb32fInit(((x+i)&1)?.8:.2,.3,.1,.8);
 if(im->mask)for(int i=0;i<n;i++)out[i]=O2argb32fInit(.5,.5,.5,1);
}
static void sample8(O2Image *im,int x,int y,O2argb8u *out,int n,O2AffineTransform t){O2argb32f f[n];sample32(im,x,y,f,n,t);for(int i=0;i<n;i++)out[i]=O2argb8uFromO2argb32f(f[i]);}
#define O2ImageBilinear_largb32f_PRE sample32
#define O2ImagePointSampling_largb32f_PRE sample32
#define O2ImageBilinear_largb8u_PRE sample8
#define O2ImageBilinearFloatTranslate_largb8u_PRE sample8
#define O2ImagePointSampling_largb8u_PRE sample8
#define O2ImageIntegerTranslate_largb8u_PRE sample8
#define O2ImageReadPatternSpan_largb8u_PRE(im,x,y,out,n,t,mode) sample8(im,x,y,out,n,t)
#define O2ImageReadPatternSpan_largb32f_PRE(im,x,y,out,n,t,mode) sample32(im,x,y,out,n,t)
static uint8_t O2Image_8u_mul_8u_div_255(uint8_t c,uint8_t a){return (c*a+127)/255;}
'''
src += sampling
functions = {
'O2Paint_pattern.m': ['ONYX2D_STATIC int o2pattern_largb8u_PRE(', 'ONYX2D_STATIC int o2pattern_largb32f_PRE('],
'O2Paint_image.m': ['static inline void O2PaintApplyGlobalAlpha8u(', 'static inline void O2PaintApplyGlobalAlpha32f(', 'static void O2PaintApplyMaskSpan32f(', 'void O2PaintApplyMaskSpan(', 'ONYX2D_STATIC int O2PaintReadResampledLowSpan_largb32f_PRE(', 'ONYX2D_STATIC int O2PaintReadResampledNoneSpan_largb32f_PRE(', 'ONYX2D_STATIC int O2PaintReadResampledLowSpan_largb8u_PRE(', 'ONYX2D_STATIC int O2PaintReadResampledLowSpanFloatTranslate_largb8u_PRE(', 'ONYX2D_STATIC int O2PaintReadResampledNoneSpan_largb8u_PRE(', 'ONYX2D_STATIC int O2PaintReadIntegerTranslateSpan_largb8u_PRE('],
'O2Paint_ramp.m': ['ONYX2D_STATIC_INLINE O2argb32f readStopColor(', 'O2argb32f O2PaintIntegrateColorRamp(', 'O2argb32f O2PaintColorRamp('],
'O2Paint_axialGradient.m': ['ONYX2D_STATIC_INLINE O2argb8u O2PaintFastAxialRamp(', 'ONYX2D_STATIC int linear_span_largb8u_PRE(', 'ONYX2D_STATIC int linear_span_largb32f_PRE('],
'O2Paint_radialGradient.m': ['ONYX2D_STATIC_INLINE void quadratic(', 'void O2PaintRadialGradient(', 'radialGradientColorAt(', 'ONYX2D_STATIC int radial_span_largb8u_PRE(', 'ONYX2D_STATIC int radial_span_largb32f_PRE(']}
# Helpers that a later cleanup removes are optional; everything else must exist.
optional = {'static inline void O2PaintApplyGlobalAlpha8u(', 'static inline void O2PaintApplyGlobalAlpha32f('}
for rel, names in functions.items():
    for name in names:
        src += ('static O2argb32f\n' if name == 'radialGradientColorAt(' else '') + function(rel, name, name in optional)
ctx = read('O2Context_builtin.m')
ft = read('O2Context_builtin_FT.m')
blend = read('include/Onyx2D/O2Context.h')
modes = blend[blend.rindex('typedef enum {', 0, blend.index('} O2BlendMode;')):blend.index('} O2BlendMode;')] + '} O2BlendMode;\n'
setup = function('O2Context_builtin.m', 'void O2ContextSetupPaintAndBlendMode(')
# Blend/coverage routines are distinct sentinels: the test compares which one was selected.
names = sorted(set(re.findall(r'\bO2(?:BlendSpan|RasterizeWriteCoverageSpan)\w*', setup)))
sentinels = ''.join('static int %s(void){return %d;}\n' % (n, i + 1) for i, n in enumerate(names))
src += modes + sentinels
src += r'''
typedef struct { int rw; } O2Surface;
typedef struct { O2Float _alpha; } O2GState;
@interface Stack : NSObject { @public O2Surface *top; }
- (NSUInteger)count;
- (id)lastObject;
@end
@implementation Stack
- (NSUInteger)count {return 1;}
- (id)lastObject {return (id)top;}
@end
typedef struct { O2Paint *_paint;
 void *_blend_argb8u_PRE,*_blend_argb32f_PRE,*_writeCoverage_argb8u_PRE,*_blendFunction,*_writeCoverageFunction;
 O2GState state;Stack *_layerStack;O2Surface *_surface;id _clipContext;int viewport;} O2Context_builtin;
#define O2ContextCurrentGState(c) (&(c)->state)
#define O2LayerGetSurface(l) ((O2Surface *)(l))
static BOOL hasViewportClip(O2Context_builtin *self){return self->viewport;}
static BOOL O2SurfaceCanReadWriteARGB8u(O2Surface *s){return s->rw;}
static void O2ContextSetPaint(O2Context_builtin *c,O2Paint *p){O2PaintRetain(p);O2PaintRelease(c->_paint);c->_paint=p;}
'''
# Production state setter, so the [0, 1] clamp is exercised where alpha is stored.
state_setter = function('O2GraphicsState.m', 'void O2GStateSetAlpha(')
src += state_setter + setup
# Call sites that decide which paint a consumer sees, compiled from the same tree. The
# image call site only exists before the fix; the FreeType argument is whatever the
# glyph renderer receives.
image_site = ''
i = ctx.find('if ([imagePaint isKindOfClass: [O2Paint_image class]])')
if i >= 0:
    image_site = balanced(ctx, i)
call = ft.index('renderFreeTypeBitmap(self, surface, &cached->bitmap,')
ft_arg = ft[call:ft.index(');', call)].rsplit(',', 1)[1].strip()
src += 'static void image_call_site(O2Context_builtin *self, O2Paint *imagePaint){O2GState *gState=&self->state;(void)gState;(void)imagePaint;\n' + image_site + '\n}\n'
src += 'static O2Paint *ft_paint(O2Context_builtin *self, O2Paint *paint){(void)self;return %s;}\n' % ft_arg
src += '#define HAS_PAINT_ALPHA %d\n' % ('O2PaintCreateWithAlpha' in read('O2Paint.m'))
src += '#define IMAGE_HAS_ALPHA %d\n' % ('O2Float _alpha' in read('include/Onyx2D/O2Paint_image.h'))
src += (root / 'tests/global-alpha-native-main.inc').read_text()
with tempfile.TemporaryDirectory(prefix='onyx-alpha-') as d:
    d = Path(d); (d/'probe.m').write_text(src)
    # Against a baseline the probe must fail; undefined behaviour in the old
    # code (a negative alpha cast to a byte) is reported and counted, not fatal.
    ubsan = 'halt_on_error=0' if a.baseline_rev else 'halt_on_error=1'
    for opt in ['-O0', '-O2']:
        exe = d / ('probe'+opt)
        subprocess.run(['clang','-x','objective-c','-I'+str(sorted(Path('/usr/lib/gcc/x86_64-linux-gnu').glob('*/include'))[-1]),opt,'-Wall','-Wextra','-Werror','-Wno-unused-parameter','-Wno-incomplete-implementation','-Wno-objc-root-class','-Wno-unused-function','-Wno-sign-compare','-Wno-unused-variable','-Wno-missing-method-return-type','-fsanitize=address,undefined',str(d/'probe.m'),'-l:libobjc.so.4','-lm','-o',str(exe)], check=True)
        r = subprocess.run([str(exe)], capture_output=True, text=True, env={**os.environ,'ASAN_OPTIONS':'detect_leaks=0','UBSAN_OPTIONS':ubsan})
        print(r.stdout, end=''); print(r.stderr, end='')
        if a.baseline_rev:
            if 'RESULT native-global-alpha' not in r.stdout:
                raise SystemExit('baseline probe did not run to completion')
            if r.returncode == 0:
                raise SystemExit('baseline %s passed at %s: the test cannot tell it from the fix' % (a.baseline_rev, opt))
            print('baseline %s fails at %s, as required' % (a.baseline_rev, opt))
        elif r.returncode:
            raise SystemExit(r.returncode)
