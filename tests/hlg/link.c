#include <CoreGraphics/CoreGraphics.h>
#include <CoreFoundation/CoreFoundation.h>
/* Official documented typed ABI; no locally defined substitute. */
extern CFStringRef const kCGColorSpaceITUR_2100_HLG;
int main(void) {
    if (!kCGColorSpaceITUR_2100_HLG ||
        CFGetTypeID(kCGColorSpaceITUR_2100_HLG) != CFStringGetTypeID() ||
        !CFStringGetLength(kCGColorSpaceITUR_2100_HLG)) return 1;
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceITUR_2100_HLG);
    if (!space) return 2;
    CGColorSpaceRelease(space);
    return 0;
}
