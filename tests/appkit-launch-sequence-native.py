#!/usr/bin/env python3
"""Launch production methods on libobjc with controlled notification/UI doubles."""
import argparse,pathlib,subprocess,tempfile
root=pathlib.Path(__file__).resolve().parents[1]
a=argparse.ArgumentParser();a.add_argument('--source-ref');args=a.parse_args()
def source(path):
 return subprocess.check_output(['git','show',args.source_ref+':AppKit/'+path],cwd=root,text=True) if args.source_ref else (root/'AppKit'/path).read_text()
def method(s,start):
 at=s.index(start);beg=s.index('{',at);depth=1;i=beg+1
 while depth:
  if s[i]=='{':depth+=1
  elif s[i]=='}':depth-=1
  i+=1
 return s[at:i]
# Reuse native collection doubles; production code is inserted without rewriting.
base=(root/'tests/appkit-selection-bindings-native.m').read_text().split('static id NSMultipleValuesMarker')[0]
program=base+(root/'tests/appkit-launch-sequence-native.m').read_text()
for token,path,start in [('FINISH_METHOD','NSApplication.m','- (void) finishLaunching'),('REOPEN_METHOD','NSApplication.m','- (void) _reopen')]:
 s=source(path);program=program.replace(token,method(s,start) if start in s else '')
inc=subprocess.check_output(['gcc','-print-file-name=include'],text=True).strip()
with tempfile.TemporaryDirectory(prefix='qv-launch-') as tmp:
 src=pathlib.Path(tmp)/'fixture.m';exe=pathlib.Path(tmp)/'fixture';src.write_text(program)
 subprocess.run(['clang','-O1','-g','-fobjc-runtime=gcc','-fconstant-string-class=FixtureString','-fobjc-exceptions','-fexceptions','-I'+inc,'-Wno-objc-method-access','-Wno-incompatible-pointer-types','-Wno-incomplete-implementation','-fsanitize=undefined','-fno-sanitize-recover=all',str(src),'-lobjc','-o',str(exe)],check=True)
 subprocess.run([str(exe)],check=True)
