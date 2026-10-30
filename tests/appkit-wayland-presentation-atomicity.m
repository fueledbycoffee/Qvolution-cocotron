#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <string.h>
#import <Onyx2D/O2Context.h>
#include <stdio.h>

@interface PixelReadProbe : O2Context { @public NSUInteger reads; }
@end
@implementation PixelReadProbe
- (O2Surface *)surface {
    reads++;
    [NSException raise:@"PixelReadProbe" format:@"presentation accessed the backing pixels"];
    return nil;
}
@end
@interface NSObject (PresentationProbe)
- (void)presentIfPossible;
@end
static void setObject(id object, const char *name, id value) {
    object_setIvar(object, class_getInstanceVariable([object class], name), value);
}
static void setFlag(id object, const char *name, BOOL value) {
    Ivar ivar = class_getInstanceVariable([object class], name);
    memcpy((char *)object + ivar_getOffset(ivar), &value, sizeof(value));
}
static BOOL attemptsPixelRead(id window) {
    @try { [window presentIfPossible]; }
    @catch (NSException *exception) {
        if (![[exception name] isEqualToString:@"PixelReadProbe"]) @throw;
        return YES;
    }
    return NO;
}
int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    Class platformClass = NSClassFromString(@"WaylandWindow");
    if (!platformClass) { fprintf(stderr,"Wayland backend required\n"); return 2; }
    NSWindow *delegate = NSAllocateObject([NSWindow class], 0, NULL);
    PixelReadProbe *context = [PixelReadProbe new];
    // Bypass platform setup: only the production presentation gate is exercised.
    id window = NSAllocateObject(platformClass, 0, NULL);
    setObject(window, "_delegate", delegate);
    setObject(window, "_context", context);
    setFlag(window, "_needsPresent", YES);
    setFlag(window, "_mapped", YES);
    setFlag(window, "_configured", YES);
    [delegate disableFlushWindow];
    [delegate disableFlushWindow];
    BOOL failed = NO;
    for (NSUInteger depth=2; depth>0; depth--) {
        if (![delegate isFlushWindowDisabled]) {
            fprintf(stderr,"FAIL: NSWindow reports drawing enabled at depth=%lu\n",(unsigned long)depth);
            failed = YES;
        }
        if (attemptsPixelRead(window)) {
            fprintf(stderr,"FAIL: pending Wayland presentation reads pixels during paused drawing (depth=%lu)\n",(unsigned long)depth);
            failed = YES;
        }
        [delegate enableFlushWindow];
    }
    if ([delegate isFlushWindowDisabled]) {
        fprintf(stderr,"FAIL: NSWindow remains paused after balanced enables\n");
        failed = YES;
    }
    NSUInteger readsBeforeResume = context->reads;
    if (!attemptsPixelRead(window) || context->reads != readsBeforeResume + 1) {
        fprintf(stderr,"FAIL: presentation must resume after drawing finishes\n");
        return 1;
    }
    setObject(window, "_delegate", nil);
    setObject(window, "_context", nil);
    // No real platform window was initialized, so do not run platform teardown.
    NSDeallocateObject(window);
    [context release];
    NSDeallocateObject(delegate);
    [pool drain];
    if (failed) return 1;
    puts("PASS: pending presentation waits for nested drawing pauses to finish");
    return 0;
}
