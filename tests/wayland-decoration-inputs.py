#!/usr/bin/env python3
"""Execute backend unmap state and style changes with native protocol doubles.
The companion Objective-C fixture covers backing pixels and real hide/show.
"""
from pathlib import Path
import re, subprocess, sys, tempfile
root=Path(__file__).resolve().parents[1]
s=(Path(sys.argv[1]) if len(sys.argv)>1 else root/'AppKit/Wayland.backend/WaylandWindow.m').read_text()
unmap=s.split('- (void) unmap {',1)[1].split('\n}',1)[0]
# Protocol teardown precedes this state transition; preserve the production tail.
unmap=unmap[unmap.index('    _mapped = NO;'):]
unmap=unmap.replace('[_display windowUnmapped: self];','').replace('[_display flush];','')
style=s.split('- (void) setStyleMask: (NSUInteger) mask {',1)[1].split('\n}',1)[0]
style=style.replace('[self updateSizeLimits];','').replace('[self updateFullscreen];','')
configure=s.split('    BOOL activationChanged = _pendingActivated != _activated;',1)[1].split('\n    if (firstConfigure',1)[0]
configure='    BOOL activationChanged = _pendingActivated != _activated;'+configure
opaque=s.split('- (void) setOpaque: (BOOL) value {',1)[1].split('\n}',1)[0]
fields=['_isOpaque','_sentGeometry','_mapped','_configureUpdatePending','_configured','_activated','_decorationsDirty','_fullscreenRequested','_pendingFullscreen','_fullscreenRecheckPending','_styleMask','_pendingActivated']
def adapt(body):
 for field in fields:body=re.sub(r'\b'+field+r'\b','self->'+field,body)
 return body
source=r'''
#include <cassert>
#include <cstdio>
using BOOL=bool;using NSUInteger=unsigned long;
#define NO false
#define YES true
constexpr NSUInteger NSWindowStyleMaskClosable=2,NSWindowStyleMaskMiniaturizable=4,NSWindowStyleMaskResizable=8;
struct O2Rect {double x=0,y=0,w=0,h=0;};
const O2Rect O2RectZero{};
struct Window {O2Rect _sentGeometry{6,6,100,80};BOOL _isOpaque=true,_mapped=true,_configureUpdatePending=true,_configured=true,_activated=true,_decorationsDirty=false,_fullscreenRequested=false,_pendingFullscreen=false,_fullscreenRecheckPending=false,_pendingActivated=false;NSUInteger _styleMask=15;};
'''
source+='void unmap(Window *self){'+adapt(unmap)+'}\n'
source+='void setStyle(Window *self,NSUInteger mask){'+adapt(style)+'}\n'
source+='void configure(Window *self){'+adapt(configure)+'}\n'
source+='void setOpaque(Window *self,BOOL value){'+adapt(opaque)+'}\n'
source+=r'''
int main(){Window w;unmap(&w);assert(!w._activated&&w._decorationsDirty);
 configure(&w);assert(!w._activated&&w._decorationsDirty);
 for(NSUInteger button:{2ul,4ul,8ul}){w._styleMask=15;w._decorationsDirty=false;setStyle(&w,15^button);assert(w._decorationsDirty);w._decorationsDirty=false;setStyle(&w,15^button);assert(!w._decorationsDirty);setStyle(&w,15);assert(w._decorationsDirty);}
 w._decorationsDirty=false;setStyle(&w,15|16);assert(!w._decorationsDirty);
 setOpaque(&w,true);assert(w._sentGeometry.w==100);
 setOpaque(&w,false);assert(!w._isOpaque&&w._sentGeometry.w==0);
 w._sentGeometry=O2Rect{6,6,100,80};setOpaque(&w,true);assert(w._isOpaque&&w._sentGeometry.w==0);
 puts("PASS retained active decorations invalidated by unmap/unfocused configure and all three button-style changes; unchanged styles reuse; opacity changes resend the opaque region");}
'''
source=source.replace('#include <cassert>','#include <cassert>\n#include <initializer_list>')
with tempfile.TemporaryDirectory(prefix='decoration-inputs-') as tmp:
 p=Path(tmp);(p/'control.cpp').write_text(source)
 subprocess.run(['c++','-std=c++17','-fsanitize=address,undefined',str(p/'control.cpp'),'-o',str(p/'control')],check=True)
 subprocess.run([str(p/'control')],check=True)
