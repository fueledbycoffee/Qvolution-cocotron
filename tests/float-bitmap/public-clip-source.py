"""Exact production clipping/raster functions with native memory adapters.
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
#include <float.h>
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
typedef struct {size_t width,height;O2argb32f *pixels;} O2Surface;
static void O2SurfaceAddDamage(O2Surface *s,int64_t x,int64_t y,int64_t w,int64_t h){(void)s;(void)x;(void)y;(void)w;(void)h;}
typedef struct {O2argb32f color;} O2Paint;
typedef O2Surface O2Image;
typedef struct O2Context_builtin {
 int _vpx,_vpy,_vpwidth,_vpheight,_edgeCount,_edgeCapacity,_edgeAllocated;
 Edge **_edges,**_sortCache;int *_winding,*_increase,*_rowIncrease;
 int sampleSizeShift,numSamples,samplesWeight;O2Float *samplesX,samplesInitialY,samplesDeltaY;int alias;
 void (*_writeCoverageFunction)(O2Surface *,O2Surface *,O2Paint *,int,int,int,int,void *);
 void *_blendFunction;struct O2Context_builtin *_clipContext;O2Surface *_surface;uint32_t *_clipSamples;BOOL _clipIsSoftPhase;
} O2Context_builtin;
static size_t O2ImageGetWidth(void *p){return ((O2Surface *)p)->width;}
static size_t O2ImageGetHeight(void *p){return ((O2Surface *)p)->height;}
static void O2Image_read_argb32f(O2Surface *s,int x,int y,O2argb32f *out,int n){assert(x>=0&&y>=0&&(size_t)(x+n)<=s->width&&(size_t)y<s->height);memcpy(out,s->pixels+y*s->width+x,n*sizeof(*out));}
static void O2ImageReadSpan_Af_MASK(O2Surface *s,int x,int y,O2Float *out,int n){assert(x>=0&&y>=0&&(size_t)(x+n)<=s->width&&(size_t)y<s->height);for(int i=0;i<n;i++)out[i]=s->pixels[y*s->width+x+i].a;}
static void O2SurfaceWriteSpan_largb32f_PRE(O2Surface *s,int x,int y,O2argb32f *in,int n){assert(x>=0&&y>=0&&(size_t)(x+n)<=s->width&&(size_t)y<s->height);memcpy(s->pixels+y*s->width+x,in,n*sizeof(*in));}
static void writeCoverage(O2Surface *s,O2Surface *mask,O2Paint *p,int x,int y,int cov,int n,void *blend){(void)p;(void)blend;assert(x>=0&&y>=0&&(size_t)(x+n)<=s->width&&(size_t)y<s->height);for(int i=0;i<n;i++)s->pixels[y*s->width+x+i]=O2argb32fInit(cov/256.f,cov/256.f,cov/256.f,cov/256.f);if(mask)for(int i=0;i<n;i++)s->pixels[y*s->width+x+i]=O2argb32fMultiplyByFloat(s->pixels[y*s->width+x+i],mask->pixels[y*mask->width+x+i].a);}
'''
for name in ['void O2RasterizerSetViewport(', 'void O2RasterizerClear(', 'void O2DContextAddEdge(', 'ONYX2D_STATIC double radicalInverseBase2(', 'void O2RasterizerSetShouldAntialias(']:src+=function(name)+'\n'
src+=function('static unsigned clipSampleCount(')+'\n'
a=source.index('ONYX2D_STATIC_INLINE void sortEdgesByMinY');b=source.index('void O2DContextClipAndFillEdges(',a);src+=source[a:b]
src+=function('static BOOL allocateClipSamples(')+'\n'
f=function('static void intersectClipContext(').replace('[self->_clipContext release];','').replace('[phase retain]','phase');src+='static void O2ContextDeviceClipReset_builtin(O2Context_builtin *s){s->_clipContext=NULL;}\n'+f
src+=function('static void normalizeClipToLayerDomain(')+'\n'
src+=r'''
typedef struct {size_t width,height,bpc,bpp,row,components;uint8_t *bytes;size_t length;O2Float *decode;BOOL isMask;int model,alpha;BOOL named;void *mask;} O2MaskInput;
typedef O2MaskInput NSData;typedef O2MaskInput *O2ColorSpaceRef;
static size_t O2ImageGetBitsPerComponent(O2MaskInput *s){return s->bpc;}
static size_t O2ImageGetBitsPerPixel(O2MaskInput *s){return s->bpp;}
static size_t O2ImageGetBytesPerRow(O2MaskInput *s){return s->row;}
static O2MaskInput *O2ImageGetColorSpace(O2MaskInput *s){return s;}
#define kO2ColorSpaceModelMonochrome 0
#define kO2ImageAlphaNone 0
static size_t O2ColorSpaceGetNumberOfComponents(O2MaskInput *s){return s->components;}
static int O2ColorSpaceGetModel(O2MaskInput *s){return s->model;}
static void *O2ColorSpaceGetName(O2MaskInput *s){return s->named?s:NULL;}
static int O2ImageGetAlphaInfo(O2MaskInput *s){return s->alpha;}
static void *O2ImageGetMask(O2MaskInput *s){return s->mask;}
static const O2Float *O2ImageGetDecode(O2MaskInput *s){return s->decode;}
static BOOL O2ImageIsMask(O2MaskInput *s){return s->isMask;}
static O2Context_builtin *createClipContext(size_t w,size_t h){O2Context_builtin *c=calloc(1,sizeof(*c));c->_surface=calloc(1,sizeof(*c->_surface));c->_surface->width=w;c->_surface->height=h;c->_surface->pixels=calloc(w*h,sizeof(O2argb32f));return c;}
'''
f=function('static O2Surface *createClipMaskImage(').replace('O2Image *image','O2MaskInput *image').replace('[image directData]','image').replace('[data bytes]','data->bytes').replace('[data length]','data->length').replace('[context->_surface retain]','context->_surface').replace('[context release];','free(context);')
src+=f+'\n'
src+=r'''
static void init(O2Context_builtin *c,O2Surface *s,int w,int h){memset(c,0,sizeof(*c));s->width=w;s->height=h;s->pixels=calloc(w*h,sizeof(O2argb32f));c->_surface=s;c->_edgeCapacity=256;c->_edges=calloc(256,sizeof(Edge *));c->_sortCache=calloc(129,sizeof(Edge *));c->_winding=calloc(w*256+1,sizeof(int));c->_rowIncrease=calloc(w*256+1,sizeof(int));c->_increase=malloc(w*sizeof(int));for(int x=0;x<w;x++)c->_increase[x]=INT_MAX;c->samplesX=calloc(256,sizeof(O2Float));c->_writeCoverageFunction=writeCoverage;O2RasterizerSetViewport(c,0,0,w,h);O2RasterizerSetShouldAntialias(c,YES,64);}
static void dispose(O2Context_builtin *c){O2RasterizerClear(c);for(int i=0;i<c->_edgeAllocated;i++)free(c->_edges[i]);free(c->_edges);free(c->_sortCache);free(c->_winding);free(c->_rowIncrease);free(c->_increase);free(c->samplesX);free(c->_clipSamples);free(c->_surface->pixels);}
static void triangle(O2Context_builtin *c){O2DContextAddEdge(c,(O2Point){2,2},(O2Point){14,2});O2DContextAddEdge(c,(O2Point){14,2},(O2Point){2,14});O2DContextAddEdge(c,(O2Point){2,14},(O2Point){2,2});}
static void rect(O2Context_builtin *c,int x,int y,int w,int h){O2DContextAddEdge(c,(O2Point){x,y},(O2Point){x+w,y});O2DContextAddEdge(c,(O2Point){x+w,y},(O2Point){x+w,y+h});O2DContextAddEdge(c,(O2Point){x+w,y+h},(O2Point){x,y+h});O2DContextAddEdge(c,(O2Point){x,y+h},(O2Point){x,y});}
static int cut(O2Point *out,const O2Point *p,int n,double nx,double ny,double d){int count=0;for(int i=0;i<n;i++){O2Point a=p[i],b=p[(i+1)%n];double da=nx*a.x+ny*a.y-d,db=nx*b.x+ny*b.y-d;if(da<=0)out[count++]=a;if((da<0&&db>0)||(da>0&&db<0)){double t=da/(da-db);out[count++]=(O2Point){a.x+t*(b.x-a.x),a.y+t*(b.y-a.y)};}}return count;}
static double area(int x,int y,bool overlap){O2Point a[16]={{x,y},{x+1,y},{x+1,y+1},{x,y+1}},b[16];int n=4;double planes[][3]={{-1,0,-2},{0,-1,-2},{1,1,16},{1,0,14},{-1,1,-.5}};for(int k=0;k<(overlap?5:3);k++){n=cut(b,a,n,planes[k][0],planes[k][1],planes[k][2]);memcpy(a,b,n*sizeof(*a));}double result=0;for(int i=0;i<n;i++)result+=a[i].x*a[(i+1)%n].y-a[(i+1)%n].x*a[i].y;return fabs(result)*.5;}
static void second(O2Context_builtin *c){O2DContextAddEdge(c,(O2Point){2.5,2},(O2Point){14,2});O2DContextAddEdge(c,(O2Point){14,2},(O2Point){14,13.5});O2DContextAddEdge(c,(O2Point){14,13.5},(O2Point){2.5,2});}
static void opposite(O2Context_builtin *c){O2DContextAddEdge(c,(O2Point){14,2},(O2Point){14,14});O2DContextAddEdge(c,(O2Point){14,14},(O2Point){2,14});O2DContextAddEdge(c,(O2Point){2,14},(O2Point){14,2});}
static void pathMask(O2Context_builtin *c,O2Surface *s,bool other){init(c,s,16,16);assert(allocateClipSamples(c));O2RasterizerSetShouldAntialias(c,YES,256);if(other)second(c);else triangle(c);O2DContextFillEdgesOnSurface(c,s,NULL,NULL,-1);for(int i=0;i<256;i++)assert(fabs(s->pixels[i].a-clipSampleCount(c->_clipSamples+i*8)/256.)<1e-6);}
int main(void){setbuf(stdout,NULL);
 O2Context_builtin c;O2Surface s;init(&c,&s,16,16);triangle(&c);O2DContextFillEdgesOnSurface(&c,&s,NULL,NULL,-1);float largest=0;int fraction=0;
 for(int y=0;y<16;y++)for(int x=0;x<16;x++){float want=x<2||y<2||x>=14||y>=14?0:x+y<15?1:x+y==15?.5:0;float got=s.pixels[y*16+x].a;largest=fmaxf(largest,fabs(got-want));fraction+=got>0&&got<1;}
 printf("triangle largest error %.9f fractional %d\n",largest,fraction);assert(largest<.008&&fraction>0);dispose(&c);
 for(int rule=-1;rule<=1;rule+=2){init(&c,&s,16,16);rect(&c,2,2,12,12);rect(&c,5,5,6,6);O2DContextFillEdgesOnSurface(&c,&s,NULL,NULL,rule);for(int y=0;y<16;y++)for(int x=0;x<16;x++){float want=x>=2&&x<14&&y>=2&&y<14&&(rule==-1||!(x>=5&&x<11&&y>=5&&y<11));assert(s.pixels[y*16+x].a==want);}dispose(&c);}
 O2Context_builtin old,phase,host;O2Surface os,ps,hs;init(&old,&os,300,3);init(&phase,&ps,300,3);memset(&host,0,sizeof(host));hs.width=300;hs.height=3;host._surface=&hs;O2RasterizerSetViewport(&host,0,0,300,3);host._clipContext=&old;
 for(int y=0;y<3;y++)for(int x=0;x<300;x++){float a=(float[]){0,.25,.5,1}[(x+y)%4],b=(float[]){1,.5,.25,0}[(x+2*y)%4];os.pixels[y*300+x]=O2argb32fInit(a,a,a,a);ps.pixels[y*300+x]=O2argb32fInit(b,b,b,b);}
 intersectClipContext(&host,&phase);assert(host._clipContext==&phase);for(int y=0;y<3;y++)for(int x=0;x<300;x++){float a=(float[]){0,.25,.5,1}[(x+y)%4],b=(float[]){1,.5,.25,0}[(x+2*y)%4];assert(ps.pixels[y*300+x].a==a*b);}dispose(&old);dispose(&phase);intersectClipContext(&host,NULL);assert(host._vpwidth==0&&host._vpheight==0&&host._clipContext==NULL);
 // True geometric path intersection and draw-geometry intersection, using the same production sample grid.
 for(int other=0;other<2;other++){
 O2Context_builtin first,next,owner,draw;O2Surface fs,ns,ds;pathMask(&first,&fs,NO);pathMask(&next,&ns,other);memset(&owner,0,sizeof(owner));owner._surface=&fs;O2RasterizerSetViewport(&owner,0,0,16,16);owner._clipContext=&first;intersectClipContext(&owner,&next);double error=0;
 for(int y=0;y<16;y++){for(int x=0;x<16;x++)error=fmax(error,fabs(ns.pixels[y*16+x].a-area(x,y,other)));}printf("sample-intersection other=%d area_error=%.9f\n",other,error);assert(error<.02);if(!other)for(int i=0;i<256;i++)assert(ns.pixels[i].a==fs.pixels[i].a);
 normalizeClipToLayerDomain(&owner,&first);for(int y=0;y<16;y++)for(int x=0;x<16;x++){float base=fs.pixels[y*16+x].a;assert(fabs(ns.pixels[y*16+x].a*base-area(x,y,other))<.02);if(!other&&base>0)assert(ns.pixels[y*16+x].a==1);}
 O2Context_builtin group;O2Surface gs;init(&group,&gs,16,16);group._clipContext=&next;O2RasterizerSetShouldAntialias(&group,YES,256);rect(&group,0,0,16,16);O2DContextFillEdgesOnSurface(&group,&gs,&ns,NULL,-1);for(int y=0;y<16;y++)for(int x=0;x<16;x++)assert(fabs(gs.pixels[y*16+x].a*fs.pixels[y*16+x].a-area(x,y,other))<.02);dispose(&group);

 for(int which=0;which<3;which++){init(&draw,&ds,16,16);draw._clipContext=&first;O2RasterizerSetShouldAntialias(&draw,YES,256);if(which==0)triangle(&draw);else if(which==1)second(&draw);else opposite(&draw);O2DContextFillEdgesOnSurface(&draw,&ds,&fs,NULL,-1);for(int y=0;y<16;y++)for(int x=0;x<16;x++){double want=which==2?0:area(x,y,which==1);assert(fabs(ds.pixels[y*16+x].a-want)<.02);}dispose(&draw);}
 dispose(&first);dispose(&next);
 }
 // Scalar soft phases stay scalar after path bits are copied, and later repeated paths remain idempotent.
 O2Context_builtin path,soft,repeated,owner;O2Surface paths,softs,repeateds;pathMask(&path,&paths,NO);init(&soft,&softs,16,16);soft._clipIsSoftPhase=YES;for(int i=0;i<256;i++){float v=(float[]){0,.25,.5,1}[i%4];softs.pixels[i]=O2argb32fInit(v,v,v,v);}memset(&owner,0,sizeof(owner));owner._surface=&paths;O2RasterizerSetViewport(&owner,0,0,16,16);owner._clipContext=&path;intersectClipContext(&owner,&soft);assert(soft._clipSamples);for(int i=0;i<256;i++)assert(fabs(softs.pixels[i].a-paths.pixels[i].a*(float[]){0,.25,.5,1}[i%4])<1e-6);pathMask(&repeated,&repeateds,NO);intersectClipContext(&owner,&repeated);for(int i=0;i<256;i++)assert(repeateds.pixels[i].a==softs.pixels[i].a);dispose(&path);dispose(&soft);dispose(&repeated);
 // Actual normalization helper: padded rows, both image directions, decode and bit packing.
 uint8_t backing[3*304];for(int y=0;y<3;y++)for(int x=0;x<304;x++)backing[y*304+x]=(uint8_t)(x*29+y*67);O2Float decode[]={.2f,.8f};
 for(int bits=1;bits<=8;bits*=8)for(int inverted=0;inverted<2;inverted++)for(int decoded=0;decoded<2;decoded++){
  O2MaskInput in={300,3,bits,bits,bits==8?304:40,1,backing,sizeof(backing),decoded?decode:NULL,inverted};O2Surface *result=createClipMaskImage(&in);assert(result);for(int y=0;y<3;y++)for(int x=0;x<300;x++){float v=bits==8?backing[y*in.row+x]/255.f:((backing[y*in.row+x/8]>>(7-x%8))&1);if(decoded)v=.2f+.6f*v;if(inverted)v=1-v;O2argb32f p=result->pixels[y*300+x];assert(fabs(p.a-v)<1e-6&&p.r==p.a&&p.g==p.a&&p.b==p.a);}free(result->pixels);free(result);
 }
 // Finite extreme decode endpoints must retain endpoint coverage in both directions.
 O2Float extent=(O2Float)(sizeof(O2Float)==sizeof(double)?DBL_MAX:FLT_MAX),endpoints[]={extent,-extent};uint8_t ends[]={0,255};for(int inverse=0;inverse<2;inverse++){O2MaskInput input={2,1,8,8,2,1,ends,2,endpoints,inverse};O2Surface *out=createClipMaskImage(&input);assert(out);assert(out->pixels[0].a==(inverse?0:1)&&out->pixels[1].a==(inverse?1:0));free(out->pixels);free(out);}
 O2MaskInput in={300,3,8,8,304,1,backing,sizeof(backing),NULL,YES};in.length=911;assert(createClipMaskImage(&in)==NULL);in.length=sizeof(backing);in.row=299;assert(createClipMaskImage(&in)==NULL);in.row=304;in.bytes=NULL;assert(createClipMaskImage(&in)==NULL);in.bytes=backing;in.decode=decode;decode[0]=NAN;assert(createClipMaskImage(&in)==NULL);decode[0]=INFINITY;assert(createClipMaskImage(&in)==NULL);in.decode=NULL;in.bpp=32;assert(createClipMaskImage(&in)==NULL);in.bpp=8;in.components=3;assert(createClipMaskImage(&in)==NULL);in.components=1;in.model=1;assert(createClipMaskImage(&in)==NULL);in.model=0;in.alpha=1;assert(createClipMaskImage(&in)==NULL);in.alpha=0;in.named=YES;assert(createClipMaskImage(&in)==NULL);in.named=NO;in.mask=&in;assert(createClipMaskImage(&in)==NULL);in.mask=NULL;in.width=0;assert(createClipMaskImage(&in)==NULL);
 puts("EXACT_RASTERIZER_PATH_RULES_MASK_NORMALIZATION_AND_INTERSECTION_PASS_NOT_GUEST");return 0;
}
'''
out=Path(tempfile.mkdtemp(prefix='public-clip-source-'))
for scalar in ['float','double']:
 (out/('probe-'+scalar+'.c')).write_text(src.replace('typedef double O2Float;', 'typedef '+scalar+' O2Float;'))
 subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-Wno-sign-compare','-Wno-unused-function','-Wno-missing-field-initializers','-fsanitize=address,undefined,float-cast-overflow',str(out/('probe-'+scalar+'.c')),'-lm','-o',str(out/('probe-'+scalar))],check=True)
 subprocess.run([str(out/('probe-'+scalar))],check=True,env={**os.environ,'ASAN_OPTIONS':'detect_leaks=0','UBSAN_OPTIONS':'halt_on_error=1'})
print('source evidence:',out)
