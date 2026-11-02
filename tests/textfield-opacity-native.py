#!/usr/bin/env python3
"""Run the production -isOpaque method with a native Objective-C cell double.
This checks the opacity contract only; the AppKit pixel regression is separate.
"""
from pathlib import Path
import argparse, subprocess
p = argparse.ArgumentParser(); p.add_argument('--out', type=Path, required=True); a = p.parse_args()
a.out.mkdir(parents=True, exist_ok=True)
root = Path(__file__).resolve().parents[1]
method = (root / 'AppKit/NSTextField.m').read_text().split('- (BOOL) isOpaque {', 1)[1].split('\n}', 1)[0]
src = r'''
#include <objc/runtime.h>
#include <assert.h>
#include <stdio.h>
__attribute__((objc_root_class)) @interface Cell { Class isa; @public BOOL draws, bezel; }
- (BOOL)drawsBackground;
- (BOOL)isBezeled;
@end
@implementation Cell
- (BOOL)drawsBackground { return draws; }
- (BOOL)isBezeled { return bezel; }
@end
__attribute__((objc_root_class)) @interface Field { Class isa; @public Cell *_cell; }
- (BOOL)isOpaque;
@end
@implementation Field
- (BOOL)isOpaque { METHOD
}
@end
int main(void) {
    Cell *c = class_createInstance(objc_getClass("Cell"), 0);
    Field *f = class_createInstance(objc_getClass("Field"), 0); f->_cell = c;
    for (int draws=0; draws<2; draws++) for (int bezel=0; bezel<2; bezel++) {
        c->draws=draws; c->bezel=bezel;
        if ([f isOpaque]) { fprintf(stderr,"FAIL opaque with draws=%d bezel=%d: cell leaves edge pixels uncovered\n",draws,bezel); return 1; }
    }
    object_dispose(f); object_dispose(c);
    puts("PASS production NSTextField opacity is conservative for all background/bezel combinations");
}
'''.replace('METHOD', method)
source = a.out / 'probe.m'; source.write_text(src)
headers = sorted(Path('/usr/lib/gcc/x86_64-linux-gnu').glob('*/include/objc/runtime.h'))[-1].parents[1]
subprocess.run(['clang', '-I'+str(headers), '-Wall', '-Wextra', '-Werror', str(source), '-l:libobjc.so.4', '-o', str(a.out/'probe')], check=True)
subprocess.run([str(a.out/'probe')], check=True)
