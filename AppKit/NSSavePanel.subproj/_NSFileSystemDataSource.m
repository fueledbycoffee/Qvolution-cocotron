#import "_NSFileSystemDataSource.h"
#import <AppKit/NSOutlineView.h>
#import <AppKit/NSWorkspace.h>

@implementation _NSFileSystemDataSource

- (id) init {
    self = [super init];
    _cachedPaths = [[NSMutableSet alloc] init];
    _directoryContents = [[NSMutableDictionary alloc] init];
    _fileManager = [[NSFileManager defaultManager] retain];

    NSMutableArray *roots = [NSMutableArray array];
    NSString *docs = [NSHomeDirectory() stringByAppendingPathComponent: @"Documents"];
    BOOL isDir = NO;
    if ([_fileManager fileExistsAtPath: docs isDirectory: &isDir] && isDir) {
        [roots addObject: [NSURL fileURLWithPath: docs]];
    }
    NSString *desktop = [NSHomeDirectory() stringByAppendingPathComponent: @"Desktop"];
    if ([_fileManager fileExistsAtPath: desktop isDirectory: &isDir] && isDir) {
        [roots addObject: [NSURL fileURLWithPath: desktop]];
    }
    NSString *downloads = [NSHomeDirectory() stringByAppendingPathComponent: @"Downloads"];
    if ([_fileManager fileExistsAtPath: downloads isDirectory: &isDir] && isDir) {
        [roots addObject: [NSURL fileURLWithPath: downloads]];
    }
    [roots addObject: [NSURL fileURLWithPath: NSHomeDirectory()]];
    [roots addObject: [NSURL fileURLWithPath: @"/"]];
    _rootItems = [roots copy];

    return self;
}

- (void) dealloc {
    [_cachedPaths release];
    [_directoryContents release];
    [_fileManager release];
    [_rootItems release];
    [super dealloc];
}

- (NSArray *) _contentsOfDirectory: (NSURL *) url {
    if (url == nil) {
        return _rootItems;
    }
    NSArray *items = [_fileManager contentsOfDirectoryAtURL: url
                                 includingPropertiesForKeys: nil
                                                    options: 0
                                                      error: nil];
    if (items == nil)
        return [NSArray array];
    return [items sortedArrayUsingComparator: ^(id u1, id u2) {
        return [[(NSURL *)u1 lastPathComponent] caseInsensitiveCompare: [(NSURL *)u2 lastPathComponent]];
    }];
}

- (NSInteger) outlineView: (NSOutlineView *) outlineView
        numberOfChildrenOfItem: (NSURL *) url
{
    NSArray *items = [self _contentsOfDirectory: url];
    if (url != nil)
        [_directoryContents setObject: items forKey: url];
    return [items count];
}

- (BOOL) outlineView: (NSOutlineView *) outlineView
        isItemExpandable: (NSURL *) url
{

    if (url == nil) {
        return YES;
    }

    BOOL isDirectory = NO;
    [_fileManager fileExistsAtPath: [url path] isDirectory: &isDirectory];
    if (isDirectory && [[NSWorkspace sharedWorkspace] isFilePackageAtPath: [url path]]) {
        return NO;
    }
    return isDirectory;
}

- (NSURL *) outlineView: (NSOutlineView *) outlineView
                  child: (NSInteger) index
                 ofItem: (NSURL *) url
{
    NSArray *items = url == nil ? _rootItems : [_directoryContents objectForKey: url];
    if (items == nil) {
        items = [self _contentsOfDirectory: url];
        [_directoryContents setObject: items forKey: url];
    }
    if (index < 0 || (NSUInteger)index >= [items count])
        return nil;
    NSURL *preRes = [items objectAtIndex: index];
    NSURL *res = [_cachedPaths member: preRes];
    if (res == nil) {
        [_cachedPaths addObject: preRes];
        res = preRes;
    }

    return res;
}

- (NSString *) outlineView: (NSOutlineView *) outlineView
        objectValueForTableColumn: (NSTableColumn *) tableColumn
                           byItem: (NSURL *) url
{
    if ([[url path] isEqualToString: @"/"])
        return @"Macintosh HD (/)";
    if ([[url path] isEqualToString: NSHomeDirectory()])
        return [NSString stringWithFormat: @"Home (~/%@)", [url lastPathComponent]];
    return [url lastPathComponent];
}

@end
