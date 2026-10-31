#import <AppKit/AppKit.h>
#import <AppKit/NSPopUpWindow.h>
#import <AppKit/NSPopUpView.h>
#import "../AppKit/Wayland.backend/WaylandDisplay.h"
#import "../AppKit/Wayland.backend/WaylandProtocol.h"
#import <objc/runtime.h>
#include <assert.h>
#include <stdio.h>
#ifdef NDEBUG
#error Assertions required
#endif
@interface NSObject (PopupConfigureProbe)
- (void)handleEvent:(uint32_t)opcode kind:(WaylandObjectKind)kind
             proxy:(struct wl_proxy *)proxy arguments:(union wl_argument *)args;
- (void)applyConfigure;
- (id)waylandDisplay;
- (void)runAfterDispatchBlocks;
@end
@interface ImmediateViewport : NSPopUpView
@end
@implementation ImmediateViewport
- (NSInteger)runTrackingWithEvent:(NSEvent *)event { return 0; }
@end
@interface ConfigurePopup : NSPopUpWindow
- (NSPopUpView *)popupView;
@end
@implementation ConfigurePopup
- (void)orderFront:(id)sender {}
- (void)display {}
- (NSPopUpView *)popupView { return _view; }
@end
static void configuredSize(ConfigurePopup *popup, int height) {
    id native = [popup platformWindow];
    union wl_argument args[4] = {{.i=0},{.i=0},{.i=260},{.i=height}};
    [native handleEvent:WP_POPUP_EV_CONFIGURE kind:WaylandObjectPopup proxy:NULL arguments:args];
    // Run production state application without manufacturing a compositor ack serial.
    [native applyConfigure];
    [[native waylandDisplay] runAfterDispatchBlocks];
    NSPopUpView *view = [popup popupView];
    printf("configured%d window%s view%s bounds%s\n", height,
            [NSStringFromSize([popup frame].size) UTF8String],
            [NSStringFromSize([view frame].size) UTF8String],
            [NSStringFromRect([view bounds]) UTF8String]);
    assert([popup frame].size.height == height);
    assert([view frame].size.height == [[popup contentView] bounds].size.height);
    assert([view frame].size.height == height);
    assert(NSContainsRect([view bounds], [view rectForSelectedItem]));
}
int main(void) {
    @autoreleasepool {
        setbuf(stdout,NULL);
        [NSApplication sharedApplication];
        ConfigurePopup *popup = [[ConfigurePopup alloc] initWithFrame:NSMakeRect(100,100,100,20)];
        NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Long"];
        for (NSUInteger i=0; i<400; ++i)
            [menu addItemWithTitle:[NSString stringWithFormat:@"Item %lu",(unsigned long)i]
                    action:NULL keyEquivalent:@""];
        [popup setMenu:menu]; [popup selectItemAtIndex:399];
        NSPopUpView *view = [popup popupView];
        object_setClass(view, [ImmediateViewport class]);
        [popup runTrackingWithEvent:nil];
        configuredSize(popup,400);
        CGFloat shortOffset = NSMinY([view bounds]);
        configuredSize(popup,800);
        assert(NSMinY([view bounds]) < shortOffset);
        [view scrollBy:0];
        CGFloat maximum = NSMinY([view bounds]);
        [view scrollBy:1e6];
        assert(NSMinY([view bounds]) == maximum);
        configuredSize(popup,300);
        [popup release]; [menu release];
        puts("PASS: native popup configure shrinks/grows viewport and clamps offset");
    }
    return 0;
}
