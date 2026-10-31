#!/usr/bin/env python3
"""Exercise actual shared record/live validation helpers with two scalar widths.

This C adapter is arithmetic/layout evidence, not Foundation/CG/guest execution.
"""
from pathlib import Path
import argparse,subprocess,tempfile,os,re
repo=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);args=p.parse_args();args.output.mkdir(exist_ok=True,parents=True)
text=(repo/'AppKit/NSImageCoding.h').read_text();functions=text[text.index('static inline BOOL QVImageCodingValidSize'):text.index('static inline NSUInteger QVImageCodingInteger')]
app=(repo/'AppKit/include/AppKit/NSBitmapImageRep.h').read_text();start=app.index('typedef enum {\n    NSAlphaFirstBitmapFormat');enums=app[start:app.index('} NSBitmapFormat;',start)+len('} NSBitmapFormat;')]
cg=(repo/'CoreGraphics/include/CoreGraphics/CGImage.h').read_text();cg=cg[cg.index('#define kCGBitmapAlphaInfoMask'):cg.index('typedef unsigned CGBitmapInfo;')];cg=cg.replace('typedef CF_ENUM(uint32_t, CGImageAlphaInfo) {','enum {').replace(' CF_SWIFT_NAME(alphaOnly)','')
main=r'''
int main(void){
 assert(QVImagePackedRGBExtent(6,2,4,32,29,0,YES));
 assert(QVImagePackedRGBExtent(6,2,4,32,29,NSAlphaFirstBitmapFormat|NSAlphaNonpremultipliedBitmapFormat,YES));
 assert(QVImagePackedRGBExtent(6,2,3,24,23,0,NO));
 assert(QVImagePackedRGBExtent(6,2,3,32,29,NSAlphaFirstBitmapFormat,NO));
 assert(!QVImagePackedRGBExtent(0,2,4,32,29,0,YES));
 assert(!QVImagePackedRGBExtent(6,0,4,32,29,0,YES));
 assert(!QVImagePackedRGBExtent(6,2,4,32,0,0,YES));
 assert(!QVImagePackedRGBExtent(6,2,4,32,23,0,YES));
 assert(!QVImagePackedRGBExtent(INT_MAX,2,4,32,INT_MAX,0,YES));
 assert(!QVImagePackedRGBExtent(6,INT_MAX,4,32,29,0,YES));
 assert(!QVImagePackedRGBExtent(6,2,0,0,29,0,NO));
 assert(!QVImagePackedRGBExtent(6,2,3,0,29,0,NO));
 assert(!QVImagePackedRGBExtent(6,2,1,8,29,0,NO));
 assert(!QVImagePackedRGBExtent(6,2,4,128,96,NSFloatingPointSamplesBitmapFormat,YES));
 assert(!QVImagePackedRGBExtent(6,2,3,24,23,NSAlphaNonpremultipliedBitmapFormat,NO));
 assert(!QVImagePackedRGBExtent((NSUInteger)-1,2,4,32,29,0,YES));
 assert(!QVImagePackedRGBExtent(6,(NSUInteger)-1,4,32,29,0,YES));
 assert(!QVImagePackedRGBExtent(6,2,4,32,(NSUInteger)-1,0,YES));
 assert(!QVImagePackedRGBExtent(6,2,(NSUInteger)-1,32,29,0,YES));
 assert(!QVImagePackedRGBExtent(6,2,4,(NSUInteger)-1,29,0,YES));
 assert(!QVImagePackedRGBExtent(6,2,4,32,29,(NSUInteger)-1,YES));
 assert(QVImagePackedRGBExtent(1,INT_MAX,3,24,1*3,0,NO)==NO);
 assert(QVImagePackedRGBExtent(1,INT_MAX/3,3,24,3,0,NO));
 unsigned orders[]={kCGBitmapByteOrderDefault,kCGBitmapByteOrder32Little,kCGBitmapByteOrder32Big};
 unsigned alphas[]={kCGImageAlphaFirst,kCGImageAlphaLast,kCGImageAlphaPremultipliedFirst,kCGImageAlphaPremultipliedLast,kCGImageAlphaNoneSkipFirst,kCGImageAlphaNoneSkipLast};
 for(unsigned i=0;i<6;i++)for(unsigned j=0;j<3;j++){
  unsigned a=alphas[i];BOOL alpha=i<4;NSUInteger format=((a==kCGImageAlphaFirst||a==kCGImageAlphaPremultipliedFirst)?NSAlphaFirstBitmapFormat:0)|((a==kCGImageAlphaFirst||a==kCGImageAlphaLast)?NSAlphaNonpremultipliedBitmapFormat:0);
  assert(QVImageCGBitmapLayout(32,alpha,format,a|orders[j]));
  assert(!QVImageCGBitmapLayout(32,!alpha,format,a|orders[j]));
  assert(!QVImageCGBitmapLayout(32,alpha,format,a|orders[j]|kCGBitmapFloatComponents));
  assert(!QVImageCGBitmapLayout(32,alpha,format,a|kCGBitmapByteOrder16Big));
 }
 assert(QVImageCGBitmapLayout(24,NO,0,kCGImageAlphaNone));
 assert(!QVImageCGBitmapLayout(24,NO,0,kCGImageAlphaNone|kCGBitmapByteOrder32Big));
 assert(!QVImageCGBitmapLayout(32,YES,0,kCGImageAlphaOnly));
 assert(!QVImageCGBitmapLayout(32,NO,0,kCGImageAlphaNone));
 assert(!QVImageCGBitmapLayout(48,NO,0,kCGImageAlphaNone));
 assert(QVImageCodingValidSize((NSSize){0,0}));assert(QVImageCodingValidSize((NSSize){7.5,3.25}));
 assert(!QVImageCodingValidSize((NSSize){NAN,1}));assert(!QVImageCodingValidSize((NSSize){1,INFINITY}));assert(!QVImageCodingValidSize((NSSize){-1,2}));
 printf("PASS actual extent/layout/size helpers with %zu-bit integer and %zu-bit CGFloat model\n",sizeof(NSUInteger)*8,sizeof(CGFloat)*8);
}
'''
for bits,integer,floating in [(32,'uint32_t','float'),(64,'uint64_t','double')]:
 source=args.output/f'layout-{bits}.c';binary=args.output/f'layout-{bits}'
 source.write_text('#include <stdint.h>\n#include <limits.h>\n#include <math.h>\n#include <assert.h>\n#include <stdio.h>\ntypedef '+integer+' NSUInteger;\ntypedef '+floating+' CGFloat;\ntypedef int BOOL;\n#define YES 1\n#define NO 0\ntypedef struct {CGFloat width,height;}NSSize;\n'+enums+'\n'+cg+'\n'+functions+'\n'+main)
 subprocess.run(['clang','-O1','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer',str(source),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True,env={**os.environ,'ASAN_OPTIONS':'detect_leaks=0'})
