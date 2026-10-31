#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>

@interface NSScreen (QvolutionColorSpaceContract)
- (NSColorSpace *)colorSpace;
@end

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    NSArray *screens = [NSScreen screens];
    if (![screens count]) { fputs("FAIL: no screens to exercise\n", stderr); return 1; }
    NSColorSpace *survivor = nil;
    for (NSScreen *screen in screens) {
        if (![screen respondsToSelector:@selector(colorSpace)]) {
            fputs("FAIL: NSScreen colorSpace selector unavailable\n", stderr); return 1;
        }
        CGDirectDisplayID display = [[[screen deviceDescription] objectForKey:@"NSScreenNumber"] unsignedIntValue];
        CGColorSpaceRef expected = CGDisplayCopyColorSpace(display);
        NSColorSpace *actual = [screen colorSpace];
        if ((expected == NULL) != (actual == nil) || (expected &&
            (CGColorSpaceGetModel(expected) != CGColorSpaceGetModel([actual CGColorSpace]) ||
             CGColorSpaceGetNumberOfComponents(expected) != CGColorSpaceGetNumberOfComponents([actual CGColorSpace])))) {
            fputs("FAIL: screen colorSpace disagrees with display provider\n", stderr); return 1;
        }
        CGColorSpaceRelease(expected);
        if (!actual || ![actual CGColorSpace]) { fputs("FAIL: backend RGB color space unavailable\n", stderr); return 1; }
        [survivor release]; survivor = [actual retain];
    }
    [pool drain];
    if (CGColorSpaceGetModel([survivor CGColorSpace]) != kCGColorSpaceModelRGB ||
        CGColorSpaceGetNumberOfComponents([survivor CGColorSpace]) != 3) {
        fputs("FAIL: retained color space did not survive pool\n", stderr); return 1;
    }
    [survivor release];
    puts("PASS: screen color-space provider bridge and ownership");
    return 0;
}
