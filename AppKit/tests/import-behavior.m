// Own-framework behavioral regression; no Apple images are inspected.
#import <Foundation/Foundation.h>
#import <AppKit/NSMenuItemBadge.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSWritingToolsCoordinator.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <dlfcn.h>
#define CHECK(expression) do { \
    if (!(expression)) { \
        fprintf(stderr, "FAIL: %s\n", #expression); \
        return 1; \
    } \
} while (0)

int main(int argc, char **argv) {
    CHECK(argc == 2);
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    void *image = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!image) { fprintf(stderr, "%s\n", dlerror()); return 1; }
    Class badge = objc_getClass("NSMenuItemBadge");
    NSMutableString *label = [NSMutableString stringWithString: @"Unread"];
    id item = [[badge alloc] initWithString: label];
    [label appendString: @" changed"];
    CHECK([[item stringValue] isEqualToString: @"Unread"]);
    id copy = [item copy];
    [item release];
    CHECK([[copy stringValue] isEqualToString: @"Unread"]);
    [copy release];
    item = [[badge alloc] initWithCount: 12];
    CHECK([item itemCount] == 12);
    CHECK([item stringValue] == nil);
    Class menuItem = objc_getClass("NSMenuItem");
    id entry = [[menuItem alloc] initWithTitle: @"Inbox" action: NULL keyEquivalent: @""];
    [entry setBadge: item];
    id entryCopy = [entry copy];
    [item release];
    [entry release];
    CHECK([[entryCopy badge] itemCount] == 12);
    [entryCopy release];
    CHECK([[badge alloc] initWithString: nil] == nil);
    Class writing = objc_getClass("NSWritingToolsCoordinator");
    CHECK(![writing isWritingToolsAvailable]);
    CHECK([[writing alloc] initWithDelegate: nil] == nil);
    puts("PASS copied badge state and unavailable Writing Tools");
    // Objective-C class metadata remains registered until process exit.
    [pool drain];
    return 0;
}
