#!/usr/bin/env python3
"""Compare VGPathFill's edges from a fill-only (positions-only) tessellation with the old source's.
Production VGPath tessellation functions and the supplied old VGPath.m's (renamed) are compiled
together with native doubles for O2Path, the affine transform and O2DContextAddEdge. For random
paths (move, line, quad, cubic, close, zero-length and repeated points, two transforms) the edges
VGPathFill emits must equal the old VGPathFill's exactly; after a fill-only tessellation,
VGPathTessellateIfNeeded must produce vertices (positions, tangents, lengths, flags), segment map
and bounds identical to a full tessellation. No Objective-C dispatch or guest claim.
  vgpath-fill-positions.py --reference <old VGPath.m> [--source <new VGPath.m>]
"""
from pathlib import Path
import argparse, os, re, subprocess, tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--reference', type=Path, required=True)
parser.add_argument('--source', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
production = (args.source or root / 'Onyx2D/VGPath.m').read_text(encoding='latin-1')
reference = args.reference.read_text(encoding='latin-1')
vgmath = (root / 'Onyx2D/include/Onyx2D/VGmath.h').read_text(encoding='latin-1')
vgmath = '\n'.join(l for l in vgmath.splitlines() if not l.startswith('#import'))


def function(text, name):
    a = text.index(name)
    a = text.rfind('\n', 0, a) + 1
    b = text.index('{', a) + 1
    depth = 1
    while depth:
        depth += (text[b] == '{') - (text[b] == '}')
        b += 1
    return text[a:b]


names = ['void VGPathAddVertex(', 'void VGPathAddEdge(', 'void VGPathAddEndPath(', 'BOOL VGPathAddLineTo(',
         'BOOL VGPathAddQuadTo(', 'BOOL VGPathAddCubicTo(', 'void VGPathTessellateIfNeeded(', 'void VGPathFill(']
newNames = names + ['static void VGPathTessellatePositionsIfNeeded(VGPath *self) {', 'static void VGPathTessellate(VGPath *self) {']


def block(text, wanted, prefix):
    out = ''.join(function(text, n) + '\n' for n in wanted)
    if prefix:
        out = re.sub(r'\bVGPath(\w+)\(', prefix + r'VGPath\1(', out)
    return out


# Helpers, flags and vertex types, from the production file (unchanged by the fill-only work).
a = production.index('static inline void RI_SWAP')
b = production.index('typedef struct {', production.index('typedef struct VertexIndex'))
helpers = production[a:b]
src = r'''
#include <assert.h>
#include <float.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef double O2Float;typedef bool BOOL;
#define YES true
#define NO false
#define RI_FLOAT_MAX FLT_MAX
#define NSZoneRealloc(z,p,n) realloc(p,n)
#define NSZoneMalloc(z,n) malloc(n)
typedef struct {O2Float x,y;} O2Point;
static O2Point O2PointMake(O2Float x,O2Float y){return (O2Point){x,y};}
typedef struct {O2Float a,b,c,d,tx,ty;} O2AffineTransform;
static O2Point O2PointApplyAffineTransform(O2Point p,O2AffineTransform t){return (O2Point){t.a*p.x+t.c*p.y+t.tx,t.b*p.x+t.d*p.y+t.ty};}
typedef enum {kO2PathElementMoveToPoint,kO2PathElementAddLineToPoint,kO2PathElementAddQuadCurveToPoint,kO2PathElementAddCurveToPoint,kO2PathElementCloseSubpath} O2PathElementType;
typedef struct {int elements,points;unsigned char types[64];O2Point coords[192];} O2Path;
static int O2PathNumberOfElements(O2Path *p){return p->elements;}
static const unsigned char *O2PathElements(O2Path *p){return p->types;}
static const O2Point *O2PathPoints(O2Path *p){return p->coords;}
typedef struct {int count;O2Point edges[200000][2];} O2Context_builtin;
static void O2DContextAddEdge(O2Context_builtin *c,O2Point a,O2Point b){assert(c->count<200000);c->edges[c->count][0]=a;c->edges[c->count][1]=b;c->count++;}
''' + vgmath + helpers + r'''
typedef struct VGPath {O2Path *_path;int _vertexCount,_vertexCapacity;struct Vertex *_vertices;int _segmentToVertexCapacity;struct VertexIndex *_segmentToVertex;
 O2Float m_userMinx,m_userMiny,m_userMaxx,m_userMaxy;BOOL _positionsOnly;} VGPath;
''' + function(production, 'int O2PathElementTypeToNumCoordinates(') + '\n'
src += 'static void VGPathTessellatePositionsIfNeeded(VGPath *self);\nstatic void VGPathTessellate(VGPath *self);\n'
src += block(production, newNames, '')
src += block(reference, names, 'reference')
src += r'''
static unsigned rng=2024;
static double coord(void){rng=rng*1664525u+1013904223u;return (rng%4000)/40.-20;}
static VGPath *create(O2Path *p){VGPath *v=calloc(1,sizeof(*v));v->_path=p;v->_vertexCapacity=4;v->_vertices=malloc(4*sizeof(Vertex));return v;}
static void destroy(VGPath *v){free(v->_vertices);free(v->_segmentToVertex);free(v);}
static O2Context_builtin a,b,c;
// Field by field: Vertex has padding that AddVertex leaves unset.
static bool sameVertices(const Vertex *x,const Vertex *y,int n){for(int i=0;i<n;i++)if(memcmp(&x[i].userPosition,&y[i].userPosition,sizeof(O2Point))||memcmp(&x[i].userTangent,&y[i].userTangent,sizeof(O2Point))||memcmp(&x[i].pathLength,&y[i].pathLength,sizeof(O2Float))||x[i].flags!=y[i].flags)return false;return true;}
int main(void){setbuf(stdout,NULL);
 unsigned paths=0;unsigned long edges=0;
 O2AffineTransform transforms[2]={{1,0,0,1,0,0},{0.7,-0.3,0.45,1.3,12.25,-3.5}};
 for(int trial=0;trial<3000;trial++){
  O2Path p;memset(&p,0,sizeof(p));int n=1+trial%20;O2Point last={coord(),coord()};
  p.types[p.elements++]=kO2PathElementMoveToPoint;p.coords[p.points++]=last;
  for(int e=1;e<n;e++){
   rng=rng*1664525u+1013904223u;int kind=rng%9;
   int k=kind<2?kO2PathElementAddLineToPoint:kind<4?kO2PathElementAddQuadCurveToPoint:kind<6?kO2PathElementAddCurveToPoint:kind==6?kO2PathElementCloseSubpath:kind==7?kO2PathElementMoveToPoint:kO2PathElementAddCurveToPoint;
   p.types[p.elements++]=k;int count=O2PathElementTypeToNumCoordinates(k);
   for(int j=0;j<count;j++){O2Point q={coord(),coord()};if(kind==8)q=last;if(trial%7==0&&j==0)q=last;p.coords[p.points++]=q;last=q;}
  }
  for(int t=0;t<2;t++){
   VGPath *fill=create(&p),*full=create(&p),*old=create(&p);
   a.count=b.count=c.count=0;
   VGPathFill(fill,transforms[t],&a);assert(fill->_positionsOnly);
   VGPathTessellateIfNeeded(full);assert(!full->_positionsOnly);VGPathFill(full,transforms[t],&b);
   referenceVGPathFill(old,transforms[t],&c);
   assert(a.count==c.count&&b.count==c.count);
   assert(!memcmp(a.edges,c.edges,sizeof(a.edges[0])*c.count)&&!memcmp(b.edges,c.edges,sizeof(b.edges[0])*c.count));
   // A later stroke or query upgrades a fill-only tessellation to the full one.
   VGPathTessellateIfNeeded(fill);assert(!fill->_positionsOnly);
   assert(fill->_vertexCount==full->_vertexCount&&fill->_vertexCount==old->_vertexCount);
   assert(sameVertices(fill->_vertices,full->_vertices,full->_vertexCount));
   assert(sameVertices(fill->_vertices,old->_vertices,old->_vertexCount));
   assert(!memcmp(fill->_segmentToVertex,full->_segmentToVertex,sizeof(VertexIndex)*p.elements));
   assert(fill->m_userMinx==full->m_userMinx&&fill->m_userMiny==full->m_userMiny&&fill->m_userMaxx==full->m_userMaxx&&fill->m_userMaxy==full->m_userMaxy);
   paths++;edges+=c.count;destroy(fill);destroy(full);destroy(old);
  }
 }
 printf("PASS %u paths, %lu fill edges identical to the old VGPathFill; upgraded tessellations identical\n",paths,edges);return 0;
}
'''
with tempfile.TemporaryDirectory(prefix='vgpath-fill-') as folder:
    folder = Path(folder)
    for scalar in ['float', 'double']:
        path = folder / (scalar + '.c')
        path.write_text(src.replace('typedef double O2Float;', 'typedef ' + scalar + ' O2Float;'))
        binary = folder / scalar
        # The tessellator's own text has unused locals and '// ... \\' comments in #if 0 blocks.
        subprocess.run(['cc', '-std=c11', '-D_DEFAULT_SOURCE', '-O2', '-Wall', '-Wextra', '-Werror', '-Wno-sign-compare',
                        '-Wno-unused-function', '-Wno-unused-parameter', '-Wno-unused-variable',
                        '-Wno-unused-but-set-variable', '-Wno-comment',
                        '-fsanitize=address,undefined,float-cast-overflow', str(path), '-lm', '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True, env={**os.environ, 'ASAN_OPTIONS': 'detect_leaks=0', 'UBSAN_OPTIONS': 'halt_on_error=1'})
