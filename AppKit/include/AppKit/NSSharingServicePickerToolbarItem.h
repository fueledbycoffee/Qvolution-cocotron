#import <AppKit/NSToolbarItem.h>
// The picker service is unavailable; the toolbar item stays disabled.
@interface NSSharingServicePickerToolbarItem : NSToolbarItem {
    id _delegate;
    id _activityItemsConfiguration;
}
@property(assign) id delegate;
@property(retain) id activityItemsConfiguration;
@end
