#!/usr/bin/env python3
"""Exercise the actual C phase decomposition helper with invariant checks."""
import pathlib,re,subprocess,tempfile
source=(pathlib.Path(__file__).resolve().parents[1]/'Onyx2D/O2Context_builtin_FT.m').read_text()
helper=re.search(r'static BOOL splitGlyphOrigin\(.*?^\}',source,re.M|re.S).group(0)
program=r'''
#include <limits.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <assert.h>
typedef double O2Float;
typedef long NSInteger;
typedef int BOOL;
#define NSIntegerMin LONG_MIN
#define NSIntegerMax LONG_MAX
#define YES 1
#define NO 0
ACTUAL_HELPER
int main(void){
 const struct {double input;long anchor;unsigned phase;} cases[]={
  {10,10,0},{10.25,10,16},{10.5,10,32},{10.999,11,0},
  {-10,-10,0},{-10.5,-11,32},{-10.001,-10,0},{-10.999,-11,0}
 };
 long anchor;uint8_t phase;
 for(unsigned i=0;i<sizeof(cases)/sizeof(cases[0]);i++){
  assert(splitGlyphOrigin(cases[i].input,&anchor,&phase));assert(anchor==cases[i].anchor&&phase==cases[i].phase);
 }
 assert(!splitGlyphOrigin(NAN,&anchor,&phase));assert(!splitGlyphOrigin(INFINITY,&anchor,&phase));assert(!splitGlyphOrigin(-INFINITY,&anchor,&phase));
 assert(!splitGlyphOrigin((double)LONG_MAX,&anchor,&phase));assert(!splitGlyphOrigin((double)LONG_MIN,&anchor,&phase));
 for(long i=-100000;i<=100000;i++){
  double value=i/113.;assert(splitGlyphOrigin(value,&anchor,&phase));
  assert(phase<64);assert(fabs((anchor+phase/64.)-value)<=1./128+1e-10);
 }
 puts("PASS: actual origin helper negative/carry/precision/invalid bounds");return 0;
}
'''.replace('ACTUAL_HELPER',helper)
with tempfile.TemporaryDirectory(prefix='font-phase-origin-') as scratch:
    p=pathlib.Path(scratch);(p/'probe.c').write_text(program)
    subprocess.run(['cc','-O2',str(p/'probe.c'),'-lm','-o',str(p/'probe')],check=True)
    subprocess.run([str(p/'probe')],check=True)
