// Copyright (c) 2026 Qvolution contributors. SPDX-License-Identifier: MIT
// Original Qvolution implementation of the public portal Settings protocol.
#pragma once
#include <dbus/dbus.h>
#include <stdbool.h>
#include <stdint.h>
typedef struct {
    uint32_t colorScheme, contrast, reducedMotion;
    double accent[3], textScale;
    bool hasAccent, overlayScrolling;
    char fontName[256];
} QVDesktopState;
void QVDesktopStateInit(QVDesktopState *state);
bool QVDesktopApply(QVDesktopState *state, const char *space, const char *key, DBusMessageIter *variant);
bool QVDesktopReadAll(QVDesktopState *state, DBusMessage *message);
bool QVDesktopChanged(QVDesktopState *state, DBusMessage *message);
DBusMessage *QVDesktopReadRequest(void);
// 0 Aqua, 1 DarkAqua, 2 high-contrast Aqua, 3 high-contrast DarkAqua.
unsigned QVDesktopAppearance(const QVDesktopState *state, bool follow, bool requiresAqua, const char *override);
