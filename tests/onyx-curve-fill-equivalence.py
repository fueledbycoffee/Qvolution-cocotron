#!/usr/bin/env python3
"""Compare production fills of flattened curves to the supplied old source with native adapters.
Rounded rects, rings and circles are flattened as VGPathAddCubicTo does (256
segments per curve), so most edges are a few hundredths of a pixel tall. At
every sample count, with and without viewport and sample-mask clips, the
pixels, clip samples, span sequence and leftover sweep state must match the
reference exactly. Unclosed edge sets and huge coordinates are compared
too. Not NaN, infinite or |x| > INT_MAX ends: both sweeps convert an edge's
x to int in initEdgeForAET, which is undefined for those (UBSan
float-cast-overflow on the old sweep), so there is nothing to compare. Also counts and times the theme's
control faces (two rings and a face per button) at 256 samples per pixel.
Reuses raster-painted-bounds.py's extraction; no guest or Objective-C claim.
  onyx-curve-fill-equivalence.py --reference <old O2Context_builtin.m> [--source <new>]
"""
from pathlib import Path
import os
import subprocess
import tempfile

here = Path(__file__).resolve().parent
painted = here / 'raster-painted-bounds.py'
prepare = painted.read_text().split("source += r'''\n#include <time.h>", 1)[0]
namespace = {'__file__': str(painted), '__name__': 'prepare'}
exec(compile(prepare, str(painted), 'exec'), namespace)
source = namespace['source'] + r'''
#include <time.h>
static unsigned rng=12345;
static double randomCoord(void){rng=rng*1664525u+1013904223u;return (rng%9600)/100.-16;}
static unsigned randomBelow(unsigned n){rng=rng*1664525u+1013904223u;return rng%n;}
static void render(O2Context_builtin *c,O2Surface *s,int reference,int rule){if(reference)referenceFillEdgesOnSurface(c,s,c->_clipContext?c->_clipContext->_surface:NULL,NULL,rule);else O2DContextFillEdgesOnSurface(c,s,c->_clipContext?c->_clipContext->_surface:NULL,NULL,rule);O2RasterizerClear(c);}
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
static int allocateClipSamplesForTest(O2Context_builtin *c){c->_clipSamples=calloc(c->_surface->width*c->_surface->height,8*sizeof(uint32_t));return c->_clipSamples!=NULL;}
static double rotCos=1,rotSin=0,offX=0,offY=0;
static O2Point place(double x,double y){return (O2Point){offX+rotCos*x-rotSin*y,offY+rotSin*x+rotCos*y};}
static O2Point pen;
static int edgeBudget=-1; // edges still to add; -1 unlimited, so a shape can be left open
static void addEdge(O2Context_builtin *c,O2Point a,O2Point b){if(edgeBudget==0)return;if(edgeBudget>0)edgeBudget--;O2DContextAddEdge(c,a,b);}
static void lineTo(O2Context_builtin *c,double x,double y){O2Point q=place(x,y);addEdge(c,pen,q);pen=q;}
static void cubicTo(O2Context_builtin *c,double x0,double y0,double x1,double y1,double x2,double y2,double x3,double y3){
 for(int i=1;i<256;i++){double t=i/256.,u=1-t;lineTo(c,x0*u*u*u+3*x1*t*u*u+3*x2*t*t*u+x3*t*t*t,y0*u*u*u+3*y1*t*u*u+3*y2*t*t*u+y3*t*t*t);}
 lineTo(c,x3,y3);}
// A closed rounded rect (quarter circles as cubics), clockwise or reversed.
static void roundedRect(O2Context_builtin *c,double x,double y,double w,double h,double r,int reverse){
 r=fmax(0,fmin(r,fmin(w,h)/2));const double k=0.5522847498*r;O2Point start=place(x+r,y);pen=start;
 if(!reverse){lineTo(c,x+w-r,y);cubicTo(c,x+w-r,y,x+w-r+k,y,x+w,y+r-k,x+w,y+r);lineTo(c,x+w,y+h-r);cubicTo(c,x+w,y+h-r,x+w,y+h-r+k,x+w-r+k,y+h,x+w-r,y+h);lineTo(c,x+r,y+h);cubicTo(c,x+r,y+h,x+r-k,y+h,x,y+h-r+k,x,y+h-r);lineTo(c,x,y+r);cubicTo(c,x,y+r,x,y+r-k,x+r-k,y,x+r,y);}
 else{cubicTo(c,x+r,y,x+r-k,y,x,y+r-k,x,y+r);lineTo(c,x,y+h-r);cubicTo(c,x,y+h-r,x,y+h-r+k,x+r-k,y+h,x+r,y+h);lineTo(c,x+w-r,y+h);cubicTo(c,x+w-r,y+h,x+w-r+k,y+h,x+w,y+h-r+k,x+w,y+h-r);lineTo(c,x+w,y+r);cubicTo(c,x+w,y+r,x+w,y+r-k,x+w-r+k,y,x+w-r,y);}
 addEdge(c,pen,start);}
// The theme's bordered face: bottom-shadow ring, border ring (even-odd) and face.
static void themeFace(O2Context_builtin *c,double x,double y,double w,double h,double r,int part){
 if(part==0){roundedRect(c,x,y,w,h,r,0);roundedRect(c,x,y+1,w,h-1,r,0);}
 else if(part==1){roundedRect(c,x,y+1,w,h-1,r,0);roundedRect(c,x+1,y+2,w-2,h-3,r-1,0);}
 else roundedRect(c,x+1,y+2,w-2,h-3,r-1,0);}
int main(void){setbuf(stdout,NULL);
 unsigned cases=0;
 const int qualities[]={1,2,3,4,8,16,32,64,100,128,256};
 for(int qi=0;qi<11;qi++)for(int mode=0;mode<4;mode++){int quality=qualities[qi];
  O2Context_builtin a,b,clip;O2Surface sa,sb,sc;init(&a,&sa,64,48);init(&b,&sb,64,48);init(&clip,&sc,64,48);
  O2RasterizerSetShouldAntialias(&a,YES,quality);O2RasterizerSetShouldAntialias(&b,YES,quality);
  if(mode&1){O2RasterizerSetViewport(&a,7,9,41,31);O2RasterizerSetViewport(&b,7,9,41,31);}
  if(mode&2){assert(allocateClipSamplesForTest(&a));assert(allocateClipSamplesForTest(&b));assert(allocateClipSamplesForTest(&clip));for(int i=0;i<64*48;i++){sc.pixels[i]=O2argb32fInit(.5,.5,.5,.5);for(int w=0;w<8;w++)clip._clipSamples[i*8+w]=0xaaaaaaaa;}a._clipContext=b._clipContext=&clip;}
  for(int trial=0;trial<60;trial++){
   double r=randomBelow(1400)/100.,x=randomCoord()/2,y=randomCoord()/2,w=2+randomBelow(4000)/100.,h=2+randomBelow(3700)/100.;
   double angle=trial%4==3?randomBelow(628)/100.:0;rotCos=cos(angle);rotSin=sin(angle);offX=randomBelow(100)/100.;offY=randomBelow(77)/77.;
   int rule=trial&1?1:-1,shape=trial%10;
   double open[8];for(int j=0;j<8;j++)open[j]=randomCoord();
   O2Context_builtin *both[2]={&a,&b};
   for(int k=0;k<2;k++){O2Context_builtin *c=both[k];
    if(shape==0)roundedRect(c,x,y,w,h,r,0);
    else if(shape==1){roundedRect(c,x,y,w,h,r,0);roundedRect(c,x+1,y+1,w-2,h-2,r-1,rule==-1);}
    else if(shape==2)roundedRect(c,x,y,r*2+.01,r*2+.01,r+.005,0);
    else if(shape==3)for(int part=0;part<3;part++)themeFace(c,x,y,w+3,h+3,5,part);
    else if(shape==4){roundedRect(c,x,y,w,h,r,0);roundedRect(c,x+w/3,y+h/3,w/3,h/3,r/3,0);}
    // Unclosed: a rounded rect missing its last corner and closing edge, and an open polyline.
    else if(shape==5){edgeBudget=600+trial;roundedRect(c,x,y,w,h,r,0);edgeBudget=-1;}
    else if(shape==6){pen=place(x,y);for(int j=0;j<4;j++)lineTo(c,open[2*j],open[2*j+1]);}
    // Huge coordinates crossing the surface: x within int range (see below), y up to 1e30.
    else{double bigX=shape==7?1e9:shape==8?3e5:1e6,bigY=shape==7?1e30:shape==8?1e9:-1e12;
     O2DContextAddEdge(c,(O2Point){-bigX,y},(O2Point){bigX,y+h});O2DContextAddEdge(c,(O2Point){bigX,y+h},(O2Point){x,bigY});O2DContextAddEdge(c,(O2Point){x,bigY},(O2Point){-bigX,y});roundedRect(c,x,y,w,h,r,1);}}
   spanHash=0;render(&a,&sa,0,rule);unsigned long long spans=spanHash;
   spanHash=0;render(&b,&sb,1,rule);
   assert(spans==spanHash);
   assert(!memcmp(sa.pixels,sb.pixels,64*48*sizeof(O2argb32f)));
   if(a._clipSamples)assert(!memcmp(a._clipSamples,b._clipSamples,64*48*8*sizeof(uint32_t)));
   for(int i=0;i<64*256+1;i++)assert(a._winding[i]==0&&b._winding[i]==0&&a._rowIncrease[i]==0);
   for(int i=0;i<64;i++)assert(a._increase[i]==INT_MAX&&b._increase[i]==INT_MAX);
   cases++;
  }
  rotCos=1;rotSin=0;offX=offY=0;
  dispose(&a);dispose(&b);dispose(&clip);
 }
 printf("PASS %u exact curve pixel/sample/span/state comparisons\n",cases);
 double seconds[2];unsigned long long visits[2];
 for(int old=0;old<2;old++){
  O2Context_builtin c;O2Surface s;init(&c,&s,640,48);O2RasterizerSetShouldAntialias(&c,YES,256);sampleVisits=0;double started=now();
  for(int repeat=0;repeat<5;repeat++)for(int button=0;button<8;button++)for(int part=0;part<3;part++){
   themeFace(&c,10+button*30.,12,26,22,5,part);render(&c,&s,old,part<2?1:-1);}
  seconds[old]=now()-started;visits[old]=sampleVisits;dispose(&c);
 }
 printf("theme faces (8 buttons x 3 rounded fills, 256 samples, x5): candidate %.3f ms %llu samples; reference %.3f ms %llu samples\n",seconds[0]*1000,visits[0],seconds[1]*1000,visits[1]);
 puts("PASS flattened curves fill identically");return 0;
}
'''
with tempfile.TemporaryDirectory(prefix='curve-fill-') as folder:
    folder = Path(folder)
    for scalar in ['float', 'double']:
        path = folder / (scalar + '.c')
        path.write_text(source.replace('typedef double O2Float;', 'typedef '+scalar+' O2Float;'))
        binary = folder / scalar
        subprocess.run(['cc', '-std=c11', '-D_POSIX_C_SOURCE=200809L', '-O2',
                        '-Wall', '-Wextra', '-Werror', '-Wno-sign-compare', '-Wno-unused-function',
                        '-fsanitize=address,undefined,float-cast-overflow', str(path), '-lm', '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True, env={**os.environ, 'ASAN_OPTIONS':'detect_leaks=0', 'UBSAN_OPTIONS':'halt_on_error=1'})
