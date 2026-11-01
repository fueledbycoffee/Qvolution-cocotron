// Own-framework behavioral regression; no Apple images are inspected.
#import <Foundation/Foundation.h>
#import <AppKit/NSMenuItemBadge.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSWritingToolsCoordinator.h>
#import <objc/runtime.h>
#include <assert.h>
#include <dlfcn.h>
int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    assert(argc == 2);
    void *image = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!image) { fprintf(stderr, "%s\n", dlerror()); return 1; }
    Class badge = objc_getClass("NSMenuItemBadge");
    NSMutableString *label = [NSMutableString stringWithString: @"Unread"];
    id item = [[badge alloc] initWithString: label];
    [label appendString: @" changed"];
    assert([[item stringValue] isEqualToString: @"Unread"]);
    id copy = [item copy];
    [item release];
    assert([[copy stringValue] isEqualToString: @"Unread"]);
    [copy release];
    item = [[badge alloc] initWithCount: 12];
    assert([item itemCount] == 12);
    assert([item stringValue] == nil);
    Class menuItem = objc_getClass("NSMenuItem");
    id entry = [[menuItem alloc] initWithTitle: @"Inbox" action: NULL keyEquivalent: @""];
    [entry setBadge: item];
    id entryCopy = [entry copy];
    [item release];
    [entry release];
    assert([[entryCopy badge] itemCount] == 12);
    [entryCopy release];
    assert([[badge alloc] initWithString: nil] == nil);
    Class writing = objc_getClass("NSWritingToolsCoordinator");
    assert(![writing isWritingToolsAvailable]);
    assert([[writing alloc] initWithDelegate: nil] == nil);
    puts("PASS copied badge state and unavailable Writing Tools");
    // Objective-C class metadata remains registered until process exit.
    [pool drain];
    return 0;
}
