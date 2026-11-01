#ifndef NS_WINDOW_FRAME_TRACE_H
#define NS_WINDOW_FRAME_TRACE_H
#import <Foundation/NSGeometry.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
// Fixed source labels describe our code paths, never a caller address/backtrace.
static inline void NSWindowTraceFrame(const char *source, NSRect before, NSRect after) {
    const char *enabled = getenv("DARLING_APPKIT_FRAME_TRACE");
    if (!enabled || strcmp(enabled, "1") || NSEqualRects(before, after)) return;
    fprintf(stderr, "APPKIT_FRAME source=%s old=%.3f,%.3f %.3fx%.3f new=%.3f,%.3f %.3fx%.3f delta=%.3f,%.3f\n",
        source, before.origin.x, before.origin.y, before.size.width, before.size.height,
        after.origin.x, after.origin.y, after.size.width, after.size.height,
        after.size.width - before.size.width, after.size.height - before.size.height);
}
#endif
