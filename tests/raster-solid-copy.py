#!/usr/bin/env python3
"""Production constant paint, float span and surface conversions vs prior span.
Native adapters supply storage/dispatch only; guest pixel gate remains required.
"""
from pathlib import Path
import argparse, os, subprocess, tempfile
p=argparse.ArgumentParser();p.add_argument('--reference',type=Path,required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[1]
fixture=root/'tests/surface-constant-span.py';ns={'__file__':str(fixture)}
exec(compile(fixture.read_text().split('with tempfile.TemporaryDirectory',1)[0],str(fixture),'exec'),ns)
src=ns['src'].split('int main(void)',1)[0]
function=ns['function']
src=src.replace('typedef bool BOOL;', '#define YES true\n#define NO false\n#define nil NULL\n#define COVERAGE_MULTIPLIER 256\n#define ONYX2D_STATIC static\n#define ONYX2D_STATIC_INLINE static inline\ntypedef bool BOOL;')
src+=r'''
typedef struct O2Paint{int(*_paint_largb32f_PRE)(struct O2Paint*,int,int,O2argb32f*,int);O2argb32f _argb32f_PRE;int skip;}O2Paint;
typedef O2Paint O2Paint_color;
typedef void(*O2BlendSpan_argb32f)(O2argb32f*,O2argb32f*,int);
static unsigned requests,reads;
static O2Float zeroToOneFromCoverage(int c){return c/256.0f;}
static int O2PaintReadSpan_largb32f_PRE(O2Paint*p,int x,int y,O2argb32f*out,int n){requests++;return p->_paint_largb32f_PRE(p,x,y,out,n);}
static BOOL O2SurfaceCanReadWriteARGB8u(O2Surface*s){return s->byte;}
static void O2Image_read_argb32f(O2Surface*s,int x,int y,O2argb32f*out,int n){reads++;if(!s->byte){memcpy(out,s->_pixelBytes+y*s->_bytesPerRow+x*16,n*16);return;}for(int i=0;i<n;i++){unsigned char*b=s->_pixelBytes+y*s->_bytesPerRow+(x+i)*4;out[i]=O2argb32fInit(b[3]/255.f,b[0]/255.f,b[1]/255.f,b[2]/255.f);}}
static void O2ImageReadSpan_Af_MASK(O2Surface*s,int x,int y,O2Float*out,int n){(void)s;for(int i=0;i<n;i++)out[i]=((x+i+y)%4)/3.;}
'''
for name in ['ONYX2D_STATIC int color_largb32f_PRE(', 'BOOL O2PaintGetConstantColor(']:src+=function(Path('Onyx2D/O2Paint_color.m'),name)+'\n'
src+=r'''
static int varying(O2Paint*p,int x,int y,O2argb32f*out,int n){(void)y;if(x==p->skip)return -1;if(p->skip>x&&p->skip<x+n)n=p->skip-x;for(int i=0;i<n;i++)out[i]=p->_argb32f_PRE;return n;}
'''
for path,name in [('O2argb32f.m','void O2BlendSpanCopy_ffff('),('O2argb32f.m','void O2BlendSpanNormal_ffff('),('O2Context_builtin.m','ONYX2D_STATIC void O2ApplyCoverageAndMaskToSpan_largb32f_PRE('),('O2Context_builtin.m','ONYX2D_STATIC void O2ApplyCoverageToSpan_largb32f_PRE('),('O2Context_builtin.m','O2RasterizeWriteCoverageSpanffff(')]:src+=('static void ' if name=='O2RasterizeWriteCoverageSpanffff(' else '')+function(Path('Onyx2D')/path,name)+'\n'
s=a.reference.read_text();i=s.index('O2RasterizeWriteCoverageSpanffff(');j=s.index('// Both text backends',i)
src+='static void '+s[i:j].replace('O2RasterizeWriteCoverageSpanffff(', 'referenceSpan(',1)
src+=r'''
int main(void){setbuf(stdout,NULL);unsigned cases=0;
 for(int mode=0;mode<5;mode++)for(int blend=0;blend<2;blend++)for(int masked=0;masked<2;masked++)for(int coverage=0;coverage<=256;coverage++)for(int paintKind=0;paintKind<2;paintKind++)for(int variant=0;variant<2;variant++){
  O2Surface s,r,mask;init(&s,mode);r=s;r._pixelBytes=r.bytes;init(&mask,4);
  O2Paint paint={paintKind?varying:color_largb32f_PRE,O2argb32fInit(randomFloat(),randomFloat(),randomFloat(),randomFloat()),100};
  if(variant)paint._argb32f_PRE=O2argb32fInit(NAN,INFINITY,-INFINITY,-0.f);
  O2BlendSpan_argb32f op=blend?O2BlendSpanNormal_ffff:O2BlendSpanCopy_ffff;
  requests=reads=0;O2RasterizeWriteCoverageSpanffff(&s,masked?&mask:NULL,&paint,2,1,coverage,300,op);
  if(mode!=4&&!blend&&!masked&&coverage==256&&!paintKind)assert(requests==0&&reads==0);
  referenceSpan(&r,masked?&mask:NULL,&paint,2,1,coverage,300,op);
  assert(!memcmp(s.bytes,r.bytes,sizeof(s.bytes)));cases++;
 }
 O2Surface s;O2Paint paint={color_largb32f_PRE,O2argb32fInit(1,.82,.82,.82),-1};double seconds[2];unsigned counts[2];
 for(int old=0;old<2;old++){init(&s,2);requests=0;double start=now();for(int i=0;i<10000;i++){if(old)referenceSpan(&s,NULL,&paint,0,0,256,320,O2BlendSpanCopy_ffff);else O2RasterizeWriteCoverageSpanffff(&s,NULL,&paint,0,0,256,320,O2BlendSpanCopy_ffff);}seconds[old]=now()-start;counts[old]=requests;}
 printf("PASS %u exact solid/procedural, byte/float, copy/normal, mask, coverage, exceptional comparisons; solid copy candidate %.3f ms %u paint spans, reference %.3f ms %u paint spans\n",cases,seconds[0]*1000,counts[0],seconds[1]*1000,counts[1]);
 assert(counts[0]==0&&counts[1]>0);return 0;
}
'''
with tempfile.TemporaryDirectory(prefix='solid-copy-') as folder:
 folder=Path(folder);path=folder/'probe.c';path.write_text(src)
 for opt in ['-O0','-O2']:
  binary=folder/('probe'+opt)
  subprocess.run(['cc','-std=c11','-D_POSIX_C_SOURCE=200809L',opt,'-Wall','-Wextra','-Werror','-Wno-unused-parameter','-fsanitize=address,undefined',str(path),'-lm','-o',str(binary)],check=True)
  subprocess.run([str(binary)],check=True,env={**os.environ,'ASAN_OPTIONS':'detect_leaks=0','UBSAN_OPTIONS':'halt_on_error=1'})
