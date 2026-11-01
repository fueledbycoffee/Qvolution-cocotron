#import <AppKit/NSView.h>
@class NSColor;
// GUESS: enum raw values; public case names from Apple's local AppKit index.
typedef NS_ENUM(NSInteger, NSTextInsertionIndicatorDisplayMode) {
    NSTextInsertionIndicatorDisplayModeAutomatic = 0,
    NSTextInsertionIndicatorDisplayModeHidden = 1,
    NSTextInsertionIndicatorDisplayModeVisible = 2,
};
@interface NSTextInsertionIndicator : NSView {
    NSColor *_color;
    NSTextInsertionIndicatorDisplayMode _displayMode;
    NSUInteger _automaticModeOptions;
    void (^_effectsViewInserter)(NSView *);
}
@property(retain) NSColor *color;
@property NSTextInsertionIndicatorDisplayMode displayMode;
@property NSUInteger automaticModeOptions;
@property(copy) void (^effectsViewInserter)(NSView *);
@end
