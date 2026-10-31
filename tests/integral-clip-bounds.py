#!/usr/bin/env python3
"""Exercise the production helper's numeric bounds with native C++ API doubles.
Only Objective-C fast enumeration is mechanically changed to range-for. Path
recognition is stubbed: these cases test bounds after the existing shape check.
"""
import pathlib,subprocess,sys,tempfile
source=pathlib.Path(sys.argv[1]) if len(sys.argv)>1 else pathlib.Path(__file__).resolve().parents[1]/'Onyx2D/O2Context_builtin.m'
text=source.read_text();helper=text.split('static BOOL clipToIntegralRects(',1)[1].split('\n- (void) clipToState:',1)[0]
helper='static BOOL clipToIntegralRects('+helper.split('\nstatic BOOL hasViewportClip',1)[0]
helper=helper.replace('for (O2ClipPhase *phase in phases)', 'for (O2ClipPhase *phase : *phases)')
prelude=r'''
#include <algorithm>
#include <vector>
#include <climits>
#include <cmath>
#include <cstdio>
#include <limits>
#define MIN(a,b) ((a)<(b)?(a):(b))
#define MAX(a,b) ((a)>(b)?(a):(b))
using BOOL=bool;using std::isfinite;using std::floor;
#define YES true
#define NO false
#ifdef MODEL_FLOAT
using O2Float=float;
#else
using O2Float=double;
#endif
struct O2Point{O2Float x,y;};struct O2Rect{O2Point origin;struct{O2Float width,height;}size;};
struct O2Path{O2Point points[4];bool rect=true;};
enum O2ClipPhaseType{O2ClipPhaseNonZeroPath,O2ClipPhaseEOPath,O2ClipPhaseMask};
struct O2ClipPhase{O2ClipPhaseType type;O2Path*path;};using NSArray=std::vector<O2ClipPhase*>;
struct Surface{size_t width,height;};struct O2Context_builtin{Surface*_surface;int viewport[4];};
size_t O2ImageGetWidth(Surface*s){return s->width;}size_t O2ImageGetHeight(Surface*s){return s->height;}
O2ClipPhaseType O2ClipPhasePhaseType(O2ClipPhase*p){return p->type;}O2Path*O2ClipPhaseObject(O2ClipPhase*p){return p->path;}
BOOL O2PathIsRect(O2Path*p,O2Rect*r){r->origin=p->points[0];r->size.width=p->points[2].x-p->points[0].x;r->size.height=p->points[2].y-p->points[0].y;return p->rect;}
const O2Point*O2PathPoints(O2Path*p){return p->points;}
void O2RasterizerSetViewport(O2Context_builtin*c,int x,int y,int w,int h){c->viewport[0]=x;c->viewport[1]=y;c->viewport[2]=w;c->viewport[3]=h;}
'''
controls=r'''
static unsigned failures;
static void test(const char*name,double a,double b,double c,double d,size_t width,size_t height,bool accepted,int x,int y,int w,int h,O2ClipPhaseType type=O2ClipPhaseNonZeroPath,bool rect=true){
 O2Path p={{{(O2Float)a,(O2Float)b},{(O2Float)c,(O2Float)b},{(O2Float)c,(O2Float)d},{(O2Float)a,(O2Float)d}},rect};
 O2ClipPhase phase={type,&p};NSArray phases={&phase};Surface surface={width,height};O2Context_builtin context={&surface,{-1,-1,-1,-1}};
 bool got=clipToIntegralRects(&context,&phases);bool ok=got==accepted;
 if(got)ok&=context.viewport[0]==x&&context.viewport[1]==y&&context.viewport[2]==w&&context.viewport[3]==h;
 else for(int v:context.viewport)ok&=v==-1;
 printf("%s %s accepted=%d viewport=%d,%d,%d,%d\n",ok?"PASS":"FAIL",name,got,context.viewport[0],context.viewport[1],context.viewport[2],context.viewport[3]);failures+=!ok;
}
int main(){
 test("ordinary",2,3,28,21,32,24,true,2,3,26,18);
 test("signed",28,21,2,3,32,24,true,2,3,26,18);
 test("empty",2,3,2,21,32,24,true,2,3,0,18);
 test("outside",100,100,200,200,32,24,true,32,24,0,0);
 test("huge-left",-std::ldexp(1.,54),0,1,24,32,24,true,0,0,1,24);
 test("huge-left-float-model",-std::ldexp(1.,24),0,1,24,32,24,true,0,0,1,24);
 test("huge-right",31,0,std::ldexp(1.,54),24,32,24,true,31,0,1,24);
 test("int-max-surface",0,0,std::ldexp(1.,31),1,INT_MAX,1,true,0,0,INT_MAX,1);
 test("unsupported-surface",0,0,1,1,(size_t)INT_MAX+1,1,false,0,0,0,0);
 test("fractional",.5,0,3,3,32,24,false,0,0,0,0);
 test("nonfinite",0,0,std::numeric_limits<double>::infinity(),3,32,24,false,0,0,0,0);
 test("mask",0,0,3,3,32,24,false,0,0,0,0,O2ClipPhaseMask);
 test("nonrect",0,0,3,3,32,24,false,0,0,0,0,O2ClipPhaseNonZeroPath,false);
 return failures?1:0;
}
'''
with tempfile.TemporaryDirectory(prefix='qv-clip-bounds-') as folder:
    path=pathlib.Path(folder);cpp=path/'bounds.cpp';cpp.write_text(prelude+helper+controls)
    failures=0
    for model in ['double','float']:
        binary=path/model
        subprocess.run(['c++','-std=c++17','-fsanitize=undefined,float-cast-overflow','-fno-sanitize-recover=all',*(['-DMODEL_FLOAT'] if model=='float' else []),str(cpp),'-o',str(binary)],check=True)
        result=subprocess.run([str(binary)],capture_output=True,text=True)
        print('MODEL',model);print(result.stdout,end='');print(result.stderr,end='')
        failures+=result.returncode!=0
    raise SystemExit(bool(failures))
