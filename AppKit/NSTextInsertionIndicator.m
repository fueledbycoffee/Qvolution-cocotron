/* Rung 3: local AppKit index, NSTextInsertionIndicator properties.
 * GUESS: a static caret replaces unavailable blinking/compositing effects.
 */
#import <AppKit/NSTextInsertionIndicator.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>
@implementation NSTextInsertionIndicator
@synthesize automaticModeOptions = _automaticModeOptions;
- (void (^)(NSView *)) effectsViewInserter { return _effectsViewInserter; }
- (void) setEffectsViewInserter: (void (^)(NSView *)) inserter {
    void (^copy)(NSView *) = [inserter copy];
    [_effectsViewInserter release];
    _effectsViewInserter = copy;
}
- (NSColor *) color { return _color; }
- (void) setColor: (NSColor *) color {
    [color retain]; [_color release]; _color = color;
    [self setNeedsDisplay: YES];
}
- (NSTextInsertionIndicatorDisplayMode) displayMode { return _displayMode; }
- (void) setDisplayMode: (NSTextInsertionIndicatorDisplayMode) mode {
    _displayMode = mode;
    [self setNeedsDisplay: YES];
}
- (void) drawRect: (NSRect) rect {
    if (_displayMode == NSTextInsertionIndicatorDisplayModeHidden) return;
    [(_color ?: [NSColor textColor]) setFill];
    [NSBezierPath fillRect: [self bounds]];
}
- (void) dealloc { [_color release]; [_effectsViewInserter release]; [super dealloc]; }
@end
