/* Full-framework checks of SPEC.md Round 3; run only on our staged frameworks.
 * Rung 2 supplies declarations; all behavior under test is chosen GUESS, rung 6.
 * This verifies Darling's contract, not Apple compatibility or pixel output. */
#include <CoreGraphics/CoreGraphicsPrivate.h>
#include <HIServices/Processes.h>
#include <CarbonCore/MacErrors.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <limits.h>
#include <math.h>
#include <pthread.h>

static unsigned checks;
#define CHECK(x) do { ++checks; if (!(x)) { fprintf(stderr, "FAIL %d: %s\n", __LINE__, #x); return 1; } } while (0)
typedef void (*Setter)(CGContextRef, bool);
typedef bool (*Getter)(CGContextRef);
static Setter setters[] = {CGContextSetAllowsAntialiasing, CGContextSetShouldAntialias,
    CGContextSetAllowsFontSmoothing, CGContextSetShouldSmoothFonts};
static Getter getters[] = {CGContextGetAllowsAntialiasing, CGContextGetShouldAntialias,
    CGContextGetAllowsFontSmoothing, CGContextGetShouldSmoothFonts};
static int state(CGContextRef c, bool a, bool s, bool f, bool t, uint32_t style) {
    CHECK(getters[0](c) == a); CHECK(getters[1](c) == s);
    CHECK(getters[2](c) == f); CHECK(getters[3](c) == t);
    CHECK(CGContextGetFontSmoothingStyle(c) == style);
    return 0;
}
static void *threadLookup(void *output) {
    *(CGSConnectionID *)output = CGSDefaultConnectionForThread();
    return NULL;
}
int main(void) {
    uint8_t pixels[2][64] = {{0}};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CHECK(space != NULL);
    CGContextRef c[2];
    for (unsigned k = 0; k < 2; ++k) {
        c[k] = CGBitmapContextCreate(pixels[k], 4, 4, 8, 16, space, kCGImageAlphaPremultipliedLast);
        CHECK(c[k] != NULL); CHECK(state(c[k], true, true, true, true, 0) == 0);
    }
    for (unsigned i = 0; i < 4; ++i) { setters[i](NULL, false); CHECK(!getters[i](NULL)); }
    CGContextSetFontSmoothingStyle(NULL, UINT32_MAX);
    CHECK(CGContextGetFontSmoothingStyle(NULL) == 0);
    CGContextSaveGState(NULL); CGContextRestoreGState(NULL);
    for (unsigned mask = 0; mask < 16; ++mask) {
        for (unsigned i = 0; i < 4; ++i) {
            setters[i](c[0], (mask >> i) & 1);
            CHECK(getters[i](c[0]) == !!((mask >> i) & 1));
        }
        CHECK(state(c[1], true, true, true, true, 0) == 0);
    }
    CGContextSetFontSmoothingStyle(c[0], 0xabcdef01u);
    CGContextSaveGState(c[0]);
    for (unsigned i = 0; i < 4; ++i) setters[i](c[0], false);
    CGContextSetFontSmoothingStyle(c[0], 0x80000000u);
    CGContextSaveGState(c[0]);
    for (unsigned i = 0; i < 4; ++i) setters[i](c[0], true);
    CGContextSetFontSmoothingStyle(c[0], UINT32_MAX);
    CGContextRestoreGState(c[0]); CHECK(state(c[0], true, false, true, false, 0x80000000u) == 0);
    CGContextSetAllowsAntialiasing(c[0], false); CGContextSetAllowsFontSmoothing(c[0], false);
    CGContextRestoreGState(c[0]); CHECK(state(c[0], false, true, false, true, 0xabcdef01u) == 0);
    CGContextRestoreGState(c[0]); CHECK(state(c[0], false, true, false, true, 0xabcdef01u) == 0);
    CHECK(state(c[1], true, true, true, true, 0) == 0);
    CGContextRelease(c[0]); CGContextRelease(c[1]);
    c[0] = CGBitmapContextCreate(pixels[0], 4, 4, 8, 16, space, kCGImageAlphaPremultipliedLast);
    CHECK(c[0] != NULL); CHECK(state(c[0], true, true, true, true, 0) == 0);
    CGContextRelease(c[0]); CGColorSpaceRelease(space);

    CGSConnectionID process = _CGSDefaultConnection();
    CGSConnectionID expected = process > 0 ? process : 0;
    CHECK(CGSDefaultConnectionForThread() == expected);
    pthread_t thread; CGSConnectionID threaded = -1;
    CHECK(pthread_create(&thread, NULL, threadLookup, &threaded) == 0);
    CHECK(pthread_join(thread, NULL) == 0); CHECK(threaded == expected);
    int values[] = {INT_MIN, -1, 0, 1, INT_MAX};
    float opacities[] = {NAN, INFINITY, -INFINITY, -1, 0, 1, 2};
    for (unsigned i = 0; i < 5; ++i) {
        CHECK(CGSSetSecureEventInput(values[i], false) == kCGErrorNotImplemented);
        CHECK(CGSSetSecureEventInput(values[i], true) == kCGErrorNotImplemented);
        CHECK(CGSSetWindowBackgroundBlurRadius(values[i], values[4-i], values[i]) == kCGErrorNotImplemented);
        CHECK(CGSSetWindowBackgroundBlurRadiusStyle(values[i], values[4-i], values[i], values[i]) == kCGErrorNotImplemented);
        for (unsigned f = 0; f < 7; ++f)
            CHECK(CGSSetWindowBackgroundBlurRadiusWithOpacityHint(values[i], values[4-i], values[i], opacities[f]) == kCGErrorNotImplemented);
    }
    struct { uint32_t before; CPSProcessSerNum psn; uint32_t after; } out = {0x12345678, {3, 4}, 0x87654321};
    CHECK(CPSGetCurrentProcess(NULL) == paramErr);
    ProcessSerialNumber actual;
    OSErr publicStatus = GetCurrentProcess(&actual);
    OSErr privateStatus = CPSGetCurrentProcess(&out.psn);
    CHECK(privateStatus == publicStatus);
    if (publicStatus == noErr) {
        CHECK(out.psn.highLongOfPSN == actual.highLongOfPSN);
        CHECK(out.psn.lowLongOfPSN == actual.lowLongOfPSN);
    } else { CHECK(out.psn.highLongOfPSN == 3); CHECK(out.psn.lowLongOfPSN == 4); }
    CHECK(out.before == 0x12345678); CHECK(out.after == 0x87654321);
    CPSProcessSerNum unchanged = out.psn;
    CHECK(CPSStealKeyFocus(NULL, UINT32_MAX) == paramErr); CHECK(CPSReleaseKeyFocus(NULL) == paramErr);
    for (unsigned i = 0; i < 3; ++i) {
        CHECK(CPSStealKeyFocus(&out.psn, (uint32_t[]){0, 1, UINT32_MAX}[i]) == unimpErr);
        CHECK(CPSReleaseKeyFocus(&out.psn) == unimpErr);
    }
    CHECK(memcmp(&out.psn, &unchanged, sizeof(unchanged)) == 0);
    printf("PASS full-framework Round 3: %u checks, %zu-bit target\n", checks, sizeof(void *) * 8);
    return 0;
}
