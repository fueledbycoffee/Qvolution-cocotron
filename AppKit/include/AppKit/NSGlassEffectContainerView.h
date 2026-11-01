#import <AppKit/NSView.h>
// Plain content container: no liquid-glass compositing is available.
@interface NSGlassEffectContainerView : NSView {
    NSView *_contentView;
    CGFloat _spacing;
}
@property(retain) NSView *contentView;
@property CGFloat spacing;
@end
