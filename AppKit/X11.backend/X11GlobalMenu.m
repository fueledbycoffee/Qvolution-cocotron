#import "X11GlobalMenu.h"
#import "X11Display.h"
#import "X11Window.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSWindow-Private.h>
#import <CoreFoundation/CoreFoundation.h>
#include <dbus/dbus.h>
#include <X11/Xatom.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <sys/time.h>
#include <unistd.h>

static const char *orbitText(const char *text) { return text ? text : "(none)"; }

static void orbitDiagnostic(const char *event, const char *format, ...) {
    const char *option = getenv("DARLING_ORBIT_MENU_DIAGNOSTICS");
    if (!option || !*option || strcmp(option, "0") == 0)
        return;
    int savedErrno = errno;
    const char *path = option[0] == '/' ? option : "/tmp/qvolution-orbit-menu.log";
    FILE *file = fopen(path, "a");
    if (file) {
        struct timeval now;
        gettimeofday(&now, NULL);
        fprintf(file, "%ld.%06d pid=%d event=%s ", (long)now.tv_sec, (int)now.tv_usec, getpid(), event);
        va_list args;
        va_start(args, format);
        vfprintf(file, format, args);
        va_end(args);
        fputc('\n', file);
        fclose(file);
    } else {
        perror("Orbit menu diagnostics: cannot open log");
    }
    errno = savedErrno;
}

static X11GlobalMenu *g_sharedGlobalMenu = nil;

// libdbus is a host ELF library called without ABI translation, so its variadic functions
// (dbus_message_append_args) receive Darwin stack-passed varargs where Linux reads registers.
static void appendBasic(DBusMessage *message, int type, const void *value) {
    DBusMessageIter iter;
    dbus_message_iter_init_append(message, &iter);
    dbus_message_iter_append_basic(&iter, type, value);
}

@interface X11GlobalMenu ()
- (void) processPendingDBusEvents;
- (void) updateWaylandMenuPresentation;
- (void) scheduleDBusWrite;
- (void) deferDBusProgressFailure;
- (void) handleDBusDisconnect;
- (void) queryOrbitIntegration: (int) kind;
- (void) receiveOrbitReply: (DBusMessage *) reply kind: (int) kind generation: (unsigned int) generation;
- (DBusHandlerResult) handleDBusMessage: (DBusMessage *) message onConnection: (DBusConnection *) connection;
@end

// GNOME's documented GetExtensionInfo/ExtensionStateChanged vardict: state d=1 is ACTIVE.
static BOOL orbitExtensionIsActive(DBusMessageIter *dictionary) {
    DBusMessageIter entries;
    dbus_message_iter_recurse(dictionary, &entries);
    while (dbus_message_iter_get_arg_type(&entries) == DBUS_TYPE_DICT_ENTRY) {
        DBusMessageIter entry, value;
        const char *key = NULL;
        dbus_message_iter_recurse(&entries, &entry);
        dbus_message_iter_get_basic(&entry, &key);
        dbus_message_iter_next(&entry);
        dbus_message_iter_recurse(&entry, &value);
        if (strcmp(key, "state") == 0)
            orbitDiagnostic("extension-state-type", "type=%d expected=%d", dbus_message_iter_get_arg_type(&value), DBUS_TYPE_DOUBLE);
        if (strcmp(key, "state") == 0 && dbus_message_iter_get_arg_type(&value) == DBUS_TYPE_DOUBLE) {
            double state = 0;
            dbus_message_iter_get_basic(&value, &state);
            orbitDiagnostic("extension-state", "state=%g active=%d", state, state == 1);
            return state == 1;
        }
        dbus_message_iter_next(&entries);
    }
    orbitDiagnostic("extension-state", "active=0 reason=missing-double-state");
    return NO;
}

enum { OrbitOwnerQuery, OrbitShellOwnerQuery, OrbitExtensionQuery, OrbitOwnerWatchQuery, OrbitStateWatchQuery };
typedef struct {
    X11GlobalMenu *exporter;
    int kind;
    unsigned int generation;
} OrbitQuery;

static void orbitQueryReply(DBusPendingCall *pending, void *data) {
    OrbitQuery *query = data;
    DBusMessage *reply = dbus_pending_call_steal_reply(pending);
    [query->exporter receiveOrbitReply: reply kind: query->kind generation: query->generation];
    if (reply) dbus_message_unref(reply);
}

static void orbitQueryFree(void *data) {
    OrbitQuery *query = data;
    [query->exporter release];
    free(query);
}

typedef struct {
    X11GlobalMenu *exporter;
    DBusTimeout *timeout;
    CFRunLoopTimerRef timer;
} OrbitTimeout;

static void orbitTimeoutFree(void *data) {
    OrbitTimeout *context = data;
    if (context->timer) {
        CFRunLoopTimerInvalidate(context->timer);
        CFRelease(context->timer);
    }
    [context->exporter release];
    free(context);
}

// A busy main thread can leave both a reply on the socket and its deadline timer
// due. Read first, so a reply that already arrived completes its pending call and
// removes this timeout; only an unanswered call then becomes NoReply. Removal
// invalidates the timer before freeing the context, so validity is checked on our
// own timer reference before the context is touched again.
static void orbitTimeoutFired(CFRunLoopTimerRef timer, void *data) {
    OrbitTimeout *context = data;
    X11GlobalMenu *exporter = [context->exporter retain];
    CFRetain(timer);
    [exporter processPendingDBusEvents];
    if (CFRunLoopTimerIsValid(timer)) {
        dbus_timeout_handle(context->timeout);
        [exporter processPendingDBusEvents];
    }
    CFRelease(timer);
    [exporter release];
}

static dbus_bool_t orbitAddTimeout(DBusTimeout *timeout, void *data) {
    if (!dbus_timeout_get_enabled(timeout))
        return TRUE;
    OrbitTimeout *context = calloc(1, sizeof(*context));
    if (!context) {
        [(X11GlobalMenu *) data deferDBusProgressFailure];
        return FALSE;
    }
    context->exporter = [(X11GlobalMenu *) data retain];
    context->timeout = timeout;
    CFTimeInterval interval = dbus_timeout_get_interval(timeout) / 1000.0;
    CFRunLoopTimerContext timerContext = { .info = context };
    context->timer = CFRunLoopTimerCreate(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + interval,
        interval, 0, 0, orbitTimeoutFired, &timerContext);
    if (!context->timer) {
        [(X11GlobalMenu *) data deferDBusProgressFailure];
        orbitTimeoutFree(context);
        return FALSE;
    }
    dbus_timeout_set_data(timeout, context, orbitTimeoutFree);
    CFRunLoopAddTimer(CFRunLoopGetMain(), context->timer, kCFRunLoopCommonModes);
    return TRUE;
}

static void orbitRemoveTimeout(DBusTimeout *timeout, void *data) {
    dbus_timeout_set_data(timeout, NULL, NULL);
}

static void orbitToggleTimeout(DBusTimeout *timeout, void *data) {
    orbitRemoveTimeout(timeout, data);
    if (!orbitAddTimeout(timeout, data))
        NSLog(@"Orbit global menu: cannot schedule D-Bus timeout");
}

static void dbusSocketCallback(CFSocketRef s, CFSocketCallBackType type,
                               CFDataRef address, const void *data, void *info) {
    X11GlobalMenu *self = (X11GlobalMenu *)info;
    [self processPendingDBusEvents];
}

static DBusHandlerResult dbusFilterCallback(DBusConnection *connection,
                                            DBusMessage *message,
                                            void *user_data) {
    X11GlobalMenu *self = (X11GlobalMenu *)user_data;
    return [self handleDBusMessage: message onConnection: connection];
}

@implementation X11GlobalMenu

+ (instancetype) sharedGlobalMenu {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        g_sharedGlobalMenu = [[X11GlobalMenu alloc] init];
    });
    return g_sharedGlobalMenu;
}

- (instancetype) init {
    self = [super init];
    if (self) {
        _itemsByID = [NSMutableDictionary new];
        _idByItem = [NSMutableDictionary new];
        _nextID = 1;
        _revision = 1;
        _available = NO;

        const char *dbusAddr = getenv("DBUS_SESSION_BUS_ADDRESS");
        orbitDiagnostic("init", "backend-requested=%s session-address-present=%d disabled-env=%d",
            orbitText(getenv("DARLING_APPKIT_BACKEND")), dbusAddr && *dbusAddr,
            getenv("DARLING_NO_GLOBAL_MENU") != NULL);
        if (!dbusAddr || !*dbusAddr || getenv("DARLING_NO_GLOBAL_MENU") ||
            [[NSUserDefaults standardUserDefaults] boolForKey: @"CocotronNoGlobalMenu"]) {
            orbitDiagnostic("decision", "hide=0 reason=initialization-disabled-or-no-session-address");
            return self;
        }

        DBusError error;
        dbus_error_init(&error);
        _connection = dbus_bus_get(DBUS_BUS_SESSION, &error);
        if (dbus_error_is_set(&error) || !_connection) {
            orbitDiagnostic("session-bus", "connected=0 error=%s", orbitText(error.name));
            orbitDiagnostic("decision", "hide=0 reason=session-bus-unavailable");
            dbus_error_free(&error);
            return self;
        }
        orbitDiagnostic("session-bus", "connected=1 unique=%s", orbitText(dbus_bus_get_unique_name(_connection)));

        dbus_connection_set_exit_on_disconnect(_connection, FALSE);
        if (!dbus_connection_set_timeout_functions(_connection, orbitAddTimeout, orbitRemoveTimeout,
                                                   orbitToggleTimeout, self, NULL)) {
            orbitDiagnostic("progress", "timeout-functions=0 reason=setup-failed");
            orbitDiagnostic("decision", "hide=0 reason=timeout-setup-failed");
            return self;
        }

        // Check if registrar exists
        dbus_bool_t hasRegistrar = dbus_bus_name_has_owner(_connection, "com.canonical.AppMenu.Registrar", &error);
        orbitDiagnostic("registrar", "present=%d error=%s", hasRegistrar, orbitText(error.name));
        if (dbus_error_is_set(&error) || !hasRegistrar) {
            dbus_error_free(&error);
            // Even if registrar isn't explicit, KDE Plasma's gmenudbusmenuproxy accepts X11 window properties!
        }

        int fd = -1;
        if (dbus_connection_get_unix_fd(_connection, &fd) && fd >= 0) {
            CFSocketContext context = {
                .version = 0,
                .info = (void *)[self retain],
                .retain = (const void *(*)(const void *))CFRetain,
                .release = (void (*)(const void *))CFRelease,
                .copyDescription = NULL
            };
            _cfSocket = CFSocketCreateWithNative(kCFAllocatorDefault, fd,
                                                 kCFSocketReadCallBack | kCFSocketWriteCallBack,
                                                 dbusSocketCallback, &context);
            if (_cfSocket) {
                CFSocketDisableCallBacks(_cfSocket, kCFSocketWriteCallBack);
                _runLoopSource = CFSocketCreateRunLoopSource(kCFAllocatorDefault, _cfSocket, 0);
                CFRunLoopAddSource(CFRunLoopGetMain(), _runLoopSource, kCFRunLoopCommonModes);
            }
        }

        static const DBusObjectPathVTable vtable = {
            .message_function = dbusFilterCallback
        };
        BOOL pathRegistered = dbus_connection_try_register_object_path(_connection, "/MenuBar", &vtable, (void *)self, &error);

        BOOL filterAdded = dbus_connection_add_filter(_connection, dbusFilterCallback, (void *)self, NULL);
        orbitDiagnostic("export-path", "registered=%d filter-added=%d error=%s", pathRegistered, filterAdded, orbitText(error.name));
        _orbitProgressFailed = !_cfSocket || !_runLoopSource;
        _available = YES;
        orbitDiagnostic("export-ready", "available=%d socket=%d runloop-source=%d progress-failed=%d",
            _available, _cfSocket != NULL, _runLoopSource != NULL, _orbitProgressFailed);
    }
    return self;
}

- (BOOL) isAvailable {
    return _available;
}

- (BOOL) isEngaged {
    return _globalMenuEngaged;
}

- (void) updateWaylandMenuPresentation {
    BOOL engaged = _available && !_orbitProgressFailed && _orbitOwnerWatchReady && _orbitStateWatchReady &&
        _orbitExtensionActive && _orbitMenuRead && _orbitOwner != nil && _orbitShellOwner != nil;
    const char *reason = !_available ? "export-unavailable" : _orbitProgressFailed ? "progress-failed" :
        !_orbitOwnerWatchReady ? "owner-watch-not-ready" : !_orbitStateWatchReady ? "state-watch-not-ready" :
        !_orbitExtensionActive ? "extension-not-active" : !_orbitMenuRead ? "no-qualified-layout-reply" :
        !_orbitOwner ? "no-orbit-owner" : !_orbitShellOwner ? "no-shell-owner" : "qualified";
    orbitDiagnostic("decision", "hide=%d previous=%d reason=%s available=%d progress-failed=%d owner-watch=%d state-watch=%d extension-active=%d menu-read=%d orbit=%s orbit-generation=%u shell=%s shell-generation=%u",
        engaged, _globalMenuEngaged, reason, _available, _orbitProgressFailed, _orbitOwnerWatchReady,
        _orbitStateWatchReady, _orbitExtensionActive, _orbitMenuRead, orbitText([_orbitOwner UTF8String]),
        _orbitOwnerGeneration, orbitText([_orbitShellOwner UTF8String]), _orbitShellGeneration);
    if (_globalMenuEngaged == engaged)
        return;
    _globalMenuEngaged = engaged;
    NSArray *windows = [[NSApp windows] copy];
    for (NSWindow *window in windows) {
        if (![window isKindOfClass: [NSPanel class]]) {
            if (_globalMenuEngaged)
                [window _hideMenuViewIfNeeded];
            else if (window != [NSApp modalWindow])
                [window _showMenuViewIfNeeded];
        }
    }
    [windows release];
}

- (void) deferDBusProgressFailure {
    orbitDiagnostic("progress", "failed=1 already-failed=%d", _orbitProgressFailed);
    if (_orbitProgressFailed)
        return;
    _orbitProgressFailed = YES;
    NSLog(@"Orbit global menu: D-Bus progress unavailable; keeping local menus");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateWaylandMenuPresentation];
    });
}

- (void) scheduleDBusWrite {
    if (_cfSocket && dbus_connection_has_messages_to_send(_connection))
        CFSocketEnableCallBacks(_cfSocket, kCFSocketWriteCallBack);
}

- (void) handleDBusDisconnect {
    orbitDiagnostic("session-bus", "connected=0 reason=disconnect");
    _available = NO;
    _orbitExtensionActive = NO;
    _orbitMenuRead = NO;
    _orbitOwnerGeneration++;
    _orbitShellGeneration++;
    [_orbitOwner release];
    _orbitOwner = nil;
    [_orbitShellOwner release];
    _orbitShellOwner = nil;
    if (_cfSocket)
        CFSocketDisableCallBacks(_cfSocket, kCFSocketReadCallBack | kCFSocketWriteCallBack);
    [self updateWaylandMenuPresentation];
}

- (void) queryOrbitIntegration: (int) kind {
    const char *destination = kind == OrbitExtensionQuery ? [_orbitShellOwner UTF8String] : DBUS_SERVICE_DBUS;
    if (!destination)
        return;
    orbitDiagnostic("query-request", "kind=%d destination=%s orbit-generation=%u shell-generation=%u",
        kind, destination, _orbitOwnerGeneration, _orbitShellGeneration);
    BOOL watch = kind == OrbitOwnerWatchQuery || kind == OrbitStateWatchQuery;
    DBusMessage *message = dbus_message_new_method_call(destination,
        kind == OrbitExtensionQuery ? "/org/gnome/Shell" : DBUS_PATH_DBUS,
        kind == OrbitExtensionQuery ? "org.gnome.Shell.Extensions" : DBUS_INTERFACE_DBUS,
        watch ? "AddMatch" : (kind == OrbitExtensionQuery ? "GetExtensionInfo" : "GetNameOwner"));
    if (!message) {
        orbitDiagnostic("query-setup", "kind=%d observed=0 reason=message-allocation", kind);
        [self deferDBusProgressFailure];
        return;
    }
    const char *argument = kind == OrbitExtensionQuery ? "global-menu@unmade.space" :
        (kind == OrbitOwnerQuery ? "space.unmade.GlobalMenu" : "org.gnome.Shell");
    if (kind == OrbitOwnerWatchQuery)
        argument = "type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',"
            "member='NameOwnerChanged',path='/org/freedesktop/DBus'";
    else if (kind == OrbitStateWatchQuery)
        argument = "type='signal',sender='org.gnome.Shell',interface='org.gnome.Shell.Extensions',"
            "member='ExtensionStateChanged',path='/org/gnome/Shell',arg0='global-menu@unmade.space'";
    appendBasic(message, DBUS_TYPE_STRING, &argument);
    dbus_message_set_auto_start(message, FALSE);
    DBusPendingCall *pending = NULL;
    BOOL observed = NO;
    if (dbus_connection_send_with_reply(_connection, message, &pending, 1000) && pending) {
        OrbitQuery *query = calloc(1, sizeof(*query));
        if (query) {
            query->exporter = [self retain];
            query->kind = kind;
            query->generation = kind == OrbitOwnerQuery ? _orbitOwnerGeneration : _orbitShellGeneration;
            observed = dbus_pending_call_set_notify(pending, orbitQueryReply, query, orbitQueryFree);
            if (!observed)
                orbitQueryFree(query);
        }
    }
    if (!observed) {
        if (pending)
            dbus_pending_call_cancel(pending);
        [self deferDBusProgressFailure];
    }
    if (pending)
        dbus_pending_call_unref(pending);
    orbitDiagnostic("query-setup", "kind=%d observed=%d serial=%u", kind, observed, dbus_message_get_serial(message));
    dbus_message_unref(message);
    [self scheduleDBusWrite];
}

- (void) receiveOrbitReply: (DBusMessage *) reply kind: (int) kind generation: (unsigned int) generation {
    orbitDiagnostic("query-reply", "kind=%d generation=%u orbit-generation=%u shell-generation=%u sender=%s expected=%s type=%d signature=%s error=%s reply-serial=%u",
        kind, generation, _orbitOwnerGeneration, _orbitShellGeneration,
        orbitText(reply ? dbus_message_get_sender(reply) : NULL),
        orbitText(kind == OrbitExtensionQuery ? [_orbitShellOwner UTF8String] : DBUS_SERVICE_DBUS),
        reply ? dbus_message_get_type(reply) : 0, orbitText(reply ? dbus_message_get_signature(reply) : NULL),
        orbitText(reply ? dbus_message_get_error_name(reply) : NULL), reply ? dbus_message_get_reply_serial(reply) : 0);
    if ((kind == OrbitOwnerQuery && generation != _orbitOwnerGeneration) ||
        ((kind == OrbitShellOwnerQuery || kind == OrbitExtensionQuery) && generation != _orbitShellGeneration)) {
        orbitDiagnostic("query-rejected", "kind=%d reason=stale-generation", kind);
        return;
    }
    const char *sender = kind == OrbitExtensionQuery ? [_orbitShellOwner UTF8String] : DBUS_SERVICE_DBUS;
    BOOL validReply = reply && dbus_message_get_type(reply) == DBUS_MESSAGE_TYPE_METHOD_RETURN &&
        sender && dbus_message_has_sender(reply, sender);
    orbitDiagnostic("query-authentication", "kind=%d valid=%d", kind, validReply);
    if (kind == OrbitOwnerWatchQuery || kind == OrbitStateWatchQuery) {
        BOOL ready = validReply && dbus_message_has_signature(reply, "");
        if (kind == OrbitOwnerWatchQuery)
            _orbitOwnerWatchReady = ready;
        else
            _orbitStateWatchReady = ready;
        unsigned int *retries = kind == OrbitOwnerWatchQuery ? &_orbitOwnerWatchRetries : &_orbitStateWatchRetries;
        if (!ready && *retries < 2) {
            // The window registration that issued this watch may not recur, so
            // retry here instead of leaving the local menu up for the session.
            (*retries)++;
            orbitDiagnostic("watch-retry", "kind=%d attempt=%u", kind, *retries);
            [self queryOrbitIntegration: kind];
        } else if (!ready) {
            _orbitOwnerMatchAdded = NO;
            NSLog(@"Orbit global menu: cannot watch integration changes");
        } else if (*retries) {
            // Changes before a late match were not observed: refresh the snapshot it guards.
            if (kind == OrbitOwnerWatchQuery) {
                _orbitOwnerGeneration++;
                _orbitShellGeneration++;
                [self queryOrbitIntegration: OrbitOwnerQuery];
                [self queryOrbitIntegration: OrbitShellOwnerQuery];
            } else if (_orbitShellOwner) {
                _orbitShellGeneration++;
                [self queryOrbitIntegration: OrbitExtensionQuery];
            }
        }
    } else if (kind == OrbitExtensionQuery) {
        DBusMessageIter dictionary;
        _orbitExtensionActive = validReply && dbus_message_has_signature(reply, "a{sv}") &&
            dbus_message_iter_init(reply, &dictionary) && orbitExtensionIsActive(&dictionary);
        if (!_orbitExtensionActive)
            _orbitMenuRead = NO;
    } else {
        const char *owner = NULL;
        DBusMessageIter iter;
        if (validReply && dbus_message_has_signature(reply, "s") && dbus_message_iter_init(reply, &iter))
            dbus_message_iter_get_basic(&iter, &owner);
        NSString **slot = kind == OrbitOwnerQuery ? &_orbitOwner : &_orbitShellOwner;
        [*slot release];
        *slot = owner ? [[NSString alloc] initWithUTF8String: owner] : nil;
        _orbitMenuRead = NO;
        if (kind == OrbitShellOwnerQuery) {
            _orbitExtensionActive = NO;
            if (_orbitShellOwner)
                [self queryOrbitIntegration: OrbitExtensionQuery];
        }
    }
    [self updateWaylandMenuPresentation];
}

- (void) processPendingDBusEvents {
    if (!_connection)
        return;
    orbitDiagnostic("transport-progress", "phase=begin pending-write=%d", dbus_connection_has_messages_to_send(_connection));
    if (!dbus_connection_read_write(_connection, 0)) {
        [self handleDBusDisconnect];
        return;
    }
    while (dbus_connection_dispatch(_connection) == DBUS_DISPATCH_DATA_REMAINS) {
    }
    if (_cfSocket)
        CFSocketDisableCallBacks(_cfSocket, kCFSocketWriteCallBack);
    [self scheduleDBusWrite];
    orbitDiagnostic("transport-progress", "phase=end pending-write=%d delivery=transport-only-no-peer-ack",
        dbus_connection_has_messages_to_send(_connection));
}

- (int32_t) idForMenuItem: (NSMenuItem *) item {
    NSValue *key = [NSValue valueWithNonretainedObject: item];
    NSNumber *num = [_idByItem objectForKey: key];
    if (!num) {
        int32_t assigned = _nextID++;
        num = @(assigned);
        [_idByItem setObject: num forKey: key];
        [_itemsByID setObject: item forKey: num];
    }
    return [num intValue];
}

- (void) appendPropertiesForItem: (NSMenuItem *) item
                        toIter: (DBusMessageIter *) dictIter {
    DBusMessageIter entryIter, variantIter;

    // label
    const char *keyLabel = "label";
    NSString *rawTitle = [item title];
    if (!rawTitle) rawTitle = @"";
    const char *labelVal = [rawTitle UTF8String];

    dbus_message_iter_open_container(dictIter, DBUS_TYPE_DICT_ENTRY, NULL, &entryIter);
    dbus_message_iter_append_basic(&entryIter, DBUS_TYPE_STRING, &keyLabel);
    dbus_message_iter_open_container(&entryIter, DBUS_TYPE_VARIANT, "s", &variantIter);
    dbus_message_iter_append_basic(&variantIter, DBUS_TYPE_STRING, &labelVal);
    dbus_message_iter_close_container(&entryIter, &variantIter);
    dbus_message_iter_close_container(dictIter, &entryIter);

    // enabled
    const char *keyEnabled = "enabled";
    dbus_bool_t enabledVal = [item isEnabled] ? TRUE : FALSE;
    dbus_message_iter_open_container(dictIter, DBUS_TYPE_DICT_ENTRY, NULL, &entryIter);
    dbus_message_iter_append_basic(&entryIter, DBUS_TYPE_STRING, &keyEnabled);
    dbus_message_iter_open_container(&entryIter, DBUS_TYPE_VARIANT, "b", &variantIter);
    dbus_message_iter_append_basic(&variantIter, DBUS_TYPE_BOOLEAN, &enabledVal);
    dbus_message_iter_close_container(&entryIter, &variantIter);
    dbus_message_iter_close_container(dictIter, &entryIter);

    // visible
    const char *keyVisible = "visible";
    dbus_bool_t visibleVal = ![item isHidden] ? TRUE : FALSE;
    dbus_message_iter_open_container(dictIter, DBUS_TYPE_DICT_ENTRY, NULL, &entryIter);
    dbus_message_iter_append_basic(&entryIter, DBUS_TYPE_STRING, &keyVisible);
    dbus_message_iter_open_container(&entryIter, DBUS_TYPE_VARIANT, "b", &variantIter);
    dbus_message_iter_append_basic(&variantIter, DBUS_TYPE_BOOLEAN, &visibleVal);
    dbus_message_iter_close_container(&entryIter, &variantIter);
    dbus_message_iter_close_container(dictIter, &entryIter);

    // type
    if ([item isSeparatorItem]) {
        const char *keyType = "type";
        const char *typeVal = "separator";
        dbus_message_iter_open_container(dictIter, DBUS_TYPE_DICT_ENTRY, NULL, &entryIter);
        dbus_message_iter_append_basic(&entryIter, DBUS_TYPE_STRING, &keyType);
        dbus_message_iter_open_container(&entryIter, DBUS_TYPE_VARIANT, "s", &variantIter);
        dbus_message_iter_append_basic(&variantIter, DBUS_TYPE_STRING, &typeVal);
        dbus_message_iter_close_container(&entryIter, &variantIter);
        dbus_message_iter_close_container(dictIter, &entryIter);
    }

    // children-display
    if ([item hasSubmenu] && [[[item submenu] itemArray] count] > 0) {
        const char *keyChildrenDisplay = "children-display";
        const char *displayVal = "submenu";
        dbus_message_iter_open_container(dictIter, DBUS_TYPE_DICT_ENTRY, NULL, &entryIter);
        dbus_message_iter_append_basic(&entryIter, DBUS_TYPE_STRING, &keyChildrenDisplay);
        dbus_message_iter_open_container(&entryIter, DBUS_TYPE_VARIANT, "s", &variantIter);
        dbus_message_iter_append_basic(&variantIter, DBUS_TYPE_STRING, &displayVal);
        dbus_message_iter_close_container(&entryIter, &variantIter);
        dbus_message_iter_close_container(dictIter, &entryIter);
    }
}

- (void) appendMenu: (NSMenu *) menu
             asNode: (int32_t) nodeId
             toIter: (DBusMessageIter *) parentIter
              depth: (int32_t) depth {
    DBusMessageIter structIter, dictIter, childrenArrayIter;

    dbus_message_iter_open_container(parentIter, DBUS_TYPE_STRUCT, NULL, &structIter);
    dbus_message_iter_append_basic(&structIter, DBUS_TYPE_INT32, &nodeId);

    // Properties dict
    dbus_message_iter_open_container(&structIter, DBUS_TYPE_ARRAY, "{sv}", &dictIter);
    if (nodeId == 0) {
        // Root properties
        const char *keyDisplay = "children-display";
        const char *valDisplay = "submenu";
        DBusMessageIter eIter, vIter;
        dbus_message_iter_open_container(&dictIter, DBUS_TYPE_DICT_ENTRY, NULL, &eIter);
        dbus_message_iter_append_basic(&eIter, DBUS_TYPE_STRING, &keyDisplay);
        dbus_message_iter_open_container(&eIter, DBUS_TYPE_VARIANT, "s", &vIter);
        dbus_message_iter_append_basic(&vIter, DBUS_TYPE_STRING, &valDisplay);
        dbus_message_iter_close_container(&eIter, &vIter);
        dbus_message_iter_close_container(&dictIter, &eIter);
    } else {
        NSMenuItem *item = [_itemsByID objectForKey: @(nodeId)];
        if (item) {
            [self appendPropertiesForItem: item toIter: &dictIter];
        }
    }
    dbus_message_iter_close_container(&structIter, &dictIter);

    // Children array
    dbus_message_iter_open_container(&structIter, DBUS_TYPE_ARRAY, "v", &childrenArrayIter);
    if (depth != 0 && menu != nil) {
        for (NSMenuItem *child in [menu itemArray]) {
            int32_t childID = [self idForMenuItem: child];
            DBusMessageIter variantChild;
            dbus_message_iter_open_container(&childrenArrayIter, DBUS_TYPE_VARIANT, "(ia{sv}av)", &variantChild);
            NSMenu *childSub = [child hasSubmenu] ? [child submenu] : nil;
            [self appendMenu: childSub asNode: childID toIter: &variantChild depth: (depth > 0 ? depth - 1 : depth)];
            dbus_message_iter_close_container(&childrenArrayIter, &variantChild);
        }
    }
    dbus_message_iter_close_container(&structIter, &childrenArrayIter);

    dbus_message_iter_close_container(parentIter, &structIter);
}

- (DBusHandlerResult) handleDBusMessage: (DBusMessage *) message
                           onConnection: (DBusConnection *) connection {
    const char *member = dbus_message_get_member(message);
    const char *path = dbus_message_get_path(message);
    const char *interface = dbus_message_get_interface(message);

    if (!member) return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;

    if (strcmp(member, "NameOwnerChanged") == 0 || strcmp(member, "ExtensionStateChanged") == 0)
        orbitDiagnostic("integration-signal", "member=%s sender=%s interface=%s path=%s signature=%s orbit-generation=%u shell-generation=%u",
            member, orbitText(dbus_message_get_sender(message)), orbitText(interface), orbitText(path),
            dbus_message_get_signature(message), _orbitOwnerGeneration, _orbitShellGeneration);

    if (dbus_message_is_signal(message, DBUS_INTERFACE_LOCAL, "Disconnected") &&
        path && strcmp(path, DBUS_PATH_LOCAL) == 0) {
        [self handleDBusDisconnect];
        return DBUS_HANDLER_RESULT_HANDLED;
    }

    if (_waylandApplicationMenu && dbus_message_is_signal(message, DBUS_INTERFACE_DBUS, "NameOwnerChanged") &&
        path && strcmp(path, DBUS_PATH_DBUS) == 0 && dbus_message_get_sender(message) &&
        strcmp(dbus_message_get_sender(message), DBUS_SERVICE_DBUS) == 0 &&
        dbus_message_has_signature(message, "sss")) {
        DBusMessageIter iter;
        const char *name = NULL, *newOwner = NULL;
        dbus_message_iter_init(message, &iter);
        dbus_message_iter_get_basic(&iter, &name);
        dbus_message_iter_next(&iter);
        dbus_message_iter_next(&iter);
        dbus_message_iter_get_basic(&iter, &newOwner);
        if (strcmp(name, "space.unmade.GlobalMenu") == 0 || strcmp(name, "org.gnome.Shell") == 0)
            orbitDiagnostic("owner-change", "name=%s new-owner=%s authenticated=1", name, orbitText(newOwner));
        if (strcmp(name, "space.unmade.GlobalMenu") == 0) {
            _orbitOwnerGeneration++;
            [_orbitOwner release];
            _orbitOwner = newOwner && *newOwner ? [[NSString alloc] initWithUTF8String: newOwner] : nil;
            _orbitMenuRead = NO;
            [self updateWaylandMenuPresentation];
            if (_orbitOwner)
                [self registerWaylandApplicationMenu: _currentMenu];
        } else if (strcmp(name, "org.gnome.Shell") == 0) {
            [_orbitShellOwner release];
            _orbitShellOwner = newOwner && *newOwner ? [[NSString alloc] initWithUTF8String: newOwner] : nil;
            _orbitShellGeneration++;
            _orbitExtensionActive = NO;
            _orbitMenuRead = NO;
            [self updateWaylandMenuPresentation];
            if (_orbitShellOwner)
                [self queryOrbitIntegration: OrbitExtensionQuery];
        } else {
            return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
        }
        return DBUS_HANDLER_RESULT_HANDLED;
    }

    if (_waylandApplicationMenu && _orbitShellOwner &&
        dbus_message_is_signal(message, "org.gnome.Shell.Extensions", "ExtensionStateChanged") &&
        dbus_message_has_sender(message, [_orbitShellOwner UTF8String]) &&
        path && strcmp(path, "/org/gnome/Shell") == 0 && dbus_message_has_signature(message, "sa{sv}")) {
        DBusMessageIter iter;
        const char *uuid = NULL;
        dbus_message_iter_init(message, &iter);
        dbus_message_iter_get_basic(&iter, &uuid);
        if (strcmp(uuid, "global-menu@unmade.space") == 0) {
            dbus_message_iter_next(&iter);
            _orbitShellGeneration++;
            _orbitExtensionActive = orbitExtensionIsActive(&iter);
            if (!_orbitExtensionActive)
                _orbitMenuRead = NO;
            [self updateWaylandMenuPresentation];
        }
        return DBUS_HANDLER_RESULT_HANDLED;
    }

    if (strcmp(member, "Introspect") == 0) {
        static const char *kIntrospectXML =
            "<!DOCTYPE node PUBLIC \"-//freedesktop//DTD D-BUS Object Introspection 1.0//EN\"\n"
            "\"http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd\">\n"
            "<node>\n"
            "  <interface name=\"org.freedesktop.DBus.Introspectable\">\n"
            "    <method name=\"Introspect\">\n"
            "      <arg name=\"xml_data\" type=\"s\" direction=\"out\"/>\n"
            "    </method>\n"
            "  </interface>\n"
            "  <interface name=\"org.freedesktop.DBus.Properties\">\n"
            "    <method name=\"Get\">\n"
            "      <arg name=\"interface_name\" type=\"s\" direction=\"in\"/>\n"
            "      <arg name=\"property_name\" type=\"s\" direction=\"in\"/>\n"
            "      <arg name=\"value\" type=\"v\" direction=\"out\"/>\n"
            "    </method>\n"
            "    <method name=\"GetAll\">\n"
            "      <arg name=\"interface_name\" type=\"s\" direction=\"in\"/>\n"
            "      <arg name=\"properties\" type=\"a{sv}\" direction=\"out\"/>\n"
            "    </method>\n"
            "  </interface>\n"
            "  <interface name=\"com.canonical.dbusmenu\">\n"
            "    <property name=\"Version\" type=\"u\" access=\"read\"/>\n"
            "    <property name=\"Status\" type=\"s\" access=\"read\"/>\n"
            "    <method name=\"GetLayout\">\n"
            "      <arg type=\"i\" name=\"parentId\" direction=\"in\"/>\n"
            "      <arg type=\"i\" name=\"recursionDepth\" direction=\"in\"/>\n"
            "      <arg type=\"as\" name=\"propertyNames\" direction=\"in\"/>\n"
            "      <arg type=\"u\" name=\"revision\" direction=\"out\"/>\n"
            "      <arg type=\"(ia{sv}av)\" name=\"layout\" direction=\"out\"/>\n"
            "    </method>\n"
            "    <method name=\"Event\">\n"
            "      <arg type=\"i\" name=\"id\" direction=\"in\"/>\n"
            "      <arg type=\"s\" name=\"eventId\" direction=\"in\"/>\n"
            "      <arg type=\"v\" name=\"data\" direction=\"in\"/>\n"
            "      <arg type=\"u\" name=\"timestamp\" direction=\"in\"/>\n"
            "    </method>\n"
            "    <method name=\"AboutToShow\">\n"
            "      <arg type=\"i\" name=\"id\" direction=\"in\"/>\n"
            "      <arg type=\"b\" name=\"needUpdate\" direction=\"out\"/>\n"
            "    </method>\n"
            "    <signal name=\"LayoutUpdated\">\n"
            "      <arg type=\"u\" name=\"revision\" direction=\"out\"/>\n"
            "      <arg type=\"i\" name=\"parent\" direction=\"out\"/>\n"
            "    </signal>\n"
            "  </interface>\n"
            "</node>\n";

        DBusMessage *reply = dbus_message_new_method_return(message);
        appendBasic(reply, DBUS_TYPE_STRING, &kIntrospectXML);
        dbus_connection_send(connection, reply, NULL);
        dbus_message_unref(reply);
        return DBUS_HANDLER_RESULT_HANDLED;
    } else if (strcmp(member, "GetAll") == 0) {
        DBusMessage *reply = dbus_message_new_method_return(message);
        DBusMessageIter replyIter, dictIter, entryIter, varIter;
        dbus_message_iter_init_append(reply, &replyIter);
        dbus_message_iter_open_container(&replyIter, DBUS_TYPE_ARRAY, "{sv}", &dictIter);

        // Version = 3
        const char *kVer = "Version";
        uint32_t verVal = 3;
        dbus_message_iter_open_container(&dictIter, DBUS_TYPE_DICT_ENTRY, NULL, &entryIter);
        dbus_message_iter_append_basic(&entryIter, DBUS_TYPE_STRING, &kVer);
        dbus_message_iter_open_container(&entryIter, DBUS_TYPE_VARIANT, "u", &varIter);
        dbus_message_iter_append_basic(&varIter, DBUS_TYPE_UINT32, &verVal);
        dbus_message_iter_close_container(&entryIter, &varIter);
        dbus_message_iter_close_container(&dictIter, &entryIter);

        // Status = "normal"
        const char *kStat = "Status";
        const char *statVal = "normal";
        dbus_message_iter_open_container(&dictIter, DBUS_TYPE_DICT_ENTRY, NULL, &entryIter);
        dbus_message_iter_append_basic(&entryIter, DBUS_TYPE_STRING, &kStat);
        dbus_message_iter_open_container(&entryIter, DBUS_TYPE_VARIANT, "s", &varIter);
        dbus_message_iter_append_basic(&varIter, DBUS_TYPE_STRING, &statVal);
        dbus_message_iter_close_container(&entryIter, &varIter);
        dbus_message_iter_close_container(&dictIter, &entryIter);

        dbus_message_iter_close_container(&replyIter, &dictIter);
        dbus_connection_send(connection, reply, NULL);
        dbus_message_unref(reply);
        return DBUS_HANDLER_RESULT_HANDLED;
    }

    if (strcmp(member, "GetLayout") == 0) {
        if (!_waylandApplicationMenu && !_globalMenuEngaged) {
            _globalMenuEngaged = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                for (NSWindow *window in [NSApp windows]) {
                    if (![window isKindOfClass: [NSPanel class]]) {
                        [window _hideMenuViewIfNeeded];
                    }
                }
            });
        }
        int32_t parentId = 0;
        int32_t recursionDepth = -1;
        DBusMessageIter argsIter;
        if (dbus_message_iter_init(message, &argsIter)) {
            if (dbus_message_iter_get_arg_type(&argsIter) == DBUS_TYPE_INT32) {
                dbus_message_iter_get_basic(&argsIter, &parentId);
                dbus_message_iter_next(&argsIter);
            }
            if (dbus_message_iter_get_arg_type(&argsIter) == DBUS_TYPE_INT32) {
                dbus_message_iter_get_basic(&argsIter, &recursionDepth);
            }
        }

        BOOL orbitReadRequest = _waylandApplicationMenu && _orbitOwner && parentId == 0 && recursionDepth != 0 &&
            dbus_message_is_method_call(message, "com.canonical.dbusmenu", "GetLayout") &&
            path && strcmp(path, "/MenuBar") == 0 && dbus_message_has_signature(message, "iias") &&
            dbus_message_has_sender(message, [_orbitOwner UTF8String]);
        orbitDiagnostic("layout-request", "serial=%u sender=%s expected=%s orbit-generation=%u shell-generation=%u wayland=%d owner-present=%d root=%d depth=%d method=%d path=%d signature=%s signature-valid=%d sender-valid=%d qualified=%d",
            dbus_message_get_serial(message), orbitText(dbus_message_get_sender(message)), orbitText([_orbitOwner UTF8String]),
            _orbitOwnerGeneration, _orbitShellGeneration, _waylandApplicationMenu, _orbitOwner != nil, parentId == 0,
            recursionDepth, dbus_message_is_method_call(message, "com.canonical.dbusmenu", "GetLayout"),
            path && strcmp(path, "/MenuBar") == 0, dbus_message_get_signature(message),
            dbus_message_has_signature(message, "iias"), _orbitOwner && dbus_message_has_sender(message, [_orbitOwner UTF8String]),
            orbitReadRequest);
        DBusMessage *reply = dbus_message_new_method_return(message);
        if (!reply) {
            orbitDiagnostic("layout-reply", "request-serial=%u queued=0 reason=allocation-failed qualified-request=%d",
                dbus_message_get_serial(message), orbitReadRequest);
            if (orbitReadRequest) {
                _orbitMenuRead = NO;
                [self updateWaylandMenuPresentation];
            }
            return DBUS_HANDLER_RESULT_NEED_MEMORY;
        }
        DBusMessageIter replyIter;
        dbus_message_iter_init_append(reply, &replyIter);

        dbus_message_iter_append_basic(&replyIter, DBUS_TYPE_UINT32, &_revision);

        NSMenu *targetMenu = _currentMenu;
        if (parentId != 0) {
            NSMenuItem *it = [_itemsByID objectForKey: @(parentId)];
            targetMenu = [it hasSubmenu] ? [it submenu] : nil;
        }

        [self appendMenu: targetMenu asNode: parentId toIter: &replyIter depth: recursionDepth];

        BOOL sent = dbus_connection_send(connection, reply, NULL);
        orbitDiagnostic("layout-reply", "request-serial=%u reply-serial=%u queued=%d signature=%s signature-valid=%d qualified-request=%d pending-write=%d delivery=queue-only",
            dbus_message_get_serial(message), dbus_message_get_serial(reply), sent, dbus_message_get_signature(reply),
            dbus_message_has_signature(reply, "u(ia{sv}av)"), orbitReadRequest, dbus_connection_has_messages_to_send(connection));
        if (orbitReadRequest) {
            _orbitMenuRead = sent && dbus_message_has_signature(reply, "u(ia{sv}av)");
            [self updateWaylandMenuPresentation];
        }

        dbus_message_unref(reply);
        return DBUS_HANDLER_RESULT_HANDLED;
    } else if (strcmp(member, "Event") == 0) {
        int32_t itemId = 0;
        const char *eventId = NULL;
        DBusMessageIter argsIter;
        if (dbus_message_iter_init(message, &argsIter)) {
            if (dbus_message_iter_get_arg_type(&argsIter) == DBUS_TYPE_INT32) {
                dbus_message_iter_get_basic(&argsIter, &itemId);
                dbus_message_iter_next(&argsIter);
            }
            if (dbus_message_iter_get_arg_type(&argsIter) == DBUS_TYPE_STRING) {
                dbus_message_iter_get_basic(&argsIter, &eventId);
            }
        }

        if (eventId && strcmp(eventId, "clicked") == 0) {
            NSMenuItem *clickedItem = [_itemsByID objectForKey: @(itemId)];
            if (clickedItem && [clickedItem action]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [NSApp sendAction: [clickedItem action] to: [clickedItem target] from: clickedItem];
                });
            }
        }

        DBusMessage *reply = dbus_message_new_method_return(message);
        dbus_connection_send(connection, reply, NULL);
        dbus_message_unref(reply);
        return DBUS_HANDLER_RESULT_HANDLED;
    } else if (strcmp(member, "AboutToShow") == 0) {
        DBusMessage *reply = dbus_message_new_method_return(message);
        dbus_bool_t needUpdate = FALSE;
        appendBasic(reply, DBUS_TYPE_BOOLEAN, &needUpdate);
        dbus_connection_send(connection, reply, NULL);
        dbus_message_unref(reply);
        return DBUS_HANDLER_RESULT_HANDLED;
    }

    return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
}

- (void) dealloc {
    if (_runLoopSource) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _runLoopSource, kCFRunLoopCommonModes);
        CFRelease(_runLoopSource);
    }
    if (_cfSocket) {
        CFSocketInvalidate(_cfSocket);
        CFRelease(_cfSocket);
    }
    if (_connection) {
        dbus_connection_unref(_connection);
    }
    [_itemsByID release];
    [_idByItem release];
    [_currentMenu release];
    [_orbitOwner release];
    [_orbitShellOwner release];
    [super dealloc];
}

- (void) updateMenu: (NSMenu *) menu {
    if (_currentMenu != menu) {
        [_currentMenu release];
        _currentMenu = [menu retain];
    }
    _revision++;
    if (!_connection || !_available)
        return;

    // Send LayoutUpdated signal
    DBusMessage *sig = dbus_message_new_signal("/MenuBar", "com.canonical.dbusmenu", "LayoutUpdated");
    if (sig) {
        int32_t rootId = 0;
        appendBasic(sig, DBUS_TYPE_UINT32, &_revision);
        appendBasic(sig, DBUS_TYPE_INT32, &rootId);
        dbus_connection_send(_connection, sig, NULL);
        dbus_message_unref(sig);
        [self scheduleDBusWrite];
    }
}

// Orbit resolves this connection's host PID through the bus daemon. No X11 ID is sent.
- (void) registerWaylandApplicationMenu: (NSMenu *) menu {
    orbitDiagnostic("backend-detected", "backend=wayland available=%d connection=%d", _available, _connection != NULL);
    _waylandApplicationMenu = YES;
    if (!_available || !_connection)
        return;
    [self updateMenu: menu];
    if (!_orbitOwnerMatchAdded) {
        _orbitOwnerMatchAdded = YES;
        _orbitOwnerWatchRetries = 0;
        _orbitStateWatchRetries = 0;
        _orbitOwnerWatchReady = NO;
        _orbitStateWatchReady = NO;
        [self queryOrbitIntegration: OrbitOwnerWatchQuery];
        [self queryOrbitIntegration: OrbitStateWatchQuery];
        [self queryOrbitIntegration: OrbitOwnerQuery];
        [self queryOrbitIntegration: OrbitShellOwnerQuery];
    }
    DBusMessage *message = dbus_message_new_method_call("space.unmade.GlobalMenu",
        "/space/unmade/GlobalMenu", "space.unmade.GlobalMenu", "RegisterWaylandMenu");
    if (message) {
        const char *path = "/MenuBar";
        appendBasic(message, DBUS_TYPE_OBJECT_PATH, &path);
        dbus_message_set_no_reply(message, TRUE);
        BOOL sent = dbus_connection_send(_connection, message, NULL);
        orbitDiagnostic("wayland-registration", "destination=space.unmade.GlobalMenu queued=%d serial=%u no-reply=1 orbit-generation=%u",
            sent, dbus_message_get_serial(message), _orbitOwnerGeneration);
        dbus_message_unref(message);
        [self scheduleDBusWrite];
    }
    // This is the user-selected duplicate-menu policy, not a presentation acknowledgement.
    [self updateWaylandMenuPresentation];
}

- (void) registerWindow: (Window) x11Window forMenu: (NSMenu *) menu {
    orbitDiagnostic("backend-detected", "backend=x11 available=%d connection=%d", _available, _connection != NULL);
    if (!_available || !_connection)
        return;

    [self updateMenu: menu];

    const char *serviceName = dbus_bus_get_unique_name(_connection);
    if (!serviceName)
        return;

    Display *dpy = [(X11Display *)[NSDisplay currentDisplay] display];
    if (!dpy || !x11Window)
        return;

    Atom serviceAtom = XInternAtom(dpy, "_KDE_NET_WM_APPMENU_SERVICE_NAME", False);
    Atom pathAtom = XInternAtom(dpy, "_KDE_NET_WM_APPMENU_OBJECT_PATH", False);
    Atom utf8Atom = XInternAtom(dpy, "UTF8_STRING", False);

    const char *objPath = "/MenuBar";

    XChangeProperty(dpy, x11Window, serviceAtom, utf8Atom, 8, PropModeReplace,
                    (const unsigned char *)serviceName, strlen(serviceName));
    XChangeProperty(dpy, x11Window, pathAtom, utf8Atom, 8, PropModeReplace,
                    (const unsigned char *)objPath, strlen(objPath));

    // Also call RegisterWindow on com.canonical.AppMenu.Registrar
    DBusMessage *msg = dbus_message_new_method_call("com.canonical.AppMenu.Registrar",
                                                    "/com/canonical/AppMenu/Registrar",
                                                    "com.canonical.AppMenu.Registrar",
                                                    "RegisterWindow");
    if (msg) {
        uint32_t winId = (uint32_t)x11Window;
        appendBasic(msg, DBUS_TYPE_UINT32, &winId);
        appendBasic(msg, DBUS_TYPE_OBJECT_PATH, &objPath);
        dbus_connection_send(_connection, msg, NULL);
        dbus_message_unref(msg);
        [self scheduleDBusWrite];
    }
}

- (void) unregisterWindow: (Window) x11Window {
    if (!_available || !_connection)
        return;

    const char *objPath = "/MenuBar";
    DBusMessage *msg = dbus_message_new_method_call("com.canonical.AppMenu.Registrar",
                                                    "/com/canonical/AppMenu/Registrar",
                                                    "com.canonical.AppMenu.Registrar",
                                                    "UnregisterWindow");
    if (msg) {
        uint32_t winId = (uint32_t)x11Window;
        appendBasic(msg, DBUS_TYPE_UINT32, &winId);
        dbus_connection_send(_connection, msg, NULL);
        dbus_message_unref(msg);
        [self scheduleDBusWrite];
    }
}

@end
