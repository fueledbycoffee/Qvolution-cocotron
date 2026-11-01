// Wayland presentation workloads for comparing DARLING_APPKIT_RENDERER=shm and
// egl in one process each. Usage: appkit-gpu-present-bench MODE FRAMES
//   present  repaint the whole window every frame (a full-window present)
//   scroll   scroll an NSScrollView document by 24 points every frame
//   fade     redraw one view with a new opacity every frame
//   damage   repaint one 160x40 rectangle per frame and report it as damage
//   soak     present FRAMES whole-window frames; descriptors and resident
//            size must not grow between frame 100 and the last frame
// The window's backing surface is sized to QV_BENCH_WIDTH x QV_BENCH_HEIGHT
// pixels (default 1932x1144). Prints one RESULT line of JSON. Statistics come
// from the backend's opt-in present timer (DARLING_APPKIT_PRESENT_TIMING=1),
// which this fixture sets, and from getrusage for the whole process.
#import <AppKit/AppKit.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>
#ifdef NDEBUG
#error Assertions required
#endif

@interface NSWindow (GPUPresentBench)
- (id) platformWindow;
@end
@interface NSObject (GPUPresentBench)
- (NSDictionary *) eglPresentationStatistics;
- (void) addDamageRect: (CGRect) rect;
- (NSPoint) contentOffset;
@end

static void fail(const char *message) {
    fprintf(stderr, "FAIL: %s\n", message);
    exit(1);
}

static double now(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

static double cpuSeconds(void) {
    struct rusage usage;
    if (getrusage(RUSAGE_SELF, &usage) != 0) fail("getrusage");
    return usage.ru_utime.tv_sec + usage.ru_utime.tv_usec / 1e6 + usage.ru_stime.tv_sec + usage.ru_stime.tv_usec / 1e6;
}

static int openDescriptors(void) {
    int count = 0, limit = getdtablesize();
    if (limit > 65536) limit = 65536;
    for (int fd = 0; fd < limit; fd++)
        if (fcntl(fd, F_GETFD) != -1) count++;
    return count;
}

// Resident size in kB from the host's procfs, or -1 when it cannot be read.
static long residentKilobytes(void) {
    const char *paths[] = {"/proc/self/status", "/Volumes/SystemRoot/proc/self/status"};
    for (int i = 0; i < 2; i++) {
        FILE *f = fopen(paths[i], "r");
        if (!f) continue;
        char line[256]; long kb = -1;
        while (fgets(line, sizeof line, f))
            if (sscanf(line, "VmRSS: %ld kB", &kb) == 1) break;
        fclose(f);
        if (kb >= 0) return kb;
    }
    return -1;
}

static int compareDoubles(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return x < y ? -1 : x > y;
}

static double percentile(double *v, size_t n, double p) {
    if (n == 0) return 0;
    qsort(v, n, sizeof *v, compareDoubles);
    size_t i = (size_t)(p * (n - 1) + 0.5);
    return v[i];
}

@interface PaintView : NSView { @public unsigned frame; CGFloat alpha; BOOL stripes; }
@end
@implementation PaintView
- (BOOL) isOpaque { return YES; }
- (void) drawRect: (NSRect) dirty {
    if (stripes) {
        // A document of 40-point bands with distinct colours, so scrolled pixels differ.
        NSRect b = [self bounds];
        for (CGFloat y = floor(NSMinY(dirty) / 40) * 40; y < NSMaxY(dirty); y += 40) {
            unsigned band = (unsigned)(y / 40);
            [[NSColor colorWithCalibratedRed:(band * 37 % 256) / 255.0 green:(band * 91 % 256) / 255.0
                                        blue:(band * 13 % 256) / 255.0 alpha:1] set];
            NSRectFill(NSMakeRect(NSMinX(b), y, NSWidth(b), 40));
        }
        return;
    }
    [[NSColor colorWithCalibratedRed:(frame % 7) / 6.0 green:(frame % 5) / 4.0 blue:(frame % 3) / 2.0 alpha:1] set];
    NSRectFill(dirty);
    if (alpha > 0) {
        [[NSColor colorWithCalibratedRed:1 green:0.5 blue:0 alpha:alpha] set];
        NSRectFillUsingOperation(NSInsetRect([self bounds], 40, 40), NSCompositeSourceOver);
    }
}
@end

@interface Bench : NSObject {
@public
    NSWindow *window; PaintView *view, *fadeView; NSScrollView *scroller;
    const char *mode; unsigned frames, done, sized, resizes; uint64_t presents;
    double *present, *frameTimes, start, cpuStart, last;
    int fdEarly; long rssEarly; uint64_t timedEarly;
}
@end
@implementation Bench
- (NSDictionary *) stats {
    NSDictionary *s = [[window platformWindow] eglPresentationStatistics];
    if (!s) fail("backend statistics");
    return s;
}
- (void) drawNextFrame {
    if (!strcmp(mode, "scroll")) {
        NSClipView *clip = [scroller contentView];
        NSPoint origin = [clip bounds].origin;
        CGFloat limit = NSHeight([[scroller documentView] frame]) - NSHeight([clip bounds]);
        origin.y = origin.y + 24 > limit ? 0 : origin.y + 24;
        [clip scrollToPoint:origin];
        [scroller reflectScrolledClipView:clip];
    } else if (!strcmp(mode, "fade")) {
        fadeView->alpha = 0.05 + (done % 19) / 20.0;
        [fadeView setNeedsDisplay:YES];
    } else if (!strcmp(mode, "damage")) {
        view->frame++;
        NSRect r = NSMakeRect(100 + (done % 10) * 40, 200, 160, 40);
        [view setNeedsDisplayInRect:r];
        // Window points to backing pixels, top row first, outset for rounding.
        NSDictionary *s = [self stats];
        CGFloat scale = [s[@"scale120"] doubleValue] / 120.0, height = NSHeight([[window contentView] bounds]);
        NSPoint offset = [[window platformWindow] contentOffset];
        CGRect pixels = CGRectMake((NSMinX(r) + offset.x) * scale - 2, (height - NSMaxY(r) + offset.y) * scale - 2,
                                   NSWidth(r) * scale + 4, NSHeight(r) * scale + 4);
        [[window platformWindow] addDamageRect:pixels];
    } else {
        view->frame++;
        [view setNeedsDisplay:YES];
    }
    [window displayIfNeeded];
}
- (void) tick: (NSTimer *) timer {
    NSDictionary *s = [self stats];
    if ([s[@"failures"] unsignedLongLongValue] && [s[@"renderer"] isEqualToString:@"egl"]) fail("EGL presentation failure");
    uint64_t p = [s[@"clientPresents"] unsignedLongLongValue];
    if (p == presents) {
        if (now() - last > 10) fail("no present for 10 s");
        return;
    }
    presents = p; double t = now();
    if (!sized) {
        // Size the backing surface in pixels, whatever the output scale.
        int w = getenv("QV_BENCH_WIDTH") ? atoi(getenv("QV_BENCH_WIDTH")) : 1932;
        int h = getenv("QV_BENCH_HEIGHT") ? atoi(getenv("QV_BENCH_HEIGHT")) : 1144;
        int sw = [s[@"surfaceWidth"] intValue], sh = [s[@"surfaceHeight"] intValue];
        if (sw == w && sh == h) {
            sized = 1; start = t; cpuStart = cpuSeconds(); timedEarly = [s[@"presentsTimed"] unsignedLongLongValue];
        } else {
            if (++resizes > 8) fail("cannot size the backing surface");
            NSSize content = [[window contentView] bounds].size;
            [window setContentSize:NSMakeSize(round(content.width * w / sw), round(content.height * h / sh))];
            last = t; [view setNeedsDisplay:YES]; [window displayIfNeeded];
            return;
        }
    } else {
        present[done] = [s[@"lastPresentNanoseconds"] doubleValue] / 1e6;
        frameTimes[done] = (t - last) * 1e3;
        done++;
        if (done == 100) { fdEarly = openDescriptors(); rssEarly = residentKilobytes(); }
    }
    last = t;
    if (done == frames) { [self finish:s]; [timer invalidate]; return; }
    [self drawNextFrame];
}
- (void) finish: (NSDictionary *) s {
    double wall = now() - start, cpu = cpuSeconds() - cpuStart;
    int fdLate = openDescriptors(); long rssLate = residentKilobytes();
    double medianPresent = percentile(present, done, 0.5), p95Present = percentile(present, done, 0.95);
    double medianFrame = percentile(frameTimes, done, 0.5);
    NSMutableDictionary *r = [NSMutableDictionary dictionaryWithDictionary:@{
        @"mode": @(mode), @"frames": @(done), @"renderer": s[@"renderer"], @"requested": s[@"requested"],
        @"fallbackReason": s[@"fallbackReason"], @"surface": [NSString stringWithFormat:@"%@x%@", s[@"surfaceWidth"], s[@"surfaceHeight"]],
        @"scale120": s[@"scale120"], @"presentMedianMs": @(medianPresent), @"presentP95Ms": @(p95Present),
        @"frameMedianMs": @(medianFrame), @"wallSeconds": @(wall), @"cpuSeconds": @(cpu),
        @"cpuMsPerFrame": @(cpu * 1e3 / done), @"swaps": s[@"swaps"], @"checks": s[@"checks"],
        @"fullUploads": s[@"fullUploads"], @"partialUploads": s[@"partialUploads"],
        @"uploadedBytes": s[@"uploadedBytes"], @"lastUploadBytes": s[@"lastUploadBytes"],
        @"failures": s[@"failures"], @"timed": @([s[@"presentsTimed"] unsignedLongLongValue] - timedEarly),
        @"fdAt100": @(fdEarly), @"fdAtEnd": @(fdLate), @"rssKbAt100": @(rssEarly), @"rssKbAtEnd": @(rssLate)}];
    printf("RESULT %s\n", [[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:r options:0 error:NULL]
                                                 encoding:NSUTF8StringEncoding] UTF8String]);
    const char *expect = getenv("QV_BENCH_EXPECT_RENDERER");
    if (expect && strcmp(expect, [s[@"renderer"] UTF8String])) fail("unexpected renderer");
    if (!strcmp(mode, "damage") && [s[@"renderer"] isEqualToString:@"egl"] && [s[@"partialUploads"] unsignedLongLongValue] < done - 1)
        fail("damage frames were not partial uploads");
    if (!strcmp(mode, "soak") && frames >= 200) {
        if (fdLate != fdEarly) fail("descriptor count changed between frame 100 and the end");
        // Allow allocator noise; a per-frame leak of one window surface would be ~8.8 MB/frame.
        if (rssEarly < 0 || rssLate - rssEarly > 8192) fail("resident size grew by more than 8 MB");
    }
    [NSApp stop:nil];
    [NSApp postEvent:[NSEvent otherEventWithType:NSApplicationDefined location:NSZeroPoint modifierFlags:0 timestamp:0
                                    windowNumber:0 context:nil subtype:0 data1:0 data2:0] atStart:NO];
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        setbuf(stdout, NULL);
        if (argc < 3) fail("usage: MODE FRAMES");
        setenv("DARLING_APPKIT_PRESENT_TIMING", "1", 1);
        [NSApplication sharedApplication];
        Bench *b = [Bench new];
        b->mode = argv[1]; b->frames = (unsigned)atoi(argv[2]);
        if (!b->frames) fail("FRAMES");
        const char *modes[] = {"present", "scroll", "fade", "damage", "soak"};
        BOOL known = NO;
        for (int i = 0; i < 5; i++) known |= !strcmp(b->mode, modes[i]);
        if (!known) fail("unknown MODE");
        b->present = calloc(b->frames, sizeof(double)); b->frameTimes = calloc(b->frames, sizeof(double));
        NSRect content = NSMakeRect(0, 0, 1932, 1144);
        b->window = [[NSWindow alloc] initWithContentRect:content styleMask:NSBorderlessWindowMask
                                                  backing:NSBackingStoreBuffered defer:NO];
        [b->window setReleasedWhenClosed:NO]; [b->window setOpaque:YES];
        b->view = [[PaintView alloc] initWithFrame:content];
        [b->view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        if (!strcmp(b->mode, "scroll")) {
            b->scroller = [[NSScrollView alloc] initWithFrame:content];
            [b->scroller setHasVerticalScroller:YES];
            [b->scroller setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
            PaintView *document = [[[PaintView alloc] initWithFrame:NSMakeRect(0, 0, 1900, 40 * 400)] autorelease];
            document->stripes = YES;
            [b->scroller setDocumentView:document];
            [b->view addSubview:b->scroller];
        } else if (!strcmp(b->mode, "fade")) {
            b->fadeView = [[PaintView alloc] initWithFrame:NSMakeRect(200, 150, 800, 600)];
            [b->view addSubview:b->fadeView];
        }
        [b->window setContentView:b->view];
        [b->window orderFront:nil]; [b->window display];
        b->last = now();
        NSTimer *timer = [NSTimer timerWithTimeInterval:0.001 target:b selector:@selector(tick:) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
        [NSApp run];
        [b->window orderOut:nil];
    }
    return 0;
}
