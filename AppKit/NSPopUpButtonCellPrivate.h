#import <AppKit/NSPopUpButtonCell.h>

@interface NSPopUpButtonCell (PopupViewportPreference)
// Zero leaves the existing native/screen size policy unchanged.
- (NSUInteger)_maximumVisibleRows;
- (void)_setMaximumVisibleRows:(NSUInteger)rows;
@end
