#!/usr/bin/env python3
"""Execute production marker initialization and automatic display recovery."""
import argparse,pathlib,subprocess,tempfile
root=pathlib.Path(__file__).resolve().parents[1]
a=argparse.ArgumentParser();a.add_argument('--source-ref');a.add_argument('--case',choices=['marker','display','flush'],required=True);args=a.parse_args()
def source(path):
 return subprocess.check_output(['git','show',args.source_ref+':AppKit/'+path],cwd=root,text=True) if args.source_ref else (root/'AppKit'/path).read_text()
def method(s,start):
 at=s.index(start);beg=s.index('{',at);depth=1;i=beg+1
 while depth:
  if s[i]=='{':depth+=1
  elif s[i]=='}':depth-=1
  i+=1
 return s[at:i]
base=(root/'tests/appkit-selection-bindings-native.m').read_text().split('static id NSMultipleValuesMarker')[0]
if args.case=='marker':
 s=source('NSController/NSController.m');init=method(s,'+ (void) load' if '+ (void) load' in s else '+ (void) initialize')
 program=base+'''
static id NSNoSelectionMarker=@"NSNoSelectionMarker",NSMultipleValuesMarker=@"NSMultipleValuesMarker",NSNotApplicableMarker=@"NSNotApplicableMarker";
@interface _NSControllerMarker:NSString @end
@implementation _NSControllerMarker
- (id)initWithString:(id)s{return self;}
MARKER_VALUE
@end
@interface NSController:NSObject @end
@implementation NSController
INIT_METHOD
@end
int main(void){
 // The client captures the export before sending its first NSController message.
 id captured=NSNoSelectionMarker;
 assert(object_getClass(captured)==objc_getClass("_NSControllerMarker"));
 assert([captured valueForKey:@"enabledEncodings"]==captured);
 [NSController class];assert(captured==NSNoSelectionMarker);
 assert(NSNoSelectionMarker!=NSMultipleValuesMarker&&NSNoSelectionMarker!=NSNotApplicableMarker);
 puts("PASS marker: stable exports and KVC before first controller use");
}
'''.replace('INIT_METHOD',init).replace('MARKER_VALUE',method(source('NSController/NSControllerMarker.m'),'- (id) valueForKey:'))
else:
 program=base+'''
#define NS_DURING @try {
#define NS_HANDLER } @catch(id localException) {
#define NS_ENDHANDLER }
#define qvEventBoundary(...)
#include <pthread.h>
#include <objc/message.h>
typedef int NSEventMask;
typedef id NSRunLoopMode;
#define NSAppKitSystem 13
static Class NSClassFromString(id s){return Nil;}
@interface NSEvent:NSObject @end
@implementation NSEvent
- (int)type{return 1;}
@end
@interface NSDate:NSObject @end
@implementation NSDate
- (double)timeIntervalSinceNow{return -1;}
@end
static int waits;
@interface Display:NSObject @end
@implementation Display
- (id)nextEventMatchingMask:(int)m untilDate:(id)d inMode:(id)mode dequeue:(BOOL)b{waits++;return nil;}
@end
@implementation NSArray (DisplayFixture)
- (void)makeObjectsPerformSelector:(SEL)s{for(id o in self)[o performSelector:s];}
@end
@implementation NSObject (PerformFixture)
- (id)performSelector:(SEL)s{return ((id(*)(id,SEL))objc_msg_lookup(self,s))(self,s);}
@end
static BOOL drawingFails,layoutFails,debugDrawing,debugMode;
static int cancelledDisplayRetries;
@interface NSRunLoop:NSObject @end
@implementation NSRunLoop
+ (id)currentRunLoop{static id loop;if(!loop)loop=[self new];return loop;}
- (void)cancelPerformSelector:(SEL)s target:(id)t argument:(id)a{assert(sel_isEqual(s,@selector(_displayAllWindowsIfNeeded)));cancelledDisplayRetries++;}
@end
static int reports,draws,flushes,layoutCalls;
static id NSApp;
@interface NSAutoreleasePool:NSObject @end
@implementation NSAutoreleasePool
- (void)drain{}
@end
@interface NSGraphicsContext:NSObject @end
@implementation NSGraphicsContext
+ (BOOL)quartzDebuggingIsEnabled{return debugDrawing;}
+ (void)setQuartzDebugMode:(BOOL)b{debugMode=b;}
@end
@interface Background:NSObject @end
@implementation Background
- (void)layoutSubtreeIfNeeded{layoutCalls++;if(layoutFails)@throw self;}
- (void)displayIfNeeded{draws++;if(drawingFails)@throw self;}
@end
@interface NSWindow:NSObject { @public id _backgroundView;int disabled;BOOL dirty; }
- (void)displayIfNeeded;
@end
@implementation NSWindow
- (void)_makeSureIsOnAScreen{}
- (BOOL)isVisible{return YES;}
- (BOOL)isMiniaturized{return NO;}
- (BOOL)viewsNeedDisplay{return dirty;}
- (void)setViewsNeedDisplay:(BOOL)b{dirty=b;}
- (id)_backgroundView{return _backgroundView;}
- (void)disableFlushWindow{disabled++;}
- (void)enableFlushWindow{disabled--;}
- (void)flushWindow{flushes++;}
- (void)flushWindowIfNeeded{flushes++;}
WINDOW_METHOD
@end
@interface App:NSObject { @public id windows,_display,_currentEvent;pthread_mutex_t *_lock; }
- (id)windows; - (void)reportException:(id)e;
@end
@implementation App
- (id)windows{return windows;}
- (void)reportException:(id)e{reports++;}
- (void)_checkForReleasedWindows{}
- (void)_checkForAppActivation{}
NEXT_METHOD
APP_METHOD
@end
int main(void){
 App *app=[App new];NSApp=app;
 NSWindow *w=[NSWindow new];w->_backgroundView=[Background new];w->dirty=YES;
 app->windows=[NSArray arrayWithObject:w];
 drawingFails=YES;
 if(FLUSH_CASE){
  for(int debug=0;debug<2;debug++){
   debugDrawing=debug;BOOL caught=NO;@try{[w displayIfNeeded];}@catch(id e){caught=YES;}
   assert(caught&&w->disabled==0&&!debugMode);
  }
  drawingFails=NO;[w displayIfNeeded];assert(w->disabled==0&&!w->dirty&&flushes>0);
  puts("PASS flush: exceptions balance debug/normal flush disables and allow redraw");
 }else{
  BOOL returned=NO;@try{[app _displayAllWindowsIfNeeded];returned=YES;}@catch(id e){}
  assert(returned&&reports==1); // event reader remains reachable after a draw failure
  drawingFails=NO;layoutFails=YES;returned=NO;
  @try{[app _displayAllWindowsIfNeeded];returned=YES;}@catch(id e){}
  assert(returned&&reports==2);
  app->_display=[Display new];
  [app nextEventMatchingMask:0 untilDate:[NSDate new] inMode:nil dequeue:YES];
  assert(waits==1&&reports==3&&cancelledDisplayRetries==3); // production event pump reaches its blocking reader

  layoutFails=NO;[app _displayAllWindowsIfNeeded];assert(!w->dirty);
  puts("PASS display: draw/layout failures return to caller and subsequent redraw succeeds");
 }
}
'''.replace('NEXT_METHOD',method(source('NSApplication.m'),'- (NSEvent *) nextEventMatchingMask:')).replace('APP_METHOD',method(source('NSApplication.m'),'- (void) _displayAllWindowsIfNeeded')).replace('WINDOW_METHOD',method(source('NSWindow.m'),'- (void) displayIfNeeded')).replace('FLUSH_CASE','1' if args.case=='flush' else '0')
inc=subprocess.check_output(['gcc','-print-file-name=include'],text=True).strip()
with tempfile.TemporaryDirectory(prefix='qv-marker-display-') as tmp:
 src=pathlib.Path(tmp)/'fixture.m';exe=pathlib.Path(tmp)/'fixture';src.write_text(program)
 subprocess.run(['clang','-O1','-g','-fobjc-runtime=gcc','-fconstant-string-class=FixtureString','-fobjc-exceptions','-fexceptions','-I'+inc,'-Wno-objc-method-access','-Wno-incompatible-pointer-types','-Wno-incomplete-implementation','-fsanitize=undefined','-fno-sanitize-recover=all',str(src),'-lobjc','-o',str(exe)],check=True)
 subprocess.run([str(exe)],check=True)
