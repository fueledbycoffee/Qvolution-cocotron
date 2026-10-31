#!/usr/bin/env python3
"""Differential production float-span execution with byte/float memory adapters."""
import argparse, os, subprocess, tempfile
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--reference',type=Path,required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[1]
fixture=root/'tests/float-bitmap/draw-source.py'
ns={'__file__':str(fixture)}
exec(compile(fixture.read_text().split("src+=ft+r'''",1)[0],str(fixture),'exec'),ns)
src=ns['src'].split('void O2ContextWriteGlyphCoverageSpanFloat(',1)[0]
src=src.replace('int width,height; } O2Surface;', 'int width,height; bool byte; } O2Surface;')
src=src.replace('(void)s; return false;', 'return s->byte;')
src=src.replace('assert(x>=0&&y>=0&&x+n<=s->width&&y<s->height);memcpy(dst,s->bytes[y]+16*x,16*n);return NULL;', '''reads++;assert(x>=0&&y>=0&&x+n<=s->width&&y<s->height);
 if(s->byte){for(int i=0;i<n;i++){unsigned char *b=s->bytes[y]+4*(x+i);dst[i]=O2argb32fInit(b[0]/255.f,b[1]/255.f,b[2]/255.f,b[3]/255.f);}}
 else memcpy(dst,s->bytes[y]+16*x,16*n);return NULL;''')
src=src.replace('assert(x>=0&&y>=0&&x+n<=s->width&&y<s->height);memcpy(s->bytes[y]+16*x,src,16*n);', '''assert(x>=0&&y>=0&&x+n<=s->width&&y<s->height);
 if(s->byte){for(int i=0;i<n;i++){unsigned char *b=s->bytes[y]+4*(x+i);b[0]=toByte(src[i].r);b[1]=toByte(src[i].g);b[2]=toByte(src[i].b);b[3]=toByte(src[i].a);}}
 else memcpy(s->bytes[y]+16*x,src,16*n);''')
src=src.replace('static O2argb32f *O2Image_read_argb32f', '''static unsigned reads;
static unsigned char toByte(float v){if(!(v>0))return 0;if(v>=1)return 255;return floorf(v*255+.5f);}
static O2argb32f *O2Image_read_argb32f''')
old=a.reference.read_text();start=old.index('O2RasterizeWriteCoverageSpanffff(');end=old.index('// Both text backends',start)
old=old[start:end].replace('O2RasterizeWriteCoverageSpanffff(', 'referenceSpan(',1)
src+='static void '+old
src+=r'''
#include <time.h>
static unsigned rng=12345;
static float randomFloat(void){rng=rng*1664525u+1013904223u;return (rng%4001)/1000.f-1;}
static void init(O2Surface *s,bool byte){memset(s,0xa7,sizeof(*s));s->width=320;s->height=4;s->byte=byte;for(int y=0;y<4;y++)for(int x=0;x<320;x++){if(byte){for(int c=0;c<4;c++)s->bytes[y][4*x+c]=(unsigned char)(rng++);}else{O2argb32f f=O2argb32fInit(randomFloat(),randomFloat(),randomFloat(),randomFloat());memcpy(s->bytes[y]+x*16,&f,16);}}}
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
int main(void){setbuf(stdout,NULL);unsigned cases=0;
 for(int byte=0;byte<2;byte++)for(int blend=0;blend<2;blend++)for(int masked=0;masked<2;masked++)for(int coverage=0;coverage<=256;coverage++)for(int variant=0;variant<3;variant++){
  O2Surface s,r,mask;init(&s,byte);r=s;init(&mask,false);
  O2Paint paint={NULL,{randomFloat(),randomFloat(),randomFloat(),randomFloat()},variant==1?100:-1};
  if(variant==2)paint.color=O2argb32fInit(NAN,INFINITY,-INFINITY,-0.f);
  O2BlendSpan_argb32f op=blend?O2BlendSpanNormal_ffff:O2BlendSpanCopy_ffff;
  reads=0;O2RasterizeWriteCoverageSpanffff(&s,masked?&mask:NULL,&paint,2,1,coverage,300,op);
  unsigned candidateReads=reads;reads=0;referenceSpan(&r,masked?&mask:NULL,&paint,2,1,coverage,300,op);
  assert(!memcmp(s.bytes,r.bytes,sizeof(s.bytes)));
  if(byte&&!blend&&!masked&&coverage==256)assert(candidateReads==0&&reads>0);
  else assert(candidateReads==reads);
  cases++;
 }
 O2Surface s;O2Paint paint={NULL,{1,.82,.82,.82},-1};double seconds[2];unsigned counts[2];
 for(int old=0;old<2;old++){init(&s,true);reads=0;double start=now();for(int i=0;i<5000;i++){if(old)referenceSpan(&s,NULL,&paint,0,0,256,320,O2BlendSpanCopy_ffff);else O2RasterizeWriteCoverageSpanffff(&s,NULL,&paint,0,0,256,320,O2BlendSpanCopy_ffff);}seconds[old]=now()-start;counts[old]=reads;}
 printf("PASS %u exact byte/float span comparisons, all coverage values, copy/normal, masks, skip spans, exceptional sources; full copy candidate %.3f ms %u reads, reference %.3f ms %u reads\n",cases,seconds[0]*1000,counts[0],seconds[1]*1000,counts[1]);return 0;
}
'''
with tempfile.TemporaryDirectory(prefix='full-copy-') as folder:
 folder=Path(folder);path=folder/'probe.c'
 for scalar in ['float','double']:
  path.write_text(src.replace('typedef float O2Float;', 'typedef '+scalar+' O2Float;'))
  for opt in ['-O0','-O2']:
   binary=folder/('probe-'+scalar+opt)
   subprocess.run(['cc','-std=c11','-D_POSIX_C_SOURCE=200809L',opt,'-Wall','-Wextra','-Werror','-Wno-unused-parameter','-Wno-unused-function','-Wno-misleading-indentation','-fsanitize=address,undefined',str(path),'-lm','-o',str(binary)],check=True)
   print('MODEL',scalar,opt,flush=True)
   subprocess.run([str(binary)],check=True,env={**os.environ,'ASAN_OPTIONS':'detect_leaks=0','UBSAN_OPTIONS':'halt_on_error=1'})
