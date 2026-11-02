#include <objc/runtime.h>
#include <assert.h>
#include <stdio.h>
#include "../AppKit/NSTitlebarRenderer.h"

__attribute__((objc_root_class))
@interface NSWindow { Class isa; }
- (BOOL)isKeyWindow;
- (BOOL)isMainWindow;
@end
@implementation NSWindow
- (BOOL)isKeyWindow { return NO; }
- (BOOL)isMainWindow { return NO; }
@end

@interface FixtureBackend : NSWindow {
@public BOOL _activated, titleWasActive, hover;
    NSTitlebarButton pressed;
    unsigned titleDraws;
}
- (NSTitlebarFrame)titlebarFrame;
- (void)drawTitle;
@end
@implementation FixtureBackend
- (NSTitlebarFrame)titlebarFrame {
    NSTitlebarFrame frame = {.width = 1600, .height = 950};
    frame.state.active = _activated;
    frame.state.hover = hover;
    frame.state.pressed = pressed;
    return frame;
}
- (void)drawTitle { titleWasActive = _activated; titleDraws++; }
@end

#ifndef DAMAGE_APPEARANCE_HEADER
#define DAMAGE_APPEARANCE_HEADER "damage-fixture-appearance.h"
#endif
#include DAMAGE_APPEARANCE_HEADER

int main(void) {
    DamageFixtureWindow *window = class_createInstance(objc_getClass("DamageFixtureWindow"), 0);
    assert(![window isKeyWindow] && ![window isMainWindow]);
    window->fixedAppearance = YES;
    FixtureBackend *backend = class_createInstance(objc_getClass("FixtureBackend"), 0);
    FixtureBackend *other = class_createInstance(objc_getClass("FixtureBackend"), 0);
    assert(![backend titlebarFrame].state.active);
    assert(DamageFixtureFixAppearance(backend));
    // Repeated compositor activation loss must change neither chrome nor title
    // input, and must leave the original state available to configure handling.
    for (unsigned i = 0; i < 100; i++) {
        backend->_activated = i % 2;
        backend->hover = YES;
        backend->pressed = NSTitlebarButtonClose;
        NSTitlebarFrame frame = [backend titlebarFrame];
        assert(frame.width == 1600 && frame.height == 950);
        assert(frame.state.active && !frame.state.hover && frame.state.pressed == NSTitlebarButtonNone);
        [backend drawTitle];
        assert(backend->titleWasActive && backend->_activated == i % 2);
        assert([window isKeyWindow] && [window isMainWindow]);
        assert(![other titlebarFrame].state.active);
    }
    assert(backend->titleDraws == 100);
    assert(!DamageFixtureFixAppearance(other)); // no global replacement/reinstall
    object_dispose(other); object_dispose(backend); object_dispose(window);
    puts("PASS fixed key/main, frame and title appearance through 100 focus transitions; compositor state and other instances preserved");
}
