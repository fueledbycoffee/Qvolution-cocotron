#!/usr/bin/env python3
"""Run production integral clip bounds and the reuse/reset branch with C++ API doubles.
The existing public-clip controls cover the unchanged nonintegral fallback.
"""
from pathlib import Path
import re, subprocess, tempfile, sys
root=Path(__file__).resolve().parents[1]
s=(Path(sys.argv[1]) if len(sys.argv)>1 else root/'Onyx2D/O2Context_builtin.m').read_text()
a=s.index('static BOOL clipToIntegralRects(');b=s.index('\nstatic BOOL hasViewportClip',a);helper=s[a:b].replace('for (O2ClipPhase *phase in phases)','for (O2ClipPhase *phase : phases->items)')
helper=s[s.index('static BOOL integralRectBounds('):s.index('static BOOL clipToIntegralRect(')]+helper
a=s.index('- (void) clipToState:');b=s.index('    // Layer drawing uses conditional coverage',a);branch=s[a:b]
branch=branch.replace('- (void) clipToState: (O2ClipState *) clipState {','void clipToState(O2Context_builtin *self, O2ClipState *clipState) {')
for var in ['_surface','_viewportClipPhases','_viewportClipWidth','_viewportClipHeight','_layerClipPhases','_clipContext','_vpx','_vpy','_vpwidth','_vpheight','_viewportClipX','_viewportClipY','_viewportClipW','_viewportClipH']:
 branch=re.sub(r'(?<![\w>])'+var+r'\b','self->'+var,branch)
replacements={
 '[clipState clipPhases]':'clipState->phases',
 '[self->_layerClipPhases count]':'self->_layerClipPhases->items.size()',
 '[self->_layerClipPhases lastObject]':'nullptr',
 '[self->_viewportClipPhases count]':'self->_viewportClipPhases->items.size()',
 '[phases isEqualToArray: self->_viewportClipPhases]':'phases->isEqual(self->_viewportClipPhases)',
 '[phases copy]':'new NSArray(*phases)',
 '[[NSArray alloc] init]':'new NSArray',
}
for a,b in replacements.items():branch=branch.replace(a,b)
branch+='self->fallbacks++;\n}\n'
preamble=r'''
#include <vector>
#include <cmath>
#include <climits>
#include <cassert>
#include <cstdio>
#include <cstdint>
using BOOL=bool;using std::isfinite;using std::floor;
#define YES true
#define NO false
#define nil nullptr
#define MIN(a,b) ((a)<(b)?(a):(b))
#define MAX(a,b) ((a)>(b)?(a):(b))
struct O2Point{double x,y;};struct O2Rect{O2Point origin;struct{double width,height;}size;};
struct O2Path{O2Point points[4];bool rect=true;};
enum O2ClipPhaseType{O2ClipPhaseNonZeroPath,O2ClipPhaseEOPath,O2ClipPhaseMask};
struct O2ClipPhase{O2ClipPhaseType type;O2Path*path;};
struct NSArray{std::vector<O2ClipPhase*>items;bool isEqual(NSArray*p){return p&&items==p->items;}};
struct O2ClipState{NSArray*phases;};struct Surface{size_t width,height;};
struct O2Context_builtin{Surface*_surface;NSArray*_layerClipPhases,*_viewportClipPhases=nullptr;size_t _viewportClipWidth=0,_viewportClipHeight=0;void*_clipContext=nullptr;int viewport[4],_vpx=0,_vpy=0,_vpwidth=0,_vpheight=0,_viewportClipX=0,_viewportClipY=0,_viewportClipW=0,_viewportClipH=0;unsigned resets=0,fallbacks=0;};
size_t O2ImageGetWidth(Surface*s){return s->width;}size_t O2ImageGetHeight(Surface*s){return s->height;}
O2ClipPhaseType O2ClipPhasePhaseType(O2ClipPhase*p){return p->type;}O2Path*O2ClipPhaseObject(O2ClipPhase*p){return p->path;}
BOOL O2PathIsRect(O2Path*p,O2Rect*r){return p->rect;}
const O2Point*O2PathPoints(O2Path*p){return p->points;}
enum {kO2PathElementMoveToPoint,kO2PathElementAddLineToPoint,kO2PathElementCloseSubpath};
size_t O2PathNumberOfElements(O2Path*p){return p->rect?5:0;}
size_t O2PathNumberOfPoints(O2Path*p){return 4;}
const unsigned char*O2PathElements(O2Path*){static const unsigned char t[]={0,1,1,1,2};return t;}

void O2RasterizerSetViewport(O2Context_builtin*c,int x,int y,int w,int h){c->viewport[0]=x;c->viewport[1]=y;c->viewport[2]=w;c->viewport[3]=h;c->_vpx=x;c->_vpy=y;c->_vpwidth=w;c->_vpheight=h;}
void O2ContextDeviceClipReset_builtin(O2Context_builtin*c){c->resets++;delete c->_viewportClipPhases;c->_viewportClipPhases=nullptr;c->_clipContext=nullptr;O2RasterizerSetViewport(c,0,0,c->_surface->width,c->_surface->height);}
'''
a=s.index('void O2ContextDeviceClipReset_builtin(');b=s.index('\nstatic O2Context_builtin *createClipContext',a)
reset=s[a:b].replace('[self->_viewportClipPhases release];','delete self->_viewportClipPhases;').replace('[self->_clipContext release];','').replace('{\n','{\n    self->resets++;\n',1)
a=preamble.index('void O2ContextDeviceClipReset_builtin(');b=len(preamble)
preamble=preamble[:a]+reset+preamble[b:]
control=r'''
int main(){Surface surface{32,24};NSArray layer,phases;O2Context_builtin c{&surface,&layer};
 O2Path p{{{2,3},{28,3},{28,21},{2,21}}};O2ClipPhase phase{O2ClipPhaseNonZeroPath,&p};phases.items={&phase};O2ClipState state{&phases};
 clipToState(&c,&state);assert(c.resets==1&&c.viewport[0]==2&&c.viewport[2]==26);
 NSArray copy=phases;O2ClipState saved{&copy};for(int i=0;i<1000;i++)clipToState(&c,&saved);assert(c.resets==1);
 O2Path p2{{{5,6},{8,6},{8,10},{5,10}}};O2ClipPhase phase2{O2ClipPhaseEOPath,&p2};phases.items.push_back(&phase2);
 clipToState(&c,&state);assert(c.resets==2&&c.viewport[0]==5&&c.viewport[2]==3);
 clipToState(&c,&saved);assert(c.resets==3&&c.viewport[0]==2&&c.viewport[2]==26);
 surface.width=12;clipToState(&c,&saved);assert(c.resets==4&&c.viewport[2]==10);
 layer.items={&phase};clipToState(&c,&saved);assert(c.resets==5&&c.fallbacks==1&&!c._viewportClipPhases);
 layer.items.clear();clipToState(&c,&saved);assert(c.resets==6);clipToState(&c,&saved);assert(c.resets==6);
 O2ContextDeviceClipReset_builtin(&c);clipToState(&c,&saved);assert(c.resets==8);
 c._clipContext=&c;clipToState(&c,&saved);assert(c.resets==9);
 O2ClipState empty{nullptr};clipToState(&c,&empty);assert(c.resets==10&&c.viewport[2]==12);clipToState(&c,&empty);assert(c.resets==10);
 delete c._viewportClipPhases;puts("PASS 1000 unchanged restores: 1 setup; changed clip, restore, resize, layer, device reset, mask and empty clip invalidate correctly");}
'''
# nil phase enumeration has Objective-C empty-array semantics.
helper=helper.replace('for (O2ClipPhase *phase : phases->items)', 'for (O2ClipPhase *phase : phases ? phases->items : std::vector<O2ClipPhase*>{})')
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp);(p/'control.cpp').write_text(preamble+helper+branch+control)
 subprocess.run(['c++','-std=c++17','-fsanitize=address,undefined',str(p/'control.cpp'),'-o',str(p/'control')],check=True)
 subprocess.run([str(p/'control')],check=True)
