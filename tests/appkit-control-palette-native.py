#!/usr/bin/env python3
"""Execute the production control-token resolver with native Cocoa doubles.
The doubles resolve catalog roles through the production P1 palette. This checks
that P4 consumes those roles, especially high contrast, without a guest runtime.
The full control raster matrix remains a guest fixture.
"""
from pathlib import Path
import argparse, os, subprocess, tempfile
p=argparse.ArgumentParser();p.add_argument('--source',type=Path);a=p.parse_args()
root=Path(__file__).resolve().parents[1]
s=(a.source or root/'AppKit/NSInterfacePart/NSGraphicsStyle.m').read_text()
enum=s[s.index('typedef enum {\n    NSControlTokenBezelBorder'):s.index('} NSControlTokenName;')+len('} NSControlTokenName;')]
start=s.index('static NSColor *NSControlToken(');end=s.index('\n}\n',start)+2
harness=r'''
#include <objc/runtime.h>
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "X11ThemePalette.h"
static int dark,high;
__attribute__((objc_root_class)) @interface FixtureString { Class isa; const char *bytes; unsigned length; }
- (const char *)UTF8String;
@end
@implementation FixtureString
- (const char *)UTF8String { return bytes; }
@end
@compatibility_alias NSString FixtureString;
__attribute__((objc_root_class)) @interface NSColor { @public Class isa; QVThemeColor value; }
+ (id)colorWithCatalogName:(NSString *)catalog colorName:(NSString *)name;
+ (id)colorWithCalibratedWhite:(double)white alpha:(double)alpha;
@end
@implementation NSColor
+ (id)colorWithCatalogName:(NSString *)catalog colorName:(NSString *)name {
 assert(!strcmp([catalog UTF8String],"System"));
 NSColor *c=class_createInstance(self,0);double accent[]={.835,.380,.600};
 assert(QVThemeLookup([name UTF8String],dark,high,accent,&c->value));return c;
}
+ (id)colorWithCalibratedWhite:(double)white alpha:(double)alpha {
 NSColor *c=class_createInstance(self,0);c->value=QVWhite(white,alpha);return c;
}
@end
__attribute__((objc_root_class)) @interface NSException
+ (void)raise:(id)name format:(id)format, ...;
@end
@implementation NSException
+ (void)raise:(id)name format:(id)format, ... { abort(); }
@end
#define NSInvalidArgumentException @"invalid"
#define BOOL int
static BOOL NSControlDrawingIsDark(void) { return dark; }
/* PRODUCTION */
static void check(NSControlTokenName token,double white,double alpha) {
 NSColor *c=NSControlToken(token);
 assert(fabs(c->value.r-white)<1e-9 && fabs(c->value.g-white)<1e-9 && fabs(c->value.b-white)<1e-9);
 assert(fabs(c->value.a-alpha)<1e-9);object_dispose(c);
}
int main(void) {
 for(dark=0;dark<=1;dark++)for(high=0;high<=1;high++) {
  check(NSControlTokenBezelBorder,dark?(high?235.0/255:1):0,high?1:(dark?.12:.18));
  check(NSControlTokenBezelBottomShadow,0,dark?.4:.08);
  check(NSControlTokenPressedFace,(dark?0x70:0xF0)/255.0,1);
  check(NSControlTokenSegmentSelected,dark?1:0,dark?.22:.14);
 }
 puts("PASS P4 production control role routing: light/dark/high contrast through P1 palette");
}
'''.replace('/* PRODUCTION */',enum+'\n'+s[start:end])
objc=subprocess.check_output(['gcc','-print-file-name=include'],text=True).strip()
with tempfile.TemporaryDirectory(prefix='qv-control-palette-') as d:
 d=Path(d);(d/'test.m').write_text(harness)
 subprocess.run(['clang','-O2','-fconstant-string-class=FixtureString','-Wno-objc-root-class','-fsanitize=address,undefined','-I'+objc,'-I'+str(root/'AppKit/X11.backend'),str(d/'test.m'),'-lobjc','-lm','-o',str(d/'test')],check=True)
 subprocess.run([str(d/'test')],check=True,env={**os.environ,'ASAN_OPTIONS':'detect_leaks=0','UBSAN_OPTIONS':'halt_on_error=1'})
