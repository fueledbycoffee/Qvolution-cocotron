#!/usr/bin/env python3
"""Execute production nib ordering and activation code with controlled windows.
This is a native control, not a substitute for the full authored nib guest test.
"""
from pathlib import Path
import os, re, subprocess, tempfile
root=Path(__file__).resolve().parents[1]
nib=Path(os.environ.get('NIB_SOURCE',root/'AppKit/nib.subproj/NSNib.m')).read_text()
start=nib.index('        if ([[objectData visibleWindows] count] > 0)')
end=nib.index('\n    }\n\n    return (objectData != nil);',start)
ordering=nib[start:end]
application=(root/'AppKit/NSApplication.m').read_text()
activation=re.search(r'- \(void\) activateIgnoringOtherApps:.*?^}',application,re.M|re.S).group()
program=r'''
#include <objc/objc.h>
#include <objc/runtime.h>
#include <objc/message.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
typedef unsigned long NSUInteger;
typedef struct { unsigned long state; id *itemsPtr; unsigned long *mutationsPtr; unsigned long extra[5]; } Enumeration;
__attribute__((objc_root_class)) @interface Root { Class isa; }
+ (id)new; + (Class)class; - (BOOL)isKindOfClass:(Class)c;
@end
@implementation Root
+ (id)new { return class_createInstance(self,0); }
+ (Class)class { return self; }
- (BOOL)isKindOfClass:(Class)c { for(Class x=object_getClass(self);x;x=class_getSuperclass(x))if(x==c)return YES;return NO; }
@end
@interface NSWindow:Root { @public BOOL visible, sheet, deferred; unsigned orders; }
- (BOOL)isVisible; - (BOOL)isSheet; - (BOOL)canBecomeKeyWindow;
- (void)makeKeyAndOrderFront:(id)sender;
@end
@implementation NSWindow
- (BOOL)isVisible { return visible; } - (BOOL)isSheet { return sheet; }
- (BOOL)canBecomeKeyWindow { return YES; }
- (void)makeKeyAndOrderFront:(id)sender { visible=YES;orders++; }
@end
@interface NSPanel:NSWindow @end
@implementation NSPanel @end
@interface List:Root { @public id items[8];NSUInteger count; }
- (NSUInteger)count;
- (NSUInteger)countByEnumeratingWithState:(Enumeration *)state objects:(id *)objects count:(NSUInteger)n;
- (void)makeObjectsPerformSelector:(SEL)selector withObject:(id)object;
@end
@implementation List
- (NSUInteger)count { return count; }
- (NSUInteger)countByEnumeratingWithState:(Enumeration *)s objects:(id *)objects count:(NSUInteger)n { if(s->state)return 0;s->state=1;s->itemsPtr=items;s->mutationsPtr=&s->extra[0];return count; }
- (void)makeObjectsPerformSelector:(SEL)s withObject:(id)o { for(NSUInteger i=0;i<count;i++)((void(*)(id,SEL,id))objc_msg_lookup(items[i],s))(items[i],s,o); }
@end
@interface Data:Root { @public List *visible; } - (List *)visibleWindows; @end
@implementation Data
- (List *)visibleWindows { return visible; }
@end
@interface App:Root { @public NSWindow *_keyWindow,*_mainWindow;List *_allObjects; }
- (List *)orderedWindows; - (void)activateIgnoringOtherApps:(BOOL)flag;
- (void)load:(Data *)objectData;
@end
@implementation App
- (List *)orderedWindows { return _allObjects; }
ACTIVATION
- (void)load:(Data *)objectData { ORDERING }
@end
int main(void) {
 for(unsigned mode=0;mode<3;mode++) {
  App *app=[App new];List *all=[List new],*selected=[List new];Data *data=[Data new];
  NSWindow *normal=[NSWindow new],*later=[NSWindow new];NSPanel *panel=[NSPanel new];later->deferred=YES;
  all->items[0]=normal;all->items[1]=panel;all->items[2]=later;all->count=3;app->_allObjects=all;
  if(mode==0){selected->items[0]=normal;selected->count=1;}
  data->visible=mode==2?nil:selected;[app load:data];
  BOOL expected=mode==0;
  if(normal->visible!=expected || panel->visible || later->visible){fprintf(stderr,"FAIL mode=%u after nib: normal=%d panel=%d deferred=%d\n",mode,normal->visible,panel->visible,later->visible);return 1;}
  [app activateIgnoringOtherApps:YES];
  assert(normal->visible==expected && !panel->visible && !later->visible);
  [panel makeKeyAndOrderFront:nil];[later makeKeyAndOrderFront:nil];
  assert(panel->visible && later->visible);
  printf("PASS %s: nib visibility, activation, explicit show\n",mode==0?"mixed":mode==1?"empty":"missing visibility metadata");
 }
}
'''.replace('ACTIVATION',activation).replace('ORDERING',ordering)
with tempfile.TemporaryDirectory(prefix='nib-native-') as temp:
 source=Path(temp)/'test.m';binary=Path(temp)/'test';source.write_text(program)
 inc=subprocess.check_output(['gcc','-print-file-name=include'],text=True).strip()
 subprocess.run(['clang','-O1','-g','-fobjc-runtime=gcc','-I'+inc,'-fsanitize=address,undefined',str(source),'-lobjc','-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True,env={**os.environ,'ASAN_OPTIONS':'detect_leaks=0','UBSAN_OPTIONS':'halt_on_error=1'})
