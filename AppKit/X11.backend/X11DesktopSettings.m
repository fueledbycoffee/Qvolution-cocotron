// Copyright (c) 2026 Qvolution contributors. SPDX-License-Identifier: MIT
#import "X11DesktopSettings.h"
#import "X11ThemePalette.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSAppearance.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSScroller.h>
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <stdlib.h>
#include <string.h>

@interface NSApplication (DesktopSettings)
- (void)_desktopSettingsDidChangeFrom:(NSAppearance *)previous;
@end
@interface X11DesktopSettings ()
- (void)processPendingEvents;
- (void)requestState;
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
    // The Info.plist opt-out and the test override are fixed for the process.
    _requiresAqua=[[[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSRequiresAquaSystemAppearance"] boolValue];
    const char *override=getenv("QVOLUTION_APPEARANCE");
    _appearanceOverride=override ? strdup(override) : NULL;
    // setObject:forKey: sends KVO synchronously; the notification covers the
    // other ways a defaults value changes, and arrives asynchronously.
    NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
    [defaults addObserver:self forKeyPath:@"QvolutionFollowSystemAppearance" options:0 context:NULL];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(invalidateAppearance)
        name:NSUserDefaultsDidChangeNotification object:defaults];
    _connection = QVDesktopOpenSessionBus(QV_DESKTOP_BUS_TIMEOUT_MS);
    if (!_connection) return self;
    // Without an error argument AddMatch does not wait for the bus; the
    // ReadAll below flushes both rules ahead of itself.
    dbus_bus_add_match(_connection, "type='signal',sender='org.freedesktop.portal.Desktop',"
        "interface='org.freedesktop.portal.Settings',member='SettingChanged',"
        "path='/org/freedesktop/portal/desktop'", NULL);
    dbus_bus_add_match(_connection, "type='signal',sender='org.freedesktop.DBus',"
        "interface='org.freedesktop.DBus',member='NameOwnerChanged',"
        "path='/org/freedesktop/DBus',arg0='org.freedesktop.portal.Desktop'", NULL);
    DBusError error; dbus_error_init(&error);
    DBusMessage *request=QVDesktopReadRequest(), *reply=NULL;
    if (request) reply=dbus_connection_send_with_reply_and_block(_connection,request,QV_DESKTOP_BUS_TIMEOUT_MS,&error);
    if (request) dbus_message_unref(request);
    dbus_error_free(&error);
    if (reply && QVDesktopReadAll(&initial,reply)) QVDesktopSharedStore(&_shared,&initial);
    // A portal that is slow or not yet running at login is not fatal: keep
    // the connection, ask again without blocking, and again when it appears.
    else if (!reply) [self requestState];
    if (reply) dbus_message_unref(reply);
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
// Asks for the whole state without waiting; processPendingEvents applies the reply.
- (void)requestState {
    DBusMessage *request=QVDesktopReadRequest();
    if (!request) return;
    dbus_uint32_t serial=0;
    if (dbus_connection_send(_connection,request,&serial)) _readAllSerial=serial;
    dbus_message_unref(request);
}
- (void)disconnect {
    if (_source) { CFRunLoopSourceInvalidate(_source); CFRelease(_source); _source=NULL; }
    if (_socket) { CFSocketInvalidate(_socket); CFRelease(_socket); _socket=NULL; }
    if (_connection) { dbus_connection_close(_connection); dbus_connection_unref(_connection); _connection=NULL; }
}
- (void)invalidateAppearance { __atomic_add_fetch(&_appearanceGeneration,1,__ATOMIC_ACQ_REL); }
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    [self invalidateAppearance];
}
- (void)dealloc {
    [[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:@"QvolutionFollowSystemAppearance"];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    free((void *)_appearanceOverride);
    [self disconnect]; pthread_mutex_destroy(&_shared.lock); [super dealloc]; }
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
        int type=dbus_message_get_type(message);
        if (!sender) ;
        else if (type==DBUS_MESSAGE_TYPE_SIGNAL && !dbus_message_get_destination(message)) {
            if (dbus_message_is_signal(message,"org.freedesktop.portal.Settings","SettingChanged"))
                changed |= QVDesktopChanged(&next,message);
            else if (QVDesktopPortalAppeared(message)) [self requestState];
        } else if (_readAllSerial && dbus_message_get_reply_serial(message)==_readAllSerial &&
                   (type==DBUS_MESSAGE_TYPE_METHOD_RETURN || type==DBUS_MESSAGE_TYPE_ERROR)) {
            // The bus forwards only replies to calls this connection made.
            _readAllSerial=0;
            if (type==DBUS_MESSAGE_TYPE_METHOD_RETURN) changed |= QVDesktopReadAll(&next,message);
        }
        dbus_message_unref(message);
    }
    if (!dbus_connection_get_is_connected(_connection)) [self disconnect];
    if (changed) {
        BOOL scrollerStyleChanged=next.overlayScrolling!=_state.overlayScrolling;
        [NSApp willChangeValueForKey:@"effectiveAppearance"];
        QVDesktopSharedStore(&_shared,&next);
        [self invalidateAppearance];
        [NSApp _desktopSettingsDidChangeFrom:previous];
        if (scrollerStyleChanged)
            [[NSNotificationCenter defaultCenter] postNotificationName:NSPreferredScrollerStyleDidChangeNotification object:nil];
    }
    [previous release];
}
// Called for every view on every draw through effectiveAppearance, so the
// defaults lookup runs only after an input changed.
- (NSAppearance *)systemAppearance {
    static NSAppearance *appearances[4];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSAppearanceName names[]={NSAppearanceNameAqua,NSAppearanceNameDarkAqua,
            NSAppearanceNameAccessibilityHighContrastAqua,NSAppearanceNameAccessibilityHighContrastDarkAqua};
        for (unsigned i=0;i<4;i++) appearances[i]=[[NSAppearance appearanceNamed:names[i]] retain];
    });
    uint64_t generation=__atomic_load_n(&_appearanceGeneration,__ATOMIC_ACQUIRE);
    uint64_t cached=__atomic_load_n(&_appearanceCache,__ATOMIC_ACQUIRE);
    if ((cached&7) && cached>>3==generation) return appearances[(cached&7)-1];
    QVDesktopState state; QVDesktopSharedLoad(&_shared,&state);
    unsigned index=QVDesktopAppearance(&state,[[NSUserDefaults standardUserDefaults] boolForKey:@"QvolutionFollowSystemAppearance"],
        _requiresAqua,_appearanceOverride);
    // A store tagged with a generation that was invalidated meanwhile is never used.
    __atomic_store_n(&_appearanceCache,generation<<3|(index+1),__ATOMIC_RELEASE);
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
