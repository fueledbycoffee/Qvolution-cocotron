// Copyright (c) 2026 Qvolution contributors. SPDX-License-Identifier: MIT
// Qvolution design tokens from parallel/visual-theme/SPEC.md, section 3.
// These values are original design choices, never samples of Apple pixels.
#pragma once
#include <stdbool.h>
#include <string.h>
#include <math.h>
typedef struct { double r, g, b, a; } QVThemeColor;
static inline QVThemeColor QVRGB(unsigned rgb) {
    return (QVThemeColor){(rgb>>16)/255.0, ((rgb>>8)&255)/255.0, (rgb&255)/255.0, 1};
}
static inline QVThemeColor QVWhite(double white, double alpha) { return (QVThemeColor){white,white,white,alpha}; }
static inline QVThemeColor QVMix(QVThemeColor x, QVThemeColor y, double t) {
    return (QVThemeColor){x.r*(1-t)+y.r*t,x.g*(1-t)+y.g*t,x.b*(1-t)+y.b*t,x.a*(1-t)+y.a*t};
}
static inline double QVLinear(double x) { return x <= .04045 ? x/12.92 : pow((x+.055)/1.055,2.4); }
static inline QVThemeColor QVOnAccent(QVThemeColor a) {
    double luminance=.2126*QVLinear(a.r)+.7152*QVLinear(a.g)+.0722*QVLinear(a.b);
    return 1.05/(luminance+.05) >= 3 ? QVWhite(1,1) : QVWhite(0,.85);
}
// All consumers, including dynamic catalog providers, resolve this same table.
static inline bool QVThemeLookup(const char *name, bool dark, bool highContrast, const double accent[3], QVThemeColor *out) {
    QVThemeColor a={accent[0],accent[1],accent[2],1}, c;
    #define ROLE(n, light, night) if (!strcmp(name,n)) { c=dark ? (night) : (light); goto found; }
    ROLE("windowBackgroundColor", QVRGB(0xECECEC), QVRGB(0x2E2E2E))
    ROLE("controlColor", QVRGB(0xFFFFFF), QVRGB(0x616161))
    ROLE("controlBackgroundColor", QVRGB(0xFFFFFF), QVRGB(0x1F1F1F))
    ROLE("textBackgroundColor", QVRGB(0xFFFFFF), QVRGB(0x1F1F1F))
    ROLE("textColor", QVWhite(0,1), QVRGB(0xEBEBEB))
    ROLE("selectedTextColor", QVWhite(0,1), QVRGB(0xEBEBEB))
    ROLE("unemphasizedSelectedTextColor", QVWhite(0,1), QVRGB(0xEBEBEB))
    ROLE("labelColor", QVWhite(0,.85), QVRGB(0xEBEBEB))
    ROLE("controlTextColor", QVWhite(0,.85), QVRGB(0xEBEBEB))
    ROLE("menuItemTextColor", QVWhite(0,.85), QVRGB(0xEBEBEB))
    ROLE("headerTextColor", QVWhite(0,.85), QVRGB(0xEBEBEB))
    ROLE("secondaryLabelColor", QVWhite(0,highContrast?.7:.5), QVWhite(1,highContrast?.7:.55))
    ROLE("tertiaryLabelColor", QVWhite(0,.26), QVWhite(1,.25))
    ROLE("quaternaryLabelColor", QVWhite(0,.1), QVWhite(1,.1))
    ROLE("disabledControlTextColor", QVWhite(0,.25), QVWhite(1,.25))
    ROLE("placeholderTextColor", QVWhite(0,.25), QVWhite(1,.25))
    ROLE("separatorColor", QVWhite(0,highContrast?1:.1), QVWhite(highContrast?235.0/255:1,highContrast?1:.1))
    ROLE("gridColor", QVRGB(0xE6E6E6), QVRGB(0x3A3A3A))
    ROLE("headerColor", QVRGB(0xFFFFFF), QVRGB(0x2E2E2E))
    ROLE("windowFrameColor", QVWhite(0,highContrast?1:.15), highContrast?QVRGB(0xEBEBEB):QVWhite(0,.6))
    ROLE("controlShadowColor", QVWhite(0,.2), QVWhite(0,.5))
    ROLE("menuBackgroundColor", QVRGB(0xF2F2F2), QVRGB(0x2A2A2A))
    ROLE("mainMenuBarColor", QVRGB(0xF2F2F2), QVRGB(0x2A2A2A))
    ROLE("selectedMenuItemColor", a, a)
    ROLE("selectedMenuItemTextColor", QVOnAccent(a), QVOnAccent(a))
    ROLE("controlAccentColor", a, a)
    ROLE("alternateSelectedControlColor", a, a)
    ROLE("alternateSelectedControlTextColor", QVOnAccent(a), QVOnAccent(a))
    ROLE("selectedContentBackgroundColor", a, QVMix(a,QVWhite(0,1),.15))
    ROLE("unemphasizedSelectedContentBackgroundColor", QVRGB(0xDCDCDC), QVRGB(0x464646))
    ROLE("unemphasizedSelectedTextBackgroundColor", QVRGB(0xDCDCDC), QVRGB(0x464646))
    ROLE("secondarySelectedControlColor", QVRGB(0xDCDCDC), QVRGB(0x464646))
    ROLE("selectedTextBackgroundColor", QVMix(QVWhite(1,1),a,.35), QVMix(QVRGB(0x1F1F1F),a,.55))
    ROLE("selectedControlColor", QVMix(QVWhite(1,1),a,.35), QVMix(QVWhite(0,1),a,.6))
    ROLE("selectedControlTextColor", QVWhite(0,.85), QVRGB(0xEBEBEB))
    ROLE("keyboardFocusIndicatorColor", ((QVThemeColor){a.r,a.g,a.b,.5}), ((QVThemeColor){a.r,a.g,a.b,.5}))
    ROLE("alternatingContentBackgroundColor", QVRGB(0xF4F5F5), QVRGB(0x262626))
    ROLE("linkColor", QVRGB(0x0068DA), QVRGB(0x419CFF))
    ROLE("knobColor", QVWhite(0,.25), QVWhite(1,.3))
    ROLE("scrollBarColor", QVWhite(1,1), QVRGB(0x1F1F1F))
    ROLE("findHighlightColor", QVRGB(0xFFFF00), QVRGB(0xFFFF00))
    ROLE("titlebar.active", QVRGB(0xE8E8E8), QVRGB(0x383838))
    ROLE("titlebar.inactive", QVRGB(0xF6F6F6), QVRGB(0x2E2E2E))
    ROLE("titlebar.hairline", QVWhite(0,highContrast?1:.1), highContrast?QVRGB(0xEBEBEB):QVWhite(0,.5))
    ROLE("bezel.border", QVWhite(0,highContrast?1:.18), highContrast?QVRGB(0xEBEBEB):QVWhite(1,.12))
    ROLE("bezel.bottomShadow", QVWhite(0,.08), QVWhite(0,.4))
    ROLE("bezel.pressedFace", QVRGB(0xF0F0F0), QVRGB(0x707070))
    ROLE("segment.selected", QVWhite(0,.14), QVWhite(1,.22))
    ROLE("window.shadow.active", QVWhite(0,.3), QVWhite(0,.55))
    ROLE("window.shadow.inactive", QVWhite(0,.12), QVWhite(0,.3))
    #undef ROLE
    return false;
found:
    *out=c; return true;
}
