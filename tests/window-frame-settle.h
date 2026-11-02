#ifndef FIXTURE_WINDOW_FRAME_SETTLE_H
#define FIXTURE_WINDOW_FRAME_SETTLE_H
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include "window-frame-settle-state.h"
@interface NSObject (FixtureFrameBackend)
- (id)platformWindow;
@end
static double fixtureFrameTime(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9;
}
static int fixtureObserveWindow(FixtureFrameState *state, NSWindow *window) {
    NSRect f = [window frame], c = [[window contentView] bounds];
    id backend = [window platformWindow];
    Ivar ivar = class_getInstanceVariable([backend class], "_configured");
    BOOL configured = YES;
    if (ivar) memcpy(&configured, (char *)backend + ivar_getOffset(ivar), sizeof configured);
    FixtureFrameSample sample = {f.origin.x, f.origin.y, f.size.width, f.size.height,
        c.size.width, c.size.height, [window backingScaleFactor], configured, [window isKeyWindow]};
    return fixtureFrameObserve(state, sample, fixtureFrameTime());
}
static void fixtureReportFrame(FixtureFrameState *state, const char *label, int result) {
    FixtureFrameSample f = state->previous;
    fprintf(stderr, "FIXTURE_FRAME %s label=%s frame=%.3f,%.3f %.3fx%.3f content=%.3fx%.3f scale=%.3f configured=%d key=%d elapsed=%.3f\n",
        result == 1 ? "settled" : "timeout", label, f.x, f.y, f.width, f.height,
        f.contentWidth, f.contentHeight, f.scale, f.configured, f.key, fixtureFrameTime() - state->began);
}
// Use this object directly from fixtures that already own an NSApp timer loop.
@interface FixtureWindowFramePump : NSObject {
@public NSWindow *window; FixtureFrameState state; int result;
}
- (void)tick:(NSTimer *)timer;
@end
@implementation FixtureWindowFramePump
- (void)tick:(NSTimer *)timer {
    result = fixtureObserveWindow(&state, window);
    if (!result) return;
    [timer invalidate]; [NSApp stop:nil];
    [NSApp postEvent:[NSEvent otherEventWithType:NSApplicationDefined location:NSZeroPoint modifierFlags:0
        timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0] atStart:NO];
}
@end
static BOOL fixtureWaitForWindowFrame(NSWindow *window, const char *label) {
    FixtureWindowFramePump *pump = [FixtureWindowFramePump new]; pump->window = window;
    fixtureObserveWindow(&pump->state, window);
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:.05 target:pump selector:@selector(tick:)
        userInfo:nil repeats:YES];
    [NSApp run]; [timer invalidate]; fixtureReportFrame(&pump->state, label, pump->result);
    BOOL settled = pump->result == 1; [pump release]; return settled;
}
#endif
