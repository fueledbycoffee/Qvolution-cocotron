#import <AppKit/NSViewController.h>
@interface NSSplitViewItemAccessoryViewController : NSViewController {
    BOOL _accessoryHidden;
    BOOL _automaticallyAppliesContentInsets;
}
@property(getter=isHidden) BOOL hidden;
// Stored only; the split view has no automatic accessory inset calculation.
@property BOOL automaticallyAppliesContentInsets;
- (void) viewWillAppear;
- (void) viewDidAppear;
- (void) viewWillDisappear;
- (void) viewDidDisappear;
@end
