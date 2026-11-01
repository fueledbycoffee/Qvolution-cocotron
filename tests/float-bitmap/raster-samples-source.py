"""Exact production raster functions with native memory adapters.
No Objective-C dispatch, state ownership, font, layer or guest qualification.
"""
from pathlib import Path
import os, subprocess, tempfile
root=Path(__file__).resolve().parents[2]
source=(root/'Onyx2D/O2Context_builtin.m').read_text()
def function(name):
 a=source.index(name);a=source.rfind('\n',0,a)+1;b=source.index('{',a)+1;depth=1
 while depth:depth+=(source[b]=='{')-(source[b]=='}');b+=1
 return source[a:b]
header=(root/'Onyx2D/include/Onyx2D/O2Context_builtin.h').read_text()
a=header.index('typedef struct Edge');b=header.index('typedef void (*O2BlendSpan_argb8u)',a);edge=header[a:b]
header=(root/'Onyx2D/include/Onyx2D/O2argb32f.h').read_text();a=header.index('typedef float O2Float32;');b=header.index('static inline O2argb32f O2argb32fSubtract');arithmetic=header[a:b]
src=r'''
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include <math.h>
#include <string.h>
#include <assert.h>
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
#define RI_CLAMP(v,a,b) (isnan(v)?(a):MAX((a),MIN((v),(b))))
#define RI_INT_CLAMP(v,a,b) MAX((a),MIN((v),(b)))
#define RI_ASSERT(v)
#define ONYX2D_STATIC static
#define ONYX2D_STATIC_INLINE static inline
#define NSZoneMalloc(z,n) malloc(n)
#define NSZoneRealloc(z,p,n) realloc(p,n)
#define NSZoneFree(z,p) free(p)
typedef struct {O2Float x,y;} O2Point;
static O2Point Vector2Subtract(O2Point a,O2Point b){return (O2Point){a.x-b.x,a.y-b.y};}
'''+arithmetic+edge+r'''
typedef struct {size_t width,height;O2argb32f *pixels;int64_t damage[4];int damaged,expectDamage;} O2Surface;
typedef struct {O2argb32f color;} O2Paint;
typedef O2Surface O2Image;
typedef struct O2Context_builtin {
 int _vpx,_vpy,_vpwidth,_vpheight,_edgeCount,_edgeCapacity,_edgeAllocated;
 Edge **_edges,**_sortCache;int *_winding,*_increase,*_rowIncrease;
 int sampleSizeShift,numSamples,samplesWeight;O2Float *samplesX,samplesInitialY,samplesDeltaY;int alias;
 void (*_writeCoverageFunction)(O2Surface *,O2Surface *,O2Paint *,int,int,int,int,void *);
 void *_blendFunction;struct O2Context_builtin *_clipContext;O2Surface *_surface;uint32_t *_clipSamples;BOOL _clipIsSoftPhase;
} O2Context_builtin;
static size_t O2ImageGetWidth(O2Surface *s){return s->width;}
static size_t O2ImageGetHeight(O2Surface *s){return s->height;}
static void O2Image_read_argb32f(O2Surface *s,int x,int y,O2argb32f *out,int n){assert(x>=0&&y>=0&&(size_t)(x+n)<=s->width&&(size_t)y<s->height);memcpy(out,s->pixels+y*s->width+x,n*sizeof(*out));}
static void O2ImageReadSpan_Af_MASK(O2Surface *s,int x,int y,O2Float *out,int n){assert(x>=0&&y>=0&&(size_t)(x+n)<=s->width&&(size_t)y<s->height);for(int i=0;i<n;i++)out[i]=s->pixels[y*s->width+x+i].a;}
static void O2SurfaceWriteSpan_largb32f_PRE(O2Surface *s,int x,int y,O2argb32f *in,int n){assert(x>=0&&y>=0&&(size_t)(x+n)<=s->width&&(size_t)y<s->height);memcpy(s->pixels+y*s->width+x,in,n*sizeof(*in));}
// Production sweeps report damage before writing; every span must lie inside it.
static void O2SurfaceAddDamage(O2Surface *s,int64_t x,int64_t y,int64_t w,int64_t h){if(w<=0||h<=0)return;if(!s->damaged){s->damage[0]=x;s->damage[1]=y;s->damage[2]=x+w;s->damage[3]=y+h;s->damaged=1;return;}if(x<s->damage[0])s->damage[0]=x;if(y<s->damage[1])s->damage[1]=y;if(x+w>s->damage[2])s->damage[2]=x+w;if(y+h>s->damage[3])s->damage[3]=y+h;}
static void writeCoverage(O2Surface *s,O2Surface *mask,O2Paint *p,int x,int y,int cov,int n,void *blend){if(s->expectDamage)assert(s->damaged&&x>=s->damage[0]&&x+n<=s->damage[2]&&y>=s->damage[1]&&y<s->damage[3]);(void)p;(void)blend;assert(x>=0&&y>=0&&(size_t)(x+n)<=s->width&&(size_t)y<s->height);for(int i=0;i<n;i++)s->pixels[y*s->width+x+i]=O2argb32fInit(cov/256.f,cov/256.f,cov/256.f,cov/256.f);if(mask)for(int i=0;i<n;i++)s->pixels[y*s->width+x+i]=O2argb32fMultiplyByFloat(s->pixels[y*s->width+x+i],mask->pixels[y*mask->width+x+i].a);}
'''
for name in ['void O2RasterizerSetViewport(', 'void O2RasterizerClear(', 'void O2DContextAddEdge(', 'ONYX2D_STATIC double radicalInverseBase2(', 'void O2RasterizerSetShouldAntialias(']:src+=function(name)+'\n'
src+=function('static unsigned clipSampleCount(')+'\n'
a=source.index('ONYX2D_STATIC_INLINE void sortEdgesByMinY');b=source.index('void O2DContextClipAndFillEdges(',a);src+=source[a:b]
src+=r'''
static void init(O2Context_builtin *c,O2Surface *s,int w,int h){memset(c,0,sizeof(*c));memset(s,0,sizeof(*s));s->width=w;s->height=h;s->pixels=calloc(w*h,sizeof(O2argb32f));c->_surface=s;c->_edgeCapacity=256;c->_edges=calloc(256,sizeof(Edge *));c->_sortCache=calloc(129,sizeof(Edge *));c->_winding=calloc(w*256+1,sizeof(int));c->_rowIncrease=calloc(w*256+1,sizeof(int));c->_increase=malloc(w*sizeof(int));for(int x=0;x<w;x++)c->_increase[x]=INT_MAX;c->samplesX=calloc(256,sizeof(O2Float));c->_writeCoverageFunction=writeCoverage;O2RasterizerSetViewport(c,0,0,w,h);O2RasterizerSetShouldAntialias(c,YES,64);}
static void dispose(O2Context_builtin *c){O2RasterizerClear(c);for(int i=0;i<c->_edgeAllocated;i++)free(c->_edges[i]);free(c->_edges);free(c->_sortCache);free(c->_winding);free(c->_rowIncrease);free(c->_increase);free(c->samplesX);free(c->_clipSamples);free(c->_surface->pixels);}
static void triangle(O2Context_builtin *c){O2DContextAddEdge(c,(O2Point){2,2},(O2Point){14,2});O2DContextAddEdge(c,(O2Point){14,2},(O2Point){2,14});O2DContextAddEdge(c,(O2Point){2,14},(O2Point){2,2});}
static void rect(O2Context_builtin *c,float x,float y,float w,float h){O2DContextAddEdge(c,(O2Point){x,y},(O2Point){x+w,y});O2DContextAddEdge(c,(O2Point){x+w,y},(O2Point){x+w,y+h});O2DContextAddEdge(c,(O2Point){x+w,y+h},(O2Point){x,y+h});O2DContextAddEdge(c,(O2Point){x,y+h},(O2Point){x,y});}
static int polygonClip(O2Point *out,const O2Point *in,int count,float nx,float ny,float d){int n=0;for(int i=0;i<count;i++){O2Point a=in[i],b=in[(i+1)%count];float da=nx*a.x+ny*a.y-d,db=nx*b.x+ny*b.y-d;if(da<=0)out[n++]=a;if((da<0&&db>0)||(da>0&&db<0)){float t=da/(da-db);out[n++]=(O2Point){a.x+t*(b.x-a.x),a.y+t*(b.y-a.y)};}}return n;}
static float area(const O2Point *p,int n){float sum=0;for(int i=0;i<n;i++)sum+=p[i].x*p[(i+1)%n].y-p[(i+1)%n].x*p[i].y;return fabs(sum)*.5f;}
static void halfplane(O2Context_builtin *c,float nx,float ny,float d){O2Point box[]={{0,0},{16,0},{16,16},{0,16}},p[8];int n=polygonClip(p,box,4,nx,ny,d);for(int i=0;i<n;i++)O2DContextAddEdge(c,p[i],p[(i+1)%n]);O2DContextFillEdgesOnSurface(c,c->_surface,NULL,NULL,-1);}
static float pixelArea(int x,int y,float nx,float ny,float d){O2Point box[]={{x,y},{x+1,y},{x+1,y+1},{x,y+1}},p[8];return area(p,polygonClip(p,box,4,nx,ny,d));}
int main(void){setbuf(stdout,NULL);
 for(int quality=1;quality<=256;quality*=2){O2Context_builtin c;O2Surface s;init(&c,&s,16,16);O2RasterizerSetShouldAntialias(&c,YES,quality);for(int i=0;i<c.numSamples;i++){assert(c.samplesX[i]>0&&c.samplesX[i]<1);{assert(fabs(c.samplesX[i]+c.samplesX[c.numSamples-1-i]-1)<1e-6);float ya=c.samplesInitialY+i*c.samplesDeltaY,yb=c.samplesInitialY+(c.numSamples-1-i)*c.samplesDeltaY;assert(fabs(ya+yb-1)<1e-6);}}dispose(&c);}
 for(int quality=2;quality<=256;quality*=2)for(int orientation=0;orientation<6;orientation++)for(int translate=0;translate<3;translate++){
  float nx=(float[]){1,0,1,1,1.41421356f,-1.41421356f}[orientation],ny=(float[]){0,1,1,-1,1,1}[orientation];float d=nx*(6.5f+translate)+ny*(7.5f-translate);
  O2Context_builtin a,b,r;O2Surface sa,sb,sr;init(&a,&sa,16,16);init(&b,&sb,16,16);init(&r,&sr,16,16);O2RasterizerSetShouldAntialias(&a,YES,quality);O2RasterizerSetShouldAntialias(&b,YES,quality);O2RasterizerSetShouldAntialias(&r,YES,quality);halfplane(&a,nx,ny,d);halfplane(&b,-nx,-ny,-d);halfplane(&r,-nx,-ny,d-16*(nx+ny));
  float largest=0;for(int y=0;y<16;y++)for(int x=0;x<16;x++){float got=sa.pixels[y*16+x].a,want=pixelArea(x,y,nx,ny,d);largest=fmaxf(largest,fabs(got-want));assert(fabs(got+sb.pixels[y*16+x].a-1)<1e-6);assert(fabs(got-sr.pixels[(15-y)*16+15-x].a)<1e-6);if(want<1e-5||want>1-1e-5)assert(fabs(got-want)<1e-5);}
  assert(largest<=2.f/sqrtf(quality));dispose(&a);dispose(&b);dispose(&r);
 }
 O2Context_builtin q;O2Surface qs;for(int reflected=0;reflected<2;reflected++){init(&q,&qs,16,16);O2RasterizerSetShouldAntialias(&q,YES,1);rect(&q,reflected?.7f:0,0,.3f,1);O2DContextFillEdgesOnSurface(&q,&qs,NULL,NULL,-1);for(int i=0;i<256;i++)assert(qs.pixels[i].a==0);dispose(&q);}
 O2Context_builtin c;O2Surface s;init(&c,&s,16,16);triangle(&c);O2DContextFillEdgesOnSurface(&c,&s,NULL,NULL,-1);float largest=0;int fraction=0;for(int y=0;y<16;y++)for(int x=0;x<16;x++){float want=x<2||y<2||x>=14||y>=14?0:x+y<15?1:x+y==15?.5:0;float got=s.pixels[y*16+x].a;largest=fmaxf(largest,fabs(got-want));fraction+=got>0&&got<1;}printf("diagonal largest area error %.9f fractional pixels %d\n",largest,fraction);assert(largest<1e-6&&fraction==12);dispose(&c);
 for(int rule=-1;rule<=1;rule+=2){init(&c,&s,16,16);rect(&c,2,2,12,12);rect(&c,5,5,6,6);O2DContextFillEdgesOnSurface(&c,&s,NULL,NULL,rule);for(int y=0;y<16;y++)for(int x=0;x<16;x++){float want=x>=2&&x<14&&y>=2&&y<14&&(rule==-1||!(x>=5&&x<11&&y>=5&&y<11));assert(s.pixels[y*16+x].a==want);}dispose(&c);}
 puts("ACTUAL_RASTER_SAMPLE_BOUNDS_SYMMETRY_REFLECTION_HALFPLANES_AND_RULES_PASS");return 0;
}
'''
out=Path(tempfile.mkdtemp(prefix='public-clip-source-'))
for scalar in ['float','double']:
 (out/('probe-'+scalar+'.c')).write_text(src.replace('typedef double O2Float;', 'typedef '+scalar+' O2Float;'))
 subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-Wno-sign-compare','-Wno-unused-function','-fsanitize=address,undefined,float-cast-overflow',str(out/('probe-'+scalar+'.c')),'-lm','-o',str(out/('probe-'+scalar))],check=True)
 subprocess.run([str(out/('probe-'+scalar))],check=True,env={**os.environ,'ASAN_OPTIONS':'detect_leaks=0','UBSAN_OPTIONS':'halt_on_error=1'})
print('source evidence:',out)
