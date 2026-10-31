// Copyright (c) 2026 Qvolution contributors. SPDX-License-Identifier: MIT
#import <Foundation/NSObject.h>
#import <CoreFoundation/CoreFoundation.h>
#import "X11DesktopSettingsCore.h"
@class NSColor, NSAppearance;
@interface X11DesktopSettings : NSObject {
    QVDesktopState _state;
    DBusConnection *_connection;
    CFSocketRef _socket;
    CFRunLoopSourceRef _source;
}
+ (instancetype)sharedSettings;
- (NSAppearance *)systemAppearance;
- (NSColor *)colorWithName:(NSString *)name appearance:(NSAppearance *)appearance;
- (NSString *)fontName;
- (double)textScalingFactor;
- (BOOL)overlayScrolling;
- (BOOL)reducedMotion;
@end
