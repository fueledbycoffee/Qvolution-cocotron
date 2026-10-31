#import <AppKit/NSAccessibilityCustomAction.h>
#import <AppKit/AppKit.h>
static void useCustomActionTypes(NSAccessibilityCustomAction *action, NSString *name,
                                 BOOL (^handler)(void), id<NSObject> target, SEL selector) {
    action.name = name;
    action.handler = handler;
    action.target = target;
    action.selector = selector;
    (void)[[NSAccessibilityCustomAction alloc] initWithName:name handler:handler];
    (void)[[NSAccessibilityCustomAction alloc] initWithName:name target:target selector:selector];
}

_Static_assert(__builtin_types_compatible_p(__typeof__(((NSAccessibilityCustomAction *)0).name), NSString *), "public NSString name type");
_Static_assert(__builtin_types_compatible_p(__typeof__(((NSAccessibilityCustomAction *)0).handler), BOOL (^)(void)), "public BOOL zero-argument handler type");
_Static_assert(__builtin_types_compatible_p(__typeof__(((NSAccessibilityCustomAction *)0).target), id<NSObject>), "public NSObject-protocol target type");
_Static_assert(__builtin_types_compatible_p(__typeof__(((NSAccessibilityCustomAction *)0).selector), SEL), "public SEL type");
