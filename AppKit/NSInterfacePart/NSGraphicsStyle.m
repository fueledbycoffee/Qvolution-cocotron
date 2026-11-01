/* Copyright (c) 2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import "NSInterfaceGraphics.h"
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSGraphicsContextFunctions.h>
#import <AppKit/NSGraphicsStyle.h>
#import <AppKit/NSGradient.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSInterfacePartAttributedString.h>
#import <AppKit/NSInterfacePartDisabledAttributedString.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSAppearance.h>

@implementation NSGraphicsStyle

static NSDictionary *sNormalMenuTextAttributes = nil;
static NSDictionary *sSelectedMenuTextAttributes = nil;
static NSDictionary *sDimmedMenuTextAttributes = nil;
static NSDictionary *sDimmedMenuTextShadowAttributes = nil;
static NSDictionary *sScrollerButtonAttributes = nil;

+ (void) initialize {
    if (sNormalMenuTextAttributes == nil) {
        NSFont *menuFont = [NSFont menuFontOfSize: 0];
        sNormalMenuTextAttributes = [[NSDictionary
                dictionaryWithObjectsAndKeys: menuFont, NSFontAttributeName,
                                              [NSColor menuItemTextColor],
                                              NSForegroundColorAttributeName,
                                              nil] retain];
        sSelectedMenuTextAttributes = [[NSDictionary
                dictionaryWithObjectsAndKeys:
                        menuFont, NSFontAttributeName,
                        [NSColor selectedMenuItemTextColor],
                        NSForegroundColorAttributeName, nil] retain];

        sDimmedMenuTextAttributes = [[NSDictionary
                dictionaryWithObjectsAndKeys: menuFont, NSFontAttributeName,
                                              [NSColor grayColor],
                                              NSForegroundColorAttributeName,
                                              nil] retain];

        sDimmedMenuTextShadowAttributes = [[NSDictionary
                dictionaryWithObjectsAndKeys: menuFont, NSFontAttributeName,
                                              [NSColor whiteColor],
                                              NSForegroundColorAttributeName,
                                              nil] retain];

        sScrollerButtonAttributes = [[NSDictionary
                dictionaryWithObjectsAndKeys: [NSFont labelFontOfSize: 8],
                                              NSFontAttributeName,
                                              [NSColor grayColor],
                                              NSForegroundColorAttributeName,
                                              nil] retain];
    }
}

- initWithView: (NSView *) view {
    _view = [view retain];
    return self;
}

- (void) dealloc {
    [_view release];
    [super dealloc];
}

@end

@implementation NSGraphicsStyle (NSMenu)

#define TITLE_TOP_MARGIN 2
#define TITLE_BOTTOM_MARGIN 2
#define BRANCH_ARROW_LEFT_MARGIN 2
#define BRANCH_ARROW_RIGHT_MARGIN 2

- (NSInterfacePartAttributedString *) branchArrow {
    static NSInterfacePartAttributedString *sBranchArrow = nil;

    if (sBranchArrow == nil)
        sBranchArrow = [[NSInterfacePartAttributedString alloc]
                initWithMarlettCharacter: 0x34];
    return sBranchArrow;
}

- (NSSize) menuItemSeparatorSize {
    return NSMakeSize(0, 9);
}

- (Margins) menuItemBranchArrowMargins {
    Margins result = [self menuItemTextMargins];

    result.left = BRANCH_ARROW_LEFT_MARGIN;
    result.right = BRANCH_ARROW_RIGHT_MARGIN;

    return result;
}

- (NSSize) menuItemBranchArrowSize {
    return NSMakeSize(5, 9);
}

- (NSSize) menuItemCheckMarkSize {
    CGFloat size = ceil([[NSFont menuFontOfSize: 0] pointSize]);
    return NSMakeSize(size, size);
}

- (Margins) menuItemGutterMargins {
    Margins result;

    result.left = 0;
    result.right = 0;
    result.top = TITLE_TOP_MARGIN;
    result.bottom = TITLE_BOTTOM_MARGIN;

    return result;
}

- (NSSize) menuItemGutterSize {
    NSSize result = NSZeroSize;
    Margins margins = [self menuItemGutterMargins];

    result = [self menuItemCheckMarkSize];

    result.height += (margins.top + margins.bottom);
    result.width += (margins.left + margins.right);

    return result;
}

- (Margins) menuItemTextMargins {
    Margins result;

    result.left = 0;
    result.right = 0;
    result.top = TITLE_TOP_MARGIN;
    result.bottom = TITLE_BOTTOM_MARGIN;

    return result;
}

- (NSSize) menuItemTextSize: (NSString *) title {
    NSSize result = NSZeroSize;
    Margins margins = [self menuItemTextMargins];

    result = [title sizeWithAttributes: sNormalMenuTextAttributes];

    result.height += (margins.top + margins.bottom);
    result.width += (margins.left + margins.right);

    return result;
}

- (NSSize) menuItemAttributedTextSize: (NSAttributedString *) title {
    NSSize result = NSZeroSize;
    Margins margins = [self menuItemTextMargins];

    result = [title size];

    result.height += (margins.top + margins.bottom);
    result.width += (margins.left + margins.right);

    return result;
}

- (CGFloat) menuBarHeight {
    NSDictionary *attributes = [NSDictionary
            dictionaryWithObjectsAndKeys: [NSFont menuFontOfSize: 0],
                                          NSFontAttributeName, nil];
    CGFloat result = [@"Menu" sizeWithAttributes: attributes].height;

    result += 2; // border top/bottom margin
    result += 4; // border
    result += 1; // sunken title baseline

    return result;
}

- (CGFloat) menuItemGutterGap {
    return 0;
}

- (void) drawMenuSeparatorInRect: (NSRect) rect {
    NSPoint point = NSMakePoint(rect.origin.x + 1, rect.origin.y + 3);
    CGFloat width = rect.size.width - 2;

    [[NSColor grayColor] setFill];
    NSRectFill(NSMakeRect(point.x, point.y, width, 1));
    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(point.x, point.y + 1, width, 1));
}

- (void) drawMenuGutterInRect: (NSRect) rect {
    // Nothing to do.
}

- (void) drawMenuItemText: (NSString *) string
                   inRect: (NSRect) rect
                  enabled: (BOOL) enabled
                 selected: (BOOL) selected
{
    // Ensure we have enough width - fractional widths give float comparison
    // trouble
    rect.size.width = ceilf(rect.size.width);

    Margins margins = [self menuItemTextMargins];

    rect.origin.x += margins.left;
    rect.origin.y += margins.top;
    rect.size.width -= (margins.left + margins.right);
    rect.size.height -= (margins.top + margins.bottom);

    if (enabled) {
        if (selected) {
            [string drawInRect: rect
                    withAttributes: sSelectedMenuTextAttributes];
        } else {
            [string drawInRect: rect withAttributes: sNormalMenuTextAttributes];
        }
    } else {
        if (!selected) {
            NSRect offsetRect = rect;
            offsetRect.origin.x += 1;
            offsetRect.origin.y += 1;
            [string drawInRect: offsetRect
                    withAttributes: sDimmedMenuTextShadowAttributes];
        }
        [string drawInRect: rect withAttributes: sDimmedMenuTextAttributes];
    }
}

- (void) drawAttributedMenuItemText: (NSAttributedString *) string
                             inRect: (NSRect) rect
                            enabled: (BOOL) enabled
                           selected: (BOOL) selected
{
    // Ensure we have enough width - fractional widths give float comparison
    // trouble
    rect.size.width = ceilf(rect.size.width);

    NSMutableAttributedString *mutableString = [string mutableCopy];

    Margins margins = [self menuItemTextMargins];

    rect.origin.x += margins.left;
    rect.origin.y += margins.top;
    rect.size.width -= (margins.left + margins.right);
    rect.size.height -= (margins.top + margins.bottom);

    NSRange range = NSMakeRange(0, [string length]);

    if (enabled) {
        if (!selected) {
            [mutableString
                    addAttributes:
                            [NSDictionary
                                    dictionaryWithObject:
                                            [NSColor menuItemTextColor]
                                                  forKey: NSForegroundColorAttributeName]
                            range: range];
        }
        [mutableString drawInRect: rect];
    } else {
        if (!selected) {
            [mutableString
                    addAttributes:
                            [NSDictionary
                                    dictionaryWithObject: [NSColor grayColor]
                                                  forKey: NSForegroundColorAttributeName]
                            range: range];
            NSRect offsetRect = rect;
            offsetRect.origin.x += 1;
            offsetRect.origin.y += 1;
            [mutableString drawInRect: offsetRect];
        }
        [mutableString drawInRect: rect];
    }
}

// Coordinates are relative to the font-sized gutter. The menu views are
// flipped; mirror the vertical coordinates for an unflipped client.
- (void) drawMenuStateMarkInRect: (NSRect) rect
                           mixed: (BOOL) mixed
                         enabled: (BOOL) enabled
                        selected: (BOOL) selected
{
    CGFloat size = MIN(MIN(rect.size.width, rect.size.height),
                       ceil([[NSFont menuFontOfSize: 0] pointSize]));
    CGFloat x = NSMidX(rect) - size / 2;
    CGFloat y = NSMidY(rect) - size / 2;
    BOOL flipped = [_view isFlipped];
    NSBezierPath *path = [NSBezierPath bezierPath];
    NSColor *color = enabled ? (selected ? [NSColor selectedMenuItemTextColor]
                                         : [NSColor menuItemTextColor])
                             : [NSColor grayColor];
    [color set];
    [path setLineWidth: MAX(1.0, size * 0.13)];
    [path setLineCapStyle: NSRoundLineCapStyle];
    [path setLineJoinStyle: NSRoundLineJoinStyle];
    if (mixed) {
        [path moveToPoint: NSMakePoint(x + size * 0.23, y + size * 0.5)];
        [path lineToPoint: NSMakePoint(x + size * 0.77, y + size * 0.5)];
    } else {
        [path moveToPoint: NSMakePoint(x + size * 0.16, y + size * (flipped ? 0.51 : 0.49))];
        [path lineToPoint: NSMakePoint(x + size * 0.39, y + size * (flipped ? 0.73 : 0.27))];
        [path lineToPoint: NSMakePoint(x + size * 0.84, y + size * (flipped ? 0.27 : 0.73))];
    }
    [path stroke];
}

- (void) drawMenuCheckmarkInRect: (NSRect) rect
                         enabled: (BOOL) enabled
                        selected: (BOOL) selected
{
    [self drawMenuStateMarkInRect: rect mixed: NO enabled: enabled selected: selected];
}

- (void) drawMenuMixedMarkInRect: (NSRect) rect
                        enabled: (BOOL) enabled
                       selected: (BOOL) selected
{
    [self drawMenuStateMarkInRect: rect mixed: YES enabled: enabled selected: selected];
}

- (void) drawMenuBranchArrowInRect: (NSRect) rect
                           enabled: (BOOL) enabled
                          selected: (BOOL) selected
{
    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
    NSColor *color;
    Margins margins = [self menuItemBranchArrowMargins];
    NSRect themeRect = rect;

    if (enabled)
        color = selected ? [NSColor selectedControlTextColor]
                         : [NSColor menuItemTextColor];
    else
        color = [NSColor disabledControlTextColor];

    [color set];

    themeRect.origin.x += margins.left;
    themeRect.origin.y += margins.top;
    themeRect.size.width -= (margins.left + margins.right);
    themeRect.size.height -= (margins.top + margins.bottom);

    CGContextBeginPath(context);
    CGContextMoveToPoint(context, NSMinX(themeRect), NSMaxY(themeRect));
    CGContextAddLineToPoint(context, NSMaxX(themeRect), NSMidY(themeRect));
    CGContextAddLineToPoint(context, NSMinX(themeRect), NSMinY(themeRect));
    CGContextClosePath(context);
    CGContextFillPath(context);
}

- (void) drawMenuSelectionInRect: (NSRect) rect enabled: (BOOL) enabled {
    if (enabled) {
        [[NSColor selectedMenuItemColor] setFill];
        NSRectFill(rect);
    }
}

- (void) drawMenuWindowBackgroundInRect: (NSRect) rect {
    [[NSColor menuBackgroundColor] setFill];
    NSRectFill(rect);
    [[NSColor windowFrameColor] set];
    NSFrameRect(rect);
}

- (void) drawMenuBarItemBorderInRect: (NSRect) rect
                               hover: (BOOL) hovering
                            selected: (BOOL) selected
{
    if (selected || hovering) {
        [[NSColor selectedMenuItemColor] setFill];
        NSRectFill(rect);
    }
}

- (void) drawMenuBarBackgroundInRect: (NSRect) rect {
    [[NSColor mainMenuBarColor] setFill];
    NSRectFill(rect);
}

@end

// Private control roles resolve through the same dynamic palette as public
// semantic colors, including live settings and high-contrast appearances.
typedef enum {
    NSControlTokenBezelBorder,
    NSControlTokenBezelBottomShadow,
    NSControlTokenPressedFace,
    NSControlTokenSegmentSelected,
} NSControlTokenName;

static BOOL NSControlDrawingIsDark(void) {
    NSAppearanceName name = [[NSAppearance currentDrawingAppearance]
            bestMatchFromAppearancesWithNames: @[
                NSAppearanceNameAqua, NSAppearanceNameDarkAqua
            ]];
    return [name isEqualToString: NSAppearanceNameDarkAqua];
}

static NSColor *NSControlToken(NSControlTokenName token) {
    NSString *name;
    switch (token) {
    case NSControlTokenBezelBorder:
        name = @"bezel.border"; break;
    case NSControlTokenBezelBottomShadow:
        name = @"bezel.bottomShadow"; break;
    case NSControlTokenPressedFace:
        name = @"bezel.pressedFace"; break;
    case NSControlTokenSegmentSelected:
        name = @"segment.selected"; break;
    default:
        [NSException raise: NSInvalidArgumentException
                    format: @"unknown control token %d", (int) token];
        return nil;
    }
    return [NSColor colorWithCatalogName: @"System" colorName: name];
}

static NSBezierPath *NSControlRoundedPath(NSRect rect, CGFloat radius) {
    radius = MAX(0, MIN(radius, MIN(rect.size.width, rect.size.height) / 2));
    return [NSBezierPath bezierPathWithRoundedRect: rect
                                           xRadius: radius
                                           yRadius: radius];
}

// The region inside outer but outside inner, filled with even-odd so the
// translucent border and shadow tokens are never composited twice.
static void NSControlFillRing(NSRect outer, CGFloat outerRadius, NSRect inner,
                              CGFloat innerRadius, NSColor *color)
{
    NSBezierPath *ring = NSControlRoundedPath(outer, outerRadius);
    [ring appendBezierPath: NSControlRoundedPath(inner, innerRadius)];
    [ring setWindingRule: NSEvenOddWindingRule];
    [color setFill];
    [ring fill];
}

@implementation NSGraphicsStyle (NSControlFaces)

- (NSRect) _bodyRectForBezel: (NSRect) rect {
    rect.size.height -= 1;
    if ([_view isFlipped] == NO)
        rect.origin.y += 1;
    return rect;
}

- (void) drawControlFaceInRect: (NSRect) rect
                        radius: (CGFloat) radius
                          fill: (NSColor *) fill
{
    NSRect body = [self _bodyRectForBezel: rect];
    NSRect face = NSInsetRect(body, 1, 1);

    NSControlFillRing(rect, radius, body, radius,
                      NSControlToken(NSControlTokenBezelBottomShadow));
    NSControlFillRing(body, radius, face, radius - 1,
                      NSControlToken(NSControlTokenBezelBorder));
    [fill setFill];
    [NSControlRoundedPath(face, radius - 1) fill];
}

- (void) drawDefaultButtonFaceInRect: (NSRect) rect pressed: (BOOL) pressed {
    NSColor *accent = [NSColor controlAccentColor];
    NSRect body = [self _bodyRectForBezel: rect];
    NSBezierPath *path = NSControlRoundedPath(body, NSControlBezelRadius);

    NSControlFillRing(rect, NSControlBezelRadius, body, NSControlBezelRadius,
                      NSControlToken(NSControlTokenBezelBottomShadow));
    if (pressed) {
        [[accent blendedColorWithFraction: 0.12
                                  ofColor: [NSColor blackColor]] setFill];
        [path fill];
    } else {
        NSColor *top = [accent blendedColorWithFraction: 0.08
                                                ofColor: [NSColor whiteColor]];
        BOOL flipped = [_view isFlipped];
        NSGradient *gradient = [[[NSGradient alloc]
                initWithStartingColor: flipped ? top : accent
                          endingColor: flipped ? accent : top] autorelease];
        [gradient drawInBezierPath: path angle: 90];
    }
}

- (void) drawFocusRingAroundRect: (NSRect) rect radius: (CGFloat) radius {
    NSBezierPath *ring = NSControlRoundedPath(NSInsetRect(rect, -1.5, -1.5),
                                              radius + 1.5);
    [[[NSColor controlAccentColor] colorWithAlphaComponent: 0.5] setStroke];
    [ring setLineWidth: 3];
    [ring stroke];
}

- (NSColor *) segmentSelectedColor {
    return NSControlToken(NSControlTokenSegmentSelected);
}

- (void) drawPopUpIndicatorInRect: (NSRect) rect
                        pullsDown: (BOOL) pullsDown
                           active: (BOOL) active
{
    NSColor *glyph = [NSColor labelColor];
    if (active) {
        [[NSColor controlAccentColor] setFill];
        [NSControlRoundedPath(rect, 4) fill];
        glyph = [NSColor alternateSelectedControlTextColor];
    }

    CGFloat midX = NSMidX(rect), midY = NSMidY(rect);
    CGFloat up = [_view isFlipped] ? -1 : 1;
    NSBezierPath *chevrons = [NSBezierPath bezierPath];
    if (pullsDown) {
        [chevrons moveToPoint: NSMakePoint(midX - 2.5, midY + up * 1.5)];
        [chevrons lineToPoint: NSMakePoint(midX, midY - up * 1.5)];
        [chevrons lineToPoint: NSMakePoint(midX + 2.5, midY + up * 1.5)];
    } else {
        [chevrons moveToPoint: NSMakePoint(midX - 2.5, midY + up * 2)];
        [chevrons lineToPoint: NSMakePoint(midX, midY + up * 5)];
        [chevrons lineToPoint: NSMakePoint(midX + 2.5, midY + up * 2)];
        [chevrons moveToPoint: NSMakePoint(midX - 2.5, midY - up * 2)];
        [chevrons lineToPoint: NSMakePoint(midX, midY - up * 5)];
        [chevrons lineToPoint: NSMakePoint(midX + 2.5, midY - up * 2)];
    }
    [chevrons setLineWidth: 1.5];
    [chevrons setLineCapStyle: NSRoundLineCapStyle];
    [chevrons setLineJoinStyle: NSRoundLineJoinStyle];
    [glyph setStroke];
    [chevrons stroke];
}

@end

@implementation NSGraphicsStyle (NSButton)

- (void) drawUnborderedButtonInRect: (NSRect) rect defaulted: (BOOL) defaulted {
}

- (void) drawPushButtonNormalInRect: (NSRect) rect defaulted: (BOOL) defaulted {
    if (defaulted)
        [self drawDefaultButtonFaceInRect: rect pressed: NO];
    else
        [self drawControlFaceInRect: rect
                             radius: NSControlBezelRadius
                               fill: [NSColor controlColor]];
}

- (void) drawPushButtonPressedInRect: (NSRect) rect {
    [self drawControlFaceInRect: rect
                         radius: NSControlBezelRadius
                           fill: NSControlToken(NSControlTokenPressedFace)];
}

- (void) drawPushButtonHighlightedInRect: (NSRect) rect {
    NSInterfaceDrawHighlightedButton(rect, rect);
}

- (NSSize) sizeOfButtonImage: (NSImage *) image
                     enabled: (BOOL) enabled
                       mixed: (BOOL) mixed
{
    return [image size];
}

- (void) drawButtonImage: (NSImage *) image
                  inRect: (NSRect) rect
                 enabled: (BOOL) enabled
                   mixed: (BOOL) mixed
{
    CGFloat fraction = enabled ? 1.0 : 0.5;

    [image drawInRect: rect
             fromRect: NSZeroRect
            operation: NSCompositeSourceOver
             fraction: fraction];
}

@end

@implementation NSGraphicsStyle (NSBrowser)

- (void) drawBrowserTitleBackgroundInRect: (NSRect) rect {
    NSInterfaceDrawBrowserHeader(rect, rect);
}

- (void) drawBrowserHorizontalScrollerWellInRect: (NSRect) rect
                                        clipRect: (NSRect) clipRect
{
    NSDrawGrayBezel(rect, clipRect);
}

@end

@implementation NSGraphicsStyle (NSColorWell)

- (NSRect) drawColorWellBorderInRect: (NSRect) rect
                             enabled: (BOOL) enabled
                            bordered: (BOOL) bordered
                              active: (BOOL) active
{
    if (bordered) {
        if (active)
            NSInterfaceDrawHighlightedButton(rect, rect);
        else
            NSInterfaceDrawButton(rect, rect);

        rect = NSInsetRect(rect, 6, 6);

        if (enabled)
            NSDrawGrayBezel(rect, rect);
    } else {
        if (enabled) {
            NSDrawGrayBezel(rect, rect);
        }
    }

    return NSInsetRect(rect, 2, 2);
}

@end

@implementation NSGraphicsStyle (NSPopUpButton)

- (void) drawPopUpButtonWindowBackgroundInRect: (NSRect) rect {
    [[NSColor menuBackgroundColor] setFill];
    NSRectFill(rect);
    [[NSColor blackColor] setStroke];
    NSFrameRect(rect);
}

@end

@implementation NSGraphicsStyle (NSOutlineView)

- (void) drawOutlineViewGridInRect: (NSRect) rect {
    NSInterfaceDrawOutlineGrid(rect, NSCurrentGraphicsPort());
}

@end

@implementation NSGraphicsStyle (NSProgressIndicator)

- (NSRect) drawProgressIndicatorBackground: (NSRect) rect
                                  clipRect: (NSRect) clipRect
                                   bezeled: (BOOL) bezeled
{
    if (bezeled) {
        NSInterfaceDrawProgressIndicatorBezel(rect, clipRect);
        return NSInsetRect(rect, 2, 2);
    } else {
        [[[_view window] backgroundColor] setFill];
        NSRectFill(rect);
        return rect;
    }
}

- (void) drawProgressIndicatorChunk: (NSRect) rect {
    [[NSColor selectedControlColor] setFill];
    NSRectFill(rect);
}

// rough estimates
#define BLOCK_WIDTH 8.0
#define BLOCK_SPACING 2.0

- (void) drawProgressIndicatorIndeterminate: (NSRect) rect
                                   clipRect: (NSRect) clipRect
                                    bezeled: (BOOL) bezeled
                                  animation: (double) animation
{
    if (bezeled)
        rect = [self drawProgressIndicatorBackground: rect
                                            clipRect: clipRect
                                             bezeled: bezeled];

    NSRect progressRect = rect;
    NSRect blockRect = progressRect;
    int numBlocks;

    numBlocks = (animation * progressRect.size.width) /
                (BLOCK_WIDTH + BLOCK_SPACING);

    if (numBlocks > 0)
        numBlocks++;

    while (numBlocks-- >= 0) {
        blockRect.size.width = BLOCK_WIDTH;

        if (NSMaxX(blockRect) > NSMaxX(progressRect))
            blockRect.size.width -= (NSMaxX(blockRect) - NSMaxX(progressRect));

        if (blockRect.size.width > 0) {
            if (numBlocks < 2) {
                [self drawProgressIndicatorChunk: blockRect];
            }
            blockRect.origin.x += BLOCK_WIDTH + BLOCK_SPACING;
        }
    }
}

- (void) drawProgressIndicatorDeterminate: (NSRect) rect
                                 clipRect: (NSRect) clipRect
                                  bezeled: (BOOL) bezeled
                                    value: (double) value
{
    if (bezeled)
        rect = [self drawProgressIndicatorBackground: rect
                                            clipRect: clipRect
                                             bezeled: bezeled];

    NSRect progressRect = rect;
    NSRect blockRect = progressRect;
    int numBlocks;

    numBlocks =
            (value * progressRect.size.width) / (BLOCK_WIDTH + BLOCK_SPACING);

    if (numBlocks > 0)
        numBlocks++;

    while (numBlocks-- >= 0) {
        blockRect.size.width = BLOCK_WIDTH;

        if (NSMaxX(blockRect) > NSMaxX(progressRect))
            blockRect.size.width -= (NSMaxX(blockRect) - NSMaxX(progressRect));

        if (blockRect.size.width > 0) {
            [self drawProgressIndicatorChunk: blockRect];
            blockRect.origin.x += BLOCK_WIDTH + BLOCK_SPACING;
        }
    }
}

@end

@implementation NSGraphicsStyle (NSScroller)

- (void) drawScrollerButtonInRect: (NSRect) rect
                          enabled: (BOOL) enabled
                          pressed: (BOOL) pressed
                         vertical: (BOOL) vertical
                         upOrLeft: (BOOL) upOrLeft
{
    /*
       unichar code=vertical?(upOrLeft?0x74:0x75):(upOrLeft?0x33:0x34);
       Class   class;
       NSInterfacePart *arrow;

       if(enabled)
        class=[NSInterfacePartAttributedString class];
       else
        class=[NSInterfacePartDisabledAttributedString class];

       arrow=[[[class alloc] initWithMarlettCharacter:code] autorelease];
    */
    NSString *arrow =
            vertical ? (upOrLeft ? @"▲" : @"▼") : (upOrLeft ? @"◀" : @"▶");

    if (!NSIsEmptyRect(rect)) {
        NSSize arrowSize =
                [arrow sizeWithAttributes: sScrollerButtonAttributes];

        if (pressed)
            [self drawPushButtonPressedInRect: rect];
        else
            [self drawPushButtonNormalInRect: rect defaulted: NO];

        if (rect.size.height > 8 && rect.size.width > 8) {
            NSPoint point = rect.origin;

            point.x += floor((rect.size.width - arrowSize.width) / 2);
            point.y += floor((rect.size.height - arrowSize.height) / 2);
            [arrow drawAtPoint: point
                    withAttributes: sScrollerButtonAttributes];
        }
    }
}

- (void) drawScrollerKnobInRect: (NSRect) rect
                       vertical: (BOOL) vertical
                      highlight: (BOOL) highlight
{
    [self drawPushButtonNormalInRect: rect defaulted: NO];
}

- (void) drawScrollerTrackInRect: (NSRect) rect
                        vertical: (BOOL) vertical
                        upOrLeft: (BOOL) upOrLeft
{
    [[NSColor colorWithCalibratedWhite: 0.9 alpha: 1] setFill];
    NSRectFill(rect);
}

- (void) drawScrollerTrackInRect: (NSRect) rect vertical: (BOOL) vertical {
    [self drawScrollerTrackInRect: rect vertical: vertical upOrLeft: NO];
}

@end

@implementation NSGraphicsStyle (NSSlider)

- (NSSize) sliderKnobSizeForControlSize: (NSControlSize) controlSize {
    switch (controlSize) {
    default:
    case NSRegularControlSize:
        return NSMakeSize(16, 16);
    case NSSmallControlSize:
        return NSMakeSize(12, 12);
    case NSMiniControlSize:
        return NSMakeSize(10, 10);
    }
}

- (void) drawSliderKnobInRect: (NSRect) rect
                     vertical: (BOOL) vertical
                  highlighted: (BOOL) highlighted
                 hasTickMarks: (BOOL) hasTickMarks
             tickMarkPosition: (NSTickMarkPosition) tickMarkPosition
{
    NSRect knobBounds = NSInsetRect(rect, 0.5, 0.5);
    NSBezierPath *path = nil;

    if (!hasTickMarks) {
        path = [NSBezierPath bezierPathWithOvalInRect: knobBounds];
    } else {
        path = [NSBezierPath bezierPath];
        CGFloat minX = NSMinX(knobBounds), maxX = NSMaxX(knobBounds), midX = NSMidX(knobBounds);
        CGFloat minY = NSMinY(knobBounds), maxY = NSMaxY(knobBounds), midY = NSMidY(knobBounds);
        CGFloat tip = roundf((vertical ? knobBounds.size.width : knobBounds.size.height) * 0.28);
        if (tip < 3.0)
            tip = 3.0;

        if (vertical) {
            if (tickMarkPosition == NSTickMarkLeft) {
                [path moveToPoint: NSMakePoint(minX, midY)];
                [path lineToPoint: NSMakePoint(minX + tip, maxY)];
                [path lineToPoint: NSMakePoint(maxX, maxY)];
                [path lineToPoint: NSMakePoint(maxX, minY)];
                [path lineToPoint: NSMakePoint(minX + tip, minY)];
                [path closePath];
            } else {
                [path moveToPoint: NSMakePoint(maxX, midY)];
                [path lineToPoint: NSMakePoint(maxX - tip, minY)];
                [path lineToPoint: NSMakePoint(minX, minY)];
                [path lineToPoint: NSMakePoint(minX, maxY)];
                [path lineToPoint: NSMakePoint(maxX - tip, maxY)];
                [path closePath];
            }
        } else {
            if (tickMarkPosition == NSTickMarkAbove) {
                [path moveToPoint: NSMakePoint(midX, maxY)];
                [path lineToPoint: NSMakePoint(maxX, maxY - tip)];
                [path lineToPoint: NSMakePoint(maxX, minY)];
                [path lineToPoint: NSMakePoint(minX, minY)];
                [path lineToPoint: NSMakePoint(minX, maxY - tip)];
                [path closePath];
            } else {
                [path moveToPoint: NSMakePoint(midX, minY)];
                [path lineToPoint: NSMakePoint(minX, minY + tip)];
                [path lineToPoint: NSMakePoint(minX, maxY)];
                [path lineToPoint: NSMakePoint(maxX, maxY)];
                [path lineToPoint: NSMakePoint(maxX, minY + tip)];
                [path closePath];
            }
        }
    }

    NSGradient *gradient;
    if (highlighted) {
        gradient = [[[NSGradient alloc] initWithStartingColor: [NSColor colorWithCalibratedWhite: 0.92 alpha: 1.0]
                                                  endingColor: [NSColor colorWithCalibratedWhite: 0.70 alpha: 1.0]] autorelease];
    } else {
        gradient = [[[NSGradient alloc] initWithStartingColor: [NSColor colorWithCalibratedWhite: 1.0 alpha: 1.0]
                                                  endingColor: [NSColor colorWithCalibratedWhite: 0.85 alpha: 1.0]] autorelease];
    }
    [gradient drawInBezierPath: path angle: 90.0];

    [[NSColor colorWithCalibratedWhite: 0.45 alpha: 1.0] setStroke];
    [path setLineWidth: 1.0];
    [path stroke];
}

- (void) drawSliderTrackInRect: (NSRect) rect
                      vertical: (BOOL) vertical
                  hasTickMarks: (BOOL) hasTickMarks
{
    NSRect groove = rect;

    if (vertical) {
        groove.size.width = 4;
        groove.origin.x = floor(rect.origin.x + (rect.size.width - 4) / 2);
    } else {
        groove.size.height = 4;
        groove.origin.y = floor(rect.origin.y + (rect.size.height - 4) / 2);
    }

    CGFloat radius = MIN(groove.size.width, groove.size.height) / 2.0;
    NSBezierPath *trackPath = [NSBezierPath bezierPathWithRoundedRect: groove
                                                              xRadius: radius
                                                              yRadius: radius];
    [[NSColor colorWithCalibratedWhite: 0.78 alpha: 1.0] setFill];
    [trackPath fill];
    [[NSColor colorWithCalibratedWhite: 0.55 alpha: 1.0] setStroke];
    [trackPath setLineWidth: 1.0];
    [trackPath stroke];
}

- (void) drawSliderTickInRect: (NSRect) rect {
    [[NSColor blackColor] setFill];
    NSRectFill(rect);
}

@end

@implementation NSGraphicsStyle (NSStepper)

- (void) drawStepperButtonInRect: (NSRect) rect
                        clipRect: (NSRect) clipRect
                         enabled: (BOOL) enabled
                     highlighted: (BOOL) highlighted
                       upNotDown: (BOOL) upNotDown
{
    unichar code = upNotDown ? 0x74 : 0x75;
    NSInterfacePart *arrow;

    if (enabled)
        arrow = [[[NSInterfacePartAttributedString alloc]
                initWithMarlettCharacter: code] autorelease];
    else
        arrow = [[[NSInterfacePartDisabledAttributedString alloc]
                initWithMarlettCharacter: code] autorelease];

    if (highlighted)
        NSDrawWhiteBezel(rect, clipRect);
    else
        NSDrawButton(rect, clipRect);

    rect.origin.x += rect.size.width / 2;
    rect.origin.x -= [arrow size].width / 2;
    rect.origin.y += rect.size.height / 2;
    rect.origin.y -= [arrow size].height / 2;
    [arrow drawAtPoint: rect.origin];
}

@end

@implementation NSGraphicsStyle (NSTableView)

- (void) drawTableViewHeaderInRect: (NSRect) rect
                       highlighted: (BOOL) highlighted
{
    NSDrawButton(rect, rect);

    if (highlighted) {
        [[NSColor darkGrayColor] setFill];
        NSRectFill(NSInsetRect(rect, 2, 2));
    }
}

- (void) drawTableViewCornerInRect: (NSRect) rect {
    NSDrawButton(rect, rect);
}

@end

@implementation NSGraphicsStyle (NSBox)

- (void) drawBoxWithLineInRect: (NSRect) rect {
    [[NSColor colorWithCalibratedWhite: 0.78 alpha: 1.0] setStroke];
    [[NSBezierPath bezierPathWithRoundedRect: rect xRadius: 4
                                     yRadius: 4] stroke];
}

- (void) drawBoxWithBezelInRect: (NSRect) rect clipRect: (NSRect) clipRect {
    [[NSColor colorWithCalibratedWhite: 0.78 alpha: 1.0] setStroke];
    [[NSBezierPath bezierPathWithRoundedRect: rect xRadius: 4
                                     yRadius: 4] stroke];
}

- (void) drawBoxWithGrooveInRect: (NSRect) rect clipRect: (NSRect) clipRect {
    [[NSColor colorWithCalibratedWhite: 0.78 alpha: 1.0] setStroke];
    [[NSBezierPath bezierPathWithRoundedRect: rect xRadius: 4
                                     yRadius: 4] stroke];
}

@end

@implementation NSGraphicsStyle (NSComboBox)

- (void) drawComboBoxButtonInRect: (NSRect) rect
                          enabled: (BOOL) enabled
                         bordered: (BOOL) bordered
                          pressed: (BOOL) pressed
{
    NSImage *image = [NSImage imageNamed: @"NSComboBoxCellDown"];
    NSSize imageSize = [image size];
    NSRect imageRect;

    if (pressed)
        NSInterfaceDrawDepressedButton(rect, rect);
    else
        NSDrawButton(rect, rect);

    imageRect.origin.x = rect.origin.x +
                         (rect.size.width - imageSize.width) / 2 +
                         (pressed ? 1 : 0);
    imageRect.origin.y = rect.origin.y +
                         (rect.size.height - imageSize.height) / 2 +
                         (pressed ? -1 : 0);
    imageRect.size = imageSize;

    [self drawButtonImage: image inRect: imageRect enabled: enabled mixed: NO];
}

@end

@implementation NSGraphicsStyle (NSTabView)

- (void) drawTabInRect: (NSRect) rect
              clipRect: (NSRect) clipRect
                 color: (NSColor *) color
              selected: (BOOL) selected
{
    NSRect originalRect = rect;
    NSRect rects[8];
    NSColor *colors[8];
    int i;

    if (selected) {
        rect.origin.x -= 2;
        rect.size.width += 3;
    } else {
        rect.size.height -= 2;
    }

    for (i = 0; i < 8; i++)
        rects[i] = rect;

    colors[0] = [NSColor controlColor];
    if (selected) {
        rects[0].origin.y -= 1;
        rects[0].size.height += 1;
    }
    colors[1] = color;
    rects[1] = NSInsetRect(rect, 1, 1);
    colors[2] = [NSColor whiteColor];
    rects[2].size.width = 1;
    rects[2].size.height -= 2;
    if (selected) {
        rects[2].origin.y -= 1;
        rects[2].size.height += 1;
    }
    colors[3] = [NSColor whiteColor];
    rects[3].origin.x += 1;
    rects[3].origin.y += rect.size.height - 2;
    rects[3].size.width = 1;
    rects[3].size.height = 1;
    colors[4] = [NSColor whiteColor];
    rects[4].origin.x += 2;
    rects[4].origin.y += rect.size.height - 1;
    rects[4].size.width = rect.size.width - 4;
    rects[4].size.height = 1;
    colors[5] = [NSColor blackColor];
    rects[5].origin.x += rect.size.width - 2;
    rects[5].origin.y += rect.size.height - 2;
    rects[5].size.width = 1;
    rects[5].size.height = 1;
    colors[6] = [NSColor controlShadowColor];
    rects[6].origin.x += rect.size.width - 2;
    rects[6].size.width = 1;
    rects[6].size.height -= 2;
    colors[7] = [NSColor blackColor];
    rects[7].origin.x += rect.size.width - 1;
    rects[7].size.width = 1;
    rects[7].size.height -= 2;
    if (selected) {
        rects[7].origin.y -= 1;
        rects[7].size.height += 1;
    }

    for (i = 0; i < 8; i++) {
        [colors[i] setFill];
        NSRectFill(rects[i]);
    }

    if (selected) { // cleanup
        NSRect erase = originalRect;

        [[NSColor controlColor] setFill];
        erase.size.height = 2;
        erase = NSInsetRect(erase, 1, 0);
        NSRectFill(erase);
    }
}

- (void) drawTabPaneInRect: (NSRect) rect {
    NSDrawButton(rect, rect);
}

- (void) drawTabViewBackgroundInRect: (NSRect) rect {
    // do nothing
}

@end

@implementation NSGraphicsStyle (NSTextField)

- (void) drawTextFieldBorderInRect: (NSRect) rect
                    bezeledNotLine: (BOOL) bezeledNotLine
{
    if (!bezeledNotLine) {
        [[NSColor blackColor] setStroke];
        NSFrameRect(rect);
        return;
    }

    [[NSColor textBackgroundColor] setFill];
    NSRectFill(NSInsetRect(rect, 1, 1));

    BOOL dark = NSControlDrawingIsDark();
    NSColor *edge = [NSColor colorWithCalibratedWhite: dark ? 1 : 0
                                                alpha: dark ? 0.12 : 0.15];
    NSColor *topEdge = dark ? edge
                            : [NSColor colorWithCalibratedWhite: 0 alpha: 0.25];
    NSRect top = rect;
    top.size.height = 1;
    if ([_view isFlipped] == NO)
        top.origin.y = NSMaxY(rect) - 1;
    NSRect rest = rect;
    rest.size.height -= 1;
    if ([_view isFlipped])
        rest.origin.y += 1;

    [topEdge setFill];
    NSRectFillUsingOperation(top, NSCompositeSourceOver);
    NSControlFillRing(rest, 0, NSInsetRect(rect, 1, 1), 0, edge);
}

- (void) drawTextViewInsertionPointInRect: (NSRect) rect
                                    color: (NSColor *) color
{
    [color setFill];
    NSRectFill(rect);
}

@end

@implementation NSView (NSGraphicsStyle)

- (NSGraphicsStyle *) graphicsStyle {
    return [[[NSGraphicsStyle alloc] initWithView: self] autorelease];
}

@end
