#import <AppKit/AppKit.h>
#include <dbus/dbus.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

@interface NSObject (OrbitMenuBackend)
- (BOOL)isAvailable;
- (BOOL)isEngaged;
- (void)registerWaylandApplicationMenu:(NSMenu *)menu;
- (void)processPendingDBusEvents;
- (DBusHandlerResult)handleDBusMessage:(DBusMessage *)message onConnection:(DBusConnection *)connection;
@end

static void appendBasic(DBusMessage *message, int type, const void *value) {
    DBusMessageIter iter;
    dbus_message_iter_init_append(message, &iter);
    dbus_message_iter_append_basic(&iter, type, value);
}

static BOOL receiveRegistration(DBusConnection *receiver, id exporter, const char *sender) {
    struct timespec start, now;
    clock_gettime(CLOCK_MONOTONIC, &start);
    do {
        [exporter processPendingDBusEvents];
        dbus_connection_read_write(receiver, 10);
        DBusMessage *message = dbus_connection_pop_message(receiver);
        if (message) {
            BOOL registration = dbus_message_is_method_call(message, "space.unmade.GlobalMenu", "RegisterWaylandMenu");
            if (registration) {
                const char *path = NULL;
                DBusMessageIter iter;
                BOOL valid = dbus_message_has_signature(message, "o") &&
                    strcmp(dbus_message_get_path(message), "/space/unmade/GlobalMenu") == 0 &&
                    strcmp(dbus_message_get_sender(message), sender) == 0 &&
                    dbus_message_get_no_reply(message);
                if (dbus_message_iter_init(message, &iter) && dbus_message_iter_get_arg_type(&iter) == DBUS_TYPE_OBJECT_PATH)
                    dbus_message_iter_get_basic(&iter, &path);
                valid = valid && path && strcmp(path, "/MenuBar") == 0;
                dbus_message_unref(message);
                return valid;
            }
            dbus_message_unref(message);
        }
        clock_gettime(CLOCK_MONOTONIC, &now);
    } while (now.tv_sec - start.tv_sec < 3);
    return NO;
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    DBusError error;
    dbus_error_init(&error);
    if (!getenv("DBUS_SESSION_BUS_ADDRESS")) { fprintf(stderr,"FAIL: isolated session bus required\n"); return 2; }
    DBusConnection *receiver = dbus_bus_get_private(DBUS_BUS_SESSION, &error);
    DBusConnection *emitter = dbus_bus_get(DBUS_BUS_SESSION, &error);
    if (!receiver || !emitter || dbus_error_is_set(&error)) { fprintf(stderr,"FAIL: session connections\n"); return 1; }
    dbus_connection_set_exit_on_disconnect(receiver, FALSE);
    int claimed = dbus_bus_request_name(receiver, "space.unmade.GlobalMenu", DBUS_NAME_FLAG_DO_NOT_QUEUE, &error);
    if (claimed != DBUS_REQUEST_NAME_REPLY_PRIMARY_OWNER) { fprintf(stderr,"FAIL: require a private bus without Orbit\n"); return 1; }
    [NSApplication sharedApplication];
    id exporter = [NSClassFromString(@"X11GlobalMenu") performSelector:@selector(sharedGlobalMenu)];
    if (![exporter respondsToSelector:@selector(registerWaylandApplicationMenu:)]) {
        fprintf(stderr,"FAIL: native Wayland Orbit registration is missing\n"); return 1;
    }
    if (![exporter isAvailable]) { fprintf(stderr,"FAIL: exporter unavailable\n"); return 1; }
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Orbit fixture"];
    [menu addItemWithTitle:@"Fixture" action:NULL keyEquivalent:@""];
    [exporter registerWaylandApplicationMenu:menu];
    const char *sender = dbus_bus_get_unique_name(emitter);
    if (!receiveRegistration(receiver, exporter, sender)) { fprintf(stderr,"FAIL: native registration wire message\n"); return 1; }

    DBusMessage *request = dbus_message_new_method_call(sender, "/MenuBar", "com.canonical.dbusmenu", "GetLayout");
    dbus_message_set_serial(request, 1);
    dbus_message_set_sender(request, dbus_bus_get_unique_name(receiver));
    int32_t root = 0;
    appendBasic(request, DBUS_TYPE_INT32, &root);
    int32_t depth = -1;
    appendBasic(request, DBUS_TYPE_INT32, &depth);
    DBusMessageIter args, properties;
    dbus_message_iter_init_append(request, &args);
    dbus_message_iter_open_container(&args, DBUS_TYPE_ARRAY, "s", &properties);
    dbus_message_iter_close_container(&args, &properties);
    [exporter handleDBusMessage:request onConnection:emitter];
    dbus_message_unref(request);
    if ([exporter isEngaged]) { fprintf(stderr,"FAIL: reading native layout must not hide local menus without acknowledgement\n"); return 1; }

    dbus_bus_release_name(receiver, "space.unmade.GlobalMenu", &error);
    [exporter processPendingDBusEvents];
    claimed = dbus_bus_request_name(receiver, "space.unmade.GlobalMenu", DBUS_NAME_FLAG_DO_NOT_QUEUE, &error);
    if (claimed != DBUS_REQUEST_NAME_REPLY_PRIMARY_OWNER || !receiveRegistration(receiver, exporter, sender)) {
        fprintf(stderr,"FAIL: Orbit owner restart must trigger registration\n"); return 1;
    }
    if ([exporter isEngaged]) { fprintf(stderr,"FAIL: restart must retain local-menu fallback\n"); return 1; }
    dbus_connection_close(receiver);
    dbus_connection_unref(receiver);
    dbus_connection_unref(emitter);
    [menu release];
    [pool drain];
    puts("PASS: native Orbit registration, no-XID wire data, local-menu fallback and daemon restart");
    return 0;
}
