/* Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 of the Software, and to permit persons to whom the Software is furnished to do
 so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE. */

// Plain C on purpose: native fixtures compile this file without Objective-C.
#include "NSTitlebarRenderer.h"
#include <math.h>

#define NSTitlebarShadowBlur 10.0
#define NSTitlebarShadowOffsetY 2.0
#define NSTitlebarGlyphBox 6.0
#define NSTitlebarGlyphStroke 1.25
#define NSTitlebarRimShade 0.85
#define NSTitlebarPressedShade 0.80
#define NSTitlebarGlyphShade 0.45
#define NSTitlebarDisabledAlpha 0.5

static NSTitlebarColor rgb(unsigned value) {
    return (NSTitlebarColor){(value >> 16) / 255.0, ((value >> 8) & 255) / 255.0,
                             (value & 255) / 255.0, 1};
}

static NSTitlebarColor black(double alpha) {
    return (NSTitlebarColor){0, 0, 0, alpha};
}

static NSTitlebarColor shade(NSTitlebarColor color, double factor) {
    return (NSTitlebarColor){color.r * factor, color.g * factor, color.b * factor, color.a};
}

NSTitlebarPalette NSTitlebarPaletteForAppearance(bool dark) {
    NSTitlebarPalette palette = {
        .barActive = dark ? rgb(0x383838) : rgb(0xE8E8E8),
        .barInactive = dark ? rgb(0x2E2E2E) : rgb(0xF6F6F6),
        .hairline = black(dark ? 0.50 : 0.10),
        .discs = {rgb(0xFF5F57), rgb(0xFDBC2E), rgb(0x29C740)},
        .discInactive = dark ? rgb(0x565656) : rgb(0xDDDDDD),
        .discInactiveRim = black(0.10),
        .shadowActive = black(dark ? 0.55 : 0.30),
        .shadowInactive = black(dark ? 0.30 : 0.12),
    };
    return palette;
}

void NSTitlebarDiscCenter(NSTitlebarButton button, double *x, double *y) {
    *x = NSTitlebarFirstDiscCenter + button * NSTitlebarDiscPitch;
    *y = NSTitlebarHeight / 2;
}

NSTitlebarButton NSTitlebarButtonAtPoint(double x, double y) {
    double reach = NSTitlebarDiscDiameter / 2 + NSTitlebarDiscHitOutset;
    for (int i = 0; i < NSTitlebarButtonCount; i++) {
        double cx, cy;
        NSTitlebarDiscCenter(i, &cx, &cy);
        if (x >= cx - reach && x < cx + reach && y >= cy - reach && y < cy + reach)
            return (NSTitlebarButton) i;
    }
    return NSTitlebarButtonNone;
}

bool NSTitlebarPointInButtonGroup(double x, double y) {
    return NSTitlebarButtonAtPoint(x, y) != NSTitlebarButtonNone;
}

double NSTitlebarTitleOriginX(double barWidth, double titleWidth, double *maximumWidth) {
    *maximumWidth = barWidth - NSTitlebarTitleMinX - NSTitlebarTitleTrailingInset;
    if (*maximumWidth < 0)
        *maximumWidth = 0;
    double x = (barWidth - titleWidth) / 2;
    return x < NSTitlebarTitleMinX ? NSTitlebarTitleMinX : x;
}

uint32_t NSTitlebarResizeEdgesAtPoint(const NSTitlebarFrame *frame, double x, double y) {
    if (frame->margin <= 0)
        return 0;
    double vx = x - frame->margin, vy = y - frame->margin;
    double w = frame->width, h = frame->height;
    double out = NSTitlebarResizeOutside, in = NSTitlebarResizeCornerInside;
    if (vx < -out || vy < -out || vx >= w + out || vy >= h + out)
        return 0;
    bool left = vx < in, right = vx >= w - in, top = vy < in, bottom = vy >= h - in;
    bool outside = vx < 0 || vy < 0 || vx >= w || vy >= h;
    if (!outside && !((left || right) && (top || bottom)))
        return 0;
    return (top ? 1 : 0) | (bottom ? 2 : 0) | (left ? 4 : 0) | (right ? 8 : 0);
}

bool NSTitlebarTrackerPress(NSTitlebarTracker *tracker, const NSTitlebarState *state, double x, double y) {
    NSTitlebarButton button = NSTitlebarButtonAtPoint(x, y);
    tracker->pressed = button != NSTitlebarButtonNone && state->enabled[button]
        ? button : NSTitlebarButtonNone;
    return tracker->pressed != NSTitlebarButtonNone;
}

NSTitlebarButton NSTitlebarTrackerRelease(NSTitlebarTracker *tracker, double x, double y) {
    NSTitlebarButton pressed = tracker->pressed;
    tracker->pressed = NSTitlebarButtonNone;
    return pressed != NSTitlebarButtonNone && NSTitlebarButtonAtPoint(x, y) == pressed
        ? pressed : NSTitlebarButtonNone;
}

// Raster

typedef struct {
    double b, g, r, a; // premultiplied
} Pixel;

static uint8_t *pixelAddress(const NSTitlebarBitmap *bitmap, int x, int y) {
    return bitmap->pixels + (size_t) y * bitmap->bytesPerRow + (size_t) x * 4;
}

static uint8_t byte(double value) {
    double scaled = floor(value * 255 + 0.5);
    return scaled < 0 ? 0 : scaled > 255 ? 255 : (uint8_t) scaled;
}

static void store(const NSTitlebarBitmap *bitmap, int x, int y, Pixel pixel) {
    uint8_t *p = pixelAddress(bitmap, x, y);
    p[0] = byte(pixel.b), p[1] = byte(pixel.g), p[2] = byte(pixel.r), p[3] = byte(pixel.a);
}

static Pixel over(Pixel destination, NSTitlebarColor color, double coverage) {
    double a = color.a * coverage;
    return (Pixel){color.b * a + destination.b * (1 - a), color.g * a + destination.g * (1 - a),
                   color.r * a + destination.r * (1 - a), a + destination.a * (1 - a)};
}

static double clamp01(double value) {
    return value < 0 ? 0 : value > 1 ? 1 : value;
}

// Signed distance from (x, y) to a rounded rectangle; negative inside.
static double roundedRectDistance(double x, double y, double left, double top,
                                  double width, double height, double radius) {
    double qx = fabs(x - (left + width / 2)) - (width / 2 - radius);
    double qy = fabs(y - (top + height / 2)) - (height / 2 - radius);
    double ox = qx > 0 ? qx : 0, oy = qy > 0 ? qy : 0;
    double inside = qx > qy ? qx : qy;
    return sqrt(ox * ox + oy * oy) + (inside < 0 ? inside : 0) - radius;
}

static double radiusOf(const NSTitlebarFrame *frame) {
    return frame->rounded ? NSTitlebarCornerRadius : 0;
}

// The shadow under the window: a falloff from the window shape moved down.
static Pixel shadowPixel(const NSTitlebarFrame *frame, double vx, double vy) {
    if (!frame->shadow)
        return (Pixel){0, 0, 0, 0};
    NSTitlebarPalette palette = NSTitlebarPaletteForAppearance(frame->state.dark);
    NSTitlebarColor color = frame->state.active ? palette.shadowActive : palette.shadowInactive;
    double d = roundedRectDistance(vx, vy, 0, NSTitlebarShadowOffsetY, frame->width,
                                   frame->height, radiusOf(frame));
    double sigma = NSTitlebarShadowBlur / 2;
    double falloff = d <= 0 ? 1 : exp(-0.5 * (d / sigma) * (d / sigma));
    return over((Pixel){0, 0, 0, 0}, color, falloff);
}

static double segmentDistance(double px, double py, double ax, double ay, double bx, double by) {
    double dx = bx - ax, dy = by - ay;
    double t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy);
    t = clamp01(t);
    double ex = px - (ax + t * dx), ey = py - (ay + t * dy);
    return sqrt(ex * ex + ey * ey);
}

static bool insideTriangle(double px, double py, const double t[6]) {
    double d1 = (px - t[2]) * (t[1] - t[3]) - (t[0] - t[2]) * (py - t[3]);
    double d2 = (px - t[4]) * (t[3] - t[5]) - (t[2] - t[4]) * (py - t[5]);
    double d3 = (px - t[0]) * (t[5] - t[1]) - (t[4] - t[0]) * (py - t[1]);
    bool negative = d1 < 0 || d2 < 0 || d3 < 0, positive = d1 > 0 || d2 > 0 || d3 > 0;
    return !(negative && positive);
}

// Glyph coverage at a point given relative to the disc centre, in logical units.
static double glyphCoverage(NSTitlebarButton button, bool fullScreen, double gx, double gy,
                            double scale) {
    double h = NSTitlebarGlyphBox / 2;
    if (button == NSTitlebarButtonZoom && fullScreen) {
        // Two opposing corner triangles, sampled 4x4 per device pixel.
        double a = h * 2 / 3;
        const double triangles[2][6] = {{-h, -h, a, -h, -h, a}, {h, h, -a, h, h, -a}};
        int hits = 0;
        for (int sy = 0; sy < 4; sy++)
            for (int sx = 0; sx < 4; sx++) {
                double x = gx + ((sx + 0.5) / 4 - 0.5) / scale;
                double y = gy + ((sy + 0.5) / 4 - 0.5) / scale;
                hits += insideTriangle(x, y, triangles[0]) || insideTriangle(x, y, triangles[1]);
            }
        return hits / 16.0;
    }
    double segments[2][4];
    int count = 0;
    if (button == NSTitlebarButtonClose) {
        double s[2][4] = {{-h, -h, h, h}, {-h, h, h, -h}};
        for (int i = 0; i < 2; i++)
            for (int j = 0; j < 4; j++) segments[i][j] = s[i][j];
        count = 2;
    } else {
        double s[2][4] = {{-h, 0, h, 0}, {0, -h, 0, h}};
        for (int i = 0; i < 2; i++)
            for (int j = 0; j < 4; j++) segments[i][j] = s[i][j];
        count = button == NSTitlebarButtonZoom ? 2 : 1;
    }
    double best = 0;
    for (int i = 0; i < count; i++) {
        double d = segmentDistance(gx, gy, segments[i][0], segments[i][1], segments[i][2],
                                   segments[i][3]) * scale;
        double c = clamp01(NSTitlebarGlyphStroke / 2 + 0.5 - d);
        if (c > best) best = c;
    }
    return best;
}

static Pixel discPixel(Pixel pixel, const NSTitlebarFrame *frame, const NSTitlebarPalette *palette,
                       NSTitlebarButton button, double vx, double vy, double scale) {
    const NSTitlebarState *state = &frame->state;
    double cx, cy;
    NSTitlebarDiscCenter(button, &cx, &cy);
    double d = hypot(vx - cx, vy - cy) * scale, r = NSTitlebarDiscDiameter / 2 * scale;
    double outer = clamp01(r + 0.5 - d);
    if (outer <= 0)
        return pixel;
    double inner = clamp01(r - 1 + 0.5 - d);
    bool enabled = state->enabled[button];
    bool colored = enabled && (state->active || state->hover);
    NSTitlebarColor fill, rim;
    if (colored) {
        fill = palette->discs[button];
        if (state->pressed == button)
            fill = shade(fill, NSTitlebarPressedShade);
        rim = shade(fill, NSTitlebarRimShade);
    } else {
        fill = palette->discInactive;
        rim = palette->discInactiveRim;
        if (!enabled) {
            fill.a *= NSTitlebarDisabledAlpha;
            rim.a *= NSTitlebarDisabledAlpha;
        }
    }
    pixel = over(pixel, rim, outer - inner);
    pixel = over(pixel, fill, inner);
    if (colored && state->hover) {
        // Centre the strokes on a device pixel so a 1.25 px line stays crisp.
        double glyph = glyphCoverage(button, state->zoomIsFullScreen, vx - cx - 0.5 / scale,
                                     vy - cy - 0.5 / scale, scale);
        if (glyph > 0)
            pixel = over(pixel, shade(palette->discs[button], NSTitlebarGlyphShade), glyph);
    }
    return pixel;
}

void NSTitlebarRenderFrame(const NSTitlebarBitmap *bitmap, const NSTitlebarFrame *frame) {
    double s = bitmap->scale, m = frame->margin, radius = radiusOf(frame);
    NSTitlebarPalette palette = NSTitlebarPaletteForAppearance(frame->state.dark);
    NSTitlebarColor bar = frame->state.active ? palette.barActive : palette.barInactive;
    // The last device row of the bar carries the hairline.
    int hairlineRow = (int) floor((m + NSTitlebarHeight) * s) - 1;
    int contentTop = hairlineRow + 1;
    int contentLeft = (int) floor(m * s + 0.5), contentRight = (int) floor((m + frame->width) * s + 0.5);
    int contentBottom = (int) floor((m + frame->height) * s + 0.5);
    for (int y = 0; y < bitmap->height; y++) {
        double vy = (y + 0.5) / s - m;
        bool contentRow = y >= contentTop && y < contentBottom;
        for (int x = 0; x < bitmap->width; x++) {
            if (contentRow && x == contentLeft && contentRight > contentLeft)
                x = contentRight;
            if (x >= bitmap->width)
                break;
            double vx = (x + 0.5) / s - m;
            Pixel pixel = shadowPixel(frame, vx, vy);
            if (y < contentTop && x >= contentLeft && x < contentRight && vy >= 0) {
                double d = roundedRectDistance(vx, vy, 0, 0, frame->width, frame->height, radius);
                double coverage = clamp01(0.5 - d * s);
                pixel = over(pixel, bar, coverage);
                if (y == hairlineRow && frame->state.hairline)
                    pixel = over(pixel, palette.hairline, coverage);
                if (vy < NSTitlebarHeight && vx < NSTitlebarFirstDiscCenter + NSTitlebarButtonCount * NSTitlebarDiscPitch)
                    for (int i = 0; i < NSTitlebarButtonCount; i++)
                        pixel = discPixel(pixel, frame, &palette, i, vx, vy, s);
            }
            store(bitmap, x, y, pixel);
        }
    }
}

void NSTitlebarMaskContentCorners(const NSTitlebarBitmap *bitmap, const NSTitlebarFrame *frame) {
    if (!frame->rounded)
        return;
    double s = bitmap->scale, m = frame->margin, r = NSTitlebarCornerRadius;
    int top = (int) floor((m + frame->height - r) * s), bottom = (int) floor((m + frame->height) * s + 0.5);
    int left = (int) floor(m * s + 0.5), right = (int) floor((m + frame->width) * s + 0.5);
    int span = (int) ceil(r * s);
    if (top < 0) top = 0;
    if (bottom > bitmap->height) bottom = bitmap->height;
    for (int y = top; y < bottom; y++) {
        double vy = (y + 0.5) / s - m;
        for (int side = 0; side < 2; side++) {
            int start = side == 0 ? left : right - span, end = side == 0 ? left + span : right;
            for (int x = start < 0 ? 0 : start; x < end && x < bitmap->width; x++) {
                double vx = (x + 0.5) / s - m;
                if (roundedRectDistance(vx, vy, 0, 0, frame->width, frame->height, r) > 0)
                    store(bitmap, x, y, shadowPixel(frame, vx, vy));
            }
        }
    }
}
