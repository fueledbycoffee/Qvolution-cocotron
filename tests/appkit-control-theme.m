// Original pixel checks for the Qvolution control theme (visual theme spec, P4).
// Controls draw into caller-owned CPU bitmaps; geometry is found from the
// rendered alpha, so the checks hold whichever way the bitmap rows run.
// Onyx2D's CPU bitmaps hold premultiplied components.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned failures;
static void expect(BOOL ok, const char *what) {
    printf("%s: %s\n", ok ? "PASS" : "FAIL", what);
    failures += !ok;
}

@interface KeyWindow : NSWindow
@end
@implementation KeyWindow
- (BOOL) isKeyWindow { return YES; }
@end

typedef struct { int w, h; unsigned char *p; int minX, minY, maxX, maxY; } Raster;
typedef struct { int r, g, b, a; } Pixel;

static Raster raster(NSView *view) {
    Raster r = {(int) NSWidth([view bounds]), (int) NSHeight([view bounds]), NULL, 1 << 20, 1 << 20, -1, -1};
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
    for (int y = 0; y < r.h; y++)
        for (int x = 0; x < r.w; x++)
            if (r.p[(y * r.w + x) * 4 + 3] > 8) {
                if (x < r.minX) r.minX = x;
                if (x > r.maxX) r.maxX = x;
                if (y < r.minY) r.minY = y;
                if (y > r.maxY) r.maxY = y;
            }
    return r;
}

static Pixel at(Raster r, int x, int y) {
    unsigned char *q = r.p + (y * r.w + x) * 4;
    return (Pixel){q[0], q[1], q[2], q[3]};
}

static Pixel rgb(NSColor *color, CGFloat alpha) {
    NSColor *c = [color colorUsingColorSpaceName: NSDeviceRGBColorSpace];
    return (Pixel){(int) lround([c redComponent] * 255), (int) lround([c greenComponent] * 255),
                   (int) lround([c blueComponent] * 255), (int) lround(alpha * 255)};
}

static BOOL near(Pixel p, Pixel q, int tolerance, BOOL withAlpha) {
    return abs(p.r - q.r) <= tolerance && abs(p.g - q.g) <= tolerance && abs(p.b - q.b) <= tolerance &&
           (!withAlpha || abs(p.a - q.a) <= tolerance);
}

static void show(const char *label, Pixel p) {
    printf("PIXEL %s %d %d %d %d\n", label, p.r, p.g, p.b, p.a);
}

static NSButton *push(NSWindow *window, NSString *title) {
    NSButton *b = [[[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 100, 32)] autorelease];
    [b setButtonType: NSMomentaryPushInButton];
    [b setBezelStyle: NSRoundedBezelStyle];
    [b setTitle: title];
    [[window contentView] addSubview: b];
    return b;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = [[KeyWindow alloc] initWithContentRect: NSMakeRect(0, 0, 400, 300)
                                                        styleMask: NSTitledWindowMask
                                                          backing: NSBackingStoreBuffered
                                                            defer: NO];
        Pixel face = rgb([NSColor controlColor], 1);
        Pixel accent = rgb([NSColor controlAccentColor], 1);
        show("controlColor", face);
        show("controlAccentColor", accent);

        Raster normal = raster(push(window, @"Cancel"));
        int midY = (normal.minY + normal.maxY) / 2;
        expect(normal.maxX - normal.minX + 1 == 90 && normal.maxY - normal.minY + 1 == 22,
               "push button bezel is 90x22 inside its 100x32 frame");
        show("push-corner", at(normal, normal.minX, normal.minY));
        expect(at(normal, normal.minX, normal.minY).a <= 8 && at(normal, normal.maxX, normal.maxY).a <= 8 &&
               at(normal, normal.minX, normal.maxY).a <= 8 && at(normal, normal.maxX, normal.minY).a <= 8,
               "push button corner pixels are transparent (radius 5)");
        show("push-border", at(normal, normal.minX, midY));
        expect(near(at(normal, normal.minX, midY), (Pixel){0, 0, 0, 46}, 4, YES),
               "push button border is bezel.border (black at 18%)");
        show("push-face", at(normal, normal.minX + 3, midY));
        expect(near(at(normal, normal.minX + 3, midY), face, 2, YES), "push button face is controlColor");

        NSButton *defaultButton = push(window, @"OK");
        [defaultButton setKeyEquivalent: @"\r"];
        [window setDefaultButtonCell: [defaultButton cell]];
        Raster def = raster(defaultButton);
        int dark = 0;
        for (int i = 0; i < def.w * def.h; i++)
            dark += def.p[i * 4 + 3] > 200 && def.p[i * 4] < 40 && def.p[i * 4 + 1] < 40 && def.p[i * 4 + 2] < 40 &&
                    !(accent.r < 40 && accent.g < 40 && accent.b < 40);
        printf("MEASURE default bbox=%d,%d..%d,%d push bbox=%d,%d..%d,%d corner-alpha=%d\n", def.minX, def.minY,
               def.maxX, def.maxY, normal.minX, normal.minY, normal.maxX, normal.maxY, at(def, def.minX, def.minY).a);
        expect(def.minX >= normal.minX && def.minY >= normal.minY && def.maxX <= normal.maxX && def.maxY <= normal.maxY,
               "default button draws no rectangle outside its bezel");
        expect(dark == 0, "default button has no black pixels");
        show("default-face", at(def, def.minX + 3, (def.minY + def.maxY) / 2));
        expect(near(at(def, def.minX + 3, (def.minY + def.maxY) / 2), accent, 14, NO) &&
               at(def, def.minX + 3, (def.minY + def.maxY) / 2).a == 255,
               "default button face is the accent fill");
        [window setDefaultButtonCell: nil];

        NSButton *pressed = push(window, @"");
        [[pressed cell] setHighlighted: YES];
        Raster down = raster(pressed);
        show("pressed-face", at(down, down.minX + 3, midY));
        expect(near(at(down, down.minX + 3, midY), (Pixel){0xF0, 0xF0, 0xF0, 255}, 2, YES),
               "pressed push button face is bezel.pressedFace");

        NSButton *disabled = push(window, @"");
        [disabled setEnabled: NO];
        Raster off = raster(disabled);
        show("disabled-face", at(off, off.minX + 3, midY));
        expect(abs(at(off, off.minX + 3, midY).a - 128) <= 3, "disabled push button draws at 50%");

        NSButton *focused = push(window, @"");
        [[focused cell] setShowsFirstResponder: YES];
        Raster ring = raster(focused);
        int bezelLeft = normal.minX;
        Pixel ringPixel = at(ring, bezelLeft - 2, midY);
        show("focus-ring", ringPixel);
        expect(ring.minX == bezelLeft - 3, "focus ring is 3 px wide outside the bezel");
        expect(near(ringPixel, (Pixel){accent.r / 2, accent.g / 2, accent.b / 2, 128}, 4, YES),
               "focus ring 2 px outside the bezel is the accent at 50%");
        expect(near(at(ring, bezelLeft, midY), (Pixel){accent.r, accent.g, accent.b, 128}, 4, NO) == NO,
               "focus ring does not cover the bezel border");

        NSPopUpButton *popup = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect(0, 0, 140, 26) pullsDown: NO]
                autorelease];
        [popup addItemsWithTitles: @[@"Helvetica", @"Times"]];
        [[window contentView] addSubview: popup];
        Raster pop = raster(popup);
        int popY = (pop.minY + pop.maxY) / 2;
        int indicatorCenter = pop.maxX - 2 - 8;
        show("popup-indicator", at(pop, indicatorCenter - 6, popY));
        expect(near(at(pop, indicatorCenter - 6, popY), accent, 2, NO) && at(pop, indicatorCenter - 6, popY).a == 255,
               "pop-up indicator square is the accent");
        NSRect titleRect = [[popup cell] titleRectForBounds: [popup bounds]];
        expect(NSWidth(titleRect) >= [[[popup cell] attributedTitle] size].width &&
                       NSMaxX(titleRect) <= indicatorCenter - 8,
               "pop-up title is not truncated and stays clear of the indicator");
        NSRect buttonTitle = [[defaultButton cell] titleRectForBounds: [defaultButton bounds]];
        expect(NSWidth(buttonTitle) >= [[[defaultButton cell] attributedTitle] size].width,
               "push button title is not truncated");

        NSSegmentedControl *segments = [[[NSSegmentedControl alloc] initWithFrame: NSMakeRect(0, 0, 120, 24)]
                autorelease];
        [segments setSegmentCount: 3];
        [[segments cell] setTrackingMode: NSSegmentSwitchTrackingSelectAny];
        for (int i = 0; i < 3; i++) {
            [segments setLabel: @"" forSegment: i];
            [segments setWidth: 40 forSegment: i];
        }
        [[window contentView] addSubview: segments];
        Raster seg = raster(segments);
        int segY = (seg.minY + seg.maxY) / 2, dividers = 0, translucent = 0;
        for (int x = seg.minX + 1; x < seg.maxX; x++) {
            Pixel p = at(seg, x, segY);
            translucent += p.a != 255;
            dividers += abs(p.r - face.r) > 6;
        }
        printf("MEASURE segmented dividers=%d translucent-interior=%d\n", dividers, translucent);
        expect(dividers == 2, "3-segment control has exactly 2 internal dividers");
        expect(translucent == 0 && at(seg, seg.minX, segY).a < 255 && at(seg, seg.maxX, segY).a < 255,
               "segmented control has one outer border and no per-segment bezels");
        [segments setSelected: YES forSegment: 0];
        Raster bold = raster(segments);
        Pixel selected = at(bold, seg.minX + 20, segY);
        Pixel token = {(int) lround(face.r * 0.86), (int) lround(face.g * 0.86), (int) lround(face.b * 0.86), 255};
        show("segment-selected", selected);
        expect(near(selected, token, 3, YES), "selected B segment is segment.selected over the face");

        NSTextField *field = [[[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 120, 22)] autorelease];
        [field setBezeled: YES];
        [field setBezelStyle: NSTextFieldSquareBezel];
        [field setBackgroundColor: [NSColor textBackgroundColor]];
        [[window contentView] addSubview: field];
        Raster text = raster(field);
        int edgeA = at(text, 60, 0).a, edgeB = at(text, 60, text.h - 1).a;
        printf("MEASURE text-field edges=%d,%d side=%d\n", edgeA, edgeB, at(text, 0, 11).a);
        expect((abs(edgeA - 64) <= 3 && abs(edgeB - 38) <= 3) || (abs(edgeB - 64) <= 3 && abs(edgeA - 38) <= 3),
               "text field top edge is black at 25%, bottom at 15%");
        expect(abs(at(text, 0, 11).a - 38) <= 3, "text field side edge is black at 15%");
        expect(near(at(text, 5, 11), rgb([NSColor textBackgroundColor], 1), 2, YES),
               "text field interior is textBackgroundColor");

        // A real key change, without the fixture's isKeyWindow override,
        // must invalidate the default button so it redraws with the accent.
        NSWindow *plain = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 200, 100)
                                                      styleMask: NSTitledWindowMask
                                                        backing: NSBackingStoreBuffered
                                                          defer: YES];
        NSButton *plainDefault = push(plain, @"OK");
        [plain setDefaultButtonCell: [plainDefault cell]];
        [plainDefault setNeedsDisplay: NO];
        [plain becomeKeyWindow];
        expect([plain isKeyWindow] && [plainDefault needsDisplay], "becoming key redraws the default button");
        [plainDefault setNeedsDisplay: NO];
        [window becomeKeyWindow];
        expect(![plain isKeyWindow] && [plainDefault needsDisplay], "resigning key redraws the default button");
        [plain release];

        printf("RESULT failures=%u\n", failures);
    }
    return failures ? 1 : 0;
}
