#!/usr/bin/env python3
"""Rasterise the shared title-bar renderer natively and check its pixels.

Compiles AppKit/NSTitlebarRenderer.m as C (it has no Objective-C) with
ASan/UBSan and asserts the visual theme spec's P3 acceptance pixels at 1x and
2x: disc centres and colours, hover glyph, inactive discs, bar fill, corner
transparency, shadow alpha, maximized margin, title centring, press tracking
and resize edges. Text rendering itself is not covered here.
"""
import argparse, os, subprocess, tempfile
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--source', type=Path)
a = p.parse_args()
root = Path(__file__).resolve().parents[1]
renderer = a.source or root / 'AppKit/NSTitlebarRenderer.m'

test = r'''
#include "NSTitlebarRenderer.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { int r, g, b, a; } RGBA;
static NSTitlebarBitmap bitmap;
static NSTitlebarFrame frame;
static int failures;

static RGBA at(double vx, double vy) {
    int x = (int) floor((vx + frame.margin) * bitmap.scale + bitmap.scale / 2 - 0.5);
    int y = (int) floor((vy + frame.margin) * bitmap.scale + bitmap.scale / 2 - 0.5);
    assert(x >= 0 && y >= 0 && x < bitmap.width && y < bitmap.height);
    uint8_t *p = bitmap.pixels + (size_t) y * bitmap.bytesPerRow + (size_t) x * 4;
    return (RGBA){p[2], p[1], p[0], p[3]};
}

static void expectRGB(const char *what, RGBA got, unsigned rgb) {
    int r = rgb >> 16, g = (rgb >> 8) & 255, b = rgb & 255;
    if (abs(got.r - r) > 2 || abs(got.g - g) > 2 || abs(got.b - b) > 2 || got.a != 255) {
        printf("FAIL %s at %gx: got %02X%02X%02X/%d, want %06X/255\n", what, bitmap.scale,
               got.r, got.g, got.b, got.a, rgb);
        failures++;
    }
}

static void expect(const char *what, int ok) {
    if (!ok) { printf("FAIL %s at %gx\n", what, bitmap.scale); failures++; }
}

static void render(double scale, double margin, int active, int hover, int pressed) {
    free(bitmap.pixels);
    frame.margin = margin; frame.width = 400; frame.height = 300 + NSTitlebarHeight;
    frame.rounded = frame.shadow = margin > 0;
    memset(&frame.state, 0, sizeof(frame.state));
    frame.state.active = active; frame.state.hover = hover; frame.state.pressed = pressed;
    frame.state.enabled[0] = frame.state.enabled[1] = frame.state.enabled[2] = 1;
    frame.state.hairline = 1;
    bitmap.scale = scale;
    bitmap.width = (int) ceil((frame.width + 2 * margin) * scale);
    bitmap.height = (int) ceil((frame.height + 2 * margin) * scale);
    bitmap.bytesPerRow = (size_t) bitmap.width * 4;
    bitmap.pixels = calloc(bitmap.height, bitmap.bytesPerRow);
    NSTitlebarRenderFrame(&bitmap, &frame);
}

static void rerender(void) {
    memset(bitmap.pixels, 0, bitmap.height * bitmap.bytesPerRow);
    NSTitlebarRenderFrame(&bitmap, &frame);
}

int main(void) {
    const unsigned discs[3] = {0xFF5F57, 0xFDBC2E, 0x29C740};
    for (double scale = 1; scale <= 2; scale++) {
        render(scale, NSTitlebarMargin, 1, 0, NSTitlebarButtonNone);
        for (int i = 0; i < 3; i++) {
            double cx, cy; NSTitlebarDiscCenter(i, &cx, &cy);
            expect("disc centre", cx == 14 + 20 * i && cy == 14);
            expectRGB("idle active disc centre", at(cx, cy), discs[i]);
            // Diameter 12: just inside the rim is disc, just outside is bar.
            for (int dir = -1; dir <= 1; dir += 2) {
                RGBA inside = at(cx + dir * 3.5, cy), outside = at(cx + dir * 7, cy);
                expect("inside disc is coloured", abs(inside.r - (int)(discs[i] >> 16)) <= 2);
                expectRGB("outside disc is bar", outside, 0xE8E8E8);
                inside = at(cx, cy + dir * 3.5), outside = at(cx, cy + dir * 7);
                expect("inside disc vertically", abs(inside.g - (int)((discs[i] >> 8) & 255)) <= 2);
                expectRGB("outside disc vertically", outside, 0xE8E8E8);
            }
        }
        expectRGB("active bar at (w/2, 4)", at(frame.width / 2, 4), 0xE8E8E8);
        RGBA corner = at(0, 0);
        expect("(0,0) carries no bar colour", corner.r == 0 && corner.g == 0 && corner.b == 0);
        expect("(0,0) is at most shadow alpha", corner.a <= (int) round(0.30 * 255));
        expect("(10,10) is opaque", at(10, 10).a == 255);
        RGBA left = at(-4, frame.height / 2);
        expect("shadow 4 px left alpha in [0.05, 0.30]", left.a >= 0.05 * 255 && left.a <= 0.30 * 255);
        expect("shadow is black", left.r == 0 && left.g == 0 && left.b == 0);
        RGBA hairline = at(frame.width / 2, NSTitlebarHeight - 1 / scale);
        expect("hairline darker than bar", hairline.r < 0xE8 - 10 && hairline.a == 255);
        expect("content untouched", at(frame.width / 2, NSTitlebarHeight + 5).a == 0);

        frame.state.hover = 1; rerender();
        expectRGB("hover close centre is glyph colour", at(14, 14),
                  ((unsigned) round(0xFF * .45) << 16) | ((unsigned) round(0x5F * .45) << 8) | (unsigned) round(0x57 * .45));
        expectRGB("hover minimize centre is glyph colour", at(34, 14),
                  ((unsigned) round(0xFD * .45) << 16) | ((unsigned) round(0xBC * .45) << 8) | (unsigned) round(0x2E * .45));

        frame.state.pressed = NSTitlebarButtonClose; frame.state.hover = 0; rerender();
        expectRGB("pressed close is fill x 0.80", at(14, 11),
                  ((unsigned) round(0xFF * .8) << 16) | ((unsigned) round(0x5F * .8) << 8) | (unsigned) round(0x57 * .8));

        render(scale, NSTitlebarMargin, 0, 0, NSTitlebarButtonNone);
        for (int i = 0; i < 3; i++) expectRGB("inactive disc", at(14 + 20 * i, 14), 0xDDDDDD);
        expectRGB("inactive bar at (w/2, 4)", at(frame.width / 2, 4), 0xF6F6F6);
        RGBA weak = at(-4, frame.height / 2);
        expect("inactive shadow lighter", weak.a > 0 && weak.a < left.a);
        frame.state.hover = 1; rerender();
        expect("hover colours discs in inactive windows", abs(at(34, 11).r - 0xFD) <= 2);
        frame.state.enabled[NSTitlebarButtonZoom] = 0; rerender();
        RGBA disabled = at(54, 14);
        expect("disabled zoom has no glyph and half alpha fill",
               abs(disabled.r - (0xDD + 0xF6) / 2) <= 3 && disabled.r == disabled.g && disabled.g == disabled.b);

        render(scale, 0, 1, 0, NSTitlebarButtonNone);
        expectRGB("maximized (0,0) is square bar", at(0, 0), 0xE8E8E8);
        expect("maximized surface has no margin", bitmap.width == (int) ceil(400 * scale));

        // Bottom corners after content drew opaque white there.
        render(scale, NSTitlebarMargin, 1, 0, NSTitlebarButtonNone);
        for (int y = 0; y < bitmap.height; y++)
            for (int x = 0; x < bitmap.width; x++) {
                double vy = (y + .5) / scale - frame.margin, vx = (x + .5) / scale - frame.margin;
                if (vy >= NSTitlebarHeight && vy < frame.height && vx >= 0 && vx < frame.width)
                    memset(bitmap.pixels + y * bitmap.bytesPerRow + x * 4, 255, 4);
            }
        NSTitlebarMaskContentCorners(&bitmap, &frame);
        RGBA bl = at(0, frame.height - 1), br = at(frame.width - 1, frame.height - 1);
        expect("bottom-left corner cut", bl.a < 0.31 * 255 && bl.r == 0);
        expect("bottom-right corner cut", br.a < 0.31 * 255 && br.r == 0);
        expect("content kept inside the radius", at(10, frame.height - 10).a == 255 &&
               at(frame.width / 2, frame.height - 1).r == 255);
        uint8_t *copy = malloc(bitmap.height * bitmap.bytesPerRow);
        memcpy(copy, bitmap.pixels, bitmap.height * bitmap.bytesPerRow);
        NSTitlebarMaskContentCorners(&bitmap, &frame);
        expect("corner mask is idempotent", !memcmp(copy, bitmap.pixels, bitmap.height * bitmap.bytesPerRow));
        free(copy);
    }

    double room, x = NSTitlebarTitleOriginX(600, 100, &room);
    expect("title centred on whole bar", x == 250 && room == 600 - 72 - 8);
    x = NSTitlebarTitleOriginX(200, 100, &room);
    expect("title shifted right of the lights", x == 72 && room == 120);

    NSTitlebarState state = {.enabled = {1, 1, 1}};
    NSTitlebarTracker tracker = {NSTitlebarButtonNone};
    expect("press close", NSTitlebarTrackerPress(&tracker, &state, 14, 14));
    expect("drag off close does not act", NSTitlebarTrackerRelease(&tracker, 14, 40) == NSTitlebarButtonNone);
    NSTitlebarTrackerPress(&tracker, &state, 14, 14);
    expect("release on another disc does not act", NSTitlebarTrackerRelease(&tracker, 34, 14) == NSTitlebarButtonNone);
    NSTitlebarTrackerPress(&tracker, &state, 14, 14);
    expect("release inside close acts", NSTitlebarTrackerRelease(&tracker, 22, 6) == NSTitlebarButtonClose);
    state.enabled[1] = 0;
    expect("disabled disc is not pressable", !NSTitlebarTrackerPress(&tracker, &state, 34, 14));
    for (double hx = 4; hx < 64; hx += 0.25)
        expect("hit areas contiguous", NSTitlebarButtonAtPoint(hx, 14) == (int) ((hx - 4) / 20));
    expect("no hit left of group", NSTitlebarButtonAtPoint(3.9, 14) == NSTitlebarButtonNone);
    expect("no hit right of group", NSTitlebarButtonAtPoint(64, 14) == NSTitlebarButtonNone);

    NSTitlebarFrame f = {.margin = 12, .width = 400, .height = 328};
    expect("left edge", NSTitlebarResizeEdgesAtPoint(&f, 12 - 3, 100) == 4);
    expect("beyond resize band", NSTitlebarResizeEdgesAtPoint(&f, 12 - 9, 100) == 0);
    expect("top-left inside corner", NSTitlebarResizeEdgesAtPoint(&f, 13, 13) == 5);
    expect("bottom-right outside", NSTitlebarResizeEdgesAtPoint(&f, 12 + 401, 12 + 329) == 10);
    expect("inside title bar moves", NSTitlebarResizeEdgesAtPoint(&f, 200, 14) == 0);
    f.margin = 0;
    expect("maximized never resizes", NSTitlebarResizeEdgesAtPoint(&f, 1, 1) == 0);

    free(bitmap.pixels);
    if (failures) { printf("%d failures\n", failures); return 1; }
    puts("PASS titlebar renderer pixels at 1x/2x: disc centres/colours, hover glyph, pressed, inactive, "
         "disabled, bar fill, corners, shadow, hairline, maximized, content corner mask, title layout, "
         "release tracking, resize edges");
    return 0;
}
'''

with tempfile.TemporaryDirectory(prefix='titlebar-pixels-') as folder:
    folder = Path(folder)
    (folder / 'test.c').write_text(test)
    binary = folder / 'test'
    subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter',
                    '-fsanitize=address,undefined', '-fno-sanitize-recover=all',
                    '-I', str(renderer.parent), '-x', 'c', str(renderer), '-x', 'c', str(folder / 'test.c'),
                    '-lm', '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True,
                   env={**os.environ, 'ASAN_OPTIONS': 'detect_leaks=1', 'UBSAN_OPTIONS': 'halt_on_error=1'})
