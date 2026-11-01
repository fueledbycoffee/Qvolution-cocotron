/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>

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
#import <AppKit/NSApplication.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSDisplay.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsStyle.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSScroller.h>
#import <AppKit/NSTrackingArea.h>
#import <Foundation/NSTimer.h>
#import "X11DesktopSettings.h"

@interface NSScroller (NSScrollerOverlay)
- (void) _revealOverlay;
@end
#import <AppKit/NSWindow.h>
#import <Foundation/NSKeyedArchiver.h>

// Declared in NSScroller.h.
NSString *const NSPreferredScrollerStyleDidChangeNotification =
        @"NSPreferredScrollerStyleDidChangeNotification";

// Private: coordinates a scroll view's two scrollers. Apps create one, set its
// delegate and ask for the scroller layout direction.
@interface NSScrollerImpPair : NSObject {
    id _delegate;
    NSScrollerStyle _scrollerStyle;
    id _verticalScrollerImp;
    id _horizontalScrollerImp;
}
@property (assign) id delegate;
@property NSScrollerStyle scrollerStyle;
@property (retain) id verticalScrollerImp;
@property (retain) id horizontalScrollerImp;
@end

@implementation NSScrollerImpPair

@synthesize delegate = _delegate;
@synthesize scrollerStyle = _scrollerStyle;
@synthesize verticalScrollerImp = _verticalScrollerImp;
@synthesize horizontalScrollerImp = _horizontalScrollerImp;

- (void) dealloc {
    [_verticalScrollerImp release];
    [_horizontalScrollerImp release];
    [super dealloc];
}

- (instancetype) init {
    self = [super init];
    if (self != nil)
        _scrollerStyle = [NSScroller preferredScrollerStyle];
    return self;
}

+ (NSUserInterfaceLayoutDirection) scrollerLayoutDirection {
    return NSUserInterfaceLayoutDirectionLeftToRight;
}

- (void) flashScrollers {
    // Overlay knobs reappear and fade again; legacy scrollers just redraw.
    for (id imp in @[ _verticalScrollerImp ?: [NSNull null],
                      _horizontalScrollerImp ?: [NSNull null] ]) {
        if ([imp respondsToSelector: @selector(_revealOverlay)])
            [imp _revealOverlay];
        if ([imp respondsToSelector: @selector(setNeedsDisplay:)])
            [imp setNeedsDisplay: YES];
    }
}

- (void) contentAreaDidResize {
    [_verticalScrollerImp setNeedsDisplay: YES];
    [_horizontalScrollerImp setNeedsDisplay: YES];
}

- (void) movedToNewWindow {
    // Scroller appearance may change with its window. Both painters should be
    // redrawn after a scroll view is attached to another window.
    [self contentAreaDidResize];
}

- (void) mouseExitedContentArea {
    // Legacy scrollers do not use hover visibility, but the painters need a
    // redraw after a tracking transition.
    [self contentAreaDidResize];
}

- (void) contentAreaWillDraw {
    // Legacy scrollers paint with their owning view's display pass.
}

- (void) contentAreaScrolled {
    // Terminal reports each scroll through this, with no argument, so the
    // imp pair redraws its painters.
    [self contentAreaDidResize];
}

@end

@implementation NSScroller

+ (CGFloat) scrollerWidth {
    return [[NSDisplay currentDisplay] scrollerWidth];
}

// Follows GNOME's org.gnome.desktop.interface overlay-scrolling key, read
// through the desktop settings portal. Without a portal the settings object
// keeps GNOME's default, which is overlay scrolling.
+ (NSScrollerStyle) preferredScrollerStyle {
    return [[X11DesktopSettings sharedSettings] overlayScrolling]
                   ? NSScrollerStyleOverlay
                   : NSScrollerStyleLegacy;
}

// Cocotron draws one scroller size for every control size and style.
+ (CGFloat) scrollerWidthForControlSize: (NSControlSize) controlSize
                          scrollerStyle: (NSScrollerStyle) scrollerStyle
{
    return [self scrollerWidth];
}
/* OS X has a global default "AppleScrollBarVariant" with the values: Single,
 DoubleMin, DoubleMax, and DoubleBoth This controls the default position of the
 scroller. This should be controlling the positioning.
 */

typedef enum {
    NSAppleScrollBarVariantSingle,
    NSAppleScrollBarVariantDoubleMin,
    NSAppleScrollBarVariantDoubleMax,
    NSAppleScrollBarVariantDoubleBoth,
} NSAppleScrollBarVariant;

static NSAppleScrollBarVariant appleScrollBarVariant(NSScroller *self) {
    return NSAppleScrollBarVariantSingle;
}

- (void) encodeWithCoder: (NSCoder *) coder {
    NSUnimplementedMethod();
}

- initWithCoder: (NSCoder *) coder {
    [super initWithCoder: coder];

    if ([coder allowsKeyedCoding]) {
        sFlags.isHoriz = (_bounds.size.width < _bounds.size.height) ? NO : YES;
        _floatValue = 0;
        _knobProportion = 0;
        _arrowsPosition = NSScrollerArrowsNone;
        [self checkSpaceForParts];
    } else {
        // GUESS (rung 6): NeXT/OpenStep typedstream layout for NSScroller
        sFlags.isHoriz = (_bounds.size.width < _bounds.size.height) ? NO : YES;
        _floatValue = 0;
        _knobProportion = 0;

        id target = nil;
        float floatVal = 0, knobProp = 0;
        SEL action = NULL;
        char arrows = 0, size = 0;

        @try {
            [coder decodeValueOfObjCType: "@" at: &target];
            [coder decodeValuesOfObjCTypes: "ff:", &floatVal, &knobProp, &action];
            [coder decodeValueOfObjCType: "c" at: &arrows];
            [coder decodeValueOfObjCType: "c" at: &size];
            _floatValue = floatVal;
            _knobProportion = knobProp;
            _arrowsPosition = (NSScrollArrowPosition)arrows;
            _controlSize = (NSControlSize)size;
            [self setTarget: target];
            [target release];
            [self setAction: action];
        } @catch (id ex) {
            // Ignore decoding mismatch
        }
        [self checkSpaceForParts];
    }
    return self;
}

- initWithFrame: (NSRect) frame {
    [super initWithFrame: frame];
    sFlags.isHoriz = (_bounds.size.width < _bounds.size.height) ? NO : YES;
    _floatValue = 0;
    _knobProportion = 0;
    // The theme draws no stepper arrows; an app can still ask for them.
    _arrowsPosition = NSScrollerArrowsNone;
    [self checkSpaceForParts];
    return self;
}

- (void) dealloc {
    [_overlayTimer invalidate];
    [_overlayTimer release];
    [_overlayTrackingArea release];
    [super dealloc];
}

#pragma mark - Overlay presentation

// Overlay knobs stay visible for this long after the last scroll, then fade.
static const NSTimeInterval kOverlayIdleDelay = 1.0;
static const NSTimeInterval kOverlayFadeDuration = 0.2;
static const NSTimeInterval kOverlayFadeStep = 1.0 / 60.0;

- (BOOL) _isOverlay {
    return _scrollerStyle == NSScrollerStyleOverlay;
}

- (void) _stopOverlayTimer {
    [_overlayTimer invalidate];
    [_overlayTimer release];
    _overlayTimer = nil;
}

- (void) _scheduleOverlayTimer: (NSTimeInterval) delay
                      selector: (SEL) selector
                       repeats: (BOOL) repeats
{
    [self _stopOverlayTimer];
    _overlayTimer = [[NSTimer timerWithTimeInterval: delay
                                             target: self
                                           selector: selector
                                           userInfo: nil
                                            repeats: repeats] retain];
    [[NSRunLoop currentRunLoop] addTimer: _overlayTimer
                                 forMode: NSRunLoopCommonModes];
}

- (void) _setOverlayOpacity: (CGFloat) opacity {
    opacity = MAX(0, MIN(1, opacity));
    if (opacity != _overlayOpacity) {
        _overlayOpacity = opacity;
        [self setNeedsDisplay: YES];
    }
}

- (void) _overlayFadeStep: (NSTimer *) timer {
    NSTimeInterval elapsed =
            [NSDate timeIntervalSinceReferenceDate] - _overlayFadeStart;
    CGFloat opacity = 1.0 - elapsed / kOverlayFadeDuration;

    if (opacity <= 0) {
        [self _stopOverlayTimer];
        opacity = 0;
    }
    [self _setOverlayOpacity: opacity];
}

- (void) _overlayIdle: (NSTimer *) timer {
    if (_isHovered || _isHighlighted) {
        [self _stopOverlayTimer];
        return;
    }
    // Reduced motion hides the knob at once instead of animating it.
    if ([[X11DesktopSettings sharedSettings] reducedMotion]) {
        [self _stopOverlayTimer];
        [self _setOverlayOpacity: 0];
        return;
    }
    _overlayFadeStart = [NSDate timeIntervalSinceReferenceDate];
    [self _scheduleOverlayTimer: kOverlayFadeStep
                       selector: @selector(_overlayFadeStep:)
                        repeats: YES];
}

// Shows the overlay knob and restarts the idle delay before it fades.
- (void) _revealOverlay {
    if (![self _isOverlay])
        return;
    [self _setOverlayOpacity: 1];
    if (_isHovered || _isHighlighted)
        [self _stopOverlayTimer];
    else
        [self _scheduleOverlayTimer: kOverlayIdleDelay
                           selector: @selector(_overlayIdle:)
                            repeats: NO];
}

- (CGFloat) _overlayOpacity {
    return _overlayOpacity;
}

- (BOOL) _isHovered {
    return _isHovered;
}

- (void) _setHovered: (BOOL) hovered {
    if (_isHovered == hovered)
        return;
    _isHovered = hovered;
    [self setNeedsDisplay: YES];
    if ([self _isOverlay]) {
        if (hovered && [self isEnabled])
            [self _revealOverlay];
        else if (!hovered && _overlayOpacity > 0)
            [self _revealOverlay];
    }
}

- (void) updateTrackingAreas {
    [super updateTrackingAreas];
    if (_overlayTrackingArea != nil) {
        [self removeTrackingArea: _overlayTrackingArea];
        [_overlayTrackingArea release];
    }
    _overlayTrackingArea = [[NSTrackingArea alloc]
            initWithRect: [self bounds]
                 options: NSTrackingMouseEnteredAndExited |
                          NSTrackingActiveInActiveApp | NSTrackingInVisibleRect
                   owner: self
                userInfo: nil];
    [self addTrackingArea: _overlayTrackingArea];
}

- (void) mouseEntered: (NSEvent *) event {
    [self _setHovered: YES];
}

- (void) mouseExited: (NSEvent *) event {
    [self _setHovered: NO];
}

// A faded overlay scroller lets clicks reach the content beneath it.
- (NSView *) hitTest: (NSPoint) point {
    if ([self _isOverlay] && _overlayOpacity <= 0 && !_isHovered)
        return nil;
    return [super hitTest: point];
}

- (BOOL) isFlipped {
    return YES;
}

- (BOOL) refusesFirstResponder {
    return YES;
}

- (BOOL) acceptsFirstResponder {
    return NO;
}

- (void) setFrame: (NSRect) frame {
    [super setFrame: frame];
    [self checkSpaceForParts];
}

- (id) target {
    return _target;
}

- (void) setTarget: (id) target {
    _target = target;
}

- (SEL) action {
    return _action;
}

- (void) setAction: (SEL) action {
    _action = action;
}

- (BOOL) isEnabled {
    return _isEnabled;
}

- (void) setEnabled: (BOOL) flag {
    _isEnabled = flag;
    [self setNeedsDisplay: YES];
}

- (BOOL) isVertical {
    return sFlags.isHoriz ? NO : YES;
}

- (float) floatValue {
    return _floatValue;
}

- (CGFloat) knobProportion {
    return _knobProportion;
}

- (void) setKnobProportion: (CGFloat) proportion {
    _knobProportion = MIN(1.0, MAX(0.0, proportion));
    [self setNeedsDisplay: YES];
}

- (NSScrollArrowPosition) arrowsPosition {
    return _arrowsPosition;
}

- (NSControlTint) controlTint {
    return _controlTint;
}

- (void) setControlTint: (NSControlTint) tint {
    _controlTint = tint;
    [self setNeedsDisplay: YES];
}

- (NSControlSize) controlSize {
    return _controlSize;
}

- (NSScrollerStyle) scrollerStyle {
    return _scrollerStyle;
}

- (NSScrollerKnobStyle) knobStyle {
    return _knobStyle;
}

- (id) scrollerImp {
    // Cocotron draws the scroller directly; there is no separate painter
    // object as in AppKit's private NSScrollerImp implementation.
    return self;
}


- (void) setFloatValue: (float) zeroToOneValue
        knobProportion: (CGFloat) zeroToOneKnob
{
    if (zeroToOneValue > 1)
        zeroToOneValue = 1;
    if (zeroToOneValue < 0)
        zeroToOneValue = 0;
    if (zeroToOneKnob > 1)
        zeroToOneKnob = 1;
    if (zeroToOneKnob < 0)
        zeroToOneKnob = 0;

    BOOL changed = (_floatValue != zeroToOneValue ||
                    _knobProportion != zeroToOneKnob);

    _floatValue = zeroToOneValue;
    _knobProportion = zeroToOneKnob;
    if (_knobProportion > 1)
        _knobProportion = 1;

    if (changed)
        [self _revealOverlay];
    [self setNeedsDisplay: YES];
}

- (double) doubleValue {
    return _floatValue;
}

- (void) setDoubleValue: (double) zeroToOneValue {
    if (zeroToOneValue > 1)
        zeroToOneValue = 1;
    if (zeroToOneValue < 0)
        zeroToOneValue = 0;

    _floatValue = zeroToOneValue;

    [self setNeedsDisplay: YES];
}

- (void) setArrowsPosition: (NSScrollArrowPosition) position {
    _arrowsPosition = position;
}

- (void) setControlSize: (NSControlSize) value {
    _controlSize = value;
    [self setNeedsDisplay: YES];
}

- (void) setScrollerStyle: (NSScrollerStyle) style {
    if (_scrollerStyle == style)
        return;
    _scrollerStyle = style;
    [self _stopOverlayTimer];
    _overlayOpacity = 0;
    [self setNeedsDisplay: YES];
}

- (void) setKnobStyle: (NSScrollerKnobStyle) style {
    _knobStyle = style;
    [self setNeedsDisplay: YES];
}

- (NSRect) frameOfDecrementPage {
    NSRect knobSlot = [self rectForPart: NSScrollerKnobSlot];
    NSRect knob = [self rectForPart: NSScrollerKnob];
    NSRect result = knobSlot;

    if (NSIsEmptyRect(knob))
        return NSZeroRect;

    if ([self isVertical]) {
        result.size.height = (knob.origin.y - knobSlot.origin.y);
        if (result.size.height <= 0)
            result = NSZeroRect;
    } else {
        result.size.width = (knob.origin.x - knobSlot.origin.x);
        if (result.size.width <= 0)
            result = NSZeroRect;
    }

    return result;
}

- (NSRect) frameOfIncrementPage {
    NSRect knobSlot = [self rectForPart: NSScrollerKnobSlot];
    NSRect knob = [self rectForPart: NSScrollerKnob];
    NSRect result = knobSlot;

    if (NSIsEmptyRect(knob))
        return NSZeroRect;

    if ([self isVertical]) {
        result.origin.y = knob.origin.y + knob.size.height;
        result.size.height =
                ((knobSlot.origin.y + knobSlot.size.height) - result.origin.y);
        if (result.size.height <= 0)
            result = NSZeroRect;
    } else {
        result.origin.x = knob.origin.x + knob.size.width;
        result.size.width =
                ((knobSlot.origin.x + knobSlot.size.width) - result.origin.x);
        if (result.size.width <= 0)
            result = NSZeroRect;
    }

    return result;
}

static inline CGFloat roundFloat(CGFloat value) {
    value += 0.5;

    return (int) value;
}

- (NSRect) rectForPart: (NSScrollerPart) part {
    NSRect bounds = [self bounds];
    NSRect decLine = bounds;
    NSRect incLine;
    NSRect knobSlot = bounds;
    NSRect knob;
    NSRect result = NSZeroRect;

    if ([self isVertical]) {
        if (_arrowsPosition == NSScrollerArrowsNone) {
            decLine = NSZeroRect;
            incLine = NSZeroRect;
        } else {
            decLine.size.height = decLine.size.width;
            if (decLine.size.height * 2 > bounds.size.height)
                decLine.size.height = floor(bounds.size.height / 2);

            incLine = decLine;

            if (appleScrollBarVariant(self) == NSAppleScrollBarVariantSingle) {
                incLine.origin.y = bounds.size.height - incLine.size.height;
                knobSlot.origin.y += decLine.size.height;
                knobSlot.size.height -=
                        decLine.size.height + incLine.size.height;
            } else {
                knobSlot.size.height -=
                        decLine.size.height + incLine.size.height;

                if (_arrowsPosition == NSScrollerArrowsMaxEnd) {
                    incLine.origin.y = bounds.size.height - incLine.size.height;
                    decLine.origin.y = incLine.origin.y - decLine.size.height;
                } else if (_arrowsPosition == NSScrollerArrowsMinEnd) {
                    incLine.origin.y = NSMaxY(decLine);
                    knobSlot.origin.y = NSMaxY(incLine);
                }
            }
        }

        knob = knobSlot;
        knob.size.height = roundFloat(knobSlot.size.height * _knobProportion);
        if (knob.size.height < knob.size.width)
            knob.size.height = knob.size.width;
        knob.origin.y +=
                floor((knobSlot.size.height - knob.size.height) * _floatValue);

        if (floor(knob.size.height) >= floor(knobSlot.size.height))
            knob = NSZeroRect;
    } else {
        if (_arrowsPosition == NSScrollerArrowsNone) {
            decLine = NSZeroRect;
            incLine = NSZeroRect;
        } else {
            decLine.size.width = decLine.size.height;
            if (decLine.size.width * 2 > bounds.size.width)
                decLine.size.width = floor(bounds.size.width / 2);

            incLine = decLine;
            incLine.origin.x = bounds.size.width - incLine.size.width;
        }

        knobSlot.origin.x += decLine.size.width;
        knobSlot.size.width -= decLine.size.width + incLine.size.width;

        knob = knobSlot;
        knob.size.width = roundFloat(knobSlot.size.width * _knobProportion);
        if (knob.size.width < knob.size.height)
            knob.size.width = knob.size.height;
        knob.origin.x +=
                floor((knobSlot.size.width - knob.size.width) * _floatValue);
        if (floor(knob.size.width) >= floor(knobSlot.size.width))
            knob = NSZeroRect;
    }

    switch (part) {
    case NSScrollerNoPart:
        result = NSZeroRect;
        break;

    case NSScrollerKnob:
        result = [self isEnabled] ? knob : NSZeroRect;
        break;

    case NSScrollerKnobSlot:
        result = knobSlot;
        break;

    case NSScrollerIncrementLine:
        result = incLine;
        break;

    case NSScrollerDecrementLine:
        result = decLine;
        break;

    case NSScrollerIncrementPage:
        result = [self frameOfIncrementPage];
        break;

    case NSScrollerDecrementPage:
        result = [self frameOfDecrementPage];
        break;
    }

    result = [self centerScanRect: result];

    return result;
}

- (void) checkSpaceForParts {
    sFlags.partsUsable = NSAllScrollerParts;
}

- (NSUsableScrollerParts) usableParts {
    return sFlags.partsUsable;
}

- (void) highlight: (BOOL) flag {
    if (_isHighlighted != flag) {
        _isHighlighted = flag;
        [self setNeedsDisplay: YES];
        [self _revealOverlay];
    }
}

- (void) drawKnobSlotInRect: (NSRect) rect highlight: (BOOL) flag {
}

- (void) drawParts {
    // do nothing
}

- (void) drawKnob {
    NSRect knob = [self rectForPart: NSScrollerKnob];

    if (NSIsEmptyRect(knob))
        return;
    if ([self _isOverlay])
        [[self graphicsStyle] drawOverlayScrollerKnobInRect: knob
                                                   vertical: [self isVertical]
                                                   expanded: _isHovered || _isHighlighted
                                                    opacity: _overlayOpacity];
    else
        [[self graphicsStyle] drawScrollerKnobInRect: knob
                                            vertical: [self isVertical]
                                           highlight: _isHighlighted || _isHovered];
}

- (void) drawArrow: (NSScrollerArrow) arrow highlight: (BOOL) highlight {
    NSRect rect = (arrow == NSScrollerIncrementArrow)
                          ? [self rectForPart: NSScrollerIncrementLine]
                          : [self rectForPart: NSScrollerDecrementLine];

    [[self graphicsStyle]
            drawScrollerButtonInRect: rect
                             enabled: [self isEnabled]
                             pressed: highlight
                            vertical: [self isVertical]
                            upOrLeft: (arrow != NSScrollerIncrementArrow)];
}

- (void) drawRect: (NSRect) rect {
    NSRect slot = [self rectForPart: NSScrollerKnobSlot];
    BOOL high;

    if ([self _isOverlay]) {
        // Overlay scrollers float over the content: nothing but the knob,
        // plus a track while the pointer is over them.
        if (_overlayOpacity <= 0)
            return;
        if (_isHovered || _isHighlighted)
            [[self graphicsStyle] drawOverlayScrollerTrackInRect: [self bounds]
                                                        vertical: [self isVertical]
                                                         opacity: _overlayOpacity];
        [self drawKnob];
        return;
    }

    if (_arrowsPosition != NSScrollerArrowsNone) {
        high = (_hitPart == NSScrollerIncrementLine) && _isHighlighted;
        [self drawArrow: NSScrollerIncrementArrow highlight: high];
        high = (_hitPart == NSScrollerDecrementLine) && _isHighlighted;
        [self drawArrow: NSScrollerDecrementArrow highlight: high];
    }

    // One track under the whole slot, so the narrow knob has track beside it.
    if (!NSIsEmptyRect(slot))
        [[self graphicsStyle] drawScrollerTrackInRect: slot
                                             vertical: [self isVertical]];

    [self drawKnob];
}

- (NSScrollerPart) hitPart {
    return _hitPart;
}

- (NSScrollerPart) testPart: (NSPoint) point {
    int part;

    _hitPart = NSScrollerNoPart;

    for (part = NSScrollerIncrementLine; part <= NSScrollerKnobSlot; part++) {
        NSRect rect = [self rectForPart: part];

        if (NSMouseInRect(point, rect, [self isFlipped])) {
            _hitPart = part;
            break;
        }
    }

    return _hitPart;
}

- (void) trackKnob: (NSEvent *) event {
    NSPoint firstPoint = [self convertPoint: [event locationInWindow]
                                   fromView: nil];
    NSRect slotRect = [self rectForPart: NSScrollerKnobSlot];
    NSRect knobRect = [self rectForPart: NSScrollerKnob];
    CGFloat totalSize;
    CGFloat startFloatValue = _floatValue;

    if ([self isVertical])
        totalSize = slotRect.size.height - knobRect.size.height;
    else
        totalSize = slotRect.size.width - knobRect.size.width;

    // Dragging shows the active knob and keeps an overlay knob visible.
    [self highlight: YES];
    do {
        NSPoint point;
        CGFloat delta;

        event = [[self window] nextEventMatchingMask: NSLeftMouseUpMask |
                                                      NSLeftMouseDraggedMask];

        point = [self convertPoint: [event locationInWindow] fromView: nil];

        if ([self isVertical])
            delta = point.y - firstPoint.y;
        else
            delta = point.x - firstPoint.x;

        if (totalSize == 0)
            _floatValue = 0;
        else
            _floatValue = startFloatValue + (delta / totalSize);
        if (_floatValue < 0)
            _floatValue = 0;
        else if (_floatValue > 1.0)
            _floatValue = 1.0;

        [self setNeedsDisplay: YES];

        [self sendAction: _action to: _target];

    } while ([event type] != NSLeftMouseUp);
    [self highlight: NO];
}

- (void) trackScrollButtons: (NSEvent *) event {
    NSRect rect = [self rectForPart: [self hitPart]];
    NSPoint point = [self convertPoint: [event locationInWindow] fromView: nil];

    // fixup to make paging behavior available via the Alt key, like NEXTSTEP
    if (([event modifierFlags] & NSAlternateKeyMask) &&
        (_hitPart == NSScrollerIncrementLine))
        _hitPart = NSScrollerIncrementPage;
    else if (([event modifierFlags] & NSAlternateKeyMask) &&
             (_hitPart == NSScrollerDecrementLine))
        _hitPart = NSScrollerDecrementPage;

    // scroll every 1/2 second...
    [NSEvent startPeriodicEventsAfterDelay: 0.0 withPeriod: 0.05];

    do {
        if ([event type] != NSPeriodic) // periodic events have location of 0,0
            point = [self convertPoint: [event locationInWindow] fromView: nil];

        [self highlight: NSMouseInRect(point, rect, [self isFlipped])];
        if (NSMouseInRect(point, rect, [self isFlipped]))
            [self sendAction: _action to: _target];

        event = [[self window] nextEventMatchingMask: NSPeriodicMask |
                                                      NSLeftMouseUpMask |
                                                      NSLeftMouseDraggedMask];
    } while ([event type] != NSLeftMouseUp);

    [NSEvent stopPeriodicEvents];

    [self highlight: NO];
}

- (void) trackPageSlots: (NSEvent *) event {
    do {
        NSPoint point = [self convertPoint: [event locationInWindow]
                                  fromView: nil];
        NSRect knobRect = [self rectForPart: NSScrollerKnob];
        NSRect knobSlotRect = [self rectForPart: NSScrollerKnobSlot];
        CGFloat roundingThreshold;

        // rounding to edges when distance from edge < size of knob
        if ([self isVertical])
            roundingThreshold = knobRect.size.height / knobSlotRect.size.height;
        else
            roundingThreshold = knobRect.size.width / knobSlotRect.size.width;

        if (NSMouseInRect(point, knobSlotRect, [self isFlipped]) &&
            !NSMouseInRect(point, knobRect, [self isFlipped])) {
            // correct for knobSlot origin
            point.x -= knobSlotRect.origin.x;
            point.y -= knobSlotRect.origin.y;

            if ([self isVertical])
                _floatValue = point.y / knobSlotRect.size.height;
            else
                _floatValue = point.x / knobSlotRect.size.width;

            if (_floatValue < roundingThreshold)
                _floatValue = 0;
            else if (_floatValue > 1.0 - roundingThreshold)
                _floatValue = 1.0;

            // knobRect may now be different
            knobRect = [self rectForPart: NSScrollerKnob];
            _hitPart = NSScrollerKnobSlot; // for scroll-to-click

            [self highlight: YES];
            [self sendAction: _action to: _target];
        }

        event = [[self window] nextEventMatchingMask: NSLeftMouseUpMask |
                                                      NSLeftMouseDraggedMask];

    } while ([event type] != NSLeftMouseUp);

    [self highlight: NO];
}

- (void) mouseDown: (NSEvent *) event {
    NSPoint point = [self convertPoint: [event locationInWindow] fromView: nil];
    NSScrollerPart part = [self testPart: point];

    if (![self isEnabled])
        return;

    switch (part) {
    case NSScrollerNoPart:
        return;

    case NSScrollerKnob:
        [self trackKnob: event];
        break;

    case NSScrollerKnobSlot:
        break;

    case NSScrollerIncrementLine:
    case NSScrollerDecrementLine:
        [self trackScrollButtons: event];
        break;

    case NSScrollerIncrementPage:
    case NSScrollerDecrementPage:
        [self trackPageSlots: event];
        break;
    }
}

- (void) scrollWheel: (NSEvent *) event {
    NSRect slotRect = [self rectForPart: NSScrollerKnobSlot];
    NSRect knobRect = [self rectForPart: NSScrollerKnob];

    if ([self isVertical]) {
        CGFloat delta = [event deltaY];
        CGFloat totalSize = slotRect.size.height - knobRect.size.height;

        if (totalSize == 0)
            _floatValue = 0;
        else
            _floatValue = _floatValue - (delta / totalSize);

        if (_floatValue < 0)
            _floatValue = 0;
        else if (_floatValue > 1.0)
            _floatValue = 1.0;

        [self setNeedsDisplay: YES];
        [self sendAction: _action to: _target];
    }
}

@end
