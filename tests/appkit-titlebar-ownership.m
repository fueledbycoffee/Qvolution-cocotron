#import <AppKit/AppKit.h>
#import "../AppKit/NSThemeFrame.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: qvolution_titlebar_policy EXPECTED_HEIGHT\n");
        return 2;
    }
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    CGFloat expected = strtod(argv[1], NULL);
    CGFloat actual = [NSThemeFrame titleBarHeightForStyleMask: NSWindowStyleMaskTitled];
    if (fabs(actual - expected) > 0.01) {
        fprintf(stderr, "FAIL: AppKit title height %.1f, expected %.1f\n", actual, expected);
        [pool drain];
        return 1;
    }
    if ([NSThemeFrame titleBarHeightForStyleMask: NSWindowStyleMaskBorderless] != 0) {
        fprintf(stderr, "FAIL: borderless window reserves a title bar\n");
        [pool drain];
        return 1;
    }
    NSRect content = NSMakeRect(10, 20, 400, 300);
    NSWindowStyleMask styles = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
    NSRect frame = [NSWindow frameRectForContentRect: content styleMask: styles];
    NSRect roundtrip = [NSWindow contentRectForFrameRect: frame styleMask: styles];
    if (!NSEqualRects(content, roundtrip)) {
        fprintf(stderr, "FAIL: window frame/content conversion does not round-trip\n");
        [pool drain];
        return 1;
    }
    puts("PASS: title-bar ownership, borderless layout and frame conversion");
    [pool drain];
    return 0;
}
