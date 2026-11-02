// Source-owned AppKit/Wayland fixture for damage-limited redraw. Reads only our own
// window's backing store and our backend's presentation counters.
//   appkit-damage-redraw verify    partial updates, then a full redraw; backing must match
//                                  (run with DARLING_APPKIT_DAMAGE_VERIFY=1: every committed
//                                  shm buffer must equal the backing store)
//   appkit-damage-redraw timing    small-region and full-window update times
//   appkit-damage-redraw animate   a 48x48 view animated by a 60 Hz timer for 3 s
// DAMAGE_EVIDENCE_DIR (optional) receives raw backing captures for cross-runtime comparison.
#import <AppKit/AppKit.h>
#import <AppKit/NSMainMenuView.h>
#import "../AppKit/NSTitlebarRenderer.h"
#import <Onyx2D/O2Context_builtin.h>
#import <Onyx2D/O2Surface.h>
#import <objc/runtime.h>
#include "damage-fixture-state.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

@interface NSObject (DamageFixtureBackend)
- (id)platformWindow;
- (NSDictionary *)eglPresentationStatistics;
- (NSTitlebarFrame)titlebarFrame;
@end

static unsigned failures, checks;
static void expect(BOOL ok, const char *name) { printf("%s %s\n", ok ? "PASS" : "FAIL", name); failures += !ok; checks++; }
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e3 + t.tv_nsec / 1e6; }
static int cmpDouble(const void *a, const void *b) { double x = *(const double *)a, y = *(const double *)b; return (x > y) - (x < y); }
static double median(double *v, int n) { qsort(v, n, sizeof *v, cmpDouble); return n ? (n & 1 ? v[n / 2] : (v[n / 2 - 1] + v[n / 2]) / 2) : NAN; }

// Time spent inside the fixture's own drawRect: implementations.
static double gradientMs, tilesMs, spinnerMs;

static NSDictionary *stats(NSWindow *w) { return [[w platformWindow] eglPresentationStatistics]; }
static unsigned long long stat(NSWindow *w, NSString *key) { id v = [stats(w) objectForKey: key]; return v ? [v unsignedLongLongValue] : 0; }
static BOOL hasDamageStats(NSWindow *w) { return [stats(w) objectForKey: @"damageRects"] != nil; }
static BOOL configured(NSWindow *w) {
    id backend = [w platformWindow];
    Ivar ivar = class_getInstanceVariable([backend class], "_configured");
    if (!ivar) { fprintf(stderr, "own Wayland backend required\n"); exit(2); }
    BOOL value; memcpy(&value, (char *)backend + ivar_getOffset(ivar), sizeof value); return value;
}
static BOOL activated(NSWindow *w) {
    NSTitlebarFrame frame = [[w platformWindow] titlebarFrame];
    return frame.state.active;
}
static BOOL framePending(NSWindow *w) {
    id backend = [w platformWindow];
    Ivar ivar = class_getInstanceVariable([backend class], "_frameCallback");
    void *value = NULL; memcpy(&value, (char *)backend + ivar_getOffset(ivar), sizeof value); return value != NULL;
}

// Full-window content that costs real raster work: bands, a grid of rounded tiles, text.
@interface Backdrop : NSView @end
@implementation Backdrop
- (BOOL)isOpaque { return YES; }
- (void)drawRect:(NSRect)dirty {
    NSRect b = [self bounds];
    double t0 = now();
    [[[[NSGradient alloc] initWithStartingColor: [NSColor colorWithCalibratedRed: .86 green: .89 blue: .95 alpha: 1]
                                    endingColor: [NSColor colorWithCalibratedRed: .97 green: .95 blue: .90 alpha: 1]] autorelease]
        drawInRect: b angle: 90];
    double t1 = now(); gradientMs += t1 - t0;
    for (CGFloat y = 8; y < NSHeight(b); y += 46)
        for (CGFloat x = 8; x < NSWidth(b); x += 58) {
            NSRect tile = NSMakeRect(x, y, 50, 38);
            if (!NSIntersectsRect(tile, dirty)) continue;
            int k = (int)(x / 58) * 7 + (int)(y / 46) * 3;
            [[NSColor colorWithCalibratedHue: (k % 23) / 23.0 saturation: .25 brightness: .97 alpha: .9] setFill];
            [[NSBezierPath bezierPathWithRoundedRect: tile xRadius: 7 yRadius: 7] fill];
        }
    tilesMs += now() - t1;
}
@end

// A small non-opaque view: its backdrop redraws behind it.
@interface Spinner : NSView { @public unsigned phase, draws; } @end
@implementation Spinner
- (void)drawRect:(NSRect)dirty {
    draws++; double t0 = now();
    NSRect b = NSInsetRect([self bounds], 4, 4);
    [[NSColor colorWithCalibratedWhite: .2 alpha: .25] setStroke];
    NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect: b]; [ring setLineWidth: 5]; [ring stroke];
    NSBezierPath *arc = [NSBezierPath bezierPath];
    NSPoint c = NSMakePoint(NSMidX(b), NSMidY(b));
    CGFloat start = (phase % 60) * 6.0;
    [arc appendBezierPathWithArcWithCenter: c radius: NSWidth(b) / 2 startAngle: start endAngle: start + 100];
    [arc setLineWidth: 5]; [[NSColor colorWithCalibratedRed: .1 green: .45 blue: .9 alpha: 1] setStroke]; [arc stroke];
    spinnerMs += now() - t0;
}
@end

@interface Driver : NSObject { @public
    NSWindow *window; Backdrop *backdrop; Spinner *spinner; NSButton *button, *check; NSTextField *field;
    NSTextView *text; NSString *mode; unsigned step, ticks; unsigned long long presentsBefore;
    double frameStart; unsigned long long animPresents0; unsigned animTicks; double animDraw[400]; BOOL keyAtStart;
    uint64_t quietPresents; unsigned quietTicks;
}
- (void)tick:(NSTimer *)timer;
@end

static NSData *capture(Driver *d) {
    O2Context_builtin *context = (id)[[d->window graphicsContext] graphicsPort];
    if (![context isKindOfClass: [O2Context_builtin class]]) { fprintf(stderr, "own bitmap context required\n"); exit(2); }
    O2Surface *surface = [context surface];
    size_t w = O2SurfaceGetWidth(surface), h = O2SurfaceGetHeight(surface), stride = O2SurfaceGetBytesPerRow(surface);
    // Pixel comparisons require identical menu/decorations as well as content.
    NSSize content = [[d->window contentView] bounds].size;
    NSSize frame = [d->window frame].size;
    NSSize logical = NSMakeSize(frame.width + 2*NSTitlebarMargin,
        frame.height + 2*NSTitlebarMargin + NSTitlebarHeight);
    CGFloat scale = stat(d->window, @"scale120") / 120.0;
    printf("GEOMETRY content=%.0fx%.0f frame=%.0fx%.0f backing=%zux%zu scale=%.3f\n",
        content.width,content.height,frame.width,frame.height,w,h,scale);
    expect(NSEqualSizes(content,NSMakeSize(1600,900)),"content size stays at the requested size");
    expect(frame.width==1600 && frame.height==900+[NSMainMenuView menuHeight],
        "local menu strip stays in the frame");
    expect(w==ceil(logical.width*scale) && h==ceil(logical.height*scale),
        "backing size includes the same frame, titlebar and margins");
    NSMutableData *data = [NSMutableData dataWithLength: w * h * 4];
    const unsigned char *p = O2SurfaceGetPixelBytes(surface);
    for (size_t row = 0; row < h; row++) memcpy((char *)[data mutableBytes] + row * w * 4, p + row * stride, w * 4);
    NSString *dir = [[[NSProcessInfo processInfo] environment] objectForKey: @"DAMAGE_EVIDENCE_DIR"];
    static unsigned serial;
    printf("CAPTURE_STATE serial=%u key=%d activated=%d\n", serial,
        [d->window isKeyWindow], activated(d->window));
    expect([d->window isKeyWindow] && activated(d->window),
        "capture has compositor-confirmed active chrome and key controls");
    if (dir) {
        [data writeToFile: [dir stringByAppendingPathComponent: [NSString stringWithFormat: @"%02u-backing-%zux%zu.bgra", serial, w, h]] atomically: YES];
    }
    serial++;
    return data;
}

// One verify step: a mutation, then a display pass; the next tick waits for its present.
static void mutate(Driver *d, unsigned step) {
    switch (step) {
    case 0: d->spinner->phase++; [d->spinner setNeedsDisplay: YES]; break;
    case 1: [d->button highlight: YES]; break;
    case 2: [d->button highlight: NO]; break;
    case 3: [d->check setState: NSOnState]; break;
    case 4: [d->field setStringValue: @"Damage-limited redraw: 42"]; break;
    case 5: [d->text setSelectedRange: NSMakeRange([[d->text string] length], 0)];
            [d->text insertText: @" more"]; break;
    case 6: case 7: { // the caret blink path: direct drawing outside a display pass
        NSRect r = NSMakeRect(181, 34, 1, 16);
        [d->text lockFocus];
        [d->text drawInsertionPointInRect: r color: [NSColor blackColor] turnedOn: step == 6];
        [d->text unlockFocus]; [d->window flushWindow]; return;
    }
    case 8: // two distant regions in one pass
        d->spinner->phase++; [d->spinner setNeedsDisplay: YES]; [d->field setStringValue: @"Two regions"]; break;
    default: d->spinner->phase++; [d->spinner setNeedsDisplay: YES]; break;
    }
    [d->window displayIfNeeded];
}
enum { VerifySteps = 16 };

static void timing(Driver *d) {
    enum { N = 21, F = 5 };
    double small[N], caret[N], highlight[N], full[F], smallDraw[N], smallPresent[N], fullDraw[F], fullPresent[F]; int inlineSmall = 0;
    double g0 = gradientMs, t0s = tilesMs, s0 = spinnerMs;
    for (int i = 0; i < N; i++) {
        while (framePending(d->window)) [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: [NSDate dateWithTimeIntervalSinceNow: .002]];
        unsigned long long p0 = stat(d->window, @"clientPresents");
        double t0 = now(); d->spinner->phase++; [d->spinner setNeedsDisplay: YES]; [d->window displayIfNeeded]; small[i] = now() - t0;
        inlineSmall += stat(d->window, @"clientPresents") == p0 + 1;
        while (framePending(d->window)) [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: [NSDate dateWithTimeIntervalSinceNow: .002]];
        NSRect r = NSMakeRect(20, 20, 1, 16);
        t0 = now(); [d->text lockFocus]; [d->text drawInsertionPointInRect: r color: [NSColor blackColor] turnedOn: i & 1];
        [d->text unlockFocus]; [d->window flushWindow]; caret[i] = now() - t0;
        while (framePending(d->window)) [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: [NSDate dateWithTimeIntervalSinceNow: .002]];
        t0 = now(); [d->button highlight: !(i & 1)]; [d->window displayIfNeeded]; highlight[i] = now() - t0;
        // The same spinner update split into the display pass and its present.
        while (framePending(d->window)) [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: [NSDate dateWithTimeIntervalSinceNow: .002]];
        d->spinner->phase++; [d->spinner setNeedsDisplay: YES];
        t0 = now(); [d->window disableFlushWindow]; [d->window displayIfNeeded]; [d->window enableFlushWindow]; smallDraw[i] = now() - t0;
        t0 = now(); [d->window flushWindow]; smallPresent[i] = now() - t0;
    }
    double g1 = gradientMs, t1s = tilesMs, s1 = spinnerMs;
    for (int i = 0; i < F; i++) {
        while (framePending(d->window)) [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: [NSDate dateWithTimeIntervalSinceNow: .002]];
        double t0 = now(); [d->window display]; full[i] = now() - t0;
        while (framePending(d->window)) [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: [NSDate dateWithTimeIntervalSinceNow: .002]];
        t0 = now(); [d->window disableFlushWindow]; [[d->window contentView] display]; [d->window enableFlushWindow]; fullDraw[i] = now() - t0;
        t0 = now(); [d->window flushWindow]; fullPresent[i] = now() - t0;
    }
    for (int i = 0; i < N; i++) printf("TIME kind=small i=%d ms=%.3f\nTIME kind=caret i=%d ms=%.3f\nTIME kind=highlight i=%d ms=%.3f\n", i, small[i], i, caret[i], i, highlight[i]);
    for (int i = 0; i < F; i++) printf("TIME kind=full i=%d ms=%.3f\n", i, full[i]);
    printf("SUMMARY timing small_median_ms=%.3f caret_median_ms=%.3f highlight_median_ms=%.3f full_median_ms=%.3f small_presented_inline=%d/%d\n",
           median(small, N), median(caret, N), median(highlight, N), median(full, F), inlineSmall, N);
    printf("SUMMARY drawrect per_small_update gradient_ms=%.3f tiles_ms=%.3f spinner_ms=%.3f (2 spinner updates per iteration)\n",
           (g1 - g0) / (2 * N), (t1s - t0s) / (2 * N), (s1 - s0) / (2 * N));
    printf("SUMMARY split small_draw_median_ms=%.3f small_present_median_ms=%.3f full_draw_median_ms=%.3f full_present_median_ms=%.3f\n",
           median(smallDraw, N), median(smallPresent, N), median(fullDraw, F), median(fullPresent, F));
    expect(inlineSmall == N, "every small update presented within its display pass");
}

@implementation Driver
- (void)tick:(NSTimer *)timer {
    if (!configured(window)) { if (++ticks < 400) return; expect(NO, "window configured"); goto finish; }
    if ([mode isEqualToString: @"timing"]) {
        // timing() spins the run loop; this timer must not fire inside it.
        [timer invalidate]; [window makeFirstResponder: nil]; [window display]; timing(self); goto finish;
    }
    if ([mode isEqualToString: @"animate"]) {
        if (animTicks == 0) { [window makeFirstResponder: nil]; [window display]; frameStart = now(); animPresents0 = stat(window, @"clientPresents"); }
        double t0 = now(); spinner->phase++; [spinner setNeedsDisplay: YES]; [window displayIfNeeded];
        if (animTicks < 400) animDraw[animTicks] = now() - t0;
        if (++animTicks < 180) return;
        double elapsed = now() - frameStart; unsigned long long frames = stat(window, @"clientPresents") - animPresents0;
        int n = animTicks < 400 ? animTicks : 400;
        printf("SUMMARY animate ticks=%u elapsed_ms=%.1f presents=%llu frame_ms=%.2f fps=%.1f draw_median_ms=%.3f damage_pixels=%llu copied_pixels=%llu\n",
               animTicks, elapsed, frames, frames ? elapsed / frames : NAN, frames * 1000.0 / elapsed, median(animDraw, n),
               stat(window, @"damagePixels"), stat(window, @"copiedPixels"));
        expect(frames > 0, "animation presented frames");
        goto finish;
    }
    // verify
    if (step == 0) {
        // Key status alone does not describe the compositor-owned chrome.
        // Never compare an active shm frame with an inactive EGL frame.
        if (++ticks >= 400) { expect(NO, "settled compositor activation"); goto finish; }
        unsigned long long presents = stat(window, @"clientPresents");
        if (!DamageFixtureSettled([window isKeyWindow], activated(window), presents,
                                  &quietPresents, &quietTicks)) return;
        ticks = 0; keyAtStart = [window isKeyWindow];
        // No first responder: a blinking caret would draw at times of its own.
        [window makeFirstResponder: nil];
        presentsBefore = stat(window, @"clientPresents") + 1; [window display]; step = 1; return;
    }
    if (![window isKeyWindow] || !activated(window)) {
        expect(NO, "compositor activation stays stable during verification"); goto finish;
    }
    if (stat(window, @"clientPresents") < presentsBefore) { if (++ticks < 400) return; expect(NO, "present after each step"); goto finish; }
    ticks = 0;
    if (step <= VerifySteps) {
        unsigned long long p0 = stat(window, @"clientPresents"), d0 = stat(window, @"damagePixels");
        mutate(self, step - 1);
        printf("STEP %u presents=%llu damage_pixels_before=%llu\n", step - 1, p0, d0);
        presentsBefore = p0 + 1; step++; return;
    }
    {
        NSData *incremental = [[capture(self) copy] autorelease];
        unsigned long long damaged = stat(window, @"damagePixels"), copied = stat(window, @"copiedPixels"), whole = stat(window, @"wholeDamagePresents");
        unsigned long long presents = stat(window, @"clientPresents");
        [window display];
        NSData *full = capture(self);
        size_t changed = 0; const unsigned char *a = [incremental bytes], *b = [full bytes];
        if ([incremental length] == [full length]) for (size_t i = 0; i < [full length]; i += 4) changed += memcmp(a + i, b + i, 4) != 0;
        printf("CHECK backing incremental-vs-full changed_pixels=%zu bytes=%zu key_at_start=%d key_at_end=%d\n", changed, [full length], keyAtStart, [window isKeyWindow]);
        expect([incremental isEqualToData: full], "backing after partial updates equals a full redraw");
        expect(spinner->draws >= 3, "spinner redrew");
        printf("STATS presents=%llu damage_pixels=%llu copied_pixels=%llu whole_damage_presents=%llu verified=%llu stale_verified=%llu damage_stats=%d\n",
               presents, damaged, copied, whole, stat(window, @"verifiedPresents"), stat(window, @"staleVerifiedPresents"), hasDamageStats(window));
        if (hasDamageStats(window)) {
            expect(stat(window, @"verifiedPresents") >= VerifySteps, "every present verified (DARLING_APPKIT_DAMAGE_VERIFY=1)");
            expect(stat(window, @"staleVerifiedPresents") == 0, "every committed buffer equals the backing store");
        }
    }
finish:
    [window orderOut: nil]; [timer invalidate]; [NSApp stop: nil];
    [NSApp postEvent: [NSEvent otherEventWithType: NSApplicationDefined location: NSZeroPoint modifierFlags: 0 timestamp: 0
                                      windowNumber: 0 context: nil subtype: 0 data1: 0 data2: 0] atStart: NO];
}
@end

int main(int argc, char **argv) { @autoreleasepool {
    setbuf(stdout, NULL);
    // Desktop menu export can asynchronously remove the local menu strip.
    // Keep identical window geometry for shm/EGL backing-pixel comparisons.
    setenv("DARLING_NO_GLOBAL_MENU", "1", 1);
    [NSApplication sharedApplication];
    Driver *d = [Driver new];
    d->mode = [[NSString alloc] initWithUTF8String: argc > 1 ? argv[1] : "verify"];
    if (![@[@"verify", @"timing", @"animate"] containsObject: d->mode]) { fprintf(stderr, "usage: verify|timing|animate\n"); return 2; }
    NSRect content = NSMakeRect(40, 40, 1600, 900);
    d->window = [[NSWindow alloc] initWithContentRect: content styleMask: NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask
                                              backing: NSBackingStoreBuffered defer: NO];
    [d->window setReleasedWhenClosed: NO]; [d->window setTitle: @"Damage-limited redraw"];
    NSView *root = [d->window contentView];
    d->backdrop = [[Backdrop alloc] initWithFrame: [root bounds]]; [d->backdrop setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    [root addSubview: d->backdrop];
    d->spinner = [[Spinner alloc] initWithFrame: NSMakeRect(1450, 760, 48, 48)]; [d->backdrop addSubview: d->spinner];
    d->button = [[NSButton alloc] initWithFrame: NSMakeRect(60, 840, 140, 32)]; [d->button setTitle: @"Highlight me"];
    [d->button setBezelStyle: NSRoundedBezelStyle]; [d->backdrop addSubview: d->button];
    d->check = [[NSButton alloc] initWithFrame: NSMakeRect(220, 845, 160, 22)]; [d->check setButtonType: NSSwitchButton];
    [d->check setTitle: @"Check box"]; [d->backdrop addSubview: d->check];
    // Not bezeled: a bezeled field claims -isOpaque while the theme's bezel edge is
    // translucent, so a partial redraw blends the edge twice (on Stage41c3 too).
    d->field = [[NSTextField alloc] initWithFrame: NSMakeRect(400, 843, 300, 24)]; [d->field setStringValue: @"Text field"];
    [d->field setBezeled: NO]; [d->field setDrawsBackground: YES];
    [d->backdrop addSubview: d->field];
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame: NSMakeRect(60, 80, 900, 700)] autorelease];
    [scroll setHasVerticalScroller: YES];
    d->text = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 880, 700)];
    [d->text setString: @"Damage-limited redraw fixture.\nOnly invalidated regions are drawn and presented.\nThe caret blinks here"];
    [scroll setDocumentView: d->text]; [d->backdrop addSubview: scroll];
    [d->window makeKeyAndOrderFront: nil];
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval: [d->mode isEqualToString: @"animate"] ? 1.0 / 60 : .02
                                                      target: d selector: @selector(tick:) userInfo: nil repeats: YES];
    [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSEventTrackingRunLoopMode];
    [NSApp run];
    id backend = [d->window platformWindow];
    printf("SURFACE stats=%s\n", [[[[backend eglPresentationStatistics] description] stringByReplacingOccurrencesOfString: @"\n" withString: @" "] UTF8String]);
    printf("RESULT appkit-damage-redraw mode=%s failures=%u checks=%u\n", [d->mode UTF8String], failures, checks);
    return failures ? 1 : 0;
}}
