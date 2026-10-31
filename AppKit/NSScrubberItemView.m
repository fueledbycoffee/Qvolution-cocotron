/*
 * This file is part of Darling.
 *
 * Copyright (C) 2024 Darling Developers
 *
 * Darling is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Darling is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Darling.  If not, see <http://www.gnu.org/licenses/>.
 */

#import <AppKit/NSScrubberItemView.h>
#import <AppKit/NSScrubberLayoutAttributes.h>

@implementation NSScrubberArrangedView

- (BOOL)isSelected { return _selected; }
- (BOOL)isHighlighted { return _highlighted; }

- (void)setSelected:(BOOL)value {
    if (_selected != value) {
        _selected = value;
        [self setNeedsDisplay:YES];
    }
}

- (void)setHighlighted:(BOOL)value {
    if (_highlighted != value) {
        _highlighted = value;
        [self setNeedsDisplay:YES];
    }
}

- (void)applyLayoutAttributes:(NSScrubberLayoutAttributes *)attributes {
    if (![attributes isKindOfClass:[NSScrubberLayoutAttributes class]])
        [NSException raise:NSInvalidArgumentException format:@"Expected scrubber layout attributes"];
    [self setFrame:[attributes frame]];
    [self setAlphaValue:[attributes alpha]];
    [self setNeedsDisplay:YES];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self != nil && [coder allowsKeyedCoding]) {
        _selected = [coder decodeBoolForKey:@"QvolutionScrubberSelected"];
        _highlighted = [coder decodeBoolForKey:@"QvolutionScrubberHighlighted"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [super encodeWithCoder:coder];
    [coder encodeBool:_selected forKey:@"QvolutionScrubberSelected"];
    [coder encodeBool:_highlighted forKey:@"QvolutionScrubberHighlighted"];
}
@end

@implementation NSScrubberItemView
@end

@implementation NSScrubberTextItemView

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end
