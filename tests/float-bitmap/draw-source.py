"""Run actual production rasterizer / FT float branch with native memory adapters.
Not Objective-C dispatch, font/cache integration, or guest runtime evidence.
"""
from pathlib import Path
import subprocess, tempfile, shutil
root=Path(__file__).resolve().parents[2]
def function(path,name):
 s=(root/'Onyx2D'/path).read_text();a=s.index(name);a=s.rfind('\n',0,a)+1;b=s.index('{',a)+1;depth=1
 while depth:depth+=(s[b]=='{')-(s[b]=='}');b+=1
 return s[a:b]
header=(root/'Onyx2D/include/Onyx2D/O2argb32f.h').read_text();a=header.index('typedef float O2Float32;');b=header.index('static inline O2argb32f O2argb32fSubtract');arithmetic=header[a:b]
ft=function('O2Context_builtin_FT.m','static void renderFreeTypeBitmap(');ft=ft[:ft.index('    O2argb8u *dstBuffer')].replace('    NSInteger renderWidth = maxX - minX;', '    NSInteger renderWidth = maxX - minX; (void)renderWidth;')+'    abort();\n}\n'
src=r'''
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <assert.h>
typedef float O2Float;typedef long NSInteger;typedef bool BOOL;
#define COVERAGE_MULTIPLIER 256
#define MIN(a,b) ((a)<(b)?(a):(b))
#define MAX(a,b) ((a)>(b)?(a):(b))
#define ONYX2D_STATIC static
#define ONYX2D_STATIC_INLINE static inline
#define YES true
#define NO false
#define nil NULL
'''+arithmetic+r'''
typedef void (*O2BlendSpan_argb32f)(O2argb32f *,O2argb32f *,int);
typedef struct { unsigned char bytes[4][(320*16)+16]; int width,height; } O2Surface;
typedef struct { void *_paint_largb8u_PRE; O2argb32f color; int skipX; } O2Paint;
typedef struct O2Context_builtin { NSInteger _vpx,_vpy,_vpwidth,_vpheight; O2BlendSpan_argb32f _blend_argb32f_PRE; struct O2Context_builtin *_clipContext; O2Surface *_surface; void *_blend_argb8u_PRE; } O2Context_builtin; typedef O2Context_builtin O2Context_builtin_FT;
typedef struct { unsigned width,rows; int pitch; unsigned char *buffer; } FT_Bitmap;
static bool O2SurfaceCanReadWriteARGB8u(O2Surface *s) { (void)s; return false; }
static O2argb32f *O2Image_read_argb32f(O2Surface *s,int x,int y,O2argb32f *dst,int n) {
 assert(x>=0&&y>=0&&x+n<=s->width&&y<s->height);memcpy(dst,s->bytes[y]+16*x,16*n);return NULL;
}
static void O2SurfaceWriteSpan_largb32f_PRE(O2Surface *s,int x,int y,O2argb32f *src,int n) {
 assert(x>=0&&y>=0&&x+n<=s->width&&y<s->height);memcpy(s->bytes[y]+16*x,src,16*n);
}
static int O2PaintReadSpan_largb32f_PRE(O2Paint *p,int x,int y,O2argb32f *src,int n) {
 (void)y;if(x==p->skipX)return -1;
 if(p->skipX>x&&p->skipX<x+n)n=p->skipX-x;
 for(int i=0;i<n;i++){src[i]=p->color;}return n;
}
static float zeroToOneFromCoverage(int c) { return c/256.0f; }
static O2Float *O2ImageReadSpan_Af_MASK(O2Surface *s,int x,int y,O2Float *out,int n) {
 for(int i=0;i<n;i++){O2argb32f p;memcpy(&p,s->bytes[y]+16*(x+i),16);out[i]=p.a;}return out;
}
'''
for file,name in [('O2argb32f.m','void O2BlendSpanCopy_ffff('),('O2argb32f.m','void O2BlendSpanNormal_ffff('),('O2Context_builtin.m','ONYX2D_STATIC void O2ApplyCoverageAndMaskToSpan_largb32f_PRE('),('O2Context_builtin.m','ONYX2D_STATIC void O2ApplyCoverageToSpan_largb32f_PRE('),('O2Context_builtin.m','O2RasterizeWriteCoverageSpanffff(')]:src+=('static void ' if name=='O2RasterizeWriteCoverageSpanffff(' else '')+function(file,name)+'\n'
src+=function('O2Context_builtin.m','void O2ContextWriteGlyphCoverageSpanFloat(')+'\n'
src+=ft+r'''
static void init(O2Surface *s,int width,int height,O2argb32f color) {
 memset(s->bytes,0xa7,sizeof(s->bytes));s->width=width;s->height=height;
 for(int y=0;y<height;y++)for(int x=0;x<width;x++)memcpy(s->bytes[y]+x*16,&color,16);
}
static void pixel(O2Surface *s,int x,int y,float r,float g,float b,float a) {
 O2argb32f p;memcpy(&p,s->bytes[y]+x*16,16);assert(fabsf(p.r-r)<1e-6&&fabsf(p.g-g)<1e-6&&fabsf(p.b-b)<1e-6&&fabsf(p.a-a)<1e-6);
}
static void padding(O2Surface *s) { for(int y=0;y<4;y++)for(int x=(y<s->height?s->width*16:0);x<(320*16)+16;x++)assert(s->bytes[y][x]==0xa7); }
int main(void) {
 O2Surface s;O2argb32f black=O2argb32fInit(0,0,0,0);
 O2Paint p={NULL,{1,.125,.25,.5},-1};
 init(&s,320,4,black);O2RasterizeWriteCoverageSpanffff(&s,NULL,&p,2,1,256,300,O2BlendSpanNormal_ffff);pixel(&s,2,1,.125,.25,.5,1);pixel(&s,301,1,.125,.25,.5,1);pixel(&s,1,1,0,0,0,0);padding(&s);
 init(&s,320,4,O2argb32fInit(.25,.5,.75,1));p.color=O2argb32fInit(.375,.125,.25,.5);O2RasterizeWriteCoverageSpanffff(&s,NULL,&p,0,0,256,320,O2BlendSpanNormal_ffff);pixel(&s,100,0,.5,.375,.625,1);padding(&s);
 O2Context_builtin_FT c={3,1,300,2,O2BlendSpanNormal_ffff,NULL,NULL,NULL};unsigned char cov[640];for(int i=0;i<640;i++)cov[i]=(unsigned char[]){0,64,128,255}[i%4];FT_Bitmap b={320,2,320,cov};p.color=O2argb32fInit(.0625,.125,.25,.5);
 for(int sign=-1;sign<=1;sign+=2) {
  init(&s,320,4,black);b.pitch=sign*320;p.skipX=100;renderFreeTypeBitmap(&c,&s,&b,0,1,&p);
  for(int y=0;y<4;y++)for(int x=0;x<320;x++) {float f=(x>=3&&x<303&&y>=1&&y<3&&x!=100)?cov[(sign>0?y-1:2-y)*320+x]/255.0f:0;pixel(&s,x,y,.0625*f,.125*f,.25*f,.5*f);}
  padding(&s);
 }
 // Nonuniform real mask alpha times glyph coverage, over a nonzero destination.
 O2Surface mask;init(&mask,320,4,black);O2Context_builtin clip={0};clip._surface=&mask;c._clipContext=&clip;p.skipX=-1;
 for(int y=0;y<4;y++)for(int x=0;x<320;x++){O2argb32f m=O2argb32fInit(.9,.1,.2,(float[]){0,.1255f,.5f,1}[x%4]);memcpy(mask.bytes[y]+x*16,&m,16);}
 b.pitch=320;init(&s,320,4,O2argb32fInit(.2,.4,.6,.8));renderFreeTypeBitmap(&c,&s,&b,0,1,&p);
 for(int y=0;y<4;y++)for(int x=0;x<320;x++) {
 float f=(x>=3&&x<303&&y>=1&&y<3)?cov[(y-1)*320+x]/255.0f*(float[]){0,.1255f,.5f,1}[x%4]:0;
 pixel(&s,x,y,.2f+(.0625f-.2f*.5f)*f,.4f+(.125f-.4f*.5f)*f,.6f+(.25f-.6f*.5f)*f,.8f+(.5f-.8f*.5f)*f);
 }
 padding(&s);padding(&mask);
 puts("ACTUAL_FLOAT_RASTER_FT_AND_MASK_BRANCH_SOURCE_PASS_NOT_GUEST_DISPATCH");return 0;
}
'''
out=Path(tempfile.mkdtemp(prefix='onyx-float-draw-'));(out/'draw.c').write_text(src)
subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-fsanitize=address,undefined',str(out/'draw.c'),'-lm','-o',str(out/'draw')],check=True)
subprocess.run([str(out/'draw')],check=True)

shutil.rmtree(out)
