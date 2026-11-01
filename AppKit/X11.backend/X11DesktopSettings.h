// Copyright (c) 2026 Qvolution contributors. SPDX-License-Identifier: MIT
#import <Foundation/NSObject.h>
#import <CoreFoundation/CoreFoundation.h>
#import "X11DesktopSettingsCore.h"
@class NSColor, NSAppearance;
@interface X11DesktopSettings : NSObject {
    QVDesktopShared _shared;
    DBusConnection *_connection;
    CFSocketRef _socket;
    CFRunLoopSourceRef _source;
    // Cached QVDesktopAppearance index, tagged with the generation it was
    // computed in; any invalidation bumps the generation.
    uint64_t _appearanceCache, _appearanceGeneration;
    BOOL _requiresAqua;
    const char *_appearanceOverride;
}
+ (instancetype)sharedSettings;
- (NSAppearance *)systemAppearance;
- (NSColor *)colorWithName:(NSString *)name appearance:(NSAppearance *)appearance;
- (NSString *)fontName;
- (double)textScalingFactor;
- (BOOL)overlayScrolling;
- (BOOL)reducedMotion;
@end
