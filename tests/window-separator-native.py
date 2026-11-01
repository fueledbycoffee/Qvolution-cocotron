#!/usr/bin/env python3
"""Execute the production NSWindow accessor against a controlled theme colour."""
import argparse,pathlib,subprocess,tempfile
root=pathlib.Path(__file__).resolve().parents[1]
a=argparse.ArgumentParser();a.add_argument('--source-ref');args=a.parse_args()
s=subprocess.check_output(['git','show',args.source_ref+':AppKit/NSWindow.m'],cwd=root,text=True) if args.source_ref else (root/'AppKit/NSWindow.m').read_text()
start='- (NSColor *) contentSeparatorColor'
body=''
if start in s:
 at=s.index(start);beg=s.index('{',at);end=s.index('}',beg);body=s[at:end+1]
program='''
#include <objc/runtime.h>
#include <assert.h>
#include <stdio.h>
__attribute__((objc_root_class)) @interface NSObject {Class isa;}
+ (id)new;- (BOOL)respondsToSelector:(SEL)s;
@end
@implementation NSObject
+ (id)new{return class_createInstance(self,0);}
- (BOOL)respondsToSelector:(SEL)s{return class_getInstanceMethod(object_getClass(self),s)!=NULL;}
@end
static id palette;
@interface NSColor:NSObject @end
@implementation NSColor
+ (id)separatorColor{return palette;}
@end
@interface NSWindow:NSObject @end
@implementation NSWindow
ACCESSOR
@end
int main(void){
 id w=[NSWindow new];assert([w respondsToSelector:@selector(contentSeparatorColor)]);
 palette=[NSColor new];assert([w contentSeparatorColor]==palette);
 palette=[NSColor new];assert([w contentSeparatorColor]==palette);
 puts("PASS window separator: observed accessor follows the current theme colour");
}
'''.replace('ACCESSOR',body)
inc=subprocess.check_output(['gcc','-print-file-name=include'],text=True).strip()
with tempfile.TemporaryDirectory(prefix='qv-window-separator-') as tmp:
 src=pathlib.Path(tmp)/'fixture.m';exe=pathlib.Path(tmp)/'fixture';src.write_text(program)
 subprocess.run(['clang','-O1','-g','-fobjc-runtime=gcc','-fobjc-exceptions','-fexceptions','-I'+inc,'-Wno-objc-method-access','-fsanitize=undefined','-fno-sanitize-recover=all',str(src),'-lobjc','-o',str(exe)],check=True)
 subprocess.run([str(exe)],check=True)
