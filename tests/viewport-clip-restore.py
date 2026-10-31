#!/usr/bin/env python3
"""Run production integral clip bounds and the reuse/reset branch with C++ API doubles.
The existing public-clip controls cover the unchanged nonintegral fallback.
"""
from pathlib import Path
import re, subprocess, tempfile, sys
root=Path(__file__).resolve().parents[1]
s=(Path(sys.argv[1]) if len(sys.argv)>1 else root/'Onyx2D/O2Context_builtin.m').read_text()
a=s.index('static BOOL clipToIntegralRects(');b=s.index('\nstatic BOOL hasViewportClip',a);helper=s[a:b].replace('for (O2ClipPhase *phase in phases)','for (O2ClipPhase *phase : phases->items)')
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
void O2RasterizerSetViewport(O2Context_builtin*c,int x,int y,int w,int h){c->viewport[0]=x;c->viewport[1]=y;c->viewport[2]=w;c->viewport[3]=h;c->_vpx=x;c->_vpy=y;c->_vpwidth=w;c->_vpheight=h;}
void O2ContextDeviceClipReset_builtin(O2Context_builtin*c){c->resets++;delete c->_viewportClipPhases;c->_viewportClipPhases=nullptr;c->_clipContext=nullptr;O2RasterizerSetViewport(c,0,0,c->_surface->width,c->_surface->height);}
'''
a=s.index('void O2ContextDeviceClipReset_builtin(');b=s.index('\nstatic O2Context_builtin *createClipContext',a)
reset=s[a:b].replace('[self->_viewportClipPhases release];','delete self->_viewportClipPhases;').replace('[self->_clipContext release];','').replace('{\n','{\n    self->resets++;\n',1)
a=preamble.index('void O2ContextDeviceClipReset_builtin(');b=len(preamble)
preamble=preamble[:a]+reset+preamble[b:]
control=r'''
int main(){Surface surface{204,160};NSArray layer,phases;O2Context_builtin c{&surface,&layer};O2ClipState empty{nullptr};
 clipToState(&c,&empty);
 // drawDecorations uses ResetClip, paints all four frame strips, then narrows
 // the viewport for title ink. A saved empty clip must restore the whole frame.
 O2RasterizerSetViewport(&c,0,0,204,34);clipToState(&c,&empty);
 if(c._vpwidth!=204||c._vpheight!=160){fprintf(stderr,"FAIL restored empty clip retained title viewport: %d,%d,%d,%d\n",c._vpx,c._vpy,c._vpwidth,c._vpheight);delete c._viewportClipPhases;return 1;}
 O2Path p{{{6,34},{198,34},{198,130},{6,130}}};O2ClipPhase phase{O2ClipPhaseNonZeroPath,&p};phases.items={&phase};O2ClipState state{&phases};
 clipToState(&c,&state);O2RasterizerSetViewport(&c,0,0,204,34);clipToState(&c,&state);
 assert(c._vpx==6&&c._vpy==34&&c._vpwidth==192&&c._vpheight==96);
 delete c._viewportClipPhases;puts("PASS direct title viewport overwritten by saved empty/content clip restoration");}
'''
# nil phase enumeration has Objective-C empty-array semantics.
helper=helper.replace('for (O2ClipPhase *phase : phases->items)', 'for (O2ClipPhase *phase : phases ? phases->items : std::vector<O2ClipPhase*>{})')
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp);(p/'control.cpp').write_text(preamble+helper+branch+control)
 subprocess.run(['c++','-std=c++17','-fsanitize=address,undefined',str(p/'control.cpp'),'-o',str(p/'control')],check=True)
 subprocess.run([str(p/'control')],check=True)
