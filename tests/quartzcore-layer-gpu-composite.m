// A CALayer tree composited by CARenderer on the GPU: moving, fading and
// scrolling layers must recomposite without drawing their content again.
// Usage: quartzcore-layer-gpu-composite [FRAMES]
// Each frame moves layer A, changes its opacity and scrolls a CAScrollLayer,
// with no explicit render call. The context's own timer must composite it.
// Every 10th frame the fixture renders once more itself and reads the GL back
// buffer before presenting: A must be at its new position with premultiplied
// red at its new opacity, and the scrolled stripe under a fixed point must be
// the band the scroll offset selects. Prints RESULT lines and exits non-zero
// on failure.
#import <AppKit/AppKit.h>
#import <OpenGL/gl.h>
#import <QuartzCore/CALayerContext.h>
#import <QuartzCore/QuartzCore.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/resource.h>
#include <time.h>
#ifdef NDEBUG
#error Assertions required
#endif

static unsigned failures, checks, renders;
static void expectThat(BOOL ok, const char *what) {
    checks++;
    if (!ok) { failures++; printf("FAIL %s\n", what); }
}
static double now(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9;
}
static double cpuSeconds(void) {
    struct rusage u; getrusage(RUSAGE_SELF, &u);
    return u.ru_utime.tv_sec + u.ru_utime.tv_usec / 1e6 + u.ru_stime.tv_sec + u.ru_stime.tv_usec / 1e6;
}

static int compare(const void *x, const void *y) {
    double a = *(const double *)x, b = *(const double *)y;
    return a < b ? -1 : a > b;
}

// Counts composites without touching the renderer: wraps -[CALayerContext render].
static IMP originalRender;
static void countingRender(id self, SEL _cmd) {
    renders++;
    ((void (*)(id, SEL))originalRender)(self, _cmd);
}

@interface Drawer : NSObject { @public unsigned solid, stripes; }
@end
@implementation Drawer
- (void) drawLayer: (CALayer *) layer inContext: (CGContextRef) context {
    CGRect b = [layer bounds];
    if ([[layer name] isEqualToString:@"A"]) {
        solid++;
        CGContextSetRGBFillColor(context, 1, 0, 0, 1);
        CGContextFillRect(context, b);
        return;
    }
    stripes++;
    for (int k = 0; k * 50 < b.size.height; k++) {
        if (k % 2) CGContextSetRGBFillColor(context, 0, 0, 1, 1);
        else CGContextSetRGBFillColor(context, 0, 1, 0, 1);
        CGContextFillRect(context, CGRectMake(0, k * 50, b.size.width, 50));
    }
}
@end

@interface Driver : NSObject {
@public
    NSWindow *window; NSView *host; CALayer *root, *a, *b; CAScrollLayer *s; Drawer *drawer;
    unsigned frame, frames; double t0, cpu0; double *renderMs; unsigned timed;
}
@end
@implementation Driver
- (CALayerContext *) context {
    CALayerContext *c = [host valueForKey:@"layerContext"];
    if (!c) { printf("FAIL no layer context\n"); exit(1); }
    return c;
}
- (void) verifyPixels {
    CALayerContext *c = [self context];
    double start = now();
    [c render];
    renderMs[timed++] = (now() - start) * 1e3;
    // The render left the layer drawable current; read before presenting it.
    CGFloat scale = [[host window] backingScaleFactor];
    unsigned char px[4] = {0};
    CGPoint pa = [a position];
    glReadPixels((GLint)(pa.x * scale), (GLint)(pa.y * scale), 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
    int expect = (int)lround([a opacity] * 255);
    char label[96];
    snprintf(label, sizeof label, "A at (%.0f,%.0f) opacity %.2f is premultiplied red %d (got %d,%d,%d,%d)",
             pa.x, pa.y, [a opacity], expect, px[0], px[1], px[2], px[3]);
    expectThat(abs(px[0] - expect) <= 2 && px[1] <= 2 && px[2] <= 2 && abs(px[3] - expect) <= 2, label);
    CGPoint origin = [s bounds].origin; CGRect sf = [s frame];
    int band = (int)floor((25 + origin.y) / 50);
    glReadPixels((GLint)((sf.origin.x + 100) * scale), (GLint)((sf.origin.y + 25) * scale), 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
    snprintf(label, sizeof label, "scroll %.0f shows band %d %s (got %d,%d,%d)", origin.y, band,
             band % 2 ? "blue" : "green", px[0], px[1], px[2]);
    expectThat(band % 2 ? (px[2] > 250 && px[1] < 5) : (px[1] > 250 && px[2] < 5), label);
    [c flush];
}
- (void) tick: (NSTimer *) timer {
    if (frame == 0) {
        expectThat(drawer->solid == 1 && drawer->stripes == 1, "each layer drew its content once before any motion");
        expectThat(CGImageGetWidth((CGImageRef)[a contents]) == 200 &&
                   CGImageGetHeight((CGImageRef)[a contents]) == 160, "contentsScale 2 rasterizes at twice the point dimensions");
        t0 = now(); cpu0 = cpuSeconds();
    }
    if (frame == frames) {
        double wall = now() - t0, cpu = cpuSeconds() - cpu0;
        expectThat(drawer->solid == 1 && drawer->stripes == 1, "moving, fading and scrolling drew no content again");
        qsort(renderMs, timed, sizeof(double), compare);
        printf("RESULT quartzcore-layer-gpu-composite failures=%u checks=%u frames=%u composites=%u "
               "content_draws=%u render_median_ms=%.3f cpu_ms_per_frame=%.3f wall_s=%.2f\n",
               failures, checks, frames, renders, drawer->solid + drawer->stripes,
               timed ? renderMs[timed / 2] : 0, cpu * 1e3 / frames, wall);
        [timer invalidate];
        [NSApp stop:nil];
        [NSApp postEvent:[NSEvent otherEventWithType:NSApplicationDefined location:NSZeroPoint modifierFlags:0
                         timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0] atStart:NO];
        return;
    }
    frame++;
    [a setPosition:CGPointMake(120 + (frame * 3) % 200, 120)];
    [a setOpacity:0.2 + (frame % 9) / 10.0];
    [s scrollToPoint:CGPointMake(0, (frame * 7) % 300)];
    if (frame % 10 == 0) [self verifyPixels];
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        setbuf(stdout, NULL);
        Method m = class_getInstanceMethod([CALayerContext class], @selector(render));
        originalRender = method_setImplementation(m, (IMP)countingRender);
        [NSApplication sharedApplication];
        Driver *d = [Driver new];
        d->frames = argc > 1 ? (unsigned)atoi(argv[1]) : 120;
        d->renderMs = calloc(d->frames + 1, sizeof(double));
        d->drawer = [Drawer new];
        d->window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 640, 480) styleMask:NSBorderlessWindowMask
                                                  backing:NSBackingStoreBuffered defer:NO];
        [d->window setReleasedWhenClosed:NO];
        d->host = [[NSView alloc] initWithFrame:NSMakeRect(20, 20, 600, 440)];
        d->root = [CALayer layer];
        d->a = [CALayer layer]; [d->a setName:@"A"]; [d->a setBounds:CGRectMake(0, 0, 100, 80)];
        [d->a setContentsScale:2];
        [d->a setDelegate:(id)d->drawer]; [d->a setNeedsDisplay];
        d->s = [CAScrollLayer layer]; [d->s setFrame:CGRectMake(380, 40, 200, 100)];
        d->b = [CALayer layer]; [d->b setName:@"B"]; [d->b setFrame:CGRectMake(0, 0, 200, 400)];
        [d->b setDelegate:(id)d->drawer]; [d->b setNeedsDisplay];
        [d->s addSublayer:d->b]; [d->root addSublayer:d->a]; [d->root addSublayer:d->s];
        [d->host setLayer:d->root]; [d->host setWantsLayer:YES];
        [[d->window contentView] addSubview:d->host];
        [d->window orderFront:nil]; [d->window display];
        // Let the first frames map the window and display the layers before moving them.
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
        NSTimer *timer = [NSTimer timerWithTimeInterval:1.0 / 60 target:d selector:@selector(tick:) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
        [NSApp run];
        // Composites the fixture did not request itself came from the context's timer.
        unsigned own = d->timed;
        printf("RESULT timer-composites=%u\n", renders - own);
        if (renders - own < d->frames / 4) { printf("FAIL property changes did not schedule composites\n"); failures++; }
        [d->window orderOut:nil];
        return failures != 0;
    }
}
