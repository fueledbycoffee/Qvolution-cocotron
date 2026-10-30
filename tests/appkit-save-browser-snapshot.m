#import <Foundation/Foundation.h>
#import "../AppKit/NSSavePanel.subproj/_NSFileSystemDataSource.h"
#include <stdio.h>

@interface _NSFileSystemDataSource (Fixture)
- (NSArray *)_contentsOfDirectory:(NSURL *)url;
- (NSInteger)outlineView:(id)view numberOfChildrenOfItem:(NSURL *)url;
- (NSURL *)outlineView:(id)view child:(NSInteger)index ofItem:(NSURL *)url;
@end
@interface CountingSource : _NSFileSystemDataSource { @public NSUInteger reads; }
@end
@implementation CountingSource
- (NSArray *)_contentsOfDirectory:(NSURL *)url {
    if (url) reads++;
    return [super _contentsOfDirectory:url];
}
@end
#define CHECK(condition, message) do { if (!(condition)) { fprintf(stderr, "FAIL: %s (directory reads=%lu)\n", message, (unsigned long)source->reads); return 1; } } while (0)
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    CountingSource *source = [CountingSource new];
    NSURL *directory = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
    NSInteger count = [source outlineView:nil numberOfChildrenOfItem:directory];
    CHECK(count == 1025, "fixture must contain 1024 files and one subdirectory");
    NSURL *first = [source outlineView:nil child:0 ofItem:directory];
    CHECK(source->reads == 1, "first child must reuse the count query listing");
    for (NSInteger i = 0; i < count; i++)
        CHECK([source outlineView:nil child:i ofItem:directory] != nil, "missing child");
    CHECK(source->reads == 1, "children must reuse one directory listing");
    NSURL *nested = [directory URLByAppendingPathComponent:@"nested"];
    CHECK([source outlineView:nil numberOfChildrenOfItem:nested] == 0, "nested fixture should be empty");
    CHECK([source outlineView:nil child:0 ofItem:directory] == first, "interleaving must preserve URL identity");
    CHECK(source->reads == 2, "interleaving must preserve parent snapshot");
    NSString *added = [[directory path] stringByAppendingPathComponent:@"zzzz-added"];
    CHECK([[NSFileManager defaultManager] createFileAtPath:added contents:[NSData data] attributes:nil], "create refresh fixture");
    CHECK([source outlineView:nil numberOfChildrenOfItem:directory] == count + 1, "count query must refresh directory");
    CHECK([source outlineView:nil child:0 ofItem:directory] == first, "refresh must preserve URL identity");
    CHECK([[[source outlineView:nil child:count ofItem:directory] lastPathComponent] isEqualToString:@"zzzz-added"], "refreshed child must be visible");
    CHECK(source->reads == 3, "refresh must enumerate only once");
    CHECK([source outlineView:nil child:-1 ofItem:directory] == nil, "negative index");
    CHECK([source outlineView:nil child:count + 1 ofItem:directory] == nil, "past-end index");
    [[NSFileManager defaultManager] removeItemAtPath:added error:NULL];
    [source release];
    [pool drain];
    puts("PASS: 1024-file listing reuse, interleaving, refresh, identity and bounds");
    return 0;
}
