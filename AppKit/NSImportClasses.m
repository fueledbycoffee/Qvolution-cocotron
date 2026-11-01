/* Public class/selector names and types: rung 3,
 * catalyst/docs-cache/index__appkit.json. GUESS: rendering/defaults where the
 * index supplies no behavior. These objects store presentation state only.
 */
#import <AppKit/NSMenuToolbarItem.h>
#import <AppKit/NSMenuItemBadge.h>
#import <AppKit/NSGlassEffectContainerView.h>
#import <AppKit/NSSplitViewItemAccessoryViewController.h>
#import <AppKit/NSWritingToolsCoordinator.h>
#import <AppKit/NSMenu.h>

@implementation NSMenuToolbarItem
@synthesize menu = _menu, showsIndicator = _showsIndicator;
- (instancetype) initWithItemIdentifier: (NSToolbarItemIdentifier) identifier {
    self = [super initWithItemIdentifier: identifier];
    if (self) {
        _showsIndicator = YES;
        _menu = [[NSMenu alloc] initWithTitle: @""];
    }
    return self;
}
- (void) dealloc {
    [_menu release];
    [super dealloc];
}
- (id) copyWithZone: (NSZone *) zone {
    NSMenuToolbarItem *copy = [super copyWithZone: zone];
    // NSToolbarItem's copy copies its own fields, not these subclass fields.
    copy->_menu = [_menu retain];
    copy->_showsIndicator = _showsIndicator;
    return copy;
}
@end

@implementation NSMenuItemBadge
@synthesize itemCount = _itemCount, type = _type, stringValue = _stringValue;
- (instancetype) initWithCount: (NSInteger) count {
    return [self initWithCount: count type: NSMenuItemBadgeTypeNone];
}
- (instancetype) initWithCount: (NSInteger) count type: (NSMenuItemBadgeType) type {
    self = [super init];
    if (self) {
        _itemCount = count;
        _type = type;
    }
    return self;
}
- (instancetype) initWithString: (NSString *) string {
    self = [super init];
    if (self) {
        if (!string) { [self release]; return nil; }
        _stringValue = [string copy];
    }
    return self;
}
+ (instancetype) updatesWithCount: (NSInteger) count {
    return [[[self alloc] initWithCount: count type: NSMenuItemBadgeTypeUpdates] autorelease];
}
+ (instancetype) newItemsWithCount: (NSInteger) count {
    return [[[self alloc] initWithCount: count type: NSMenuItemBadgeTypeNewItems] autorelease];
}
+ (instancetype) alertsWithCount: (NSInteger) count {
    return [[[self alloc] initWithCount: count type: NSMenuItemBadgeTypeAlerts] autorelease];
}
- (void) dealloc { [_stringValue release]; [super dealloc]; }
- (id) copyWithZone: (NSZone *) zone { return [self retain]; }
@end

@implementation NSGlassEffectContainerView
@synthesize spacing = _spacing;
- (NSView *) contentView { return _contentView; }
- (void) setContentView: (NSView *) view {
    if (view == _contentView) return;
    [view retain];
    [_contentView removeFromSuperview];
    [_contentView release];
    _contentView = view;
    if (view) {
        [view setFrame: [self bounds]];
        [view setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
        [self addSubview: view];
    }
}
- (void) dealloc { [_contentView release]; [super dealloc]; }
@end

@implementation NSSplitViewItemAccessoryViewController
@synthesize automaticallyAppliesContentInsets = _automaticallyAppliesContentInsets;
- (BOOL) isHidden { return _accessoryHidden; }
- (void) setHidden: (BOOL) hidden {
    _accessoryHidden = hidden;
    if ([self isViewLoaded]) [[self view] setHidden: hidden];
}
- (void) viewDidLoad {
    [super viewDidLoad];
    [[self view] setHidden: _accessoryHidden];
}
- (void) viewWillAppear { }
- (void) viewDidAppear { }
- (void) viewWillDisappear { }
- (void) viewDidDisappear { }
@end

@implementation NSWritingToolsCoordinator
+ (BOOL) isWritingToolsAvailable { return NO; }
- (instancetype) init { [self release]; return nil; }
- (instancetype) initWithDelegate: (id) delegate { return [self init]; }
@end

#import <AppKit/NSSharingServicePickerToolbarItem.h>
@implementation NSSharingServicePickerToolbarItem
@synthesize delegate = _delegate, activityItemsConfiguration = _activityItemsConfiguration;
- (BOOL) isEnabled { return NO; }
- (void) setEnabled: (BOOL) enabled { [super setEnabled: NO]; }
- (void) validate { [super setEnabled: NO]; }
- (void) dealloc { [_activityItemsConfiguration release]; [super dealloc]; }
- (id) copyWithZone: (NSZone *) zone {
    NSSharingServicePickerToolbarItem *copy = [super copyWithZone: zone];
    copy->_activityItemsConfiguration = [_activityItemsConfiguration retain];
    return copy;
}
@end
