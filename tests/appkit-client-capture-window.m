// Original real-backend hook acceptance; no input or screenshot APIs.
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define CHECK(x) do{if(!(x)){fprintf(stderr,"FAIL line%d: %s\n",__LINE__,#x);exit(1);}}while(0)
@interface NSObject(CaptureStats)
- (NSDictionary *)eglPresentationStatistics;
@end
@interface CaptureView:NSView { @public BOOL changed; } @end
@implementation CaptureView
- (void)drawRect:(NSRect)rect {
    [(changed?[NSColor blueColor]:[NSColor redColor]) set];NSRectFill([self bounds]);
    [[NSColor greenColor] set];NSRectFill(NSMakeRect(0,0,13,11));
}
@end
@interface Driver:NSObject { @public NSWindow *window;CaptureView *view;NSString *directory;unsigned ticks;BOOL enabled; }
- (void)tick:(NSTimer *)timer;
@end
@implementation Driver
- (void)tick:(NSTimer *)timer {
    ++ticks;view->changed=!view->changed;[view setNeedsDisplay:YES];[window display];
    if(ticks<24)return;
    NSArray *files=[[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:NULL];
    CHECK(files!=nil);NSUInteger count=0;
    for(NSString *name in files)if([name hasPrefix:@"cpu-client-"]&&[name hasSuffix:@".png"])++count;
    CHECK(enabled?count==8:count==0);
    id backend=[window platformWindow];
    CHECK([NSStringFromClass([backend class]) isEqualToString:@"WaylandWindow"]);
    CHECK([backend respondsToSelector:@selector(eglPresentationStatistics)]);
    NSDictionary *stats=[backend eglPresentationStatistics];
    CHECK([stats[@"clientPresents"] unsignedLongLongValue]>=8);
    CHECK([stats[@"captured"] unsignedIntValue]==count);
    CHECK([stats[@"captureRequested"] boolValue]==(getenv("DARLING_APPKIT_CAPTURE_DIR")!=NULL));
    CHECK([stats[@"captureReady"] boolValue]==enabled);
    CHECK([stats[@"captureError"] unsignedIntValue]==(!enabled&&getenv("DARLING_APPKIT_CAPTURE_DIR")?1:0));
    [window orderOut:nil];[timer invalidate];[NSApp stop:nil];
    [NSApp postEvent:[NSEvent otherEventWithType:NSApplicationDefined location:NSZeroPoint modifierFlags:0 timestamp:0
        windowNumber:0 context:nil subtype:0 data1:0 data2:0] atStart:NO];
    puts("PASS: natural real-backend client presents and capture configuration/budget");
}
@end
int main(int argc,char **argv) {@autoreleasepool {
    CHECK(argc==3);NSString *directory=[NSString stringWithUTF8String:argv[1]];
    CHECK([directory isAbsolutePath]);
    CHECK([[[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:NULL] count]==0);
    BOOL enabled=strcmp(argv[2],"enabled")==0;
    CHECK(enabled||strcmp(argv[2],"off")==0||strcmp(argv[2],"invalid")==0);
    if(enabled)setenv("DARLING_APPKIT_CAPTURE_DIR",argv[1],1);
    else if(strcmp(argv[2],"invalid")==0)setenv("DARLING_APPKIT_CAPTURE_DIR","relative-invalid",1);
    else unsetenv("DARLING_APPKIT_CAPTURE_DIR");
    [NSApplication sharedApplication];Driver *driver=[Driver new];driver->enabled=enabled;driver->directory=[directory copy];
    driver->window=[[NSWindow alloc] initWithContentRect:NSMakeRect(80,100,96,64) styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
    [driver->window setReleasedWhenClosed:NO];driver->view=[[CaptureView alloc] initWithFrame:NSMakeRect(0,0,96,64)];
    [driver->window setContentView:driver->view];[driver->window orderFront:nil];[driver->window display];
    NSTimer *timer=[NSTimer scheduledTimerWithTimeInterval:0.05 target:driver selector:@selector(tick:) userInfo:nil repeats:YES];
    [NSApp run];[timer invalidate];[driver->window release];[driver->view release];[driver->directory release];[driver release];
}return 0;}
