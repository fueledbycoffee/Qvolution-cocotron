"""Run actual C-only PNG helpers and fallback, not a substitute CGImage provider."""
from pathlib import Path
import subprocess, tempfile, importlib.util, os, sys
sys.dont_write_bytecode=True
import argparse
ap=argparse.ArgumentParser();ap.add_argument('output',type=Path);args=ap.parse_args();notes=args.output.resolve();notes.mkdir(exist_ok=True,parents=True);repo=Path(__file__).resolve().parents[1];text=(repo/'Onyx2D/O2Encoder_PNG.m').read_text()
header=(repo/'Onyx2D/include/Onyx2D/O2Image.h').read_text();enum=header[header.index('#define kO2BitmapAlphaInfoMask'):header.index('#import <Onyx2D/O2ColorSpace.h>')]
helper=text[text.index('static unsigned char *O2PNGCopyPixels'):text.index('static unsigned char *O2PNGCopyImagePixels')]
fallback=text[text.index('typedef unsigned int stbiw_uint32;'):text.rindex('void O2PNGEncoderWriteImage(')]
fixture=(repo/'tests/imageio-png-encode-contract.m').read_text();case_decl=fixture[fixture.index('typedef struct'):fixture.index('static CGImageRef imageFor')].replace('CGImageAlphaInfo','O2ImageAlphaInfo').replace('CGBitmapInfo','O2BitmapInfo').replace('kCG','kO2')
preamble='''#include <assert.h>
#include <stdint.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
typedef int BOOL;
#define YES 1
#define NO 0
static long alloc_fail=-1, allocations=0, live=0;
static void *test_malloc(size_t n){if(allocations++==alloc_fail)return NULL;void *p=malloc(n);if(p)live++;return p;}
static void *test_calloc(size_t n,size_t s){if(allocations++==alloc_fail)return NULL;void *p=calloc(n,s);if(p)live++;return p;}
static void *test_realloc(void *p,size_t n){if(allocations++==alloc_fail)return NULL;void *q=realloc(p,n);if(q&&!p)live++;return q;}
static void test_free(void *p){if(p){live--;free(p);}}
#define free test_free
#define malloc test_malloc
#define calloc test_calloc
#define realloc test_realloc
'''
main=r'''
static void vectors(const char *dir) {
 for(unsigned c=0;c<sizeof(cases)/sizeof(cases[0]);c++) {
  Case v=cases[c];unsigned char source[58];memset(source,0xD3,sizeof(source));size_t stride=6*v.channels+5;
  for(int y=0;y<2;y++)for(int x=0;x<6;x++) {
   unsigned alphas[]={0,1,64,128,254,255}, a=alphas[x];
   unsigned rgb[]={31+x*29,193-y*67-x*11,17+y*109+x*7};
   int pm=v.alpha==kO2ImageAlphaPremultipliedFirst||v.alpha==kO2ImageAlphaPremultipliedLast;
   int ha=pm||v.alpha==kO2ImageAlphaFirst||v.alpha==kO2ImageAlphaLast;
   int first=v.alpha==kO2ImageAlphaFirst||v.alpha==kO2ImageAlphaPremultipliedFirst||v.alpha==kO2ImageAlphaNoneSkipFirst;
   unsigned char pixel[4];for(unsigned i=0;i<3;i++)pixel[i+first]=pm?(rgb[i]*a+127)/255:rgb[i];
   if(v.channels==4){pixel[first?0:3]=ha?a:0xAB;if(v.order==kO2BitmapByteOrder32Little)for(int i=0;i<2;i++){unsigned char t=pixel[i];pixel[i]=pixel[3-i];pixel[3-i]=t;}}
   memcpy(source+y*stride+x*v.channels,pixel,v.channels);
  }
  unsigned char old[58];memcpy(old,source,58);size_t channels=0;
  unsigned char *out=O2PNGCopyPixels(source,2*stride,6,2,8,v.channels*8,stride,v.alpha|v.order,&channels);
  assert(out&&channels==(v.channels==4&&c<8?4:3));assert(!memcmp(source,old,58));
  char path[4096];snprintf(path,sizeof(path),"%s/%s.raw",dir,v.name);FILE *f=fopen(path,"wb");assert(f);assert(fwrite(out,1,6*2*channels,f)==6*2*channels);fclose(f);
  int length=0;unsigned char *png=stbi_write_png_to_mem(out,6,2,channels,&length);assert(png&&length>0);
  snprintf(path,sizeof(path),"%s/%s.png",dir,v.name);f=fopen(path,"wb");assert(f);assert(fwrite(png,1,length,f)==(size_t)length);fclose(f);free(png);free(out);
 }
}
static void errors(void) {
 unsigned char bytes[8]={19,27,33,128};size_t n=0;
 #define BAD(data,length,w,h,bpc,bpp,stride,info) assert(!O2PNGCopyPixels(data,length,w,h,bpc,bpp,stride,info,&n))
 BAD(NULL,4,1,1,8,32,4,kO2ImageAlphaLast);
 BAD(bytes,3,1,1,8,32,4,kO2ImageAlphaLast);
 BAD(bytes,8,1,2,8,32,5,kO2ImageAlphaLast);
 BAD(bytes,8,1,2,8,32,3,kO2ImageAlphaLast);
 BAD(bytes,8,1,1,16,48,6,kO2ImageAlphaNone);
 BAD(bytes,8,0,1,8,32,4,kO2ImageAlphaLast);
 BAD(bytes,SIZE_MAX,1,3,8,32,SIZE_MAX,kO2ImageAlphaLast);
 BAD(bytes,8,1,1,8,32,4,kO2ImageAlphaLast|kO2BitmapByteOrder16Big);
 BAD(bytes,8,1,1,8,32,4,kO2ImageAlphaLast|kO2BitmapFloatComponents);
 BAD(bytes,8,1,1,8,32,4,kO2ImageAlphaOnly);
 BAD(bytes,8,1,1,8,24,3,kO2ImageAlphaNoneSkipFirst);
 BAD(bytes,8,1,1,8,24,3,kO2ImageAlphaNone|kO2BitmapByteOrder32Little);
 // Last-row padding is not required, but every pixel byte must exist.
 unsigned char *out=O2PNGCopyPixels(bytes,8,1,2,8,32,4,kO2ImageAlphaLast,&n);assert(out);free(out);
 allocations=0;alloc_fail=0;BAD(bytes,8,1,1,8,32,4,kO2ImageAlphaLast);alloc_fail=-1;
 // All actual malloc/calloc/realloc sites in fallback must unwind on failure.
 unsigned char rgba[48];for(int i=0;i<48;i++)rgba[i]=(unsigned char)(17*i);int length;
 allocations=0;unsigned char *png=stbi_write_png_to_mem(rgba,6,2,4,&length);assert(png);free(png);long count=allocations;
 for(long i=0;i<count;i++){allocations=0;alloc_fail=i;png=stbi_write_png_to_mem(rgba,6,2,4,&length);assert(!png);assert(live==0);}
 alloc_fail=-1;printf("PASS actual fallback %ld allocation failure points and normalizer bounds/layout errors\n",count);
}
int main(int argc,char **argv){assert(argc==2);errors();vectors(argv[1]);puts("PASS actual C helpers + fallback13vectors; independent oracle required");}
'''
outdir=notes/'native-output';outdir.mkdir(exist_ok=True)
c=notes/'native-source-check.c';c.write_text(preamble+enum+helper+fallback+case_decl+main)
binary=notes/'native-source-check'
subprocess.run(['clang','-O1','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-D__LITTLE_ENDIAN__',str(c),'-o',str(binary)],check=True)
subprocess.run([str(binary),str(outdir)],check=True,env={**os.environ,'ASAN_OPTIONS':'detect_leaks=0'})
spec=importlib.util.spec_from_file_location('oracle',repo/'tests/check-png-encode.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
for name in module.NAMES:
 raw=(outdir/(name+'.raw')).read_bytes();expected=module.expected(name);channels=4 if name.endswith(('premul','straight')) else 3
 assert raw==bytes(v for pixel in expected for v in pixel[:channels]),name
errors=module.check(outdir);assert not errors,errors
print('PASS independently expected canonical samples + Pillow/IHDR13actual fallback outputs')
