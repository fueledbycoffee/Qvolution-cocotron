#!/usr/bin/env python3
"""Run actual origin/bitmap helpers with explicit 32/64-bit integer models."""
import pathlib,re,subprocess,tempfile
source=(pathlib.Path(__file__).resolve().parents[1]/'Onyx2D/O2Context_builtin_FT.m').read_text()
helpers='\n'.join(re.search(r'static BOOL '+name+r'\(.*?^\}',source,re.M|re.S).group(0) for name in ['splitGlyphOrigin','glyphBitmapPosition'])
program=r'''
#include <limits.h>
#include <math.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <assert.h>
typedef FLOAT_TYPE O2Float;
typedef INTEGER_TYPE NSInteger;
typedef int BOOL;
#define NSIntegerMin INTEGER_MIN
#define NSIntegerMax INTEGER_MAX
#define YES 1
#define NO 0
ACTUAL_HELPERS
int main(void){
 const struct {double input;int64_t anchor;unsigned phase;} cases[]={
  {10,10,0},{10.25,10,16},{10.5,10,32},{10.999,11,0},
  {-10,-10,0},{-10.5,-11,32},{-10.001,-10,0},{-10.999,-11,0}
 };
 NSInteger anchor,x,y;uint8_t phase;
 for(unsigned i=0;i<sizeof(cases)/sizeof(cases[0]);i++){
  assert(splitGlyphOrigin(cases[i].input,&anchor,&phase));assert(anchor==cases[i].anchor&&phase==cases[i].phase);
 }
 assert(!splitGlyphOrigin(NAN,&anchor,&phase));assert(!splitGlyphOrigin(INFINITY,&anchor,&phase));assert(!splitGlyphOrigin(-INFINITY,&anchor,&phase));
 double upper=(double)((long double)NSIntegerMax+1.0L);
 assert(!splitGlyphOrigin((O2Float)upper,&anchor,&phase));
 O2Float below=sizeof(O2Float)==sizeof(float)?nextafterf((float)NSIntegerMin,-INFINITY):nextafter((double)NSIntegerMin-1.0,-INFINITY);
 assert(!splitGlyphOrigin(below,&anchor,&phase));
 assert(splitGlyphOrigin((O2Float)NSIntegerMin,&anchor,&phase)&&anchor==NSIntegerMin&&phase==0);
 O2Float last=sizeof(O2Float)==sizeof(float)?nextafterf((float)upper,0):nextafter(upper,0);
 if(sizeof(NSInteger)==4 && sizeof(O2Float)==8)last=(double)NSIntegerMax;
 assert(splitGlyphOrigin(last,&anchor,&phase));
 if(sizeof(NSInteger)==4 && sizeof(O2Float)==8){
  assert(splitGlyphOrigin((double)INT32_MIN-.001,&anchor,&phase)&&anchor==INT32_MIN&&phase==0);
  assert(splitGlyphOrigin((double)INT32_MAX+.5,&anchor,&phase)&&anchor==INT32_MAX&&phase==32);
  assert(!splitGlyphOrigin((double)INT32_MAX+.999,&anchor,&phase));
 }
 for(long i=-100000;i<=100000;i++){
  O2Float value=(O2Float)(i/113.);assert(splitGlyphOrigin(value,&anchor,&phase));
  assert(phase<64);assert(fabs((anchor+phase/64.)-(double)value)<=1./128+1e-10);
 }
 assert(glyphBitmapPosition(10,20,2,3,8,9,&x,&y)&&x==12&&y==17);
 assert(glyphBitmapPosition(NSIntegerMin,NSIntegerMin,0,0,1,1,&x,&y));
 assert(glyphBitmapPosition(NSIntegerMax-1,NSIntegerMax-1,0,0,1,1,&x,&y));
 assert(!glyphBitmapPosition(NSIntegerMax,0,1,0,1,1,&x,&y));
 assert(!glyphBitmapPosition(NSIntegerMin,0,-1,0,1,1,&x,&y));
 assert(!glyphBitmapPosition(0,NSIntegerMin,0,1,1,1,&x,&y));
 assert(!glyphBitmapPosition(0,NSIntegerMax,0,-1,1,1,&x,&y));
 assert(!glyphBitmapPosition(NSIntegerMax,0,0,0,1,1,&x,&y));
 assert(!glyphBitmapPosition(0,NSIntegerMax,0,0,1,1,&x,&y));
 assert(!glyphBitmapPosition(0,0,0,0,(size_t)NSIntegerMax+1,1,&x,&y));
 puts("PASS: INTEGER_TYPE/FLOAT_TYPE actual origin and checked bitmap arithmetic");return 0;
}
'''.replace('ACTUAL_HELPERS',helpers)
with tempfile.TemporaryDirectory(prefix='font-phase-origin-') as scratch:
    p=pathlib.Path(scratch)
    for integer,floating,minimum,maximum in [('int64_t','double','INT64_MIN','INT64_MAX'),('int32_t','double','INT32_MIN','INT32_MAX'),('int32_t','float','INT32_MIN','INT32_MAX')]:
        candidate=program.replace('INTEGER_TYPE',integer).replace('FLOAT_TYPE',floating).replace('INTEGER_MIN',minimum).replace('INTEGER_MAX',maximum)
        (p/'probe.c').write_text(candidate)
        subprocess.run(['cc','-O2','-fsanitize=undefined','-fno-sanitize-recover=all',str(p/'probe.c'),'-lm','-o',str(p/'probe')],check=True)
        subprocess.run([str(p/'probe')],check=True)
