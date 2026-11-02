#ifndef DAMAGE_FIXTURE_APPEARANCE_H
#define DAMAGE_FIXTURE_APPEARANCE_H
#include <objc/runtime.h>
#include "../AppKit/NSTitlebarRenderer.h"

// Only this fixture's verify window has a declared active/key/main appearance.
@interface DamageFixtureWindow : NSWindow { @public BOOL fixedAppearance; }
@end
@implementation DamageFixtureWindow
- (BOOL)isKeyWindow { return fixedAppearance ? YES : [super isKeyWindow]; }
- (BOOL)isMainWindow { return fixedAppearance ? YES : [super isMainWindow]; }
@end

static IMP damageOriginalFrame, damageOriginalTitle;
static Ivar damageActivated;

static NSTitlebarFrame damageFixedFrame(id self, SEL cmd) {
    NSTitlebarFrame frame = ((NSTitlebarFrame (*)(id, SEL))damageOriginalFrame)(self, cmd);
    frame.state.active = true;
    frame.state.hover = false;
    frame.state.pressed = NSTitlebarButtonNone;
    return frame;
}

static void damageFixedTitle(id self, SEL cmd) {
    // drawTitle reads the backend's ivar directly. Restore it so configure still
    // sees the real compositor transition; only the drawing input is fixed.
    BOOL *active = (BOOL *)((char *)self + ivar_getOffset(damageActivated));
    BOOL previous = *active;
    *active = YES;
    @try { ((void (*)(id, SEL))damageOriginalTitle)(self, cmd); }
    @finally { *active = previous; }
}

static BOOL DamageFixtureFixAppearance(id backend) {
    Class parent = object_getClass(backend);
    Method frame = class_getInstanceMethod(parent, sel_registerName("titlebarFrame"));
    Method title = class_getInstanceMethod(parent, sel_registerName("drawTitle"));
    damageActivated = class_getInstanceVariable(parent, "_activated");
    if (!frame || !title || !damageActivated) return NO;
    Class fixed = objc_allocateClassPair(parent, "DamageFixtureBackend", 0);
    if (!fixed) return NO;
    damageOriginalFrame = method_getImplementation(frame);
    damageOriginalTitle = method_getImplementation(title);
    if (!class_addMethod(fixed, sel_registerName("titlebarFrame"), (IMP)damageFixedFrame, method_getTypeEncoding(frame)) ||
        !class_addMethod(fixed, sel_registerName("drawTitle"), (IMP)damageFixedTitle, method_getTypeEncoding(title))) return NO;
    objc_registerClassPair(fixed);
    object_setClass(backend, fixed);
    return YES;
}
#endif
