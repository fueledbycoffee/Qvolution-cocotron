// Copyright (c) 2026 Qvolution contributors. SPDX-License-Identifier: MIT
#import "X11DesktopSettings.h"
#import "X11ThemePalette.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSAppearance.h>
#import <AppKit/NSColor.h>
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>

@interface NSApplication (DesktopSettings)
- (void)_desktopSettingsDidChangeFrom:(NSAppearance *)previous;
@end
@interface X11DesktopSettings ()
- (void)processPendingEvents;
- (void)disconnect;
@end
static void settingsSocket(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
    [(X11DesktopSettings *)info processPendingEvents];
}
@implementation X11DesktopSettings
+ (instancetype)sharedSettings {
    // The first caller can be a drawing thread (a dynamic colour provider or
    // effectiveAppearance) rather than display initialization.
    static X11DesktopSettings *settings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ settings = [[self alloc] init]; });
    return settings;
}
- (instancetype)init {
    if (!(self=[super init])) return nil;
    QVDesktopState initial; QVDesktopStateInit(&initial);
    QVDesktopSharedInit(&_shared,&initial);
    // Avoid libdbus autolaunch (and any display-dependent side effects) without a bus.
    if (!getenv("DBUS_SESSION_BUS_ADDRESS")) return self;
    DBusError error; dbus_error_init(&error);
    _connection = dbus_bus_get_private(DBUS_BUS_SESSION, &error);
    if (dbus_error_is_set(&error)) dbus_error_free(&error);
    if (!_connection) return self;
    dbus_connection_set_exit_on_disconnect(_connection, FALSE);
    dbus_bus_add_match(_connection, "type='signal',sender='org.freedesktop.portal.Desktop',"
        "interface='org.freedesktop.portal.Settings',member='SettingChanged',"
        "path='/org/freedesktop/portal/desktop'", &error);
    if (dbus_error_is_set(&error)) { dbus_error_free(&error); [self disconnect]; return self; }
    DBusMessage *request=QVDesktopReadRequest(), *reply=NULL;
    if (request) reply=dbus_connection_send_with_reply_and_block(_connection,request,300,&error);
    if (request) dbus_message_unref(request);
    if (dbus_error_is_set(&error)) dbus_error_free(&error);
    if (!reply || !dbus_message_has_signature(reply,"a{sa{sv}}")) {
        if (reply) dbus_message_unref(reply);
        [self disconnect]; return self;
    }
    QVDesktopReadAll(&initial,reply); dbus_message_unref(reply);
    QVDesktopSharedStore(&_shared,&initial);
    int fd=-1;
    if (!dbus_connection_get_unix_fd(_connection,&fd)) { [self disconnect]; return self; }
    CFSocketContext context={.info=self};
    _socket=CFSocketCreateWithNative(NULL,fd,kCFSocketReadCallBack,settingsSocket,&context);
    if (!_socket) { [self disconnect]; return self; }
    CFSocketSetSocketFlags(_socket,CFSocketGetSocketFlags(_socket)&~kCFSocketCloseOnInvalidate);
    _source=CFSocketCreateRunLoopSource(NULL,_socket,0);
    if (!_source) { [self disconnect]; return self; }
    CFRunLoopAddSource(CFRunLoopGetMain(),_source,kCFRunLoopCommonModes);
    // send_with_reply_and_block can queue signals while waiting for ReadAll.
    // Drain them on the main loop, which owns every later state change.
    dispatch_async(dispatch_get_main_queue(), ^{ [self processPendingEvents]; });
    return self;
}
- (void)disconnect {
    if (_source) { CFRunLoopSourceInvalidate(_source); CFRelease(_source); _source=NULL; }
    if (_socket) { CFSocketInvalidate(_socket); CFRelease(_socket); _socket=NULL; }
    if (_connection) { dbus_connection_close(_connection); dbus_connection_unref(_connection); _connection=NULL; }
}
- (void)dealloc { [self disconnect]; pthread_mutex_destroy(&_shared.lock); [super dealloc]; }
- (void)processPendingEvents {
    if (!_connection) return;
    NSAppearance *previous=[[NSApp effectiveAppearance] retain];
    BOOL changed=NO;
    // Only this main-thread drain writes the shared state.
    QVDesktopState next; QVDesktopSharedLoad(&_shared,&next);
    dbus_connection_read_write(_connection,0);
    DBusMessage *message;
    while ((message=dbus_connection_pop_message(_connection))) {
        // Only this private connection's authenticated broadcast match is used.
        // Reject unicast messages, which can bypass a bus match rule.
        const char *sender=dbus_message_get_sender(message);
        if (sender && dbus_message_is_signal(message,"org.freedesktop.portal.Settings","SettingChanged")) {
            if (!dbus_message_get_destination(message)) changed |= QVDesktopChanged(&next,message);
        }
        dbus_message_unref(message);
    }
    if (!dbus_connection_get_is_connected(_connection)) [self disconnect];
    if (changed) {
        [NSApp willChangeValueForKey:@"effectiveAppearance"];
        QVDesktopSharedStore(&_shared,&next);
        [NSApp _desktopSettingsDidChangeFrom:previous];
    }
    [previous release];
}
- (NSAppearance *)systemAppearance {
    NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
    QVDesktopState state; QVDesktopSharedLoad(&_shared,&state);
    unsigned index=QVDesktopAppearance(&state,[defaults boolForKey:@"QvolutionFollowSystemAppearance"],
        [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSRequiresAquaSystemAppearance"] boolValue],getenv("QVOLUTION_APPEARANCE"));
    NSAppearanceName names[]={NSAppearanceNameAqua,NSAppearanceNameDarkAqua,
        NSAppearanceNameAccessibilityHighContrastAqua,NSAppearanceNameAccessibilityHighContrastDarkAqua};
    static NSAppearance *appearances[4];
    if (!appearances[index]) appearances[index]=[NSAppearance appearanceNamed:names[index]];
    return appearances[index];
}
- (NSColor *)colorWithName:(NSString *)name appearance:(NSAppearance *)appearance {
    NSString *n=[appearance name];
    BOOL dark=[n isEqualToString:NSAppearanceNameDarkAqua] || [n isEqualToString:NSAppearanceNameVibrantDark] ||
        [n isEqualToString:NSAppearanceNameAccessibilityHighContrastDarkAqua] || [n isEqualToString:NSAppearanceNameAccessibilityHighContrastVibrantDark];
    BOOL high=[n isEqualToString:NSAppearanceNameAccessibilityHighContrastDarkAqua] ||
        [n isEqualToString:NSAppearanceNameAccessibilityHighContrastAqua] || [n isEqualToString:NSAppearanceNameAccessibilityHighContrastVibrantDark] ||
        [n isEqualToString:NSAppearanceNameAccessibilityHighContrastVibrantLight];
    QVDesktopState state; QVDesktopSharedLoad(&_shared,&state);
    QVThemeColor c;
    if (!QVThemeLookup([name UTF8String],dark,high,state.accent,&c)) return nil;
    return [NSColor colorWithSRGBRed:c.r green:c.g blue:c.b alpha:c.a];
}
- (NSString *)fontName {
    QVDesktopState state; QVDesktopSharedLoad(&_shared,&state);
    return state.fontName[0] ? [NSString stringWithUTF8String:state.fontName] : nil;
}
- (double)textScalingFactor { QVDesktopState state; QVDesktopSharedLoad(&_shared,&state); return state.textScale; }
- (BOOL)overlayScrolling { QVDesktopState state; QVDesktopSharedLoad(&_shared,&state); return state.overlayScrolling; }
- (BOOL)reducedMotion { QVDesktopState state; QVDesktopSharedLoad(&_shared,&state); return state.reducedMotion==1; }
@end
