// Copyright (c) 2026 Qvolution contributors. SPDX-License-Identifier: MIT
#import <AppKit/NSView.h>

__attribute__((visibility("hidden"))) void _NSRegisterApplicationAppearanceObserver(id observer);
__attribute__((visibility("hidden"))) void _NSUnregisterApplicationAppearanceObserver(id observer);

@interface NSObject (NSApplicationAppearanceInternal)
- (void)_applicationAppearanceDidChangeFrom:(NSAppearance *)previous;
@end

@interface NSView (NSAppearanceInternal)
- (void)_registerForApplicationAppearanceChanges;
- (void)_appearanceDidChangeFrom:(NSAppearance *)previous;
@end
