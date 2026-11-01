// Converts an authored NIBArchive nib (tests/nib-visible-fixtures.py na-*.nib) and checks that
// the visible-at-launch set reaches NSIBObjectData: argv[2] is the expected window title, or
// "-" for an empty set. Isolates the NSNibArchive conversion from nib instantiation.
#import <AppKit/AppKit.h>
#import "../AppKit/nib.subproj/NSNibArchive.h"
#include <stdio.h>

@interface NSObject (OwnVisibleWindows)
- (NSSet *)visibleWindows;
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 3) return 2;
        [NSApplication sharedApplication];
        NSData *input = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
        NSData *keyed = NSKeyedArchiveDataFromNibArchiveData(input);
        if (keyed == nil) { fprintf(stderr, "FAIL: conversion rejected the nib\n"); return 1; }
        NSKeyedUnarchiver *unarchiver = [[[NSKeyedUnarchiver alloc] initForReadingWithData:keyed] autorelease];
        id objectData = [unarchiver decodeObjectForKey:@"IB.objectdata"];
        NSSet *visible = [objectData visibleWindows];
        NSString *expected = [NSString stringWithUTF8String:argv[2]];
        BOOL wantEmpty = [expected isEqualToString:@"-"];
        NSString *title = [[visible anyObject] title];
        if (wantEmpty ? [visible count] != 0 : ([visible count] != 1 || ![title isEqualToString:expected])) {
            fprintf(stderr, "FAIL: NSVisibleWindows count=%lu title=%s, expected %s\n",
                    (unsigned long)[visible count], [title UTF8String] ?: "(none)", argv[2]);
            return 1;
        }
        printf("PASS: converted NIBArchive keeps NSVisibleWindows (%s)\n", argv[2]);
    }
    return 0;
}
