#import <Foundation/Foundation.h>
// The optional service is unavailable. Check availability before constructing.
@interface NSWritingToolsCoordinator : NSObject
+ (BOOL) isWritingToolsAvailable;
- (instancetype) initWithDelegate: (id) delegate;
@end
