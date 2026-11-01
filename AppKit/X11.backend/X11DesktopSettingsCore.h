// Copyright (c) 2026 Qvolution contributors. SPDX-License-Identifier: MIT
// Original Qvolution implementation of the public portal Settings protocol.
#pragma once
#include <dbus/dbus.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
typedef struct {
    uint32_t colorScheme, contrast, reducedMotion;
    double accent[3], textScale;
    bool hasAccent, overlayScrolling;
    char fontName[256];
} QVDesktopState;
void QVDesktopStateInit(QVDesktopState *state);
// The published state: written by the main-thread portal drain, read by any
// drawing thread (dynamic colours, effectiveAppearance). Readers copy it whole
// under the lock, so they never see a partly written accent or font name.
typedef struct {
    pthread_mutex_t lock;
    QVDesktopState state;
} QVDesktopShared;
void QVDesktopSharedInit(QVDesktopShared *shared, const QVDesktopState *state);
void QVDesktopSharedLoad(QVDesktopShared *shared, QVDesktopState *state);
void QVDesktopSharedStore(QVDesktopShared *shared, const QVDesktopState *state);
bool QVDesktopApply(QVDesktopState *state, const char *space, const char *key, DBusMessageIter *variant);
bool QVDesktopReadAll(QVDesktopState *state, DBusMessage *message);
bool QVDesktopChanged(QVDesktopState *state, DBusMessage *message);
DBusMessage *QVDesktopReadRequest(void);
// libdbus waits 25 s by default; display initialization must not.
#define QV_DESKTOP_BUS_TIMEOUT_MS 300
// The session bus named by DBUS_SESSION_BUS_ADDRESS, registered with a
// bounded Hello. NULL without an address (no autolaunch) or on failure.
DBusConnection *QVDesktopOpenSessionBus(int timeoutMilliseconds);
// A NameOwnerChanged broadcast saying the portal service now has an owner.
bool QVDesktopPortalAppeared(DBusMessage *message);
// 0 Aqua, 1 DarkAqua, 2 high-contrast Aqua, 3 high-contrast DarkAqua.
unsigned QVDesktopAppearance(const QVDesktopState *state, bool follow, bool requiresAqua, const char *override);
