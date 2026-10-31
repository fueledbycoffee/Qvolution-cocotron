#include <CoreGraphics/CoreGraphics.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdio.h>
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "failed line %d: %s\n", __LINE__, #c); return 1; } } while (0)
int main(void) {
    const CFStringRef *symbol = dlsym(RTLD_DEFAULT, "kCGColorSpaceITUR_2100_HLG");
    if (!symbol) { puts("ABSENT_DATA_SYMBOL"); return 77; }
    CFStringRef name = *symbol;
    CHECK(name && CFGetTypeID(name) == CFStringGetTypeID() && CFStringGetLength(name) > 0);
    CGColorSpaceRef hlg = CGColorSpaceCreateWithName(name);
    CHECK(hlg && CGColorSpaceGetModel(hlg) == kCGColorSpaceModelRGB);
    CHECK(CGColorSpaceGetNumberOfComponents(hlg) == 3);
    CHECK(CFEqual(CGColorSpaceGetName(hlg), name));
    CFStringRef owned = CGColorSpaceCopyName(hlg);
    CHECK(owned && CFEqual(owned, name));
    CGColorSpaceRelease(hlg);
    CHECK(CFEqual(owned, name));
    CFRelease(owned);
    CFMutableStringRef dynamic = CFStringCreateMutableCopy(NULL, 0, name);
    hlg = CGColorSpaceCreateWithName(dynamic);
    CFRelease(dynamic);
    CHECK(hlg && CFEqual(CGColorSpaceGetName(hlg), name));
    CHECK(CGColorSpaceIsHLGBased(hlg) && CGColorSpaceUsesITUR_2100TF(hlg));
    CGColorSpaceRef pq = CGColorSpaceCreateWithName(kCGColorSpaceITUR_2100_PQ);
    CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGColorSpaceRef device = CGColorSpaceCreateDeviceRGB();
    CHECK(pq && srgb && device);
    CHECK(!CGColorSpaceIsHLGBased(pq) && CGColorSpaceUsesITUR_2100TF(pq));
    CHECK(!CGColorSpaceIsHLGBased(srgb) && !CGColorSpaceUsesITUR_2100TF(srgb));
    CHECK(!CGColorSpaceIsHLGBased(device) && !CGColorSpaceUsesITUR_2100TF(device));
    CHECK(!CGColorSpaceIsHLGBased(NULL) && !CGColorSpaceUsesITUR_2100TF(NULL));
    CHECK(!CGColorSpaceCreateWithName(NULL));
    CHECK(!CGColorSpaceCreateWithName(CFSTR("qvolution-fixture-unknown")));
    CGFloat values[] = {0.5, 0.25, 0.75, 0.25};
    CGColorRef hdr = CGColorCreate(hlg, values), sdr = CGColorCreate(srgb, values);
    CHECK(hdr && sdr);
    CHECK(!CGColorEqualToColor(hdr, sdr));
    CHECK(!CGColorCreateCopyByMatchingToColorSpace(srgb, kCGRenderingIntentDefault, hdr, NULL));
    CHECK(!CGColorCreateCopyByMatchingToColorSpace(hlg, kCGRenderingIntentDefault, sdr, NULL));
    CGColorRef copy = CGColorCreateCopyByMatchingToColorSpace(srgb, kCGRenderingIntentDefault, sdr, NULL);
    CHECK(copy && CGColorGetAlpha(copy) == 0.25);
    CGColorRelease(copy); CGColorRelease(hdr); CGColorRelease(sdr);
    CGColorSpaceRelease(hlg); CGColorSpaceRelease(pq); CGColorSpaceRelease(srgb); CGColorSpaceRelease(device);
    puts("METADATA_PASS_MATCHING_EXPLICITLY_UNSUPPORTED");
    return 0;
}
