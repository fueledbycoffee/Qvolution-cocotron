#!/usr/bin/env python3
"""Execute production begin/end state bookkeeping with C++ API doubles.
Not a PDF/bitmap rendering test; run layer-clip.m under Darling for that gate.
An optional source root permits the same check against the reviewed baseline.
"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
base = (root / 'Onyx2D/O2Context.m').read_text()
builtin = (root / 'Onyx2D/O2Context_builtin.m').read_text()

def method(source, selector):
    start = source.index('- (void) ' + selector)
    end = source.index('\n}', start) + 2
    return source[start:end]

parts = [method(base, 'beginTransparencyLayerWithInfo:'), method(base, 'endTransparencyLayer'),
         method(builtin, 'beginTransparencyLayerWithInfo:'), method(builtin, 'endTransparencyLayer')]
# Rendering/compositing is exercised by the separate framework fixture.
parts[2] = parts[2].split('    /**')[0] + '}\n'
parts[3] = parts[3].split('    O2Size size = [self size];')[0] + '}\n'
replacements = {
    '[super beginTransparencyLayerWithInfo: unused]': 'baseBegin(self, unused)',
    '[super endTransparencyLayer]': 'baseEnd(self)',
    '[self size]': '0',
    '[O2GStateClipState(O2ContextCurrentGState(self)) clipPhases]': 'nullptr',
    '[[phases copy] autorelease]': 'phases',
    '[NSArray array]': 'nullptr',
    '[NSNumber numberWithBool: NO]': 'false',
    '[NSNumber numberWithBool: YES]': 'true',
    '[[self->_transparencyLayerStates lastObject] boolValue]': 'self->_transparencyLayerStates.last()',
    '[_transparencyLayerStates count]': 'self->_transparencyLayerStates.size()',
    '[_stateStack count]': 'self->_stateStack.size()',
    '[_stateStack objectAtIndex:[_stateStack count] - 2]': '(&self->state)',
    'O2ColorSpaceRequireSupportedRendering(O2ColorGetColorSpace(restored->_shadowColor))': '(void)0',
}
for i, name in enumerate(['baseBegin', 'baseEnd', 'builtinBegin', 'builtinEnd']):
    text = re.sub(r'- \(void\) beginTransparencyLayerWithInfo: \(NSDictionary \*\) unused',
                  'void ' + name + '(Context *self, void *unused)', parts[i])
    text = text.replace('- (void) endTransparencyLayer', 'void ' + name + '(Context *self)')
    text = text.replace('[_stateStack objectAtIndex:[_stateStack count] - 2]', '(&self->state)')
    for old, new in replacements.items():
        text = text.replace(old, new)
    text = re.sub(r'(?<![\w>])(_(?:layerStack|layerClipPhases|transparencyLayerStates|stateStack))\b', r'self->\1', text)
    text = re.sub(r'\[(self->\w+) addObject:\s*(.*?)\];', r'\1.push(\2);', text, flags=re.S)
    text = re.sub(r'\[(self->\w+) removeLastObject\]', r'\1.pop()', text)
    text = re.sub(r'\[(self->\w+) lastObject\]', r'\1.last()', text)
    text = re.sub(r'\[(self->\w+) replaceObjectAtIndex:\s*(.*?)\s+withObject:\s*(.*?)\];',
                  r'\1.replace(\2, \3);', text, flags=re.S)
    parts[i] = text

preamble = r'''
#include <cassert>
#include <cstdio>
#include <vector>
#define nil nullptr
#define NO false
#define YES true
using NSArray = void;
struct O2GState { bool _shadowKernel=false; };
using O2LayerRef = int*;
struct Stack {
 std::vector<intptr_t> v;
 template<class T> void push(T p){v.push_back((intptr_t)p);}
 void push(std::nullptr_t){v.push_back(0);}
 void pop(){assert(!v.empty());v.pop_back();}
 intptr_t last(){return v.empty()?0:v.back();}
 size_t size(){return v.size();}
 void replace(size_t i,bool p){v.at(i)=p;}
};
struct Context {
 Stack _layerStack,_layerClipPhases,_transparencyLayerStates,_stateStack;
 O2GState state; int clip=100; bool fail=false; int layer=1;
 Context(){_stateStack.push(clip);}
};
void O2ContextSaveGState(Context*c){c->_stateStack.push(c->clip);}
void O2ContextRestoreGState(Context*c){c->clip=c->_stateStack.last();c->_stateStack.pop();}
O2GState*O2ContextCurrentGState(Context*c){return &c->state;}
void*O2GStateClipState(O2GState*){return nullptr;}
bool missingContext=false;
O2LayerRef O2LayerCreateWithContext(Context*c,int,void*){return c->fail?nullptr:&c->layer;}
void*O2LayerGetContext(O2LayerRef p){return missingContext?nullptr:p;}
O2LayerRef O2LayerRetain(intptr_t p){return (int*)p;}
void O2LayerRelease(O2LayerRef){}
'''
control = r'''
int main(){
 Context pdf; baseBegin(&pdf,nullptr);pdf.clip=20;baseEnd(&pdf);
 assert(pdf.clip==100 && pdf._stateStack.size()==1);
 baseEnd(&pdf);assert(pdf._stateStack.size()==1);
 Context bitmap; builtinBegin(&bitmap,nullptr);bitmap.clip=40;
 builtinBegin(&bitmap,nullptr);bitmap.clip=20;builtinEnd(&bitmap);
 assert(bitmap.clip==40 && bitmap._layerStack.size()==1);
 bitmap.fail=true;builtinBegin(&bitmap,nullptr);bitmap.clip=10;builtinEnd(&bitmap);
 assert(bitmap.clip==40 && bitmap._layerStack.size()==1);
 bitmap.fail=false;builtinBegin(&bitmap,nullptr);bitmap.clip=5;builtinEnd(&bitmap);
 assert(bitmap.clip==40 && bitmap._layerStack.size()==1);
 builtinEnd(&bitmap);assert(bitmap.clip==100 && bitmap._layerStack.size()==0);
 assert(bitmap._stateStack.size()==1 && bitmap._transparencyLayerStates.size()==0);
 Context failed;failed.fail=true;builtinBegin(&failed,nullptr);failed.clip=1;builtinEnd(&failed);
 assert(failed.clip==100 && failed._stateStack.size()==1);
 Context invalid;missingContext=true;builtinBegin(&invalid,nullptr);invalid.clip=1;builtinEnd(&invalid);
 assert(invalid.clip==100 && invalid._stateStack.size()==1);
 puts("PASS unsupported, failed, successful and mixed nested production layer state paths");
}
'''
with tempfile.TemporaryDirectory() as directory:
    source = Path(directory) / 'layers.cpp'
    source.write_text('#include <cstdint>\n' + preamble + '\n'.join(parts) + control)
    binary = Path(directory) / 'layers'
    subprocess.run(['c++', '-std=c++17', '-fsanitize=address,undefined', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
