"""Run actual derived clip transform guards with both O2Float widths; not dispatch."""
from pathlib import Path
import os, subprocess, tempfile
root=Path(__file__).resolve().parents[2]
def function(text,name):
 a=text.index(name);a=text.rfind('\n',0,a)+1;b=text.index('{',a)+1;depth=1
 while depth:depth+=(text[b]=='{')-(text[b]=='}');b+=1
 return text[a:b]
affine=(root/'Onyx2D/O2AffineTransform.m').read_text();builtin=(root/'Onyx2D/O2Context_builtin.m').read_text()
src=r'''
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <limits.h>
#include <float.h>
#include <math.h>
#include <stdio.h>
#include <assert.h>
typedef double O2Float;typedef bool BOOL;
#define YES true
#define NO false
typedef struct {O2Float x,y;} O2Point;typedef struct {O2Float width,height;} O2Size;typedef struct {O2Point origin;O2Size size;} O2Rect;typedef struct {O2Float a,b,c,d,tx,ty;} O2AffineTransform;
typedef struct {size_t width,height;} O2Image;typedef O2Image *O2ImageRef;
static size_t O2ImageGetWidth(O2Image *i){return i->width;}static size_t O2ImageGetHeight(O2Image *i){return i->height;}
'''
for name in ['O2AffineTransform O2AffineTransformMakeScale(', 'O2AffineTransform O2AffineTransformMakeTranslation(', 'O2AffineTransform O2AffineTransformConcat(', 'O2AffineTransform O2AffineTransformInvert(', 'O2AffineTransform O2AffineTransformScale(', 'O2Point O2PointApplyAffineTransform(']:src+=function(affine,name)+'\n'
src+=function(builtin,'static inline O2AffineTransform\ncreateImageToSurfaceTransform(')+'\n'+function(builtin,'static BOOL clipMaskTransformIsSafe(')+'\n'
src+=r'''
int main(void){O2Image image={12,12};O2Rect rect={{2,2},{12,12}};O2AffineTransform good[]={{1,0,0,1,3,4},{2,0,0,3,0,0},{0,1,-1,0,16,0},{1,.25,.5,1,0,0},{-1,0,0,1,16,0}};for(unsigned i=0;i<sizeof(good)/sizeof(*good);i++)assert(clipMaskTransformIsSafe(&image,rect,good[i],16,16));
 O2Float extent=(O2Float)(sizeof(O2Float)==sizeof(double)?DBL_MAX:FLT_MAX);O2AffineTransform identity={1,0,0,1,0,0},huge=identity;O2Rect bad=rect;bad.origin.x=extent;huge.tx=extent;assert(!clipMaskTransformIsSafe(&image,bad,huge,16,16));huge=identity;huge.tx=extent;assert(!clipMaskTransformIsSafe(&image,rect,huge,16,16));huge=identity;huge.a=1e-20;assert(!clipMaskTransformIsSafe(&image,rect,huge,16,16));huge=identity;huge.a=extent;huge.d=extent;assert(!clipMaskTransformIsSafe(&image,rect,huge,16,16));bad=rect;bad.size.width=0;assert(!clipMaskTransformIsSafe(&image,bad,identity,16,16));huge=identity;huge.a=0;assert(!clipMaskTransformIsSafe(&image,rect,huge,16,16));huge=identity;huge.tx=NAN;assert(!clipMaskTransformIsSafe(&image,rect,huge,16,16));
 puts("ACTUAL_CLIP_DERIVED_TRANSFORM_RANGE_GUARD_PASS_NOT_GUEST");return 0;}
'''
out=Path(tempfile.mkdtemp(prefix='clip-transform-source-'))
for scalar in ['float','double']:
 (out/(scalar+'.c')).write_text(src.replace('typedef double O2Float;', 'typedef '+scalar+' O2Float;'))
 subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-fsanitize=address,undefined,float-cast-overflow',str(out/(scalar+'.c')),'-lm','-o',str(out/scalar)],check=True)
 subprocess.run([str(out/scalar)],check=True,env={**os.environ,'ASAN_OPTIONS':'detect_leaks=0','UBSAN_OPTIONS':'halt_on_error=1'})
print('source evidence:',out)
