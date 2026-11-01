#!/usr/bin/env python3
"""Run NSWindow's production title methods with native Objective-C dispatch.

Only Foundation strings, the platform window, menu and display are doubles.
No Apple binary, display, container or network is used. --source accepts an
older NSWindow.m for the negative control (each recursive getter exits at 4).
"""
from pathlib import Path
import argparse
import os
import re
import shlex
import subprocess
import tempfile

assert os.environ.get("QV_SLOT", "").startswith("build-"), "run via dashboard/qv-slot build"
root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source", type=Path, default=root / "AppKit/NSWindow.m")
args = parser.parse_args()
source = args.source.read_text()
signatures = [
    "- (void) _updatePlatformWindowTitle {",
    "- (void) _createPlatformWindowOnMainThread {",
    "- (BOOL) _isApplicationWindow {",
    "- (void) setTitle: (NSString *) title {",
    "- (void) setMiniwindowTitle: (NSString *) title {",
    "- (void) setDocumentEdited: (BOOL) flag {",
    "- (NSString *) title {",
    "- (NSString *) miniwindowTitle {",
    "- (BOOL) isMiniaturized {",
    "- (BOOL) isVisible {",
    "- (BOOL) isExcludedFromWindowsMenu {",
    "- (void) platformWindowMiniaturized: (CGWindow *) window {",
    "- (void) platformWindowDeminiaturized: (CGWindow *) window {",
]
methods = "\n".join(re.search(re.escape(s) + r".*?^}", source, re.M | re.S).group()
                    for s in signatures)
program = r'''
#include <objc/objc.h>
#include <objc/runtime.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
__attribute__((objc_root_class)) @interface Root { Class isa; }
+ (id)new; + (Class)class; - (id)retain; - (void)release;
- (BOOL)isKindOfClass:(Class)c;
@end
@implementation Root
+ (id)new { return class_createInstance(self, 0); }
+ (Class)class { return self; }
- (id)retain { return self; } - (void)release {}
- (BOOL)isKindOfClass:(Class)c {
    for (Class k = object_getClass(self); k; k = class_getSuperclass(k))
        if (k == c) return YES;
    return NO;
}
@end
// The constant-string ABI is the host GNU runtime's; no Foundation is linked.
@interface NSString : Root { @public const char *bytes; unsigned length; }
- (NSString *)copy; - (NSString *)stringByAppendingString:(NSString *)s;
@end
static NSString *string(const char *s) {
    NSString *v = [NSString new]; v->bytes = strdup(s); v->length = strlen(s); return v;
}
@implementation NSString
- (NSString *)copy { return string(bytes); }
- (NSString *)stringByAppendingString:(NSString *)s {
    assert(s); char *joined = malloc(length + s->length + 1);
    strcpy(joined, bytes); strcat(joined, s->bytes);
    NSString *v = string(joined); free(joined); return v;
}
@end
@interface CGWindow : Root { @public BOOL mini; NSString *shown; unsigned updates; }
- (BOOL)isMiniaturized; - (void)setTitle:(NSString *)title;
@end
@implementation CGWindow
- (BOOL)isMiniaturized { return mini; }
- (void)setTitle:(NSString *)title { shown = [title copy]; updates++; }
@end
@interface Background : Root { @public unsigned redraws; }
- (void)setNeedsDisplay:(BOOL)flag;
@end
@implementation Background
- (void)setNeedsDisplay:(BOOL)flag { assert(flag); redraws++; }
@end
@interface App : Root { @public NSString *menuTitle; unsigned changes; }
- (void)changeWindowsItem:(id)window title:(NSString *)title filename:(BOOL)filename;
- (void)updateWindows;
@end
@implementation App
- (void)changeWindowsItem:(id)window title:(NSString *)title filename:(BOOL)filename {
    assert(window && !filename); menuTitle = [title copy]; changes++;
}
- (void)updateWindows {}
@end
static App *NSApp;
static CGWindow *nextPlatform;
@interface NSDisplay : Root
+ (id)currentDisplay; - (CGWindow *)newWindowWithDelegate:(id)delegate;
@end
@implementation NSDisplay
+ (id)currentDisplay { return [self new]; }
- (CGWindow *)newWindowWithDelegate:(id)delegate { assert(delegate); return nextPlatform; }
@end
@interface NSDraggingManager : Root
+ (id)draggingManager; - (void)registerWindow:(id)window dragTypes:(id)types;
@end
@implementation NSDraggingManager
+ (id)draggingManager { return [self new]; }
- (void)registerWindow:(id)window dragTypes:(id)types { assert(window && !types); }
@end
enum { NSWindowAbove = 1, NSWindowOut = 0 };
#define NSWindowDidMiniaturizeNotification @"miniaturized"
#define NSWindowDidDeminiaturizeNotification @"deminiaturized"
@interface NSWindow : Root {
@public NSString *_title, *_miniwindowTitle; CGWindow *_platformWindow;
    Background *_backgroundView;
    BOOL _isDocumentEdited, _isVisible, _excludedFromWindowsMenu, _isActive;
    id _sheetContext, _childWindows, _drawers;
}
- (void)_updatePlatformWindowTitle; - (void)_createPlatformWindowOnMainThread;
- (BOOL)_isApplicationWindow;
- (void)setTitle:(NSString *)title; - (void)setMiniwindowTitle:(NSString *)title;
- (void)setDocumentEdited:(BOOL)flag;
- (NSString *)title; - (NSString *)miniwindowTitle;
- (BOOL)isMiniaturized; - (BOOL)isVisible; - (BOOL)isExcludedFromWindowsMenu;
- (void)platformWindowMiniaturized:(CGWindow *)window;
- (void)platformWindowDeminiaturized:(CGWindow *)window;
- (BOOL)isKeyWindow; - (BOOL)isMainWindow; - (long)windowNumber;
- (void)postNotificationName:(NSString *)name;
@end
@interface NSPanel : NSWindow @end
@implementation NSPanel @end
@implementation NSWindow
/* PRODUCTION */
- (BOOL)isKeyWindow { return NO; } - (BOOL)isMainWindow { return NO; }
- (long)windowNumber { return 1; }
- (void)postNotificationName:(NSString *)name { assert(name); }
@end
static unsigned depth, getterCalls;
static void enterGetter(const char *name) {
    getterCalls++;
    if (++depth > 3) {
        fprintf(stderr, "FAIL recursive -%s reached depth %u\n", name, depth);
        exit(1);
    }
}
/* SUBCLASSES */
static void equal(NSString *actual, const char *expected) {
    assert(actual && !strcmp(actual->bytes, expected));
}
int main(int argc, char **argv) {
    assert(argc == 2);
    NSApp = [App new];
    NSWindow *w = [(id)objc_getClass(argv[1]) new]; assert(w);
    CGWindow *platform = [CGWindow new];
    w->_platformWindow = platform; w->_backgroundView = [Background new];
    w->_isVisible = YES;
    [w setTitle:@"normal"];
    equal(w->_title, "normal"); equal(w->_miniwindowTitle, "normal");
    equal(platform->shown, "normal"); equal(NSApp->menuTitle, "normal");
    assert(w->_title != w->_miniwindowTitle && NSApp->changes == 1);
    [w setMiniwindowTitle:@"mini"];
    equal(platform->shown, "normal"); equal(NSApp->menuTitle, "normal");
    [w setDocumentEdited:YES]; equal(platform->shown, "* normal");
    platform->mini = YES;
    [w platformWindowMiniaturized:platform]; equal(platform->shown, "* mini");
    [w setMiniwindowTitle:@"small"]; equal(platform->shown, "* small");
    [w setDocumentEdited:NO]; equal(platform->shown, "small");
    [w setTitle:@"renamed"];
    equal(platform->shown, "renamed"); equal(NSApp->menuTitle, "renamed");
    equal(w->_miniwindowTitle, "renamed");
    [w setMiniwindowTitle:@"icon"];
    platform->mini = NO;
    [w platformWindowDeminiaturized:platform]; equal(platform->shown, "renamed");
    w->_platformWindow = nil; nextPlatform = platform;
    unsigned updates = platform->updates;
    [w _createPlatformWindowOnMainThread];
    assert(w->_platformWindow == platform && platform->updates == updates + 1);
    equal(platform->shown, "renamed");
    [w _createPlatformWindowOnMainThread]; assert(platform->updates == updates + 1);
    unsigned changes = NSApp->changes;
    w->_isVisible = NO; [w setTitle:@"hidden"]; assert(NSApp->changes == changes);
    w->_isVisible = YES; w->_excludedFromWindowsMenu = YES;
    [w setTitle:@"excluded"]; assert(NSApp->changes == changes);
    w->_excludedFromWindowsMenu = NO;
    [w setTitle:@"visible"]; equal(NSApp->menuTitle, "visible");
    NSPanel *panel = [NSPanel new]; panel->_isVisible = YES;
    changes = NSApp->changes; [panel setTitle:@"panel"]; assert(NSApp->changes == changes);
    // A deferred window has no backend; this must not query an NSWindow getter.
    w->_platformWindow = nil; [w setTitle:@"deferred"];
    assert(!getterCalls && !depth);
    // Public getters still dispatch to the subclass. Their setter call now ends.
    if (!strcmp(argv[1], "TitleWindow")) (void)[w title];
    if (!strcmp(argv[1], "MiniTitleWindow")) (void)[w miniwindowTitle];
    if (!strcmp(argv[1], "MiniStateWindow")) (void)[w isMiniaturized];
    if (!strcmp(argv[1], "VisibleWindow")) (void)[w isVisible];
    if (!strcmp(argv[1], "ExcludedWindow")) (void)[w isExcludedFromWindowsMenu];
    assert(getterCalls == (strcmp(argv[1], "NSWindow") != 0) && !depth);
    printf("PASS %s: title setters, menu, edited/mini state, creation, callbacks, public dispatch\n", argv[1]);
}
'''.replace("/* PRODUCTION */", methods)
getters = [
    ("TitleWindow", "NSString *", "title"),
    ("MiniTitleWindow", "NSString *", "miniwindowTitle"),
    ("MiniStateWindow", "BOOL", "isMiniaturized"),
    ("VisibleWindow", "BOOL", "isVisible"),
    ("ExcludedWindow", "BOOL", "isExcludedFromWindowsMenu"),
]
subclasses = "\n".join(f'''
@interface {name} : NSWindow @end
@implementation {name}
- ({kind}){getter} {{
    enterGetter("{getter}");
    [self setTitle:@"from getter"];
    {kind} result = [super {getter}];
    depth--; return result;
}}
@end
''' for name, kind, getter in getters)
program = program.replace("/* SUBCLASSES */", subclasses)
include = subprocess.check_output(["gcc", "-print-file-name=include"], text=True).strip()
failures = 0
with tempfile.TemporaryDirectory(prefix="window-title-native-") as directory:
    directory = Path(directory)
    fixture = directory / "test.m"
    binary = directory / "test"
    fixture.write_text(program)
    for opt in ("-O0", "-O2"):
        command = ["clang", opt, "-g", "-fobjc-runtime=gcc", "-fconstant-string-class=NSString",
                   "-Wno-objc-method-access", "-I" + include, "-fsanitize=address,undefined",
                   str(fixture), "-lobjc", "-o", str(binary)]
        print("BUILD", shlex.join(command), flush=True)
        subprocess.run(command, check=True)
        for name in ["NSWindow", *(g[0] for g in getters)]:
            print("RUN", opt, name, flush=True)
            result = subprocess.run([str(binary), name], env={**os.environ,
                "ASAN_OPTIONS": "detect_leaks=0", "UBSAN_OPTIONS": "halt_on_error=1"})
            failures += result.returncode != 0
print(f"RESULT source={args.source} failed={failures}/12", flush=True)
raise SystemExit(bool(failures))
