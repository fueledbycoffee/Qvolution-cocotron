#!/usr/bin/env python3
"""Compare exact production sweeps to the supplied old source with native adapters.
Reuses the existing raster fixture extraction; no guest or Objective-C claim.
"""
import argparse
import re
from pathlib import Path
import os
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--reference', type=Path, required=True)
parser.add_argument('--source', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
fixture = root / 'tests/float-bitmap/raster-samples-source.py'
namespace = {'__file__': str(fixture), 'production': str(args.source or root / 'Onyx2D/O2Context_builtin.m')}
extract = fixture.read_text().split("out=Path(tempfile.mkdtemp", 1)[0]
extract = extract.replace("source=(root/'Onyx2D/O2Context_builtin.m').read_text()", 'source=Path(production).read_text()')
exec(compile(extract, str(fixture), 'exec'), namespace)
source = namespace['src'].split('int main(void)', 1)[0]
reference = args.reference.read_text()
# The reference sweep with its own edge-list helpers, renamed: production
# helpers may store per-edge state the old sweep does not expect.
a = reference.index('ONYX2D_STATIC_INLINE void sortEdgesByMinY')
b = reference.index('\nvoid O2DContextClipAndFillEdges(', a)
old = reference[a:b]
for name in ['sortEdgesByMinY', 'initEdgeForAET', 'incrementEdgeForAET', 'removeEdgeFromAET',
             'CoverageNode', 'writeCoverageNode']:
    old = re.sub(r'\b%s\b' % name, 'reference_' + name, old)
old = re.sub(r'\bO2DContextFillEdgesOnSurface\b', 'referenceFillEdgesOnSurface', old)
# Span order and extent, not only final pixels: incrementally evaluated paints
# (gradients, images) see span starts.
source = source.replace('static void writeCoverage(O2Surface *s,O2Surface *mask,O2Paint *p,int x,int y,int cov,int n,void *blend){',
    'static unsigned long long spanHash;static void writeCoverage(O2Surface *s,O2Surface *mask,O2Paint *p,int x,int y,int cov,int n,void *blend){'
    '{int v[4]={x,y,cov,n};for(int i=0;i<4;i++){spanHash^=(unsigned)v[i];spanHash*=1099511628211ULL;}}', 1)
assert 'spanHash^=' in source
source = source.replace('sampleIndex++;', 'sampleIndex++; sampleVisits++;')
old = old.replace('sampleIndex++;', 'sampleIndex++; sampleVisits++;')
source = source.replace('void O2DContextFillEdgesOnSurface(', 'static unsigned long long sampleVisits;\nvoid O2DContextFillEdgesOnSurface(', 1)
source += old
source += r'''
#include <time.h>
static unsigned rng=12345;
static double randomCoord(void){rng=rng*1664525u+1013904223u;return (rng%9600)/100.-16;}
static void polygon(O2Context_builtin *c,const O2Point *p,int n){for(int i=0;i<n;i++)O2DContextAddEdge(c,p[i],p[(i+1)%n]);}
static void render(O2Context_builtin *c,O2Surface *s,int reference,int rule){if(reference)referenceFillEdgesOnSurface(c,s,c->_clipContext?c->_clipContext->_surface:NULL,NULL,rule);else O2DContextFillEdgesOnSurface(c,s,c->_clipContext?c->_clipContext->_surface:NULL,NULL,rule);O2RasterizerClear(c);}
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
int main(void){setbuf(stdout,NULL);
 unsigned cases=0;
 for(int quality=1;quality<=256;quality*=2)for(int mode=0;mode<4;mode++){
  O2Context_builtin a,b,clip;O2Surface sa,sb,sc;init(&a,&sa,64,48);init(&b,&sb,64,48);init(&clip,&sc,64,48);
  O2RasterizerSetShouldAntialias(&a,YES,quality);O2RasterizerSetShouldAntialias(&b,YES,quality);
  if(mode&1){O2RasterizerSetViewport(&a,7,9,41,31);O2RasterizerSetViewport(&b,7,9,41,31);}
  if(mode&2){assert(allocateClipSamplesForTest(&a));assert(allocateClipSamplesForTest(&b));assert(allocateClipSamplesForTest(&clip));for(int i=0;i<64*48;i++){sc.pixels[i]=O2argb32fInit(.5,.5,.5,.5);for(int w=0;w<8;w++)clip._clipSamples[i*8+w]=0xaaaaaaaa;}a._clipContext=b._clipContext=&clip;}
  for(int trial=0;trial<150;trial++){
   O2Point p[6];int n=3+trial%4;for(int j=0;j<n;j++)p[j]=(O2Point){randomCoord(),randomCoord()};
   // Closed self-intersections, offscreen geometry, degenerate and thin marks.
   if(trial%3==0){double x=randomCoord(),y=randomCoord();p[0]=(O2Point){x,y};p[1]=(O2Point){x+1,y};p[2]=(O2Point){x+1,y+8};p[3]=(O2Point){x,y+8};n=4;}
   if(trial%19==0){for(int j=0;j<n;j++)p[j].x=10;}
   polygon(&a,p,n);polygon(&b,p,n);int rule=trial&1?1:-1;spanHash=0;render(&a,&sa,0,rule);unsigned long long spans=spanHash;spanHash=0;render(&b,&sb,1,rule);
   assert(spans==spanHash);
   assert(!memcmp(sa.pixels,sb.pixels,64*48*sizeof(O2argb32f)));
   if(a._clipSamples)assert(!memcmp(a._clipSamples,b._clipSamples,64*48*8*sizeof(uint32_t)));
   for(int i=0;i<64*256+1;i++)assert(a._winding[i]==0&&b._winding[i]==0);
   for(int i=0;i<64;i++)assert(a._increase[i]==INT_MAX&&b._increase[i]==INT_MAX);
   cases++;
  }
  dispose(&a);dispose(&b);dispose(&clip);
 }
 unsigned long long visits[2];double seconds[2];
 for(int old=0;old<2;old++){
  O2Context_builtin c;O2Surface s;init(&c,&s,1024,48);O2RasterizerSetShouldAntialias(&c,YES,256);sampleVisits=0;double started=now();
  for(int repeat=0;repeat<20;repeat++)for(int tick=0;tick<100;tick++){
   double x=5+tick*9,y=5.25;O2Point outer[]={{x-.5,y-.5},{x+1.5,y-.5},{x+1.5,y+8.5},{x-.5,y+8.5}};
   O2Point inner[]={{x+.5,y+.5},{x+.5,y+7.5},{x+.5,y+7.5},{x+.5,y+.5}};
   polygon(&c,outer,4);polygon(&c,inner,4);render(&c,&s,old,-1);
  }
  seconds[old]=now()-started;visits[old]=sampleVisits;dispose(&c);
 }
 printf("PASS %u exact pixel/sample/state comparisons; candidate %.3f ms %llu samples; reference %.3f ms %llu samples\n",cases,seconds[0]*1000,visits[0],seconds[1]*1000,visits[1]);
 assert(visits[0]*4<visits[1]);
 puts("PASS painted sweep bounds preserve raster output and reduce thin-mark sample work by >4x");return 0;
}
'''
# Existing fixture models allocation directly; add a small test-only adapter.
source = source.replace('#include <time.h>', '''static int allocateClipSamplesForTest(O2Context_builtin *c){c->_clipSamples=calloc(c->_surface->width*c->_surface->height,8*sizeof(uint32_t));return c->_clipSamples!=NULL;}
#include <time.h>''')
with tempfile.TemporaryDirectory(prefix='painted-bounds-') as folder:
    folder = Path(folder)
    for scalar in ['float', 'double']:
        path = folder / (scalar + '.c')
        path.write_text(source.replace('typedef double O2Float;', 'typedef '+scalar+' O2Float;'))
        binary = folder / scalar
        subprocess.run(['cc', '-std=c11', '-D_POSIX_C_SOURCE=200809L', '-O2',
                        '-Wall', '-Wextra', '-Werror', '-Wno-sign-compare', '-Wno-unused-function',
                        '-fsanitize=address,undefined,float-cast-overflow', str(path), '-lm', '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True, env={**os.environ, 'ASAN_OPTIONS':'detect_leaks=0', 'UBSAN_OPTIONS':'halt_on_error=1'})
