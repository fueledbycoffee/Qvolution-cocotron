/* Exercise the actual fake service with a prequeued bus signal and Read call.
 * Only connection I/O is mocked; messages/variants use the real libdbus API. */
#define main policyMain
#include "ui-font-policy-native.c"
#undef main

static DBusMessage *queued[2];
static unsigned consumed;
static int replied;
static DBusConnection *connection = (DBusConnection *)&queued;

DBusConnection *__wrap_dbus_bus_get_private(DBusBusType type, DBusError *error) {
    assert(type == DBUS_BUS_SESSION); (void)error; return connection;
}
void __wrap_dbus_connection_set_exit_on_disconnect(DBusConnection *bus, dbus_bool_t value) {
    assert(bus == connection && !value);
}
int __wrap_dbus_bus_request_name(DBusConnection *bus, const char *name, unsigned flags, DBusError *error) {
    assert(bus == connection && !strcmp(name, "org.freedesktop.portal.Desktop") && !flags);
    (void)error; return DBUS_REQUEST_NAME_REPLY_PRIMARY_OWNER;
}
DBusMessage *__wrap_dbus_connection_pop_message(DBusConnection *bus) {
    assert(bus == connection);
    return consumed < 2 ? queued[consumed++] : NULL;
}
dbus_bool_t __wrap_dbus_connection_read_write(DBusConnection *bus, int timeout) {
    assert(bus == connection && timeout == 1000);
    /* A blocking wait with queued messages recreates the host timeout. */
    assert(consumed == 2 && "fake portal must drain queued messages before waiting");
    return FALSE;
}
dbus_bool_t __wrap_dbus_connection_send(DBusConnection *bus, DBusMessage *reply, dbus_uint32_t *serial) {
    assert(bus == connection && !serial && consumed == 2);
    char *text = O2UIFontDescriptionFromReply(reply);
    assert(text && !strcmp(text, "Inter Bold 11")); free(text);
    replied = 1; return TRUE;
}
void __wrap_dbus_connection_flush(DBusConnection *bus) { assert(bus == connection && replied); }
void __wrap_dbus_connection_close(DBusConnection *bus) { assert(bus == connection && replied); }
void __wrap_dbus_connection_unref(DBusConnection *bus) {
    assert(bus == connection && replied);
    puts("PASS fake portal drains queued NameAcquired and Read before blocking (mock connection I/O)");
    fflush(stdout);
}
int main(void) {
    queued[0] = dbus_message_new_signal("/org/freedesktop/DBus", "org.freedesktop.DBus", "NameAcquired");
    queued[1] = dbus_message_new_method_call("org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop", "org.freedesktop.portal.Settings", "Read");
    assert(queued[0] && queued[1]);
    dbus_message_set_serial(queued[1], 1);
    DBusMessageIter args; dbus_message_iter_init_append(queued[1], &args);
    const char *space = "org.gnome.desktop.interface", *key = "font-name";
    assert(dbus_message_iter_append_basic(&args, DBUS_TYPE_STRING, &space));
    assert(dbus_message_iter_append_basic(&args, DBUS_TYPE_STRING, &key));
    int ready = open("/dev/null", O_WRONLY); assert(ready >= 0);
    fakePortal(ready, "Inter Bold 11", 1, 0, 0);
    return 1;
}
