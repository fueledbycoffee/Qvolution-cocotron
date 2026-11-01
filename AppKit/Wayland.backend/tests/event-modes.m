/* Delayed mapping makes configure arrive after nextEvent's pre-wait dispatch.
 * Run under Darling on a compositor; all code and inspected state are ours. */
#import <AppKit/AppKit.h>
#import <AppKit/NSDisplay.h>
#include <stdio.h>

static unsigned exposures;
static BOOL mapped;
@interface ModeWindow : NSWindow
@end
@implementation ModeWindow
- (void) platformWindowExposed: (id) platform inRect: (NSRect) rect {
    ++exposures;
    [super platformWindowExposed: platform inRect: rect];
}
@end
static void mapWindow(CFRunLoopTimerRef timer, void *info) {
    mapped = YES;
    [(NSWindow *)info orderFront: nil];
}
int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    NSDisplay *display = [NSDisplay currentDisplay];
    if (![[NSStringFromClass([display class]) lowercaseString] containsString: @"wayland"]) return 2;
    NSArray *modes = @[NSDefaultRunLoopMode, NSModalPanelRunLoopMode,
                       NSEventTrackingRunLoopMode, @"QVPrivateEventMode"];
    for (NSString *mode in modes) {
        mapped = NO; exposures = 0;
        ModeWindow *window = [[ModeWindow alloc] initWithContentRect: NSMakeRect(40, 40, 273, 209)
                styleMask: NSTitledWindowMask backing: NSBackingStoreBuffered defer: YES];
        [window setReleasedWhenClosed: NO];
        CFRunLoopTimerContext context = {.version = 0, .info = window};
        CFRunLoopTimerRef timer = CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent() + .05,
                0, 0, 0, mapWindow, &context);
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, (CFStringRef)mode);
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 2];
        double start = CFAbsoluteTimeGetCurrent();
        do {
            [display nextEventMatchingMask: NSAnyEventMask untilDate: deadline inMode: mode dequeue: YES];
        } while (!mapped && [deadline timeIntervalSinceNow] > 0);
        double elapsed = CFAbsoluteTimeGetCurrent() - start;
        printf("mode=%s mapped=%d exposed=%u elapsed=%.3f\n", [mode UTF8String], mapped, exposures, elapsed);
        CFRunLoopTimerInvalidate(timer); CFRelease(timer);
        if (!mapped || !exposures || elapsed >= 1) return 1;
        [window close]; [window release];
    }
    [pool drain]; return 0;
}
