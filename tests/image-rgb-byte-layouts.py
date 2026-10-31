#!/usr/bin/env python3
"""Actual own factory/readers with independent packed bytes; not full CGImage execution."""
from pathlib import Path
import subprocess,tempfile,os,re
repo=Path(__file__).resolve().parents[1];source=(repo/'Onyx2D/O2Image.m').read_text()
def body(signature):
 start=source.index(signature);opening=source.index('{',start);depth=1;end=opening+1
 while depth:
  if source[end]=='{':depth+=1
  elif source[end]=='}':depth-=1
  end+=1
 return source[start:end]
header=(repo/'Onyx2D/include/Onyx2D/O2Image.h').read_text();enums=header[header.index('#define kO2BitmapAlphaInfoMask'):header.index('#import <Onyx2D/O2ColorSpace.h>')]
pixel=(repo/'Onyx2D/include/Onyx2D/O2argb8u.h').read_text();pixel=pixel[pixel.index('typedef struct'):pixel.index('#define COVERAGE_MULTIPLIER')]
factory=body('ONYX2D_STATIC BOOL initFunctionsForRGBColorSpace(')
readers=['O2ImageRead_RGBA8888_to_argb8u','O2ImageRead_ABGR8888_to_argb8u','O2ImageRead_BGRA8888_to_argb8u','O2ImageRead_RGB888_to_argb8u','O2ImageRead_BGRX8888_to_argb8u','O2ImageRead_XRGB8888_to_argb8u']
callbacks=set(re.findall(r'= (O2\w+);',factory));expected=set(readers)|{'O2ImageRead_argb32fLittle_to_argb32f','O2ImageRead_argb32fBig_to_argb32f','O2ImageRead_G8_to_A8','O2ImageRead_G8_to_argb8u','O2ImageRead_GA88_to_argb8u','O2ImageRead_G3B5X1R5G2_to_argb8u','O2ImageRead_BARG4444_to_argb8u','O2ImageRead_RGBA4444_to_argb8u','O2ImageRead_RGBA2222_to_argb8u'};assert callbacks==expected,callbacks
pre=r'''#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
typedef int BOOL;
#define YES 1
#define NO 0
#define ONYX2D_STATIC static
#define ONYX2D_STATIC_INLINE static inline
'''+enums+pixel+r'''
typedef struct {float a,r,g,b;} O2argb32f;
typedef struct O2Image O2Image;
struct O2Image {size_t _bytesPerRow,_directLength;const uint8_t *_directBytes;O2BitmapInfo _bitmapInfo;O2argb8u *(*_read_argb8u)(O2Image*,int,int,O2argb8u*,int);O2argb32f *(*_read_argb32f)(O2Image*,int,int,O2argb32f*,int);uint8_t *(*_read_a8u)(O2Image*,int,int,uint8_t*,int);};
static const void *directBytes(O2Image *self){return self->_directBytes;}
'''
for name in sorted(callbacks):
 ret='O2argb32f *' if 'argb32f' in name else 'uint8_t *' if name=='O2ImageRead_G8_to_A8' else 'O2argb8u *'
 if name in readers:pre+=ret+name+'(O2Image*,int,int,O2argb8u*,int);\n'
 else:pre+='static '+ret+name+'(O2Image *s,int x,int y,'+ret+'p,int n){abort();}\n'
production=body('ONYX2D_STATIC_INLINE const void *scanlineAtY(')+'\n'+factory+'\n'+'\n'.join(body('O2argb8u *'+name+'(')for name in readers)
test=r'''
static unsigned failures;
struct Case{const char *name;unsigned alpha,order;int channels;};
static unsigned pm(unsigned channel,unsigned alpha){return (channel*alpha+127)/255;}
static unsigned run(struct Case c){
 uint8_t bytes[64],saved[64];memset(bytes,0xD3,sizeof(bytes));size_t stride=6*c.channels+5;
 const unsigned alphas[]={0,1,64,128,254,255};int premul=c.alpha==kO2ImageAlphaPremultipliedFirst||c.alpha==kO2ImageAlphaPremultipliedLast;
 int hasAlpha=premul||c.alpha==kO2ImageAlphaFirst||c.alpha==kO2ImageAlphaLast;
 int first=c.alpha==kO2ImageAlphaFirst||c.alpha==kO2ImageAlphaPremultipliedFirst||c.alpha==kO2ImageAlphaNoneSkipFirst;
 int little=c.order==kO2BitmapByteOrder32Little||c.order==kO2BitmapByteOrder16Little;
 for(unsigned y=0;y<2;y++)for(unsigned x=0;x<6;x++){
  unsigned r=31+x*29,g=193-y*67-x*11,b=17+y*109+x*7,a=alphas[x];if(premul){r=pm(r,a);g=pm(g,a);b=pm(b,a);}
  uint8_t q[4];if(c.channels==3){q[0]=r;q[1]=g;q[2]=b;}else{q[first?1:0]=r;q[first?2:1]=g;q[first?3:2]=b;q[first?0:3]=hasAlpha?a:0xAB;if(little)for(unsigned k=0;k<2;k++){uint8_t t=q[k];q[k]=q[3-k];q[3-k]=t;}}
  memcpy(bytes+y*stride+x*c.channels,q,c.channels);
 }
 memcpy(saved,bytes,sizeof(bytes));O2Image image={0};image._bytesPerRow=stride;image._directLength=stride*2;image._directBytes=bytes;image._bitmapInfo=c.alpha|c.order;
 int accepted=initFunctionsForRGBColorSpace(&image,8,c.channels*8,image._bitmapInfo);
 if(!accepted){printf("FAIL CONSTRUCT %s\n",c.name);return 1;}
 unsigned bad=0;
 for(unsigned y=0;y<2;y++)for(unsigned partial=0;partial<2;partial++){
  int start=partial?1:0,count=partial?4:6;
  O2argb8u output[8],sentinel[8];memset(output,0xC7,sizeof(output));memcpy(sentinel,output,sizeof(output));
  O2argb8u *direct=image._read_argb8u(&image,start,y,output+1,count);O2argb8u *actual=direct?direct:output+1;
  int shouldDirect=0;
#ifdef __LITTLE_ENDIAN__
  shouldDirect=premul&&first&&little;
#endif
  if((direct!=NULL)!=shouldDirect)bad++;
  if(direct){if((const uint8_t*)direct!=bytes+y*stride+start*c.channels||memcmp(output,sentinel,sizeof(output)))bad++;}
  else if(memcmp(output,sentinel,sizeof(O2argb8u))||memcmp(output+count+1,sentinel+count+1,(7-count)*sizeof(O2argb8u)))bad++;
  for(unsigned i=0;i<(unsigned)count;i++){
   unsigned x=i+start,a=hasAlpha?alphas[x]:255,r=31+x*29,g=193-y*67-x*11,b=17+y*109+x*7;
   if(hasAlpha){r=pm(r,a);g=pm(g,a);b=pm(b,a);}
   if(actual[i].r!=r||actual[i].g!=g||actual[i].b!=b||actual[i].a!=a)bad++;
  }
 }
 if(memcmp(bytes,saved,sizeof(bytes)))bad++;
 O2argb8u outside[1],unchanged[1];memset(outside,0xBC,sizeof(outside));memcpy(unchanged,outside,sizeof(outside));if(image._read_argb8u(&image,0,2,outside,1)||memcmp(outside,unchanged,sizeof(outside)))bad++;
 printf("%s PIXELS %s errors=%u\n",bad?"FAIL":"PASS",c.name,bad);return bad?1:0;
}
int main(void){
 struct Case cases[]={
 {"rgba-straight",kO2ImageAlphaLast,kO2BitmapByteOrder32Big,4},{"rgba-premul",kO2ImageAlphaPremultipliedLast,kO2BitmapByteOrder32Big,4},
 {"argb-straight",kO2ImageAlphaFirst,kO2BitmapByteOrder32Big,4},{"argb-premul",kO2ImageAlphaPremultipliedFirst,kO2BitmapByteOrder32Big,4},
 {"bgra-straight",kO2ImageAlphaFirst,kO2BitmapByteOrder32Little,4},{"bgra-premul",kO2ImageAlphaPremultipliedFirst,kO2BitmapByteOrder32Little,4},
 {"abgr-straight",kO2ImageAlphaLast,kO2BitmapByteOrder32Little,4},{"abgr-premul",kO2ImageAlphaPremultipliedLast,kO2BitmapByteOrder32Little,4},
 {"rgb",kO2ImageAlphaNone,kO2BitmapByteOrderDefault,3},{"rgbx",kO2ImageAlphaNoneSkipLast,kO2BitmapByteOrder32Big,4},
 {"xrgb",kO2ImageAlphaNoneSkipFirst,kO2BitmapByteOrder32Big,4},{"bgrx",kO2ImageAlphaNoneSkipFirst,kO2BitmapByteOrder32Little,4},{"xbgr",kO2ImageAlphaNoneSkipLast,kO2BitmapByteOrder32Little,4}};
 for(unsigned i=0;i<13;i++)failures+=run(cases[i]);printf("CORE13 failures=%u\n",failures);
 for(unsigned i=9;i<13;i++){struct Case c=cases[i];c.order=c.order==kO2BitmapByteOrder32Little?kO2BitmapByteOrder16Little:kO2BitmapByteOrder16Big;failures+=run(c);}
 struct Case pmBig=cases[3],pmLittle=cases[5];pmBig.order=kO2BitmapByteOrder16Big;pmLittle.order=kO2BitmapByteOrder16Little;failures+=run(pmBig);failures+=run(pmLittle);
 O2Image image={0};assert(!initFunctionsForRGBColorSpace(&image,8,32,kO2ImageAlphaFirst|kO2BitmapByteOrder16Big));assert(!initFunctionsForRGBColorSpace(&image,8,32,kO2ImageAlphaFirst|kO2BitmapByteOrder16Little));
 printf("RESULT total failures=%u (legacy16aliases are existingdispatch controls, not nativeformatqualification)\n",failures);return failures?1:0;
}
'''
with tempfile.TemporaryDirectory(prefix='qv-image-layout-')as d:
 failed=False
 for endian in ('LITTLE','BIG'):
  f=Path(d)/('test-'+endian+'.c');out=f.with_suffix('');f.write_text(pre+production+test)
  subprocess.run(['clang','-std=gnu11','-UNDEBUG','-D__'+endian+'_ENDIAN__','-U__'+('BIG'if endian=='LITTLE'else'LITTLE')+'_ENDIAN__','-fsanitize=address,undefined',str(f),'-o',str(out)],check=True)
  print('BRANCH',endian,flush=True);r=subprocess.run([str(out)],env={**os.environ,'ASAN_OPTIONS':'detect_leaks=0'},timeout=20)
  failed|=r.returncode!=0
 if failed:raise SystemExit(1)
