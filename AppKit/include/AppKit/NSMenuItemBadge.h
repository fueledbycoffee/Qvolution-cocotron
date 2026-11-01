#import <Foundation/Foundation.h>
// GUESS: raw enum values are not provided by the cached documentation index.
typedef NS_ENUM(NSInteger, NSMenuItemBadgeType) {
    NSMenuItemBadgeTypeNone = 0,
    NSMenuItemBadgeTypeUpdates = 1,
    NSMenuItemBadgeTypeNewItems = 2,
    NSMenuItemBadgeTypeAlerts = 3,
};
@interface NSMenuItemBadge : NSObject <NSCopying> {
    NSInteger _itemCount;
    NSMenuItemBadgeType _type;
    NSString *_stringValue;
}
- (instancetype) initWithCount: (NSInteger) count;
- (instancetype) initWithCount: (NSInteger) count type: (NSMenuItemBadgeType) type;
- (instancetype) initWithString: (NSString *) string;
+ (instancetype) updatesWithCount: (NSInteger) count;
+ (instancetype) newItemsWithCount: (NSInteger) count NS_RETURNS_NOT_RETAINED;
+ (instancetype) alertsWithCount: (NSInteger) count;
@property(readonly) NSInteger itemCount;
@property(readonly) NSMenuItemBadgeType type;
@property(readonly, copy) NSString *stringValue;
@end
