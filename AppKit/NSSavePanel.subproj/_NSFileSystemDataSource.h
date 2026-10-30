#import <Foundation/Foundation.h>

@interface _NSFileSystemDataSource : NSObject {
    NSMutableSet *_cachedPaths;
    NSMutableDictionary *_directoryContents;
    NSFileManager *_fileManager;
    NSArray *_rootItems;
}

@end
