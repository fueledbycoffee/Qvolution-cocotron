#import <AppKit/AppKit.h>
#import <AppKit/NSPopUpWindow.h>
#import <AppKit/NSPopUpView.h>
#import <objc/runtime.h>
#include <assert.h>
#include <stdio.h>
#ifdef NDEBUG
#error Assertions required
#endif

@interface NSPopUpView (ViewportTest)
- (void)scrollBy:(CGFloat)delta;
- (NSRect)rectForItemAtIndex:(NSInteger)index;
- (NSInteger)itemIndexForPoint:(NSPoint)point;
@end
@interface ProbeWheel : NSEvent
@end
@implementation ProbeWheel
- (CGFloat)deltaY { return -1; }
@end
@interface ProbeView : NSPopUpView
@end
@implementation ProbeView
- (NSInteger)runTrackingWithEvent:(NSEvent *)event { return 0; }
@end
@interface ProbeWindow : NSPopUpWindow
- (NSPopUpView *)popupView;
@end
@implementation ProbeWindow
- (void)orderFront:(id)sender {}
- (NSScreen *)screen {
    return [[[NSScreen alloc] initWithFrame:NSMakeRect(-1280, 100, 1280, 900)
            visibleFrame:NSMakeRect(-1280, 140, 1280, 840)] autorelease];
}
- (NSPopUpView *)popupView { return _view; }
@end

static void assertSelectionVisible(NSPopUpView *view) {
    NSRect item = [view rectForSelectedItem];
    assert(NSContainsRect([view bounds], item));
    NSPoint center = NSMakePoint(NSMidX(item), NSMidY(item));
    assert([view itemIndexForPoint:center] >= 0);
}
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Many fonts"];
        [menu setAutoenablesItems:NO];
        for (NSUInteger i=0; i<400; ++i)
            [menu addItemWithTitle:[NSString stringWithFormat:@"Family %03lu", (unsigned long)i]
                    action:NULL keyEquivalent:@""];
        [[menu itemAtIndex:399] setTitle:@"Zulu"];
        NSInteger selections[] = {0, 200, 399};
        for (unsigned i=0; i<3; ++i) {
            ProbeWindow *window = [[ProbeWindow alloc] initWithFrame:NSMakeRect(-40, 950, 100, 20)];
            [window setMenu:menu];
            [window selectItemAtIndex:selections[i]];
            NSPopUpView *view = [window popupView];
            object_setClass(view, [ProbeView class]);
            assert([window runTrackingWithEvent:nil] == 0);
            assert(NSContainsRect([[window screen] visibleFrame], [window frame]));
            assert([view frame].size.height == [window frame].size.height);
            assertSelectionVisible(view);
            [view scrollBy:1e6];
            CGFloat lastOffset = NSMinY([view bounds]);
            assert(lastOffset > 0);
            [view scrollBy:1e6];
            assert(NSMinY([view bounds]) == lastOffset);
            [view scrollBy:-1e6];
            assert(NSMinY([view bounds]) == 0);
            ProbeWheel *wheel = [ProbeWheel new];
            [view scrollWheel:wheel];
            [wheel release];
            assert(NSMinY([view bounds]) > 0);
            [view selectItemAtIndex:398];
            [view moveDown:nil];
            assertSelectionVisible(view);
            [view selectItemAtIndex:1];
            [view moveUp:nil];
            assertSelectionVisible(view);
            [view insertText:@"Z"];
            assert(NSEqualRects([view rectForSelectedItem], [view rectForItemAtIndex:399]));
            assertSelectionVisible(view);
            [window release];
        }
        ProbeWindow *shortWindow = [[ProbeWindow alloc] initWithFrame:NSMakeRect(-600, 500, 100, 20)];
        NSMenu *shortMenu = [[NSMenu alloc] initWithTitle:@"Short"];
        [shortMenu addItemWithTitle:@"Only" action:NULL keyEquivalent:@""];
        [shortWindow setMenu:shortMenu];
        [shortWindow selectItemAtIndex:0];
        NSPopUpView *shortView = [shortWindow popupView];
        object_setClass(shortView, [ProbeView class]);
        [shortWindow runTrackingWithEvent:nil];
        assert([shortWindow frame].size.height == [shortView sizeForContents].height);
        [shortView scrollBy:100];
        assert(NSMinY([shortView bounds]) == 0);
        [shortWindow release]; [shortMenu release]; [menu release];
        puts("PASS: bounded 400-item popup, selection and scroll reachability");
    }
    return 0;
}
