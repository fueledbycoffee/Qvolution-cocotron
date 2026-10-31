# Native execution of actual new packing validator; not allocation/dispatch proof.
from pathlib import Path
import subprocess,sys
root=Path(__file__).resolve().parents[2];text=(root/'Onyx2D/O2BitmapFormat.h').read_text()
a=text.index('static inline BOOL O2BitmapFormatSupportsFloatRGBA(');b=text.index('{',a)+1;depth=1
while depth:depth+=(text[b]=='{')-(text[b]=='}');b+=1
function=text[a:b].replace('[colorSpace type]','*colorSpace')
assert len(sys.argv)==2, 'pass an explicit output directory outside the checkout'
out=Path(sys.argv[1]).resolve();assert not out.is_relative_to(root)
out.mkdir(parents=True,exist_ok=True)
source='''#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <limits.h>
#include <stdio.h>
#include <assert.h>
typedef bool BOOL;typedef int *O2ColorSpaceRef;typedef unsigned O2BitmapInfo;
#define nil NULL
#define YES true
#define NO false
#define kO2ColorSpaceModelRGB 1
#define kO2BitmapFloatComponents 0x100
#define kO2BitmapAlphaInfoMask 0x1f
#define kO2BitmapByteOrderMask 0x7000
#define kO2ImageAlphaPremultipliedLast 1
#define kO2BitmapByteOrder32Little 0x2000
#define kO2BitmapByteOrder32Big 0x4000
'''+function+'''
int main(void) {
 int rgb=1,gray=0;unsigned le=0x2101,be=0x4101;
 assert(O2BitmapFormatSupportsFloatRGBA(5,3,32,128,96,&rgb,le));
 assert(O2BitmapFormatSupportsFloatRGBA(5,3,32,128,96,&rgb,be));
 assert(!O2BitmapFormatSupportsFloatRGBA(5,3,32,128,79,&rgb,le));
 assert(!O2BitmapFormatSupportsFloatRGBA(5,3,32,32,96,&rgb,le));
 assert(!O2BitmapFormatSupportsFloatRGBA(5,3,8,128,96,&rgb,le));
 assert(!O2BitmapFormatSupportsFloatRGBA(5,3,32,128,96,&gray,le));
 assert(!O2BitmapFormatSupportsFloatRGBA(5,3,32,128,96,NULL,le));
 unsigned rejected[]={0x2001,0x2102,0x2103,0x1101,0x3101,0x101,0xa101};
 for(unsigned i=0;i<sizeof(rejected)/sizeof(*rejected);i++)
  assert(!O2BitmapFormatSupportsFloatRGBA(5,3,32,128,96,&rgb,rejected[i]));
 assert(O2BitmapFormatSupportsFloatRGBA(INT_MAX/16,1,32,128,(INT_MAX/16)*16u,&rgb,le));
 assert(!O2BitmapFormatSupportsFloatRGBA((size_t)INT_MAX/16+1,1,32,128,(size_t)INT_MAX+1,&rgb,le));
 assert(O2BitmapFormatSupportsFloatRGBA(1,INT_MAX/16,32,128,16,&rgb,le));
 assert(!O2BitmapFormatSupportsFloatRGBA(1,(size_t)INT_MAX/16+1,32,128,16,&rgb,le));
 assert(!O2BitmapFormatSupportsFloatRGBA(1,2,32,128,SIZE_MAX,&rgb,le));
 puts("ACTUAL_FLOAT_FORMAT_SOURCE_PASS_ALLOCATION_RUNTIME_PENDING");return 0;
}
'''
(out/'format.c').write_text(source)
subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-fsanitize=undefined,address',str(out/'format.c'),'-o',str(out/'format')],check=True)
subprocess.run([str(out/'format')],check=True)
