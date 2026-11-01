// Original pixel checks for the Qvolution scroller and menu theme (visual theme
// spec, section 5 and phase P5). Views draw into caller-owned CPU bitmaps.
// Vertical positions are checked both ways up, because whether a flipped view's
// first row lands at the top of the bitmap depends on the context, not on the
// theme. Onyx2D's CPU bitmaps hold premultiplied components.
#import <AppKit/AppKit.h>
#import <AppKit/NSMenuView.h>
#import <AppKit/NSMenuWindow.h>
#import <AppKit/NSPopUpView.h>
#import <AppKit/NSPopUpWindow.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned failures, checks;
static void expect(BOOL ok, const char *what) {
    printf("%s: %s\n", ok ? "PASS" : "FAIL", what);
    failures += !ok;
    checks++;
}

@interface NSScroller (P5Fixture)
- (CGFloat) _overlayOpacity;
@end

typedef struct { int w, h; unsigned char *p; } Raster;
typedef struct { int r, g, b, a; } Pixel;

static Raster raster(NSView *view) {
    Raster r = {(int) NSWidth([view bounds]), (int) NSHeight([view bounds]), NULL};
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes: NULL pixelsWide: r.w pixelsHigh: r.h bitsPerSample: 8
                     samplesPerPixel: 4 hasAlpha: YES isPlanar: NO colorSpaceName: NSDeviceRGBColorSpace
                        bitmapFormat: NSAlphaNonpremultipliedBitmapFormat bytesPerRow: r.w * 4
                        bitsPerPixel: 32] autorelease];
    memset([rep bitmapData], 0, r.w * r.h * 4);
    NSGraphicsContext *old = [[NSGraphicsContext currentContext] retain];
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: rep]];
    [view drawRect: [view bounds]];
    [NSGraphicsContext setCurrentContext: old];
    [old release];
    r.p = malloc(r.w * r.h * 4);
    memcpy(r.p, [rep bitmapData], r.w * r.h * 4);
    return r;
}

static Pixel at(Raster r, int x, int y) {
    unsigned char *q = r.p + (y * r.w + x) * 4;
    return (Pixel){q[0], q[1], q[2], q[3]};
}

// Opaque sRGB pixel of a colour, composited over an opaque background.
static Pixel over(NSColor *color, Pixel bg) {
    NSColor *c = [color colorUsingColorSpaceName: NSDeviceRGBColorSpace];
    double a = [c alphaComponent];
    return (Pixel){(int) lround([c redComponent] * 255 * a + bg.r * (1 - a)),
                   (int) lround([c greenComponent] * 255 * a + bg.g * (1 - a)),
                   (int) lround([c blueComponent] * 255 * a + bg.b * (1 - a)), 255};
}

static BOOL near(Pixel p, Pixel q, int tolerance) {
    return abs(p.r - q.r) <= tolerance && abs(p.g - q.g) <= tolerance && abs(p.b - q.b) <= tolerance &&
           abs(p.a - q.a) <= tolerance;
}

static void show(const char *label, Pixel p) {
    printf("PIXEL %s %d %d %d %d\n", label, p.r, p.g, p.b, p.a);
}

static int columnsWithAlpha(Raster r, int y) {
    int n = 0;
    for (int x = 0; x < r.w; x++) n += at(r, x, y).a > 8;
    return n;
}

static int firstColumnWithAlpha(Raster r, int y) {
    for (int x = 0; x < r.w; x++)
        if (at(r, x, y).a > 8) return x;
    return -1;
}

static NSScroller *vertical(NSScrollerStyle style) {
    NSScroller *s = [[[NSScroller alloc] initWithFrame: NSMakeRect(0, 0, 15, 200)] autorelease];
    [s setScrollerStyle: style];
    [s setEnabled: YES];
    [s setFloatValue: 0.5 knobProportion: 0.3];
    return s;
}

static void scrollerChecks(void) {
    Pixel white = {255, 255, 255, 255};
    Pixel track = over([NSColor scrollBarColor], white);
    Pixel separator = over([NSColor separatorColor], track);
    Pixel knob = over([NSColor knobColor], track);
    Pixel knobActive = over([[NSColor knobColor] colorWithAlphaComponent: [[NSColor knobColor] alphaComponent] * 2], track);
    show("legacy-expected-track", track);
    show("legacy-expected-knob", knob);

    NSScroller *legacy = vertical(NSScrollerStyleLegacy);
    expect([legacy arrowsPosition] == NSScrollerArrowsNone, "new scrollers default to no arrows");
    expect(NSIsEmptyRect([legacy rectForPart: NSScrollerIncrementLine]) &&
           NSIsEmptyRect([legacy rectForPart: NSScrollerDecrementLine]), "legacy scroller has no arrow parts");
    Raster l = raster(legacy);
    int arrowPixels = 0;
    for (int y = 0; y < 15; y++)
        for (int x = 1; x < 15; x++)
            arrowPixels += !near(at(l, x, y), track, 2) + !near(at(l, x, l.h - 1 - y), track, 2);
    expect(arrowPixels == 0, "legacy scroller ends draw no arrow pixels, only track");
    show("legacy-track", at(l, 1, 100));
    show("legacy-edge", at(l, 0, 100));
    show("legacy-knob", at(l, 7, 100));
    expect(near(at(l, 1, 5), track, 2), "legacy track is scrollBarColor");
    expect(near(at(l, 0, 5), separator, 2), "legacy track has a 1 px leading separatorColor line");
    int knobCols = 0, knobFirst = -1;
    for (int x = 1; x < 15; x++)
        if (!near(at(l, x, 100), track, 2)) { knobCols++; if (knobFirst < 0) knobFirst = x; }
    printf("MEASURE legacy knob columns=%d first=%d\n", knobCols, knobFirst);
    expect(knobCols == 7 && knobFirst == 4, "legacy knob is a 7 px capsule centred in 15 px");
    expect(near(at(l, 7, 100), knob, 2), "legacy knob is knobColor over the track");
    // The knob spans rows 72..127 either way up; both ends are rounded.
    show("legacy-knob-end", at(l, 4, 72));
    expect(near(at(l, 7, 73), knob, 2) && !near(at(l, 4, 72), knob, 2) && !near(at(l, 4, 127), knob, 2),
           "legacy knob ends are rounded");

    NSScroller *hot = vertical(NSScrollerStyleLegacy);
    [hot highlight: YES];
    Raster h = raster(hot);
    show("legacy-knob-highlighted", at(h, 7, 100));
    expect(near(at(h, 7, 100), knobActive, 2), "dragged legacy knob doubles the knob alpha");
    [hot highlight: NO];
    [hot mouseEntered: nil];
    Raster hv = raster(hot);
    expect(near(at(hv, 7, 100), knobActive, 2), "hovered legacy knob doubles the knob alpha");
    NSWindow *host = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 40, 220)
                                                 styleMask: NSBorderlessWindowMask
                                                   backing: NSBackingStoreBuffered
                                                     defer: NO];
    [[host contentView] addSubview: legacy];
    expect([[host contentView] hitTest: NSMakePoint(7, 100)] == legacy, "legacy scroller takes clicks");

    NSScroller *overlay = vertical(NSScrollerStyleOverlay);
    Raster o = raster(overlay);
    show("overlay-knob", at(o, 9, 100));
    printf("MEASURE overlay knob columns=%d first=%d opacity=%.2f\n", columnsWithAlpha(o, 100),
           firstColumnWithAlpha(o, 100), [overlay _overlayOpacity]);
    expect(columnsWithAlpha(o, 100) == 7 && firstColumnWithAlpha(o, 100) == 6,
           "overlay knob is 7 px, 2 px from the trailing edge");
    expect(at(o, 0, 100).a == 0 && at(o, 3, 5).a == 0, "overlay scroller draws no track");
    expect(abs(at(o, 9, 100).a - (int) lround([[NSColor knobColor] alphaComponent] * 255)) <= 2,
           "overlay knob is knobColor");

    [overlay mouseEntered: nil];
    Raster ov = raster(overlay);
    show("overlay-hover-track", at(ov, 1, 5));
    show("overlay-hover-edge", at(ov, 0, 5));
    show("overlay-hover-knob", at(ov, 7, 100));
    int hoverFirst = -1, hoverCols = 0;
    for (int x = 1; x < 15; x++)
        if (at(ov, x, 100).r < at(ov, 1, 100).r - 20) { hoverCols++; if (hoverFirst < 0) hoverFirst = x; }
    printf("MEASURE overlay hover knob columns=%d first=%d\n", hoverCols, hoverFirst);
    expect(hoverCols == 11 && hoverFirst == 2, "hovered overlay knob widens to 11 px");
    expect(abs(at(ov, 1, 5).a - 230) <= 3, "hovered overlay track is controlBackgroundColor at 90%");
    expect(at(ov, 0, 5).a > at(ov, 1, 5).a && at(ov, 0, 5).r < at(ov, 1, 5).r,
           "hovered overlay track has a leading separator line");
    [overlay mouseExited: nil];

    NSScroller *fading = vertical(NSScrollerStyleOverlay);
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]];
    printf("MEASURE opacity at 0.5 s=%.2f\n", [fading _overlayOpacity]);
    expect([fading _overlayOpacity] == 1, "overlay knob stays visible 0.5 s after scrolling");
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.7]];
    Raster f = raster(fading);
    int visible = 0;
    for (int i = 0; i < f.w * f.h; i++) visible += f.p[i * 4 + 3] != 0;
    printf("MEASURE opacity at 1.2 s=%.2f visible-pixels=%d\n", [fading _overlayOpacity], visible);
    expect(visible == 0, "overlay knob is transparent 1.2 s after scrolling stops");
    [[host contentView] addSubview: fading];
    // The legacy scroller lies under it at the same place and may take the click.
    expect([[host contentView] hitTest: NSMakePoint(9, 100)] != fading,
           "faded overlay scroller passes clicks through");
    [fading setFloatValue: 0.6 knobProportion: 0.3];
    expect([fading _overlayOpacity] == 1, "scrolling shows a faded overlay knob again");

    NSScroller *horizontal = [[[NSScroller alloc] initWithFrame: NSMakeRect(0, 0, 200, 15)] autorelease];
    [horizontal setScrollerStyle: NSScrollerStyleOverlay];
    [horizontal setEnabled: YES];
    [horizontal setFloatValue: 0.5 knobProportion: 0.3];
    Raster hz = raster(horizontal);
    int rows = 0, firstRow = -1, lastRow = -1;
    for (int y = 0; y < hz.h; y++)
        if (at(hz, 100, y).a > 8) { rows++; if (firstRow < 0) firstRow = y; lastRow = y; }
    printf("MEASURE horizontal overlay knob rows=%d first=%d last=%d\n", rows, firstRow, lastRow);
    expect(rows == 7 && (firstRow == 2 || lastRow == hz.h - 3), "horizontal overlay knob is 7 px, 2 px from an edge");

    for (int style = 0; style < 2; style++) {
        NSScrollView *sv = [[[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)] autorelease];
        [sv setHasVerticalScroller: YES];
        [sv setScrollerStyle: style ? NSScrollerStyleOverlay : NSScrollerStyleLegacy];
        NSTextView *text = [[[NSTextView alloc] initWithFrame: [[sv contentView] bounds]] autorelease];
        [text setAutoresizingMask: NSViewWidthSizable];
        [sv setDocumentView: text];
        [text setString: [@"" stringByPaddingToLength: 4000 withString: @"scroll me " startingAtIndex: 0]];
        printf("MEASURE %s clip=%.0f text=%.0f scroller-x=%.0f\n", style ? "overlay" : "legacy",
               NSWidth([[sv contentView] frame]), NSWidth([text frame]), NSMinX([[sv verticalScroller] frame]));
        if (style) {
            expect(NSWidth([[sv contentView] frame]) == 200 && NSWidth([text frame]) == 200,
                   "overlay: text view width equals the scroll view width");
            expect(NSMinX([[sv verticalScroller] frame]) == 185 && [[sv verticalScroller] scrollerStyle] == NSScrollerStyleOverlay,
                   "overlay: scroller lies over the content's trailing edge");
        } else {
            expect(NSWidth([[sv contentView] frame]) == 185, "legacy: clip view leaves room for the scroller");
        }
    }
    // A nib decodes a scroll view laid out for legacy scrollers, then the view
    // adopts the preferred style. Report (not assert) whether the document
    // view follows the wider clip view.
    NSScrollView *nibLike = [[[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)] autorelease];
    [nibLike setHasVerticalScroller: YES];
    [nibLike setScrollerStyle: NSScrollerStyleLegacy];
    NSTextView *nibText = [[[NSTextView alloc] initWithFrame: [[nibLike contentView] bounds]] autorelease];
    [nibText setAutoresizingMask: NSViewWidthSizable];
    [nibLike setDocumentView: nibText];
    [nibLike setScrollerStyle: NSScrollerStyleOverlay];
    printf("MEASURE style-switch clip=%.0f text=%.0f container=%.0f\n", NSWidth([[nibLike contentView] frame]),
           NSWidth([nibText frame]), [[nibText textContainer] containerSize].width);
    NSScrollView *fresh = [[[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 50, 50)] autorelease];
    printf("MEASURE preferredScrollerStyle=%ld\n", (long) [NSScroller preferredScrollerStyle]);
    expect([fresh scrollerStyle] == [NSScroller preferredScrollerStyle], "scroll views start with the preferred style");
}

static NSMenu *sampleMenu(void) {
    NSMenu *menu = [[[NSMenu alloc] initWithTitle: @"Sample"] autorelease];
    NSMenuItem *alpha = [menu addItemWithTitle: @"Alpha" action: @selector(terminate:) keyEquivalent: @""];
    [alpha setState: NSControlStateValueOn];
    [menu addItemWithTitle: @"Beta" action: @selector(terminate:) keyEquivalent: @""];
    [menu addItem: [NSMenuItem separatorItem]];
    NSMenuItem *gamma = [menu addItemWithTitle: @"Gamma" action: NULL keyEquivalent: @""];
    [gamma setSubmenu: [[[NSMenu alloc] initWithTitle: @"Sub"] autorelease]];
    [menu setAutoenablesItems: NO];
    return menu;
}

// The accent band: rows whose middle pixel is the accent.
static BOOL accentBand(Raster r, Pixel accent, int *first, int *last) {
    *first = *last = -1;
    for (int y = 0; y < r.h; y++)
        if (near(at(r, r.w / 2, y), accent, 3)) { if (*first < 0) *first = y; *last = y; }
    return *first >= 0;
}

static void menuShapeChecks(const char *name, NSView *view, Pixel background, Pixel border) {
    Raster r = raster(view);
    char label[128];
    printf("MEASURE %s size=%dx%d\n", name, r.w, r.h);
    snprintf(label, sizeof label, "%s corner pixels are transparent (radius 6)", name);
    expect(at(r, 0, 0).a == 0 && at(r, r.w - 1, 0).a == 0 && at(r, 0, r.h - 1).a == 0 &&
           at(r, r.w - 1, r.h - 1).a == 0 && at(r, 1, 0).a == 0 && at(r, 0, 1).a == 0, label);
    show("menu-edge", at(r, r.w / 2, 0));
    snprintf(label, sizeof label, "%s edge is the menu.border token over menuBackgroundColor", name);
    expect(near(at(r, r.w / 2, 0), border, 3) && near(at(r, 0, r.h / 2), border, 3), label);
    snprintf(label, sizeof label, "%s fills menuBackgroundColor inside the border", name);
    expect(near(at(r, 2, r.h / 2), background, 2) || near(at(r, 2, r.h / 2 + 3), background, 2), label);
    snprintf(label, sizeof label, "%s corner arc pixel is partly covered", name);
    expect(at(r, 1, 1).a > 0 && at(r, 1, 1).a < 255, label);
}

static void selectionChecks(const char *name, Raster r, Pixel accent, Pixel background) {
    char label[160];
    int first, last;
    BOOL found = accentBand(r, accent, &first, &last);
    int mid = (first + last) / 2;
    printf("MEASURE %s selection rows=%d..%d\n", name, first, last);
    snprintf(label, sizeof label, "%s selection row centre is the accent", name);
    expect(found && near(at(r, r.w / 2, mid), accent, 3), label);
    show("selection-left", at(r, 5, mid));
    snprintf(label, sizeof label, "%s selection is inset 5 px on both sides", name);
    expect(found && near(at(r, 4, mid), background, 3) && near(at(r, 5, mid), accent, 3) &&
           near(at(r, r.w - 6, mid), accent, 3) && near(at(r, r.w - 5, mid), background, 3), label);
    snprintf(label, sizeof label, "%s selection corners are rounded (radius 4)", name);
    expect(found && !near(at(r, 5, first), accent, 3) && !near(at(r, r.w - 6, last), accent, 3), label);
}

static int countMark(Raster r, int y0, int y1, BOOL light) {
    int n = 0;
    for (int y = y0; y <= y1; y++)
        for (int x = 6; x < 26; x++) {
            Pixel p = at(r, x, y);
            n += light ? (p.r > 225 && p.g > 225 && p.b > 225) : (p.r < 110 && p.g < 110 && p.b < 110 && p.a > 200);
        }
    return n;
}

static void menuChecks(void) {
    Pixel white = {255, 255, 255, 255};
    Pixel background = over([NSColor menuBackgroundColor], white);
    Pixel border = over([NSColor colorWithCatalogName: @"System" colorName: @"menu.border"], background);
    Pixel accent = over([NSColor selectedMenuItemColor], white);
    Pixel line = over([NSColor separatorColor], background);
    show("menu-expected-background", background);
    show("menu-expected-accent", accent);

    NSMenuWindow *window = [[NSMenuWindow alloc] initWithMenu: sampleMenu()];
    NSMenuView *view = [window menuView];
    expect(![window isOpaque] && [[window backgroundColor] alphaComponent] == 0,
           "menu window is transparent around the rounded menu");
    menuShapeChecks("menu", view, background, border);

    Raster normal = raster(view);
    int first, last;
    expect(!accentBand(normal, accent, &first, &last), "menu: no selection drawn when nothing is selected");

    // Separator: the only row, both ways up, that is darker in the middle and
    // background within 10 px of each side.
    int sepRow = -1;
    for (int y = 3; y < normal.h - 3; y++)
        if (near(at(normal, normal.w / 2, y), line, 2) && near(at(normal, 9, y), background, 2) &&
            near(at(normal, 10, y), line, 2) && near(at(normal, normal.w - 11, y), line, 2) &&
            near(at(normal, normal.w - 10, y), background, 2)) { sepRow = y; break; }
    const int sepExpected = 3 + 22 + 22 + 5;
    printf("MEASURE separator row=%d (or %d from the other edge)\n", sepRow, normal.h - 1 - sepRow);
    expect(sepRow >= 0 && near(at(normal, normal.w / 2, sepRow + 1), background, 2) &&
           near(at(normal, normal.w / 2, sepRow - 1), background, 2),
           "separator is a 1 px separatorColor line inset 10 px");
    expect(sepRow == sepExpected || normal.h - 1 - sepRow == sepExpected,
           "separator line is centred in an 11 px row after two 22 px rows");

    [view setSelectedItemIndex: 1];
    Raster beta = raster(view);
    selectionChecks("menu", beta, accent, background);
    accentBand(beta, accent, &first, &last);
    printf("MEASURE menu row height=%d\n", last - first + 1);
    expect(last - first + 1 == 22, "menu rows are 22 px tall");

    // Checkmark on the first row, normal then highlighted.
    [view setSelectedItemIndex: 0];
    Raster hiAlpha = raster(view);
    accentBand(hiAlpha, accent, &first, &last);
    int lightMarks = countMark(hiAlpha, first, last, YES);
    int darkMarksHi = countMark(hiAlpha, first, last, NO);
    [view setSelectedItemIndex: NSNotFound];
    Raster loAlpha = raster(view);
    int darkMarks = countMark(loAlpha, first, last, NO);
    printf("MEASURE check mark normal-dark=%d highlighted-light=%d highlighted-dark=%d\n", darkMarks, lightMarks, darkMarksHi);
    expect(darkMarks >= 6, "normal check mark is drawn in the menu text colour");
    expect(lightMarks >= 6 && darkMarksHi == 0, "highlighted check mark is drawn in the on-accent colour");

    NSPopUpWindow *popup = [[NSPopUpWindow alloc] initWithFrame: NSMakeRect(0, 0, 160, 80)];
    [popup setMenu: sampleMenu()];
    [popup selectItemAtIndex: 1];
    NSView *popupView = [[[popup contentView] subviews] objectAtIndex: 0];
    NSSize size = [(NSPopUpView *) popupView sizeForContents];
    [popupView setFrame: NSMakeRect(0, 0, MAX(size.width, 160), size.height)];
    expect(![popup isOpaque] && [[popup backgroundColor] alphaComponent] == 0,
           "pop-up menu window is transparent around the rounded menu");
    menuShapeChecks("pop-up", popupView, background, border);
    selectionChecks("pop-up", raster(popupView), accent, background);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        scrollerChecks();
        menuChecks();
        printf("RESULT appkit-scroller-menu-theme failures=%u checks=%u\n", failures, checks);
    }
    return failures ? 1 : 0;
}
