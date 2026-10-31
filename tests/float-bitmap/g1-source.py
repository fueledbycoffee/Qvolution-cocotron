"""Exact production G1 readers with bounded scanline memory adapter."""
from pathlib import Path
import subprocess, tempfile, shutil
root=Path(__file__).resolve().parents[2]
s=(root/'Onyx2D/O2Image.m').read_text();a=s.index('ONYX2D_STATIC O2argb8u *O2ImageRead_G1_to_argb8u');b=s.index('ONYX2D_STATIC BOOL initFunctionsForMonochrome',a)
c=r'''
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <assert.h>
#include <string.h>
#define ONYX2D_STATIC static
typedef struct {uint8_t a,r,g,b;} O2argb8u;
typedef struct {size_t _width,_height;const void *bytes;size_t stride,length;} O2Image;
static const void *scanlineAtY(O2Image *s,int y){if(y<0||(size_t)y>=s->_height||s->length<(y+1)*s->stride)return NULL;return (const uint8_t *)s->bytes+y*s->stride;}
'''+s[a:b]+r'''
int main(void){
 uint8_t bits[]={0x96,0x69,0xa0,0xa7,0x12,0x34,0xe0,0xa7};O2Image s={19,2,bits,4,8};
 for(int y=0;y<2;y++)for(int x=0;x<19;x++)for(int n=1;n<=19-x;n++){
  O2argb8u pixels[21];uint8_t alpha[21];memset(pixels,0xa7,sizeof(pixels));memset(alpha,0xa7,sizeof(alpha));
  O2ImageRead_G1_to_argb8u(&s,x,y,pixels+1,n);O2ImageRead_G1_to_A8(&s,x,y,alpha+1,n);
  for(int i=0;i<n;i++){int want=((bits[y*4+(x+i)/8]>>(7-(x+i)%8))&1)*255;assert(pixels[i+1].r==want&&pixels[i+1].g==want&&pixels[i+1].b==want&&pixels[i+1].a==255&&alpha[i+1]==want);}
  for(int i=0;i<21;i++)if(i<1||i>n){O2argb8u want={0xa7,0xa7,0xa7,0xa7};assert(!memcmp(&pixels[i],&want,4)&&alpha[i]==0xa7);}
 }
 s.length=7;O2argb8u p={1,2,3,4};uint8_t a=0x55;O2ImageRead_G1_to_argb8u(&s,0,1,&p,1);O2ImageRead_G1_to_A8(&s,0,1,&a,1);assert(p.r==2&&a==0x55);
 puts("ACTUAL_G1_PARTIAL_SPAN_AND_ROW_CAPACITY_PASS_NOT_GUEST");return 0;
}
'''
out=Path(tempfile.mkdtemp(prefix='onyx-float-g1-'));(out/'g1.c').write_text(c)
subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-fsanitize=address,undefined',str(out/'g1.c'),'-o',str(out/'g1')],check=True);subprocess.run([str(out/'g1')],check=True)

shutil.rmtree(out)
