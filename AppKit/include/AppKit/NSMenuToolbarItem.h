#import <AppKit/NSToolbarItem.h>
@class NSMenu;
@interface NSMenuToolbarItem : NSToolbarItem {
    NSMenu *_menu;
    BOOL _showsIndicator;
}
@property(retain) NSMenu *menu;
@property BOOL showsIndicator;
@end
