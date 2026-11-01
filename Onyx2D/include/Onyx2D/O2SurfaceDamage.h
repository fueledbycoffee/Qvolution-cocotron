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

#ifndef O2SURFACEDAMAGE_H
#define O2SURFACEDAMAGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// A short list of device pixel rectangles covering every pixel written since
// the list was last emptied. Rows count from the first row in memory, as the
// surface's pixels (and wl_surface.damage_buffer) do. Adding merges rectangles
// to keep at most O2SurfaceDamageMaxRects, so the list may cover more than was
// written, never less. Rectangles may overlap after a merge.
enum { O2SurfaceDamageMaxRects = 8 };

typedef struct O2SurfaceDamageRect {
    int32_t x, y, width, height;
} O2SurfaceDamageRect;

typedef struct O2SurfaceDamage {
    int32_t count;
    O2SurfaceDamageRect rects[O2SurfaceDamageMaxRects];
} O2SurfaceDamage;

// Adds the rectangle clipped to [0, limitWidth) x [0, limitHeight). Empty
// rectangles, and rectangles already covered by one entry, add nothing.
void O2SurfaceDamageAdd(O2SurfaceDamage *damage, int64_t x, int64_t y,
                        int64_t width, int64_t height, int32_t limitWidth,
                        int32_t limitHeight);
void O2SurfaceDamageUnion(O2SurfaceDamage *damage, const O2SurfaceDamage *other,
                          int32_t limitWidth, int32_t limitHeight);
// The sum of the rectangles' areas (overlaps count twice).
int64_t O2SurfaceDamagePixelCount(const O2SurfaceDamage *damage);

#ifdef __cplusplus
}
#endif

#endif
