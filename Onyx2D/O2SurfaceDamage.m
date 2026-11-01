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

// Plain C (no Objective-C), so tests/onyx2d-surface-damage.py compiles it natively.
#include <Onyx2D/O2SurfaceDamage.h>

static int contains(O2SurfaceDamageRect outer, O2SurfaceDamageRect inner) {
    return inner.x >= outer.x && inner.y >= outer.y &&
           inner.x + inner.width <= outer.x + outer.width &&
           inner.y + inner.height <= outer.y + outer.height;
}

static O2SurfaceDamageRect unite(O2SurfaceDamageRect a, O2SurfaceDamageRect b) {
    int32_t x0 = a.x < b.x ? a.x : b.x, y0 = a.y < b.y ? a.y : b.y;
    int32_t x1 = a.x + a.width > b.x + b.width ? a.x + a.width : b.x + b.width;
    int32_t y1 = a.y + a.height > b.y + b.height ? a.y + a.height : b.y + b.height;
    return (O2SurfaceDamageRect){x0, y0, x1 - x0, y1 - y0};
}

static int64_t area(O2SurfaceDamageRect r) {
    return (int64_t) r.width * r.height;
}

// Drops every entry that `cover` contains.
static void removeCovered(O2SurfaceDamage *damage, O2SurfaceDamageRect cover) {
    int32_t out = 0;
    for (int32_t i = 0; i < damage->count; i++)
        if (!contains(cover, damage->rects[i]))
            damage->rects[out++] = damage->rects[i];
    damage->count = out;
}

static void addRect(O2SurfaceDamage *damage, O2SurfaceDamageRect rect) {
    for (int32_t i = 0; i < damage->count; i++)
        if (contains(damage->rects[i], rect))
            return;
    removeCovered(damage, rect);
    if (damage->count < O2SurfaceDamageMaxRects) {
        damage->rects[damage->count++] = rect;
        return;
    }
    // Full: merge into the entry whose bounds grow least.
    int32_t best = 0;
    int64_t bestGrowth = INT64_MAX;
    for (int32_t i = 0; i < damage->count; i++) {
        int64_t growth = area(unite(damage->rects[i], rect)) - area(damage->rects[i]);
        if (growth < bestGrowth) {
            bestGrowth = growth;
            best = i;
        }
    }
    O2SurfaceDamageRect merged = unite(damage->rects[best], rect);
    damage->rects[best] = damage->rects[--damage->count];
    removeCovered(damage, merged);
    damage->rects[damage->count++] = merged;
}

void O2SurfaceDamageAdd(O2SurfaceDamage *damage, int64_t x, int64_t y,
                        int64_t width, int64_t height, int32_t limitWidth,
                        int32_t limitHeight)
{
    if (width <= 0 || height <= 0 || limitWidth <= 0 || limitHeight <= 0)
        return;
    int64_t x0 = x < 0 ? 0 : x, y0 = y < 0 ? 0 : y;
    int64_t x1 = x + width > limitWidth ? limitWidth : x + width;
    int64_t y1 = y + height > limitHeight ? limitHeight : y + height;
    if (x1 <= x0 || y1 <= y0)
        return;
    addRect(damage, (O2SurfaceDamageRect){(int32_t) x0, (int32_t) y0,
                                         (int32_t) (x1 - x0), (int32_t) (y1 - y0)});
}

void O2SurfaceDamageUnion(O2SurfaceDamage *damage, const O2SurfaceDamage *other,
                          int32_t limitWidth, int32_t limitHeight)
{
    for (int32_t i = 0; i < other->count; i++)
        O2SurfaceDamageAdd(damage, other->rects[i].x, other->rects[i].y,
                           other->rects[i].width, other->rects[i].height,
                           limitWidth, limitHeight);
}

int64_t O2SurfaceDamagePixelCount(const O2SurfaceDamage *damage) {
    int64_t total = 0;
    for (int32_t i = 0; i < damage->count; i++)
        total += area(damage->rects[i]);
    return total;
}
