#!/usr/bin/env python3
"""Compile Onyx2D/O2SurfaceDamage.m natively (it is plain C) and check the region list:
it covers every pixel added, stays inside the limits, keeps at most O2SurfaceDamageMaxRects
entries, stays exact while disjoint rectangles fit, and drops covered entries.
Usage: python3 tests/onyx2d-surface-damage.py [--source <O2SurfaceDamage.m>]
"""
import argparse, os, subprocess, tempfile
from pathlib import Path

p = argparse.ArgumentParser(); p.add_argument('--source', type=Path); a = p.parse_args()
root = Path(__file__).resolve().parents[1]
source = a.source or root / 'Onyx2D/O2SurfaceDamage.m'
probe = r'''
#include <Onyx2D/O2SurfaceDamage.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>
enum { W = 97, H = 61 };
static unsigned rng = 2024;
static int below(int n) { rng = rng * 1664525u + 1013904223u; return (int) ((rng >> 8) % (unsigned) n); }
static int covered(const O2SurfaceDamage *d, int x, int y) {
    for (int i = 0; i < d->count; i++)
        if (x >= d->rects[i].x && x < d->rects[i].x + d->rects[i].width &&
            y >= d->rects[i].y && y < d->rects[i].y + d->rects[i].height)
            return 1;
    return 0;
}
static void wellFormed(const O2SurfaceDamage *d) {
    assert(d->count >= 0 && d->count <= O2SurfaceDamageMaxRects);
    for (int i = 0; i < d->count; i++) {
        const O2SurfaceDamageRect r = d->rects[i];
        assert(r.width > 0 && r.height > 0 && r.x >= 0 && r.y >= 0 && r.x + r.width <= W && r.y + r.height <= H);
        for (int j = 0; j < d->count; j++)
            if (i != j) {
                const O2SurfaceDamageRect s = d->rects[j];
                assert(!(s.x >= r.x && s.y >= r.y && s.x + s.width <= r.x + r.width && s.y + s.height <= r.y + r.height));
            }
    }
}
int main(void) {
    setbuf(stdout, NULL);
    unsigned long long checks = 0;
    for (int trial = 0; trial < 20000; trial++) {
        O2SurfaceDamage d; memset(&d, 0, sizeof d);
        static unsigned char want[H][W]; memset(want, 0, sizeof want);
        int adds = 1 + below(24);
        for (int k = 0; k < adds; k++) {
            // Mostly small marks, some off the edges, some empty or huge.
            long long x = below(W + 40) - 20, y = below(H + 40) - 20, w = below(trial % 7 == 0 ? 200 : 14) - 1, h = below(trial % 5 == 0 ? 200 : 14) - 1;
            if (k == 0 && trial % 11 == 0) { x = -((long long) 1 << 40); w = (long long) 1 << 41; }
            O2SurfaceDamageAdd(&d, x, y, w, h, W, H);
            for (long long yy = y < 0 ? 0 : y; yy < y + h && yy < H; yy++)
                for (long long xx = x < 0 ? 0 : x; xx < x + w && xx < W; xx++) want[yy][xx] = 1;
            wellFormed(&d);
            for (int yy = 0; yy < H; yy++)
                for (int xx = 0; xx < W; xx++)
                    if (want[yy][xx]) { assert(covered(&d, xx, yy)); checks++; }
        }
    }
    // Exact while disjoint rectangles fit; merging only past the limit.
    O2SurfaceDamage d; memset(&d, 0, sizeof d);
    for (int i = 0; i < O2SurfaceDamageMaxRects; i++) O2SurfaceDamageAdd(&d, i * 12, 3, 2, 18, W, H);
    assert(d.count == O2SurfaceDamageMaxRects && O2SurfaceDamagePixelCount(&d) == 2 * 18 * O2SurfaceDamageMaxRects);
    O2SurfaceDamageAdd(&d, 0, 3, 1, 1, W, H);  // already covered: nothing changes
    assert(d.count == O2SurfaceDamageMaxRects && O2SurfaceDamagePixelCount(&d) == 2 * 18 * O2SurfaceDamageMaxRects);
    O2SurfaceDamageAdd(&d, 13, 30, 2, 2, W, H);  // past the limit: merges into its nearest neighbour
    assert(d.count == O2SurfaceDamageMaxRects && covered(&d, 13, 30) && covered(&d, 14, 31));
    O2SurfaceDamageAdd(&d, 0, 0, W, H, W, H);  // a covering rectangle replaces everything
    assert(d.count == 1 && O2SurfaceDamagePixelCount(&d) == W * H);
    O2SurfaceDamage e; memset(&e, 0, sizeof e);
    O2SurfaceDamageAdd(&e, 5, 5, 4, 4, W, H);
    O2SurfaceDamage u; memset(&u, 0, sizeof u);
    O2SurfaceDamageAdd(&u, 50, 40, 3, 3, W, H);
    O2SurfaceDamageUnion(&u, &e, W, H);
    assert(u.count == 2 && covered(&u, 5, 5) && covered(&u, 52, 42) && !covered(&u, 20, 20));
    printf("PASS surface damage regions cover %llu added pixels within %d rects; exact while disjoint rects fit\n", checks, O2SurfaceDamageMaxRects);
    return 0;
}
'''
out = Path(tempfile.mkdtemp(prefix='surface-damage-'))
(out / 'probe.c').write_text(probe)
subprocess.run(['cc', '-std=c11', '-O1', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined', '-I', str(root / 'Onyx2D/include'),
                '-x', 'c', str(source), '-x', 'c', str(out / 'probe.c'), '-o', str(out / 'probe')], check=True)
subprocess.run([str(out / 'probe')], check=True, env={**os.environ, 'UBSAN_OPTIONS': 'halt_on_error=1'})
