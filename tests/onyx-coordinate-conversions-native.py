#!/usr/bin/env python3
"""Run production O2GState conversion methods and affine math on host libobjc.

Only Foundation geometry types and object allocation are adapted. This does not
exercise the guest Foundation, CoreGraphics bridge, or pixel renderer.
"""
import argparse
from pathlib import Path
import os
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--source-file', type=Path)
args = parser.parse_args()
component = Path(__file__).resolve().parents[1]
args.output.mkdir(parents=True, exist_ok=True)
source = (args.source_file or component / 'Onyx2D/O2GraphicsState.m').read_text()
methods = source[source.index('- (O2Point) convertPointToDeviceSpace:'):source.index('void O2GStateSetDeviceSpaceCTM(')]
concat = source[source.index('void O2GStateConcatCTM('):source.index('O2ClipState *O2GStateClipState(')]
shim = args.output / 'Foundation'
shim.mkdir(exist_ok=True)
(shim / 'Foundation.h').write_text(r'''
#pragma once
#include <objc/objc.h>
#include <math.h>
typedef struct { double x, y; } NSPoint;
typedef struct { double width, height; } NSSize;
typedef struct { NSPoint origin; NSSize size; } NSRect;
static inline NSPoint NSMakePoint(double x,double y) { return (NSPoint){x,y}; }
static inline NSRect NSMakeRect(double x,double y,double w,double h) { return (NSRect){{x,y},{w,h}}; }
#define NSMinX(r) ((r).origin.x)
#define NSMinY(r) ((r).origin.y)
#define NSMaxX(r) ((r).origin.x+(r).size.width)
#define NSMaxY(r) ((r).origin.y+(r).size.height)
static inline NSRect NSIntersectionRect(NSRect a,NSRect b) {
    double x=fmax(NSMinX(a),NSMinX(b)),y=fmax(NSMinY(a),NSMinY(b));
    return NSMakeRect(x,y,fmax(0,fmin(NSMaxX(a),NSMaxX(b))-x),fmax(0,fmin(NSMaxY(a),NSMaxY(b))-y));
}
''')
preamble = r'''
#include <objc/Object.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <Onyx2D/O2AffineTransform.h>
#define O2UnimplementedMethod() ((void)0)
@interface O2GState : Object {
@public
    O2AffineTransform _deviceSpaceTransform, _userSpaceTransform;
    BOOL _fontIsDirty;
}
@end
@implementation O2GState
'''
main = r'''
static unsigned failures, checks;
static void check(const char *name, const char *kind, double a, double b) {
    checks++;
    if (!isfinite(a) || fabs(a-b)>1e-10) {
        fprintf(stderr,"FAIL %s %s: got %.15g expected %.15g\n",name,kind,a,b);
        failures++;
    }
}
static void conversions(const char *name,O2GState *s,O2Point dp,O2Size ds,O2Rect dr,
                        O2Point up,O2Size us,O2Rect ur) {
    O2Point p=[s convertPointToDeviceSpace:O2PointMake(2,3)];
    check(name,"device point x",p.x,dp.x); check(name,"device point y",p.y,dp.y);
    p=[s convertPointToUserSpace:O2PointMake(2,3)];
    check(name,"user point x",p.x,up.x); check(name,"user point y",p.y,up.y);
    O2Size z=[s convertSizeToDeviceSpace:O2SizeMake(4,6)];
    check(name,"device size w",z.width,ds.width); check(name,"device size h",z.height,ds.height);
    z=[s convertSizeToUserSpace:O2SizeMake(4,6)];
    check(name,"user size w",z.width,us.width); check(name,"user size h",z.height,us.height);
    O2Rect r=[s convertRectToDeviceSpace:O2RectMake(2,3,4,6)];
    check(name,"device rect x",r.origin.x,dr.origin.x); check(name,"device rect y",r.origin.y,dr.origin.y);
    check(name,"device rect w",r.size.width,dr.size.width); check(name,"device rect h",r.size.height,dr.size.height);
    r=[s convertRectToUserSpace:O2RectMake(2,3,4,6)];
    check(name,"user rect x",r.origin.x,ur.origin.x); check(name,"user rect y",r.origin.y,ur.origin.y);
    check(name,"user rect w",r.size.width,ur.size.width); check(name,"user rect h",r.size.height,ur.size.height);
    printf("CHECK %s: six conversions\n",name);
}
#define P(x,y) O2PointMake(x,y)
#define S(w,h) O2SizeMake(w,h)
#define R(x,y,w,h) O2RectMake(x,y,w,h)
int main(void) {
    O2GState *s=class_createInstance(objc_getClass("O2GState"),0);
    s->_deviceSpaceTransform=O2AffineTransformIdentity;
    s->_userSpaceTransform=O2AffineTransformIdentity;
    conversions("identity",s,P(2,3),S(4,6),R(2,3,4,6),P(2,3),S(4,6),R(2,3,4,6));
    O2GStateConcatCTM(s,O2AffineTransformMakeTranslation(10,-4));
    conversions("translation",s,P(12,-1),S(4,6),R(12,-1,4,6),P(-8,7),S(4,6),R(-8,7,4,6));
    O2GStateConcatCTM(s,O2AffineTransformMakeScale(2,3));
    conversions("scale",s,P(14,5),S(8,18),R(14,5,8,18),P(-4,7./3),S(2,2),R(-4,7./3,2,2));
    s->_deviceSpaceTransform=O2AffineTransformMake(0,1,-1,0,10,20);
    conversions("quarter rotation",s,P(7,22),S(-6,4),R(1,22,6,4),P(-17,8),S(6,-4),R(-17,4,6,4));
    double q=sqrt(.5);
    s->_deviceSpaceTransform=O2AffineTransformMake(q,q,-q,q,10,20);
    conversions("45 degree bounds",s,P(10-q,20+5*q),S(-2*q,10*q),R(10-7*q,20+5*q,10*q,10*q),
                P(-25*q,-9*q),S(10*q,2*q),R(-25*q,-13*q,10*q,10*q));
    s->_deviceSpaceTransform=O2AffineTransformMake(1,0,0,-1,0,100);
    s->_userSpaceTransform=O2AffineTransformIdentity;
    conversions("flipped device",s,P(2,97),S(4,-6),R(2,91,4,6),P(2,97),S(4,-6),R(2,91,4,6));
    O2GStateConcatCTM(s,O2AffineTransformMakeScale(2,3));
    O2GStateConcatCTM(s,O2AffineTransformMakeTranslation(5,7));
    conversions("flipped concatenated CTM",s,P(14,70),S(8,-18),R(14,52,8,18),
                P(-4,76./3),S(2,-2),R(-4,70./3,2,2));
    s->_deviceSpaceTransform=O2AffineTransformMake(1,0,2,1,10,-4);
    conversions("shear bounds",s,P(18,-1),S(16,6),R(18,-1,16,6),P(-22,7),S(-8,6),R(-34,7,16,6));
    // Same one-pixel rectangles used by the menu fixture, in a flipped surface.
    s->_deviceSpaceTransform=O2AffineTransformMake(1,0,0,-1,0,110);
    O2Rect mark=[s convertRectToDeviceSpace:R(22,44,1,1)];
    O2Rect off=[s convertRectToDeviceSpace:R(22,14,1,1)];
    check("menu sample","mark x",mark.origin.x,22); check("menu sample","mark y",mark.origin.y,65);
    check("menu sample","off y",off.origin.y,95); check("menu sample","width",mark.size.width,1);
    check("menu sample","height",mark.size.height,1);
    object_dispose(s);
    printf("RESULT onyx-coordinate-conversions failures=%u checks=%u\n",failures,checks);
    return failures?1:0;
}
'''
file = args.output / 'coordinate-conversions.m'
file.write_text(preamble + methods + '\n@end\n' + concat + main)
binary = args.output / 'coordinate-conversions'
include = subprocess.check_output(['gcc', '-print-file-name=include'], text=True).strip()
command = ['clang', '-O1', '-g', '-Wall', '-Wextra', '-Werror', '-fobjc-runtime=gcc',
           '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
           '-I' + include, '-I' + str(args.output), '-I' + str(component / 'Onyx2D/include'),
           str(file), str(component / 'Onyx2D/O2AffineTransform.m'),
           str(component / 'Onyx2D/O2Geometry.m'), '-lobjc', '-lm', '-o', str(binary)]
subprocess.run(command, check=True)
# GNU libobjc retains process-global runtime allocations; keep ASan/UBSan enabled.
result = subprocess.run([str(binary)], env={**os.environ, 'ASAN_OPTIONS': 'detect_leaks=0'})
raise SystemExit(result.returncode)
