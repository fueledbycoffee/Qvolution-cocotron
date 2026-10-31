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

// Private window chrome renderer: title bar, traffic lights, rounded corners
// and drop shadow, rasterised in plain C so that every backend draws the same
// pixels and native fixtures can check them without the Objective-C runtime.
// Sizes and colours are Qvolution design tokens (visual theme spec, sections
// 3 and 4), not values taken from Apple software.

#ifndef NSTITLEBARRENDERER_H
#define NSTITLEBARRENDERER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Logical (1x) geometry, measured from the visible window's top-left corner.
#define NSTitlebarHeight 28.0
#define NSTitlebarMargin 12.0
#define NSTitlebarCornerRadius 10.0
#define NSTitlebarDiscDiameter 12.0
#define NSTitlebarDiscPitch 20.0
#define NSTitlebarFirstDiscCenter 14.0
#define NSTitlebarDiscHitOutset 4.0
#define NSTitlebarTitleMinX 72.0
#define NSTitlebarTitleTrailingInset 8.0
#define NSTitlebarFontSize 13.0
#define NSTitlebarResizeOutside 8.0
#define NSTitlebarResizeCornerInside 4.0

typedef enum {
    NSTitlebarButtonNone = -1,
    NSTitlebarButtonClose = 0,
    NSTitlebarButtonMinimize = 1,
    NSTitlebarButtonZoom = 2,
    NSTitlebarButtonCount = 3
} NSTitlebarButton;

// Straight (not premultiplied) sRGB components in [0, 1].
typedef struct {
    double r, g, b, a;
} NSTitlebarColor;

typedef struct {
    bool active;        // the window is the activated toplevel
    bool dark;          // DarkAqua tokens instead of Aqua
    bool hover;         // the pointer is over the three-disc group
    NSTitlebarButton pressed; // tracked and still under the pointer
    bool enabled[NSTitlebarButtonCount];
    bool zoomIsFullScreen; // NSWindowCollectionBehaviorFullScreenPrimary
    bool hairline;      // draw titlebar.hairline along the bar's bottom row
} NSTitlebarState;

// The whole backing surface: premultiplied ARGB in 32-bit little-endian words
// (Onyx2D kO2ImageAlphaPremultipliedFirst | kO2BitmapByteOrder32Little).
typedef struct {
    uint8_t *pixels;
    size_t bytesPerRow;
    int width, height; // device pixels
    double scale;      // device pixels per logical pixel
} NSTitlebarBitmap;

typedef struct {
    double margin;        // logical shadow margin around the visible window
    double width, height; // logical visible size, title bar included
    bool rounded;         // NSTitlebarCornerRadius corners
    bool shadow;
    NSTitlebarState state;
} NSTitlebarFrame;

typedef struct {
    NSTitlebarColor barActive, barInactive, hairline;
    NSTitlebarColor discs[NSTitlebarButtonCount];
    NSTitlebarColor discInactive, discInactiveRim;
    NSTitlebarColor shadowActive, shadowInactive;
} NSTitlebarPalette;

NSTitlebarPalette NSTitlebarPaletteForAppearance(bool dark);

// Disc centre in logical coordinates from the visible origin.
void NSTitlebarDiscCenter(NSTitlebarButton button, double *x, double *y);
// The disc whose hit area (disc outset NSTitlebarDiscHitOutset) contains the
// point, ignoring whether it is enabled; NSTitlebarButtonNone otherwise.
NSTitlebarButton NSTitlebarButtonAtPoint(double x, double y);
// The union of the three hit areas, where hovering reveals the glyphs.
bool NSTitlebarPointInButtonGroup(double x, double y);

// Where the title starts: centred on the whole bar width, moved right to
// NSTitlebarTitleMinX when it would overlap the lights. *maximumWidth receives
// the room left before the trailing inset; a wider title must be truncated.
double NSTitlebarTitleOriginX(double barWidth, double titleWidth, double *maximumWidth);

// xdg_toplevel resize edges (top 1, bottom 2, left 4, right 8) for a point in
// logical surface coordinates, or 0 when the point does not resize.
uint32_t NSTitlebarResizeEdgesAtPoint(const NSTitlebarFrame *frame, double x, double y);

// Press/release tracking: a button acts only when released over the same disc.
typedef struct {
    NSTitlebarButton pressed;
} NSTitlebarTracker;
// Returns YES when the press landed on an enabled disc and is now tracked.
bool NSTitlebarTrackerPress(NSTitlebarTracker *tracker, const NSTitlebarState *state, double x, double y);
// Ends tracking; returns the button to act on, or NSTitlebarButtonNone.
NSTitlebarButton NSTitlebarTrackerRelease(NSTitlebarTracker *tracker, double x, double y);

// Draws the margin (shadow or transparent), the title bar with its top
// corners and the traffic lights. Leaves the content area below the bar alone.
void NSTitlebarRenderFrame(const NSTitlebarBitmap *bitmap, const NSTitlebarFrame *frame);
// Cuts the two bottom corners of the content after the application drew it.
// Overwrites rather than blends, so repeating it on unchanged pixels is exact.
void NSTitlebarMaskContentCorners(const NSTitlebarBitmap *bitmap, const NSTitlebarFrame *frame);

#ifdef __cplusplus
}
#endif

#endif
