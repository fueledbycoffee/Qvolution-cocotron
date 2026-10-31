#!/usr/bin/env python3
"""Exercise the production tile method with native view/damage boundary doubles.
The row painter is a synthetic stale-row oracle, not an AppKit pixel result.
"""
import argparse, os, pathlib, subprocess, tempfile
p=argparse.ArgumentParser();p.add_argument('--revision');a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]
text=(subprocess.check_output(['git','show',a.revision+':AppKit/NSScrollView.m'],cwd=root,text=True)
      if a.revision else (root/'AppKit/NSScrollView.m').read_text())
def block(start):
 pos=text.index(start);end=text.index('{',pos)+1;depth=1
 while depth:
  depth+=(text[end]=='{')-(text[end]=='}');end+=1
 return text[pos:end]
helper=block('static void tileSubview(') if 'static void tileSubview(' in text else ''
harness=(root/'tests/scrollview-tile-damage.inc').read_text().replace('/* PRODUCTION */',helper+'\n'+block('- (void) tile {'))
with tempfile.TemporaryDirectory(prefix='ruler-tile-') as tmp:
 path=pathlib.Path(tmp);(path/'test.m').write_text(harness)
 include=subprocess.check_output(['gcc','-print-file-name=include'],text=True).strip()
 subprocess.run(['clang','-x','objective-c','-I'+include,'-Wno-objc-root-class','-Werror=objc-method-access','-fsanitize=address,undefined','-fno-omit-frame-pointer',str(path/'test.m'),'-lobjc','-lm','-o',str(path/'test')],check=True)
 env=dict(os.environ,ASAN_OPTIONS='detect_leaks=0',UBSAN_OPTIONS='halt_on_error=1')
 subprocess.run([str(path/'test')],env=env,check=True)
