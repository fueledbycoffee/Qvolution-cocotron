// Copyright (c) 2026 Qvolution contributors. SPDX-License-Identifier: MIT
#import <AppKit/NSView.h>

static NSString *const _NSApplicationEffectiveAppearanceDidChange = @"_NSApplicationEffectiveAppearanceDidChange";
static NSString *const _NSPreviousEffectiveAppearance = @"previousEffectiveAppearance";

@interface NSView (NSAppearanceInternal)
- (void)_registerForApplicationAppearanceChanges;
- (void)_appearanceDidChangeFrom:(NSAppearance *)previous;
@end
