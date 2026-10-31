// Original public-display regression; own subclass observes calls, never replaces rendering.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static unsigned failures,draws;
static void expectFlush(BOOL value,const char *message){printf("%s: %s\n",value?"PASS":"FAIL",message);failures+=!value;}
@interface NSObject(OwnFlushStatistics)
- (NSDictionary *)eglPresentationStatistics;
@end
static int ownFlag(id backend,const char *name,BOOL pointer){
 if(![NSStringFromClass([backend class])isEqualToString:@"WaylandWindow"])return -1;
 Ivar field=class_getInstanceVariable([backend class],name);if(!field)return -1;
 const unsigned char *bytes=(const unsigned char *)backend+ivar_getOffset(field);
 if(pointer){void *value=NULL;memcpy(&value,bytes,sizeof(value));return value!=NULL;}
 BOOL value=NO;memcpy(&value,bytes,sizeof(value));return value!=NO;
}
@interface FlushWindow:NSWindow { @public unsigned requests,eligible,deferred; }
- (int)ownDepth;
- (BOOL)ownPending;
@end
@implementation FlushWindow
- (void)flushWindow{requests++;if([self isFlushWindowDisabled])deferred++;else eligible++;[super flushWindow];}
- (int)ownDepth{return _flushDisabled;}
- (BOOL)ownPending{return _flushNeeded;}
@end
@interface FlushView:NSView @end
@implementation FlushView
- (void)drawRect:(NSRect)dirty{
 ++draws;[[NSColor redColor]setFill];NSRectFill([self bounds]);
 [[NSColor greenColor]setFill];NSRectFill(NSMakeRect(0,0,13,11));
 [[NSColor blueColor]setFill];NSRectFill(NSMakeRect(173,89,19,7));
}
@end
@interface FlushDriver:NSObject { @public FlushWindow *window;FlushView *view;NSString *mode;unsigned ticks;BOOL tested; }
- (void)tick:(NSTimer *)timer;
- (void)contract;
@end
@implementation FlushDriver
- (void)contract{
 // Public positive control clears any pending frontend flush before testing display.
 [window flushWindow];
 NSDictionary *positive=[[window platformWindow]eglPresentationStatistics];
 expectFlush([positive[@"clientPresents"]unsignedLongLongValue]>0&&[positive[@"captured"]unsignedIntValue]>0,"explicit flush positive control delivers actual own native client pixels");
 unsigned before=window->requests,wasDrawn=draws;
 expectFlush(![window ownPending]&&![window isFlushWindowDisabled],"public explicit flush clears pending state with flushing enabled");
 [window display];
 expectFlush(draws>wasDrawn,"display really redraws original CPU content");
 expectFlush(window->requests==before+1,"display requests one actual public flush after completed redraw");
 expectFlush([window ownDepth]==0,"display restores original enabled depth");
 [window flushWindow];
 [window disableFlushWindow];[window disableFlushWindow];
 before=window->deferred;unsigned eligible=window->eligible;wasDrawn=draws;
 [window display];
 expectFlush(draws>wasDrawn&&[window ownDepth]==2,"display draws but preserves both caller disable levels");
 expectFlush(window->deferred==before+1&&window->eligible==eligible&&[window ownPending],"nested display queues its flush without submitting while caller-disabled");
 [window enableFlushWindow];before=window->deferred;[window flushWindowIfNeeded];
 expectFlush([window ownDepth]==1&&window->deferred==before+1&&window->eligible==eligible&&[window ownPending],"one enable and pending retry retain final caller disable and pending work");
 [window enableFlushWindow];before=window->eligible;[window flushWindowIfNeeded];
 expectFlush([window ownDepth]==0&&window->eligible==before+1&&![window ownPending],"fully enabled pending retry reaches actual backend once");
 before=window->requests;[window flushWindowIfNeeded];expectFlush(window->requests==before,"clean pending retry submits nothing");
 [window orderOut:nil];before=window->requests;wasDrawn=draws;[window display];
 expectFlush(window->requests==before&&draws==wasDrawn,"hidden display requests neither drawing nor backend flush");
}
- (void)tick:(NSTimer *)timer{
 ++ticks;id backend=[window platformWindow];NSDictionary *stats=[backend eglPresentationStatistics];
 printf("TICK %u draws=%u visible=%d depth=%d pending=%d mapped=%d configured=%d configurePending=%d framePending=%d needsPresent=%d presents=%llu captured=%u\n",ticks,draws,[window isVisible],[window ownDepth],[window ownPending],ownFlag(backend,"_mapped",NO),ownFlag(backend,"_configured",NO),ownFlag(backend,"_configureUpdatePending",NO),ownFlag(backend,"_frameCallback",YES),ownFlag(backend,"_needsPresent",NO),[stats[@"clientPresents"]unsignedLongLongValue],[stats[@"captured"]unsignedIntValue]);
 if([mode isEqualToString:@"contract"]){
  if(ownFlag(backend,"_configured",NO)==1&&ownFlag(backend,"_configureUpdatePending",NO)==0&&ownFlag(backend,"_context",YES)==1){[self contract];tested=YES;}
  else if(ticks<100)return;
  expectFlush(tested,"actual native configure reached before public flush contract checks");
 }else{
  [window display];if(ticks<8)return;
  stats=[backend eglPresentationStatistics];
  expectFlush(draws>=8,"natural public display repeatedly drew own input");
  expectFlush([stats[@"clientPresents"]unsignedLongLongValue]>0,"natural display delivers actual first native client frame without explicit caller flush");
  expectFlush([stats[@"captureRequested"]boolValue]&&[stats[@"captureReady"]boolValue]&&[stats[@"captureError"]unsignedIntValue]==0,"own client capture configured successfully");
  expectFlush([stats[@"captured"]unsignedIntValue]>0,"actual natural frame creates own pixel artifact for independent checker");
 }
 [window orderOut:nil];[timer invalidate];[NSApp stop:nil];
 [NSApp postEvent:[NSEvent otherEventWithType:NSApplicationDefined location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0]atStart:NO];
}
- (void)dealloc{[window release];[view release];[mode release];[super dealloc];}
@end
int main(int argc,char **argv){@autoreleasepool{
 setbuf(stdout,NULL);puts("ENTER original NSWindow display/flush regression");
 if(argc!=3)return 2;NSString *mode=[NSString stringWithUTF8String:argv[2]];
 if(![@[@"contract",@"natural"]containsObject:mode])return 2;
 setenv("DARLING_APPKIT_CAPTURE_DIR",argv[1],1);[NSApplication sharedApplication];
 FlushDriver *driver=[FlushDriver new];driver->mode=[mode copy];
 driver->window=[[FlushWindow alloc]initWithContentRect:NSMakeRect(100,100,192,96)styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
 [driver->window setReleasedWhenClosed:NO];[driver->window setTitle:@"Own flush input"];
 driver->view=[[FlushView alloc]initWithFrame:NSMakeRect(0,0,192,96)];[driver->window setContentView:driver->view];[driver->window orderFront:nil];[driver->window display];
 NSTimer *timer=[NSTimer scheduledTimerWithTimeInterval:.05 target:driver selector:@selector(tick:)userInfo:nil repeats:YES];
 [NSApp run];[timer invalidate];[driver release];
 printf("RESULT %u failures\n",failures);return failures?1:0;
}}
