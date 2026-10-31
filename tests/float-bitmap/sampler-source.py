"""Actual production samplers, masks, alpha extraction and pattern paint.
Memory/image adapters only; does not establish Objective-C or guest dispatch.
"""
from pathlib import Path
import subprocess, tempfile, shutil
root=Path(__file__).resolve().parents[2]
def fn(path,name):
 s=(root/'Onyx2D'/path).read_text();a=s.index(name);a=s.rfind('\n',0,a)+1;b=s.index('{',a)+1;depth=1
 while depth:depth+=(s[b]=='{')-(s[b]=='}');b+=1
 return s[a:b]
h=(root/'Onyx2D/include/Onyx2D/O2argb32f.h').read_text();arithmetic=h[h.index('typedef float O2Float32;'):h.index('static inline O2argb32f O2argb32fSubtract')]
src=r'''
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <assert.h>
#include <float.h>
typedef float O2Float;
#define MIN(a,b) ((a)<(b)?(a):(b))
#define MAX(a,b) ((a)>(b)?(a):(b))
#define ONYX2D_STATIC static
#define ONYX2D_STATIC_INLINE static inline
#define RI_FLOOR_TO_INT(x) ((int)floorf(x))
#define RI_INT_MIN(a,b) MIN(a,b)
#define RI_INT_MAX(a,b) MAX(a,b)
#define RI_INT_CLAMP(v,a,b) MIN(MAX(v,a),b)
#define RI_INT_MOD(v,n) ((((v)%(int)(n))+(int)(n))%(int)(n))
typedef struct {uint8_t a,r,g,b;} O2argb8u;
typedef struct {double a,b,c,d,tx,ty;} O2AffineTransform;
typedef struct {float x,y;} O2Point;
static O2Point O2PointMake(double x,double y){return (O2Point){x,y};}
typedef int O2PatternTiling;
enum {kO2PatternTilingNoDistortion,kO2PatternTilingConstantSpacingMinimalDistortion,kO2PatternTilingConstantSpacing};
'''+arithmetic+r'''
typedef struct {size_t _width,_height;O2argb32f *pixels;} O2Image;
typedef struct {O2Image *_image,*_mask;O2AffineTransform m_surfaceToPaintMatrix,_surfaceToMask;float _alpha;} O2Paint;
typedef O2Paint O2Paint_image;
typedef O2Paint O2Paint_pattern;
static O2argb32f *O2Image_read_argb32f(O2Image *s,int x,int y,O2argb32f *out,int n){assert(x>=0&&y>=0&&n>=0&&(size_t)(x+n)<=s->_width&&(size_t)y<s->_height);memcpy(out,s->pixels+y*s->_width+x,n*sizeof(*out));return NULL;}
'''
for file,name in [
 ('O2Image.m','static O2Float *O2ImageRead_argb32f_to_Af('),
 ('O2Image.m','void O2ImageReadTileSpanExtendEdge__largb32f_PRE('),
 ('O2Image.m','void O2ImageBilinear_largb32f_PRE('),
 ('O2Image.m','void O2ImagePointSampling_largb32f_PRE('),
 ('O2Paint_image.m','static inline void O2PaintApplyGlobalAlpha32f('),
 ('O2Paint_image.m','static void O2PaintApplyMaskSpan32f('),
 ('O2Paint_image.m','ONYX2D_STATIC int O2PaintReadResampledLowSpan_largb32f_PRE('),
 ('O2Paint_image.m','ONYX2D_STATIC int O2PaintReadResampledNoneSpan_largb32f_PRE('),
 ('O2Image.m','void O2ImageReadTexelTileRepeat_largb32f_PRE('),
 ('O2Image.m','void O2ImagePattern_Bilinear('),
 ('O2Image.m','void O2ImagePattern_PointSampling_largb32f_PRE('),
 ('O2Image.m','void O2ImageReadPatternSpan_largb32f_PRE('),
 ('O2Paint_pattern.m','ONYX2D_STATIC int o2pattern_largb32f_PRE('),
 ('include/Onyx2D/O2argb32f.h','static inline uint8_t O2ByteFromFloat('),
 ]:src+=fn(file,name)+'\n'
src+=r'''
static float channel(O2argb32f p,int c){return c==0?p.r:c==1?p.g:c==2?p.b:p.a;}
static float texel(O2Image *s,int x,int y,int c){x=MAX(0,MIN(x,(int)s->_width-1));y=MAX(0,MIN(y,(int)s->_height-1));return channel(s->pixels[y*s->_width+x],c);}
static float oracle(O2Image *s,int x,int y,O2AffineTransform t,int c,int bilinear){
 double u=(x+.5)*t.a+(y+.5)*t.c+t.tx, v=(x+.5)*t.b+(y+.5)*t.d+t.ty;
 if(!bilinear)return texel(s,floor(u),floor(v),c);
 u-=.5;v-=.5;int ix=floor(u),iy=floor(v);double fx=u-ix,fy=v-iy;
 return texel(s,ix,iy,c)*(1-fx)*(1-fy)+texel(s,ix+1,iy,c)*fx*(1-fy)+texel(s,ix,iy+1,c)*(1-fx)*fy+texel(s,ix+1,iy+1,c)*fx*fy;
}
int main(void){
 O2argb32f sp[6],mp[6];for(int i=0;i<6;i++){sp[i]=O2argb32fInit(i*.125f-.25f,.12345f+i*.015625f,1.25f-i*.25f,.25f+i*.125f);mp[i]=O2argb32fInit(.0625f+i*.125f,.1f,.2f,.9f-i*.0625f);}
 O2Image image={3,2,sp},mask={3,2,mp};O2Paint p={&image,&mask,{.375,.125,-.125,.75,-2,1.25},{-.25,.0625,.125,.5,5,-1.5},.375f};O2argb32f got[320];
 for(int bilinear=0;bilinear<2;bilinear++){
  int count=bilinear?O2PaintReadResampledLowSpan_largb32f_PRE(&p,-3,1,got,320):O2PaintReadResampledNoneSpan_largb32f_PRE(&p,-3,1,got,320);assert(count==320);
  for(int i=0;i<320;i++)for(int c=0;c<4;c++){float want=oracle(&image,i-3,1,p.m_surfaceToPaintMatrix,c,bilinear)*oracle(&mask,i-3,1,p._surfaceToMask,0,bilinear)*p._alpha;assert(fabsf(channel(got[i],c)-want)<2e-6f);}
 }
 // Direct alpha extraction crosses its256 boundary and retains sub-byte precision.
 O2argb32f pixels[300];for(int i=0;i<300;i++)pixels[i]=O2argb32fInit(.3,.2,.1,.000125f*i);O2Image wide={300,1,pixels};float alpha[300];O2ImageRead_argb32f_to_Af(&wide,0,0,alpha,300);for(int i=0;i<300;i++)assert(alpha[i]==pixels[i].a);
 // Real pattern paint uses nonuniform image texels, including negative repeats.
 p._image=&image;p.m_surfaceToPaintMatrix=(O2AffineTransform){1,0,0,1,0,0};o2pattern_largb32f_PRE(&p,-5,-1,got,320);
 for(int i=0;i<320;i++)for(int c=0;c<4;c++)assert(channel(got[i],c)==channel(sp[3+RI_INT_MOD(i-5,3)],c));
 float values[]={NAN,INFINITY,-INFINITY,FLT_MAX,-FLT_MAX,-.1f,0,.5f,1,1.1f};unsigned expected[]={0,255,0,255,0,0,0,128,255,255};for(unsigned i=0;i<sizeof(values)/sizeof(*values);i++)assert(O2ByteFromFloat(values[i])==expected[i]);
 puts("ACTUAL_FLOAT_SAMPLER_MASK_ALPHA_PATTERN_AND_BYTE_MAP_PASS_NOT_GUEST");return 0;
}
'''
out=Path(tempfile.mkdtemp(prefix='onyx-float-sampler-'));(out/'sampler.c').write_text(src)
subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-fsanitize=address,undefined,float-cast-overflow',str(out/'sampler.c'),'-lm','-o',str(out/'sampler')],check=True)
subprocess.run([str(out/'sampler')],check=True)

shutil.rmtree(out)
