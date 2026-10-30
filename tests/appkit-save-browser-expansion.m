#import <AppKit/AppKit.h>
#include <stdio.h>
#include <sys/time.h>
static double now(void) { struct timeval t; gettimeofday(&t, NULL); return t.tv_sec + t.tv_usec / 1000000.0; }
static void mark(const char *label, double start) { fprintf(stderr, "%s: %.3fs\n", label, now()-start); fflush(stderr); }
int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    double start = now();
    NSSavePanel *panel = [NSSavePanel savePanel];
    mark("savePanel created", start);
    NSOutlineView *outline = [panel valueForKey:@"outlineView"];
    if ([outline autoresizesOutlineColumn]) {
        fprintf(stderr,"FAIL: save browser measures every filename on expansion\n");
        return 1;
    }
    [outline reloadData];
    mark("outline reloaded", start);
    id root = nil;
    for (NSInteger row=0; row<[outline numberOfRows]; row++) {
        id item = [outline itemAtRow:row];
        if ([[item path] isEqualToString:@"/"]) { root=item; break; }
    }
    if (!root) return 2;
    [outline expandItem:root];
    mark("root expanded", start);
    id tmp = nil;
    for (NSInteger row=0; row<[outline numberOfRows]; row++) {
        id item = [outline itemAtRow:row];
        if ([[item path] isEqualToString:@"/tmp"]) { tmp=item; break; }
    }
    if (!tmp) return 3;
    fprintf(stderr,"expanding /tmp\n"); fflush(stderr);
    [outline expandItem:tmp];
    mark("tmp expanded", start);
    fprintf(stderr,"rows: %ld\n", (long)[outline numberOfRows]); fflush(stderr);
    [panel makeKeyAndOrderFront:nil];
    [panel display];
    mark("panel displayed", start);
    [panel close];
    [pool drain];
    puts("PASS: real save-panel nib, root and /tmp expansion and display");
    return 0;
}
