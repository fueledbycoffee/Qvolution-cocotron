#import <AppKit/AppKit.h>
#import <AppKit/NSPopUpWindow.h>
#import <AppKit/NSPopUpView.h>
#import <CoreGraphics/CGWindowPrivate.h>
#import "../AppKit/Wayland.backend/WaylandFullscreen.h"
#import <objc/runtime.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>
#ifdef NDEBUG
#error Assertions required
#endif
@interface NSObject (WaylandOutputProbe)
- (BOOL)isMapped;
- (id)waylandDisplay;
- (size_t)fullscreenOutputs:(WaylandFullscreenOutput *)outputs
                   proxies:(struct wl_proxy **)proxies max:(size_t)max entered:(NSSet *)entered;
@end
@interface ProbeStopper : NSObject
@end
@implementation ProbeStopper
- (void)fire:(NSTimer *)timer {
    [NSApp stop:nil];
    [NSApp postEvent:[NSEvent otherEventWithType:NSApplicationDefined location:NSZeroPoint
            modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0]
            atStart:YES];
}
@end
@interface ImmediateView : NSPopUpView
@end
@implementation ImmediateView
- (NSInteger)runTrackingWithEvent:(NSEvent *)event { return 0; }
@end
@interface QuietPopup : NSPopUpWindow
- (NSPopUpView *)popupView;
@end
@implementation QuietPopup
- (void)orderFront:(id)sender {}
- (NSPopUpView *)popupView { return _view; }
@end
int main(int argc, char **argv) {
    @autoreleasepool {
        setbuf(stdout,NULL);
        puts("ENTER popup output probe");
        [NSApplication sharedApplication];
        puts("RETURN sharedApplication");
        NSWindow *parent = [[NSWindow alloc] initWithContentRect:NSMakeRect(100,100,500,300)
                styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
        [parent setTitle:@"Qvolution popup output probe"];
        puts("CALL makeKeyAndOrderFront");
        [parent makeKeyAndOrderFront:nil];
        puts("RETURN makeKeyAndOrderFront");
        ProbeStopper *stopper = [[[ProbeStopper alloc] init] autorelease];
        [NSTimer scheduledTimerWithTimeInterval:1 target:stopper selector:@selector(fire:)
                userInfo:nil repeats:NO];
        [NSApp run];
        id nativeParent = [parent platformWindow];
        assert([NSStringFromClass([nativeParent class]) isEqualToString:@"WaylandWindow"]);
        Ivar membershipIvar = class_getInstanceVariable([nativeParent class], "_surfaceOutputs");
        assert(membershipIvar);
        NSMutableSet *membership = object_getIvar(nativeParent, membershipIvar);
        NSSet *saved = [membership copy];
        id display = [nativeParent waylandDisplay];
        WaylandFullscreenOutput outputs[32];
        struct wl_proxy *proxies[32];
        size_t count = [display fullscreenOutputs:outputs proxies:proxies max:32 entered:saved];
        printf("AppKit guessed screen=%s frame=%s; actual mapped=%d output count=%zu\n",
                [NSStringFromRect([[parent screen] frame]) UTF8String],
                [NSStringFromRect([parent frame]) UTF8String], [nativeParent isMapped], count);
        for (size_t i=0; i<count; ++i)
            printf("logical output%zu=%dx%d entered=%d\n",i, outputs[i].width,outputs[i].height,outputs[i].entered);
        if (argc>1 && strcmp(argv[1],"--diagnostic")==0) {
            [saved release]; [parent orderOut:nil]; [parent release]; return 0;
        }
        assert(count > 0);
        NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Many"];
        for (NSUInteger i=0; i<400; ++i)
            [menu addItemWithTitle:[NSString stringWithFormat:@"Item %lu",(unsigned long)i]
                    action:NULL keyEquivalent:@""];
        // The parent surface's coordinates do not locate it globally on Wayland.
        // Inject each real output's enter membership into this own-source parent;
        // the actual backend hook must use real logical topology, not _frame.
        for (size_t i=0; i<count; ++i) {
            [membership removeAllObjects];
            [membership addObject:[NSValue valueWithPointer:proxies[i]]];
            QuietPopup *popup = [[QuietPopup alloc] initWithFrame:NSMakeRect(120,200,120,20)];
            [popup setMenu:menu]; [popup selectItemAtIndex:399];
            object_setClass([popup popupView], [ImmediateView class]);
            id nativePopup = [popup platformWindow];
            assert(![nativePopup isMapped]);
            [popup runTrackingWithEvent:nil];
            assert([popup frame].size.height <= outputs[i].height);
            assert([popup frame].size.width <= outputs[i].width);
            assert(![nativePopup isMapped]);
            assert([nativePopup respondsToSelector:@selector(maximumPopupSize)]);
            CGSize limit = [nativePopup maximumPopupSize];
            assert(limit.width == outputs[i].width && limit.height == outputs[i].height);
            printf("output%zu popup viewport=%s\n",i,[NSStringFromSize([popup frame].size) UTF8String]);
            [popup release];
        }
        [membership setSet:saved];
        [saved release]; [menu release]; [parent orderOut:nil]; [parent release];
        puts("PASS: popup bounds follow actual parent output membership");
    }
    return 0;
}
