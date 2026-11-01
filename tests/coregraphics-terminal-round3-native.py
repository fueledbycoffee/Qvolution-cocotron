#!/usr/bin/env python3
"""SPEC.md Round 3 native contracts; extracted production bodies, host adapters.

No Apple behavior is asserted. Run with qv-slot build. Object allocation, array
ownership, and external siblings are adapters; public wrappers, state mutation,
save/restore and initializers are unchanged production definitions.
"""
import argparse
import os
from pathlib import Path
import re
import subprocess

def definition(source, prefix):
    """Copy a whole production definition, rejecting a missing/ambiguous match."""
    matches = list(re.finditer(r'^' + re.escape(prefix), source, re.MULTILINE))
    if len(matches) != 1:
        raise ValueError(f'expected one definition: {prefix}')
    start = matches[0].start()
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end] + '\n'


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
root = Path(__file__).resolve().parents[1]
bridge = (root / 'CoreGraphics/CGContext.m').read_text()
backend = (root / 'Onyx2D/O2Context.m').read_text()
state = (root / 'Onyx2D/O2GraphicsState.m').read_text()
cgs = (root / 'CoreGraphics/CGS.m').read_text()
names = ['AllowsAntialiasing', 'ShouldAntialias', 'AllowsFontSmoothing', 'ShouldSmoothFonts']
# Resolve every required definition before compiling: the clean base must fail.
functions = ''.join(definition(backend, 'BOOL O2ContextGet' + n + '(') for n in names)
functions += ''.join(definition(backend, 'void O2ContextSet' + n + '(') for n in names)
functions += definition(backend, 'uint32_t O2ContextGetFontSmoothingStyle(')
functions += definition(backend, 'void O2ContextSetFontSmoothingStyle(')
functions += definition(backend, 'void O2ContextSaveGState(')
functions += definition(backend, 'void O2ContextRestoreGState(')
functions += ''.join(definition(bridge, 'bool CGContextGet' + n + '(') for n in names)
functions += ''.join(definition(bridge, 'void CGContextSet' + n + '(') for n in names)
functions += definition(bridge, 'uint32_t CGContextGetFontSmoothingStyle(')
functions += definition(bridge, 'void CGContextSetFontSmoothingStyle(')
functions += definition(bridge, 'void CGContextSaveGState(')
functions += definition(bridge, 'void CGContextRestoreGState(')
functions += definition(cgs, 'CGSConnectionID CGSDefaultConnectionForThread(')
for n in ['CGSSetSecureEventInput', 'CGSSetWindowBackgroundBlurRadius',
          'CGSSetWindowBackgroundBlurRadiusWithOpacityHint', 'CGSSetWindowBackgroundBlurRadiusStyle']:
    functions += definition(cgs, 'CGError ' + n + '(')
for n in ['CPSGetCurrentProcess', 'CPSStealKeyFocus', 'CPSReleaseKeyFocus']:
    functions += definition(cgs, 'OSErr ' + n + '(')
preamble = r'''
#include <objc/Object.h>
#include <objc/runtime.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <math.h>
#define CHECK(x) do { checks++; if (!(x)) { fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#x); exit(1); } } while(0)
static unsigned checks;
typedef void NSZone;
typedef double O2Float;
typedef struct { double a,b,c,d,tx,ty; } O2AffineTransform;
static const O2AffineTransform O2AffineTransformIdentity = {1,0,0,1,0,0};
typedef struct { double width,height; } O2Size;
static O2Size O2SizeMake(double w,double h) { return (O2Size){w,h}; }
enum { kO2BlendModeNormal, kO2InterpolationDefault };
@interface Stub : Object
+ new;
+ alloc;
- init;
- retain;
- autorelease;
- (void) release;
- (void*) methodForSelector:(SEL)s;
@end
@implementation Stub
+ new { return [[self alloc] init]; }
+ alloc { return class_createInstance(self, 0); }
- init { return self; }
- retain { return self; }
- autorelease { return self; }
- (void) release {}
- (void*) methodForSelector:(SEL)s { return NULL; }
@end
@interface NSMutableArray : Stub { id values[32]; unsigned used; }
- (void) addObject:(id)o;
- (void) removeLastObject;
- lastObject;
- (unsigned) count;
@end
@implementation NSMutableArray
- (void) addObject:(id)o { if(used==32) abort(); values[used++]=o; }
- (void) removeLastObject { if(!used) abort(); used--; }
- lastObject { return used ? values[used-1] : nil; }
- (unsigned) count { return used; }
@end
@interface O2ClipState : Stub @end
@implementation O2ClipState @end
@interface O2Color : Stub @end
@implementation O2Color @end
@interface O2MutablePath : Stub @end
@implementation O2MutablePath @end
@interface O2GState : Stub {
@public
 O2AffineTransform _deviceSpaceTransform, _userSpaceTransform;
 id _clipState,_strokeColor,_fillColor,_font,_encoding,_pdfCharWidths,_fontState;
 id _shadowColor; void *_shadowKernel;
 BOOL _fillColorIsDirty,_fontIsDirty,_shouldAntialias,_shouldSmoothFonts;
 uint32_t _fontSmoothingStyle;
 double _pointSize,_lineWidth,_miterLimit,_alpha; int _blendMode,_interpolationQuality,_antialiasingQuality;
 O2Size _patternPhase;
 double *_dashLengths; int _dashLengthsCount;
}
- initWithDeviceTransform:(O2AffineTransform)t;
- (void) setShouldAntialias:(BOOL)b;
- (void) setShouldSmoothFonts:(BOOL)b;
@end
@interface O2Context : Stub {
@public
 O2AffineTransform _userToDeviceTransform,_textMatrix;
 NSMutableArray *_layerStack,*_stateStack;
 O2GState *_currentState;
 O2MutablePath *_path;
 BOOL _allowsAntialiasing,_allowsFontSmoothing;
 void *_showTextFunction,*_showGlyphsFunction;
}
- initWithGraphicsState:(O2GState*)state;
- (void) clipToState:(id)s;
@end
typedef O2Context *O2ContextRef;
typedef O2Context *CGContextRef;
typedef void *O2ContextShowGlyphsFunction;
static void *O2ContextDefaultShowText;
static O2GState *O2ContextCurrentGState(O2ContextRef c) { return c->_currentState; }
static id NSCopyObject(id o,unsigned unused,NSZone *z) {
 id result = class_createInstance(object_getClass(o),0);
 memcpy((char*)result+sizeof(Class),(char*)o+sizeof(Class),class_getInstanceSize(object_getClass(o))-sizeof(Class));
 return result;
}
static id O2ClipStateCreateCopy(id o) { return o; }
static id O2ColorCreateCopy(id o) { return o; }
static void *O2GaussianKernelRetain(void *p) { return p; }
static void *NSZoneMalloc(NSZone *z,size_t n) { return malloc(n); }
static id O2GStateClipState(O2GState *s) { return s->_clipState; }
typedef int CGSConnectionID,CGSWindowID,CGError;
typedef int16_t OSErr;
typedef struct { uint32_t highLongOfPSN,lowLongOfPSN; } CPSProcessSerNum;
typedef struct { uint32_t highLongOfPSN,lowLongOfPSN; } ProcessSerialNumber;
enum { kCGErrorNotImplemented=1006,paramErr=-50,unimpErr=-4,noErr=0 };
static int manager,calls,processCalls; static OSErr processStatus;
static CGSConnectionID _CGSDefaultConnection(void) { calls++; return manager; }
static OSErr GetCurrentProcess(ProcessSerialNumber *p) {
 processCalls++; p->highLongOfPSN=0xabcdef01; p->lowLongOfPSN=0x76543210; return processStatus;
}
'''
methods = '@implementation O2GState\n'
methods += definition(state, '- initWithDeviceTransform:')
for n in ['ShouldAntialias','ShouldSmoothFonts']:
    methods += definition(state, '- (void) set' + n + ':')
methods += '@end\n' + definition(state, 'O2GState *O2GStateCopyWithZone(')
methods += '@implementation O2Context\n' + definition(backend, '- initWithGraphicsState:')
methods += '- (void) clipToState:(id)s {}\n@end\n'
main = r'''
typedef void (*Setter)(CGContextRef,bool);
typedef bool (*Getter)(CGContextRef);
static Setter setters[]={CGContextSetAllowsAntialiasing,CGContextSetShouldAntialias,CGContextSetAllowsFontSmoothing,CGContextSetShouldSmoothFonts};
static Getter getters[]={CGContextGetAllowsAntialiasing,CGContextGetShouldAntialias,CGContextGetAllowsFontSmoothing,CGContextGetShouldSmoothFonts};
static void verify(CGContextRef c,bool a,bool s,bool f,bool t,uint32_t style) {
 CHECK(getters[0](c)==a); CHECK(getters[1](c)==s); CHECK(getters[2](c)==f); CHECK(getters[3](c)==t);
 CHECK(CGContextGetFontSmoothingStyle(c)==style);
}
int main(void) {
 O2Context *c[2];
 for(unsigned k=0;k<2;k++) {
  O2GState *s=[[O2GState alloc] initWithDeviceTransform:O2AffineTransformIdentity];
  c[k]=[[O2Context alloc] initWithGraphicsState:s]; verify(c[k],true,true,true,true,0);
 }
 for(unsigned i=0;i<4;i++) { setters[i](NULL,false); CHECK(!getters[i](NULL)); }
 CGContextSetFontSmoothingStyle(NULL,UINT32_MAX); CHECK(CGContextGetFontSmoothingStyle(NULL)==0);
 CGContextSaveGState(NULL); CGContextRestoreGState(NULL);
 for(unsigned mask=0;mask<16;mask++) {
  for(unsigned i=0;i<4;i++) setters[i](c[0],(mask>>i)&1);
  for(unsigned i=0;i<4;i++) CHECK(getters[i](c[0])==!!((mask>>i)&1));
  verify(c[1],true,true,true,true,0);
 }
 uint32_t styles[]={0,1,0x80000000u,UINT32_MAX,0xabcdef01};
 for(unsigned i=0;i<5;i++) { CGContextSetFontSmoothingStyle(c[0],styles[i]); verify(c[0],true,true,true,true,styles[i]); }
 CGContextSaveGState(c[0]);
 for(unsigned i=0;i<4;i++) setters[i](c[0],false);
 CGContextSetFontSmoothingStyle(c[0],0x80000000u);
 CGContextSaveGState(c[0]);
 for(unsigned i=0;i<4;i++) setters[i](c[0],true);
 CGContextSetFontSmoothingStyle(c[0],UINT32_MAX);
 CGContextRestoreGState(c[0]); verify(c[0],true,false,true,false,0x80000000u);
 CGContextSetAllowsAntialiasing(c[0],false); CGContextSetAllowsFontSmoothing(c[0],false);
 CGContextRestoreGState(c[0]); verify(c[0],false,true,false,true,0xabcdef01);
 CGContextRestoreGState(c[0]); verify(c[0],false,true,false,true,0xabcdef01);
 verify(c[1],true,true,true,true,0);
 for(unsigned i=0;i<4;i++) { manager=(int[]){-123,0,1,INT_MAX}[i]; int before=calls;
  CHECK(CGSDefaultConnectionForThread()==(manager>0?manager:0)); CHECK(calls==before+1); }
 int before=calls;
 int vals[]={INT_MIN,-1,0,1,INT_MAX}; float opacity[]={NAN,INFINITY,-INFINITY,-1,0,1,2};
 for(unsigned i=0;i<5;i++) {
  CHECK(CGSSetSecureEventInput(vals[i],false)==1006); CHECK(CGSSetSecureEventInput(vals[i],true)==1006);
  for(unsigned j=0;j<5;j++) for(unsigned k=0;k<5;k++) {
   CHECK(CGSSetWindowBackgroundBlurRadius(vals[i],vals[j],vals[k])==1006);
   CHECK(CGSSetWindowBackgroundBlurRadiusStyle(vals[i],vals[j],vals[k],vals[j])==1006);
   for(unsigned f=0;f<7;f++) CHECK(CGSSetWindowBackgroundBlurRadiusWithOpacityHint(vals[i],vals[j],vals[k],opacity[f])==1006);
  }
 }
 CHECK(calls==before);
 struct { uint32_t before; CPSProcessSerNum psn; uint32_t after; } out={0x12345678,{3,4},0x87654321};
 CHECK(CPSGetCurrentProcess(NULL)==paramErr); CHECK(processCalls==0);
 OSErr statuses[]={unimpErr,paramErr,1,INT16_MIN,INT16_MAX};
 for(unsigned i=0;i<5;i++) { processStatus=statuses[i]; CHECK(CPSGetCurrentProcess(&out.psn)==statuses[i]); CHECK(out.psn.highLongOfPSN==3); CHECK(out.psn.lowLongOfPSN==4); }
 processStatus=0; CHECK(CPSGetCurrentProcess(&out.psn)==0);
 CHECK(out.psn.highLongOfPSN==0xabcdef01); CHECK(out.psn.lowLongOfPSN==0x76543210);
 CHECK(out.before==0x12345678); CHECK(out.after==0x87654321);
 CHECK(CPSStealKeyFocus(NULL,UINT32_MAX)==paramErr); CHECK(CPSReleaseKeyFocus(NULL)==paramErr);
 CPSProcessSerNum copy=out.psn;
 for(unsigned i=0;i<3;i++) { CHECK(CPSStealKeyFocus(&out.psn,(uint32_t[]){0,1,UINT32_MAX}[i])==unimpErr); CHECK(CPSReleaseKeyFocus(&out.psn)==unimpErr); }
 CHECK(!memcmp(&copy,&out.psn,sizeof(copy)));
 // Unsupported focus calls must not dereference even a non-null unreadable token.
 CHECK(CPSStealKeyFocus((CPSProcessSerNum*)(uintptr_t)1,0)==unimpErr);
 CHECK(CPSReleaseKeyFocus((CPSProcessSerNum*)(uintptr_t)1)==unimpErr);
 printf("PASS Round 3: %u checks; defaults, isolation, nested state, nulls, style, siblings, unsupported paths\n",checks);
 return 0;
}
'''
source=args.output/'round3.m'
source.write_text(preamble+methods+functions+main)
include=subprocess.check_output(['gcc','-print-file-name=include'],text=True).strip()
binary=args.output/'round3'
subprocess.run(['clang','-O1','-g','-Wall','-Wextra','-Wno-unused-parameter',
 '-Wno-unused-function','-Wno-missing-method-return-type','-Werror','-fobjc-runtime=gcc','-fsanitize=address,undefined',
 '-fno-omit-frame-pointer','-I'+include,str(source),'-lobjc','-o',str(binary)],check=True)
subprocess.run([str(binary)],check=True,env={**os.environ,'ASAN_OPTIONS':'detect_leaks=0'})
