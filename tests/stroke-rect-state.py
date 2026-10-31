#!/usr/bin/env python3
"""Execute the exact width-only production control flow with native C++ doubles."""
from pathlib import Path
import subprocess, tempfile, sys
root=Path(__file__).resolve().parents[1]
source=Path(sys.argv[1]) if len(sys.argv)>1 else root/'Onyx2D/O2Context.m'
s=source.read_text();a=s.index('void O2ContextStrokeRectWithWidth(');b=s.index('\nvoid O2ContextStrokeEllipseInRect',a);f=s[a:b]
# C++ RAII implements Objective-C @finally on both normal and exceptional exits.
f=f.replace('@try {','{ struct Finally { O2GState *state; double width; ~Finally(){O2GStateSetLineWidth(state,width);} } finally{gState,savedWidth};').replace('} @finally {\n        O2GStateSetLineWidth(gState, savedWidth);\n    }','}')
preamble=r'''
#include <cassert>
#include <cstdio>
#include <stdexcept>
using O2Float=double;struct O2Rect{double x,y,w,h;};
struct O2GState{double _lineWidth=7;unsigned color=0x12345678;};
struct Context{O2GState state;int saves=0,restores=0,clips=0,begins=0,adds=0,strokes=0;bool fail=false;double seenWidth;O2Rect rect;};
using O2ContextRef=Context*;
#define nil nullptr
O2GState*O2ContextCurrentGState(Context*c){return &c->state;}
void O2GStateSetLineWidth(O2GState*s,double w){s->_lineWidth=w;}
void O2ContextSetLineWidth(Context*c,double w){c->state._lineWidth=w;}
void O2ContextSaveGState(Context*c){c->saves++;}
void O2ContextRestoreGState(Context*c){c->restores++;c->clips++;c->state._lineWidth=7;}
void O2ContextBeginPath(Context*c){c->begins++;}
void O2ContextAddRect(Context*c,O2Rect r){c->adds++;c->rect=r;}
void O2ContextStrokePath(Context*c){c->strokes++;c->seenWidth=c->state._lineWidth;if(c->fail)throw std::runtime_error("stroke failure");}
'''
control=r'''
int main(){O2ContextStrokeRectWithWidth(nullptr,{},1);
 for(int failure=0;failure<2;failure++){Context c;c.fail=failure;bool caught=false;try{O2ContextStrokeRectWithWidth(&c,{2,3,4,5},1.5);}catch(...){caught=true;}
 assert(caught==bool(failure));assert(c.state._lineWidth==7&&c.state.color==0x12345678);
 assert(c.begins==1&&c.adds==1&&c.strokes==1&&c.seenWidth==1.5);assert(c.rect.x==2&&c.rect.h==5);
 assert(c.saves==0&&c.restores==0&&c.clips==0);
 }puts("PASS exact rectangle stroke: geometry, width, state, exception restore; zero clip replays");}
'''
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp);(p/'control.cpp').write_text(preamble+f+control)
 subprocess.run(['c++','-std=c++17','-fsanitize=address,undefined',str(p/'control.cpp'),'-o',str(p/'control')],check=True)
 subprocess.run([str(p/'control')],check=True)
