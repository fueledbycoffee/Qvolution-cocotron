#!/usr/bin/env python3
"""Exact source writers: constant span replication vs normal per-pixel output."""
from pathlib import Path
import os, subprocess, tempfile
root=Path(__file__).resolve().parents[1]
def function(path,name):
 text=(root/path).read_text();a=text.index(name);a=text.rfind('\n',0,a)+1;b=text.index('{',a)+1;depth=1
 while depth:depth+=(text[b]=='{')-(text[b]=='}');b+=1
 return text[a:b]
header=(root/'Onyx2D/include/Onyx2D/O2argb32f.h').read_text()
arithmetic=header[header.index('typedef float O2Float32;'):header.index('static inline O2argb32f O2argb32fSubtract')]
src=r'''
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdio.h>
#include <assert.h>
#include <time.h>
typedef bool BOOL;typedef double O2Float;
#define MIN(a,b) ((a)<(b)?(a):(b))
#define MAX(a,b) ((a)>(b)?(a):(b))
#define RI_INT_MIN MIN
#define RI_INT_MAX MAX
#define RI_FLOOR_TO_INT(v) ((int)floor(v))
'''+arithmetic+function(Path('Onyx2D/include/Onyx2D/O2argb32f.h'),'static inline uint8_t O2ByteFromFloat(')+r'''
typedef struct{uint8_t b,g,r,a;} O2argb8u;
typedef struct O2Surface{uint8_t bytes[3*5280];uint8_t *_pixelBytes;size_t _bytesPerRow;int bits;bool byte;void(*_writeargb32f)(struct O2Surface*,int,int,O2argb32f*,int);void(*_writeargb8u)(struct O2Surface*,int,int,O2argb8u*,int);}O2Surface;
'''
for name in ['static void O2SurfaceWrite_argb32f_to_argb8u(', 'static void O2SurfaceWrite_argb32f_to_ABGR8888(', 'static void O2SurfaceWrite_argb8u_to_BGRA8888(', 'static void O2SurfaceWrite_argb8u_to_ARGB8888(', 'static void O2SurfaceWrite_argb32f_to_argb8u_to_ANY(', 'void O2SurfaceWriteSpan_largb32f_PRE(']:src+=function(Path('Onyx2D/O2Surface.m'),name)+'\n'
src+=r'''
static void rawFloat(O2Surface*s,int x,int y,O2argb32f*span,int n){memcpy(s->_pixelBytes+y*s->_bytesPerRow+x*16,span,n*16);}
static unsigned rng=12345;static float randomFloat(void){rng=rng*1664525u+1013904223u;return (rng%4001)/1000.f-1;}
static void init(O2Surface*s,int mode){memset(s,0,sizeof(*s));memset(s->bytes,0xa7,sizeof(s->bytes));s->_pixelBytes=s->bytes;s->_bytesPerRow=5280;s->bits=mode==4?128:32;s->byte=mode!=4;s->_writeargb32f=mode==0?O2SurfaceWrite_argb32f_to_argb8u:mode==1?O2SurfaceWrite_argb32f_to_ABGR8888:mode==4?rawFloat:O2SurfaceWrite_argb32f_to_argb8u_to_ANY;s->_writeargb8u=mode==3?O2SurfaceWrite_argb8u_to_ARGB8888:O2SurfaceWrite_argb8u_to_BGRA8888;}
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
int main(void){setbuf(stdout,NULL);O2argb32f span[320];unsigned cases=0;
 for(int mode=0;mode<5;mode++)for(int n=0;n<=300;n++)for(int variant=0;variant<4;variant++){
  O2Surface a,b;init(&a,mode);init(&b,mode);
  O2argb32f color=O2argb32fInit(randomFloat(),randomFloat(),randomFloat(),randomFloat());
  if(variant==3)color=O2argb32fInit(NAN,INFINITY,-INFINITY,-0.f);
  for(int i=0;i<320;i++)span[i]=color;
  if(variant==1)span[n/2].r=randomFloat();
  if(variant==2)for(int i=0;i<320;i++)span[i].g=randomFloat();
  O2SurfaceWriteSpan_largb32f_PRE(&a,2,1,span,n);if(n)b._writeargb32f(&b,2,1,span,n);
  assert(!memcmp(a.bytes,b.bytes,sizeof(a.bytes)));cases++;
 }
 for(int i=0;i<320;i++)span[i]=O2argb32fInit(.82,.82,.82,1);
 O2Surface s;init(&s,2);double seconds[2];
 for(int old=0;old<2;old++){double start=now();for(int i=0;i<10000;i++){if(old)s._writeargb32f(&s,0,1,span,320);else O2SurfaceWriteSpan_largb32f_PRE(&s,0,1,span,320);}seconds[old]=now()-start;}
 printf("PASS %u exact constant/varying/exceptional span comparisons in RGBA/ABGR/BGRA/ARGB/float with row guards; candidate %.3f ms reference %.3f ms\n",cases,seconds[0]*1000,seconds[1]*1000);return 0;
}
'''
with tempfile.TemporaryDirectory(prefix='constant-span-') as folder:
 folder=Path(folder);path=folder/'probe.c';path.write_text(src)
 for opt in ['-O0','-O2']:
  binary=folder/('probe'+opt)
  subprocess.run(['cc','-std=c11','-D_POSIX_C_SOURCE=200809L',opt,'-Wall','-Wextra','-Werror','-fsanitize=address,undefined',str(path),'-lm','-o',str(binary)],check=True)
  subprocess.run([str(binary)],check=True,env={**os.environ,'ASAN_OPTIONS':'detect_leaks=0','UBSAN_OPTIONS':'halt_on_error=1'})
