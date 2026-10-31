#import <AppKit/NSScrollView.h>

@class NSTextView, NSPopUpButton, NSButton;

BOOL NSTextInspectorKeepsRulerContext(NSTextView *view, NSResponder *proposed);

typedef NS_ENUM(NSInteger, NSTextInspectorFontAction) {
    NSTextInspectorFontFamily, NSTextInspectorFontSize, NSTextInspectorFontTrait
};

@interface _NSTextInspectorBar : NSView {
    NSTextView *_textView;
    NSPopUpButton *_family, *_size;
    NSButton *_bold, *_italic, *_underline, *_left, *_center, *_right;
    NSTextInspectorFontAction _fontAction;
    NSString *_familyValue;
    CGFloat _sizeValue;
    BOOL _removeTrait;
    NSUInteger _trait;
}
- (id)initWithTextView:(NSTextView *)view;
- (NSTextView *)textView;
- (void)setTextView:(NSTextView *)view;
- (void)sync;
- (CGFloat)preferredHeightForWidth:(CGFloat)width;
@end

@interface NSScrollView (NSTextInspectorBar)
- (NSView *)_textInspectorBar;
- (void)_setTextInspectorBar:(NSView *)view;
@end
