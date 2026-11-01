#!/usr/bin/env python3
"""Exercise CARenderer's production stencil-free projection helper without GL.
Only GL state access is adapted; no container, context, GPU or Apple code.
Run under qv-slot build (the script compiles an ASan/UBSan native executable).
"""
from pathlib import Path
import argparse, os, subprocess
p = argparse.ArgumentParser()
p.add_argument('--out', required=True, type=Path)
a = p.parse_args()
assert os.environ.get('QV_SLOT', '').startswith('build-'), 'qv-slot build required'
source = (Path(__file__).resolve().parents[1] / 'QuartzCore/CARenderer.m').read_text()
start = source.index('static void scissorLayerMask(')
end = source.index('\n}\n', start) + 3
helper = source[start:end]
adapter = r'''
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
typedef double GLdouble;
typedef int GLint, GLsizei;
typedef struct { double x,y; } Point;
typedef struct { double width,height; } Size;
typedef struct { Point origin; Size size; } CGRect;
#define MIN(a,b) ((a)<(b)?(a):(b))
#define MAX(a,b) ((a)>(b)?(a):(b))
enum { GL_MODELVIEW_MATRIX, GL_PROJECTION_MATRIX, GL_VIEWPORT, GL_SCISSOR_BOX, GL_SCISSOR_TEST };
static double model[16], projection[16];
static int viewport[4]={0,0,200,100}, box[4], enabled;
static void glGetDoublev(int key,double *out) { memcpy(out,key==GL_MODELVIEW_MATRIX?model:projection,16*sizeof(double)); }
static void glGetIntegerv(int key,int *out) { memcpy(out,key==GL_VIEWPORT?viewport:box,4*sizeof(int)); }
static int glIsEnabled(int key) { assert(key==GL_SCISSOR_TEST); return enabled; }
static void glEnable(int key) { assert(key==GL_SCISSOR_TEST); enabled=1; }
static void glScissor(int x,int y,int w,int h) { box[0]=x;box[1]=y;box[2]=w;box[3]=h; }
static void reset(void) {
 memset(model,0,sizeof(model)); memset(projection,0,sizeof(projection)); enabled=0;
 model[0]=model[5]=model[10]=model[15]=1;
 projection[0]=projection[5]=.02; projection[10]=-1; projection[12]=projection[13]=-1; projection[15]=1;
}
static void expect(int x,int y,int w,int h) {
 if (!(enabled && box[0]==x && box[1]==y && box[2]==w && box[3]==h))
   fprintf(stderr,"scissor got %d,%d %dx%d expected %d,%d %dx%d\n",box[0],box[1],box[2],box[3],x,y,w,h);
 assert(enabled && box[0]==x && box[1]==y && box[2]==w && box[3]==h);
}
'''
main = r'''
int main(void) {
 CGRect rect={{0,0},{40,30}};
 reset(); model[12]=10; model[13]=20; scissorLayerMask(rect); expect(20,20,80,30);
 model[12]=30; scissorLayerMask(rect); expect(60,20,40,30); // nested intersection
 reset(); model[5]=-1; model[12]=10; model[13]=80; scissorLayerMask(rect); expect(20,50,80,30);
 reset(); model[0]=model[5]=0; model[1]=1; model[4]=-1; model[12]=50;model[13]=20;
 scissorLayerMask(rect); expect(40,20,60,40); // transformed bounding rectangle
 reset(); model[12]=10.25; model[13]=20.25; scissorLayerMask(rect); expect(20,20,81,31);
 reset(); model[12]=-30; model[13]=-20; scissorLayerMask(rect); expect(0,0,20,10);
 reset(); model[12]=120; scissorLayerMask(rect); assert(box[2]==0);
 reset(); model[15]=-1; scissorLayerMask(rect); expect(0,0,200,100); // near plane
 puts("PASS production scissor projection: scale, flip, nesting, rotation, rounding, viewport, near plane");
}
'''
a.out.mkdir(parents=True, exist_ok=True)
c = a.out / 'layer-scissor.c'
c.write_text(adapter + helper + main)
binary = a.out / 'layer-scissor'
subprocess.run(['cc', '-std=c11', '-O1', '-g', '-Wall', '-Wextra', '-Werror',
                '-fsanitize=address,undefined,float-cast-overflow', str(c), '-lm', '-o', str(binary)], check=True)
subprocess.run([str(binary)], check=True)
