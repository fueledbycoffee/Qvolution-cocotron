/* Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 of the Software, and to permit persons to whom the Software is furnished to do
 so, subject to the following conditions:
 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE. */
#import "NSTextInspectorBar.h"
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSFontManager.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSPopUpButton.h>
#import <AppKit/NSTextView.h>
#import <AppKit/NSWindow.h>

@implementation _NSTextInspectorBar
- (NSButton *)button:(NSString *)title identifier:(NSString *)identifier action:(SEL)action {
    NSButton *button=[[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];
    [button setTitle:title];
    [button setIdentifier:identifier];
    [button setToolTip:identifier];
    [button setButtonType:NSPushOnPushOffButton];
    [button setTarget:self]; [button setAction:action];
    [self addSubview:button];
    return button;
}
- (id)initWithTextView:(NSTextView *)view {
    if ((self=[super initWithFrame:NSMakeRect(0,0,450,30)]) == nil) return nil;
    _textView=view;
    [self setIdentifier:@"NSTextViewInspectorBar"];
    _family=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_family setIdentifier:@"Font family"];
    [_family setToolTip:@"Font family"];
    [_family addItemsWithTitles:[[[NSFontManager sharedFontManager] availableFontFamilies]
            sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]];
    [_family setTarget:self]; [_family setAction:@selector(changeFamily:)];
    [self addSubview:_family]; [_family release];
    _size=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_size setIdentifier:@"Font size"]; [_size setToolTip:@"Font size"];
    [_size addItemsWithTitles:[NSArray arrayWithObjects:@"8",@"9",@"10",@"11",@"12",@"14",@"16",@"18",@"24",@"36",@"48",@"72",nil]];
    [_size setTarget:self]; [_size setAction:@selector(changeSize:)];
    [self addSubview:_size]; [_size release];
    _bold=[self button:@"B" identifier:@"Bold" action:@selector(changeBold:)];
    _italic=[self button:@"I" identifier:@"Italic" action:@selector(changeItalic:)];
    _underline=[self button:@"U" identifier:@"Underline" action:@selector(changeUnderline:)];
    _left=[self button:@"L" identifier:@"Align left" action:@selector(changeAlignment:)];
    _center=[self button:@"C" identifier:@"Align center" action:@selector(changeAlignment:)];
    _right=[self button:@"R" identifier:@"Align right" action:@selector(changeAlignment:)];
    [_left setTag:NSLeftTextAlignment]; [_center setTag:NSCenterTextAlignment]; [_right setTag:NSRightTextAlignment];
    [self sync];
    [self resizeSubviewsWithOldSize:NSZeroSize];
    return self;
}
- (void)dealloc { [_familyValue release]; [super dealloc]; }
- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return YES; }
- (NSTextView *)textView { return _textView; }
- (void)setTextView:(NSTextView *)view { _textView=view; [self sync]; }
- (CGFloat)preferredHeightForWidth:(CGFloat)width { return width < 450 ? 60 : 30; }
- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    CGFloat width=NSWidth([self bounds]);
    BOOL wrapped=width < 450;
    CGFloat familyWidth=wrapped ? MAX(0,width-68) : MIN(160,MAX(80,width-290));
    [_family setFrame:NSMakeRect(4,3,familyWidth,24)];
    [_size setFrame:NSMakeRect(familyWidth+8,3,56,24)];
    CGFloat x=wrapped ? 4 : familyWidth+68, y=wrapped ? 33 : 3;
    NSArray *buttons=[NSArray arrayWithObjects:_bold,_italic,_underline,_left,_center,_right,nil];
    for (NSButton *button in buttons) {
        [button setFrame:NSMakeRect(x,y,28,24)]; x+=32;
    }
}
- (void)drawRect:(NSRect)rect {
    [[NSColor controlColor] setFill]; NSRectFill(rect);
    [[NSColor controlShadowColor] setFill];
    NSRectFill(NSMakeRect(0,NSHeight([self bounds])-1,NSWidth([self bounds]),1));
}
- (void)sync {
    BOOL enabled=_textView && [_textView isRichText] && [_textView isEditable];
    for (id control in [self subviews]) [control setEnabled:enabled];
    if (!_textView) return;
    NSDictionary *attributes=[_textView typingAttributes];
    NSFont *font=[attributes objectForKey:NSFontAttributeName];
    if (!font) font=[_textView font];
    NSString *family=[font familyName];
    if (family) {
        if (![[_family itemTitles] containsObject:family]) [_family addItemWithTitle:family];
        [_family selectItemWithTitle:family];
    }
    NSString *size=[NSString stringWithFormat:@"%g",(double)[font pointSize]];
    if (![[_size itemTitles] containsObject:size]) [_size addItemWithTitle:size];
    [_size selectItemWithTitle:size];
    NSFontTraitMask traits=[[NSFontManager sharedFontManager] traitsOfFont:font];
    [_bold setState:(traits & NSBoldFontMask) ? NSControlStateValueOn : NSControlStateValueOff];
    [_italic setState:(traits & NSItalicFontMask) ? NSControlStateValueOn : NSControlStateValueOff];
    [_underline setState:[[attributes objectForKey:NSUnderlineStyleAttributeName] integerValue] ? NSControlStateValueOn : NSControlStateValueOff];
    NSParagraphStyle *style=[attributes objectForKey:NSParagraphStyleAttributeName];
    if (!style) style=[_textView defaultParagraphStyle];
    NSTextAlignment alignment=style ? [style alignment] : NSNaturalTextAlignment;
    [_left setState:(alignment==NSLeftTextAlignment || alignment==NSNaturalTextAlignment) ? NSControlStateValueOn : NSControlStateValueOff];
    [_center setState:alignment==NSCenterTextAlignment ? NSControlStateValueOn : NSControlStateValueOff];
    [_right setState:alignment==NSRightTextAlignment ? NSControlStateValueOn : NSControlStateValueOff];
}
- (NSFont *)convertFont:(NSFont *)font {
    NSFontManager *manager=[NSFontManager sharedFontManager];
    if (_fontAction==NSTextInspectorFontFamily) return [manager convertFont:font toFamily:_familyValue];
    if (_fontAction==NSTextInspectorFontSize) return [manager convertFont:font toSize:_sizeValue];
    return _removeTrait ? [manager convertFont:font toNotHaveTrait:_trait]
                        : [manager convertFont:font toHaveTrait:_trait];
}
- (void)applyFont {
    if (![_textView isEditable] || ![_textView isRichText]) return;
    NSRange selection=[_textView selectedRange];
    [[_textView window] makeFirstResponder:_textView];
    [_textView changeFont:self];
    [_textView setSelectedRange:selection];
    [self sync];
}
- (void)changeFamily:(id)sender {
    NSString *family=[[_family titleOfSelectedItem] copy];
    [_familyValue release]; _familyValue=family;
    _fontAction=NSTextInspectorFontFamily; [self applyFont];
}
- (void)changeSize:(id)sender {
    _sizeValue=[[_size titleOfSelectedItem] doubleValue];
    _fontAction=NSTextInspectorFontSize; [self applyFont];
}
- (void)changeBold:(NSButton *)sender {
    _fontAction=NSTextInspectorFontTrait; _trait=NSBoldFontMask; _removeTrait=[sender state]==NSControlStateValueOff; [self applyFont];
}
- (void)changeItalic:(NSButton *)sender {
    _fontAction=NSTextInspectorFontTrait; _trait=NSItalicFontMask; _removeTrait=[sender state]==NSControlStateValueOff; [self applyFont];
}
- (void)changeUnderline:(id)sender {
    if (![_textView isEditable] || ![_textView isRichText]) return;
    [[_textView window] makeFirstResponder:_textView];
    [_textView underline:sender]; [self sync];
}
- (void)changeAlignment:(NSButton *)sender {
    NSRange range=[_textView rangeForUserParagraphAttributeChange];
    if (![_textView isRichText] || range.location==NSNotFound) return;
    [[_textView window] makeFirstResponder:_textView];
    if ([sender tag]==NSLeftTextAlignment) [_textView alignLeft:sender];
    else if ([sender tag]==NSCenterTextAlignment) [_textView alignCenter:sender];
    else [_textView alignRight:sender];
    [self sync];
}
@end
