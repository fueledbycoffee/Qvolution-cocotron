/* Regression: -nextValidKeyView and -previousValidKeyView must end when the key
 * view chain cycles among views that cannot become key without containing the
 * starting view. A watchdog thread exits the process if a walk does not return,
 * so a regression fails instead of hanging. Needs no compositor; run in the guest.
 * All code and inspected state are ours. */
#import <AppKit/AppKit.h>
#include <pthread.h>
#include <stdio.h>
#include <unistd.h>

// setNextKeyView: records the reverse link through this private setter; calling it
// directly lets the fixture point a start view's previous link into a loop.
@interface NSView (QVKeyViewTest)
- (void) _setPreviousKeyView: (NSView *) previous;
@end
@interface RefusingView : NSView
@end
@implementation RefusingView
- (BOOL) acceptsFirstResponder { return NO; }
@end
@interface AcceptingView : NSView
@end
@implementation AcceptingView
- (BOOL) acceptsFirstResponder { return YES; }
@end

static volatile int stage;
static void *watchdog(void *unused) {
    sleep(10);
    printf("FAIL watchdog: a key view walk did not return (stage %d)\n", stage);
    fflush(stdout);
    _exit(3);
}

static int failures;
static void expect(const char *what, NSView *got, NSView *want) {
    BOOL ok = got == want;
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok) failures++;
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    pthread_t thread;
    pthread_create(&thread, NULL, watchdog, NULL);

    NSView *start = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
    RefusingView *a = [[RefusingView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
    RefusingView *b = [[RefusingView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
    RefusingView *c = [[RefusingView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];

    // start -> a -> b -> c -> b: the loop b, c never reaches start again.
    [start setNextKeyView: a]; [a setNextKeyView: b];
    [b setNextKeyView: c]; [c setNextKeyView: b];
    stage = 1;
    expect("next: cycle without the start, no valid view", [start nextValidKeyView], nil);
    // setNextKeyView: made b.previous = c and c.previous = b, a loop that excludes
    // start; point start's previous link into it.
    [start _setPreviousKeyView: b];
    stage = 2;
    expect("previous: cycle without the start, no valid view", [start previousValidKeyView], nil);

    // A valid view before the loop is still found; one inside the loop too.
    AcceptingView *valid = [[AcceptingView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
    [a setNextKeyView: valid]; [valid setNextKeyView: b];
    stage = 4;
    expect("next: valid view before the loop", [start nextValidKeyView], valid);
    [a setNextKeyView: b]; [c setNextKeyView: valid]; [valid setNextKeyView: b];
    stage = 5;
    expect("next: valid view inside the loop", [start nextValidKeyView], valid);

    // A plain acyclic chain and a self-referencing start behave as before.
    [start setNextKeyView: start];
    stage = 6;
    expect("next: chain that only returns to the start", [start nextValidKeyView], nil);
    [pool drain];
    printf("%s key-view-cycle failures=%d\n", failures ? "FAIL" : "PASS", failures);
    return failures ? 1 : 0;
}
