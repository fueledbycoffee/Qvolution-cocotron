// Copyright (c) 2026 Qvolution contributors. SPDX-License-Identifier: MIT
#include "X11DesktopSettingsCore.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

void QVDesktopStateInit(QVDesktopState *s) {
    memset(s, 0, sizeof(*s));
    s->accent[0] = 10.0/255; s->accent[1] = 122.0/255; s->accent[2] = 1;
    s->textScale = 1; s->overlayScrolling = true;
}

void QVDesktopSharedInit(QVDesktopShared *shared, const QVDesktopState *state) {
    pthread_mutex_init(&shared->lock, NULL);
    shared->state = *state;
}

void QVDesktopSharedLoad(QVDesktopShared *shared, QVDesktopState *state) {
    pthread_mutex_lock(&shared->lock);
    *state = shared->state;
    pthread_mutex_unlock(&shared->lock);
}

void QVDesktopSharedStore(QVDesktopShared *shared, const QVDesktopState *state) {
    pthread_mutex_lock(&shared->lock);
    shared->state = *state;
    pthread_mutex_unlock(&shared->lock);
}

bool QVDesktopApply(QVDesktopState *s, const char *space, const char *key, DBusMessageIter *variant) {
    if (!space || !key || dbus_message_iter_get_arg_type(variant) != DBUS_TYPE_VARIANT) return false;
    DBusMessageIter v; dbus_message_iter_recurse(variant, &v);
    QVDesktopState next = *s;
    int type = dbus_message_iter_get_arg_type(&v);
    if (!strcmp(space, "org.freedesktop.appearance")) {
        uint32_t *slot = !strcmp(key, "color-scheme") ? &next.colorScheme :
            !strcmp(key, "contrast") ? &next.contrast : !strcmp(key, "reduced-motion") ? &next.reducedMotion : NULL;
        if (slot && type == DBUS_TYPE_UINT32) dbus_message_iter_get_basic(&v, slot);
        else if (!strcmp(key, "accent-color") && type == DBUS_TYPE_STRUCT) {
            DBusMessageIter rgb; dbus_message_iter_recurse(&v, &rgb);
            double a[3];
            for (int i = 0; i < 3; i++) {
                if (dbus_message_iter_get_arg_type(&rgb) != DBUS_TYPE_DOUBLE) return false;
                dbus_message_iter_get_basic(&rgb, a+i); dbus_message_iter_next(&rgb);
            }
            if (dbus_message_iter_get_arg_type(&rgb) != DBUS_TYPE_INVALID) return false;
            next.hasAccent = true;
            for (int i = 0; i < 3; i++) if (!isfinite(a[i]) || a[i] < 0 || a[i] > 1) next.hasAccent = false;
            if (next.hasAccent) memcpy(next.accent, a, sizeof(a));
            else { next.accent[0]=10.0/255; next.accent[1]=122.0/255; next.accent[2]=1; }
        } else return false;
    } else if (!strcmp(space, "org.gnome.desktop.interface")) {
        if (!strcmp(key, "font-name") && type == DBUS_TYPE_STRING) {
            const char *font; dbus_message_iter_get_basic(&v, &font);
            if (strlen(font) >= sizeof(next.fontName)) return false;
            strcpy(next.fontName, font);
        } else if (!strcmp(key, "text-scaling-factor") && type == DBUS_TYPE_DOUBLE) {
            double scale; dbus_message_iter_get_basic(&v, &scale);
            if (!isfinite(scale) || scale <= 0) return false;
            next.textScale = scale;
        } else if (!strcmp(key, "overlay-scrolling") && type == DBUS_TYPE_BOOLEAN) {
            dbus_bool_t enabled; dbus_message_iter_get_basic(&v, &enabled); next.overlayScrolling = enabled;
        } else return false;
    } else return false;
    if (!memcmp(&next, s, sizeof(next))) return false;
    *s = next; return true;
}

bool QVDesktopReadAll(QVDesktopState *s, DBusMessage *message) {
    if (!message || !dbus_message_has_signature(message, "a{sa{sv}}")) return false;
    DBusMessageIter root, spaces; dbus_message_iter_init(message, &root); dbus_message_iter_recurse(&root, &spaces);
    bool changed = false;
    while (dbus_message_iter_get_arg_type(&spaces) == DBUS_TYPE_DICT_ENTRY) {
        DBusMessageIter entry, keys; const char *space;
        dbus_message_iter_recurse(&spaces, &entry); dbus_message_iter_get_basic(&entry, &space);
        dbus_message_iter_next(&entry); dbus_message_iter_recurse(&entry, &keys);
        while (dbus_message_iter_get_arg_type(&keys) == DBUS_TYPE_DICT_ENTRY) {
            DBusMessageIter pair; const char *key;
            dbus_message_iter_recurse(&keys, &pair); dbus_message_iter_get_basic(&pair, &key);
            dbus_message_iter_next(&pair); changed |= QVDesktopApply(s, space, key, &pair);
            dbus_message_iter_next(&keys);
        }
        dbus_message_iter_next(&spaces);
    }
    return changed;
}

bool QVDesktopChanged(QVDesktopState *s, DBusMessage *message) {
    if (!dbus_message_is_signal(message, "org.freedesktop.portal.Settings", "SettingChanged") ||
        !dbus_message_has_path(message, "/org/freedesktop/portal/desktop") ||
        !dbus_message_has_signature(message, "ssv")) return false;
    DBusMessageIter v; const char *space, *key;
    dbus_message_iter_init(message, &v); dbus_message_iter_get_basic(&v, &space);
    dbus_message_iter_next(&v); dbus_message_iter_get_basic(&v, &key); dbus_message_iter_next(&v);
    return QVDesktopApply(s, space, key, &v);
}

DBusMessage *QVDesktopReadRequest(void) {
    DBusMessage *m = dbus_message_new_method_call("org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop", "org.freedesktop.portal.Settings", "ReadAll");
    if (!m) return NULL;
    DBusMessageIter root, array; dbus_message_iter_init_append(m, &root);
    bool ok = dbus_message_iter_open_container(&root, DBUS_TYPE_ARRAY, "s", &array);
    const char *spaces[] = {"org.freedesktop.appearance", "org.gnome.desktop.interface"};
    for (int i = 0; ok && i < 2; i++) ok = dbus_message_iter_append_basic(&array, DBUS_TYPE_STRING, spaces+i);
    if (ok) ok = dbus_message_iter_close_container(&root, &array);
    if (!ok) { dbus_message_unref(m); return NULL; }
    dbus_message_set_auto_start(m, FALSE);
    return m;
}

DBusConnection *QVDesktopOpenSessionBus(int timeout) {
    // dbus_bus_get would autolaunch without an address and send an unbounded Hello.
    const char *address = getenv("DBUS_SESSION_BUS_ADDRESS");
    if (!address || !address[0]) return NULL;
    DBusError error; dbus_error_init(&error);
    DBusConnection *bus = dbus_connection_open_private(address, &error);
    if (!bus) { dbus_error_free(&error); return NULL; }
    dbus_connection_set_exit_on_disconnect(bus, FALSE);
    // send_with_reply_and_block applies no timeout while the connection is
    // still authenticating (observed with libdbus 1.16 against a socket that
    // accepts and never answers), so authenticate under the bound first.
    struct timespec start; clock_gettime(CLOCK_MONOTONIC, &start);
    for (;;) {
        if (dbus_connection_get_is_authenticated(bus) || !dbus_connection_get_is_connected(bus)) break;
        struct timespec now; clock_gettime(CLOCK_MONOTONIC, &now);
        long spent = (now.tv_sec - start.tv_sec) * 1000 + (now.tv_nsec - start.tv_nsec) / 1000000;
        if (spent >= timeout) break;
        dbus_connection_read_write(bus, (int)(timeout - spent));
    }
    if (!dbus_connection_get_is_authenticated(bus)) {
        dbus_error_free(&error); dbus_connection_close(bus); dbus_connection_unref(bus);
        return NULL;
    }
    DBusMessage *hello = dbus_message_new_method_call(DBUS_SERVICE_DBUS, DBUS_PATH_DBUS, DBUS_INTERFACE_DBUS, "Hello");
    DBusMessage *reply = hello ? dbus_connection_send_with_reply_and_block(bus, hello, timeout, &error) : NULL;
    if (hello) dbus_message_unref(hello);
    dbus_error_free(&error);
    DBusMessageIter value; const char *name = NULL;
    if (reply && dbus_message_has_signature(reply, "s") && dbus_message_iter_init(reply, &value))
        dbus_message_iter_get_basic(&value, &name);
    bool registered = name && dbus_bus_set_unique_name(bus, name);
    if (reply) dbus_message_unref(reply);
    if (registered) return bus;
    dbus_connection_close(bus); dbus_connection_unref(bus);
    return NULL;
}

bool QVDesktopPortalAppeared(DBusMessage *message) {
    if (!dbus_message_is_signal(message, DBUS_INTERFACE_DBUS, "NameOwnerChanged") ||
        !dbus_message_has_sender(message, DBUS_SERVICE_DBUS) ||
        !dbus_message_has_signature(message, "sss")) return false;
    DBusMessageIter v; const char *name, *previous, *owner;
    dbus_message_iter_init(message, &v); dbus_message_iter_get_basic(&v, &name);
    dbus_message_iter_next(&v); dbus_message_iter_get_basic(&v, &previous);
    dbus_message_iter_next(&v); dbus_message_iter_get_basic(&v, &owner);
    return !strcmp(name, "org.freedesktop.portal.Desktop") && owner[0];
}

unsigned QVDesktopAppearance(const QVDesktopState *s, bool follow, bool requiresAqua, const char *override) {
    if (requiresAqua) return 0;
    bool dark = s->colorScheme == 1;
    if (override && !strcmp(override,"dark")) dark = true;
    else if (override && !strcmp(override,"light")) dark = false;
    return (follow && dark ? 1u : 0u) | (s->contrast == 1 ? 2u : 0u);
}
