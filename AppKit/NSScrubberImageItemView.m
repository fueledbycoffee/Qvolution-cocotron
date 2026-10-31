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

#import <AppKit/NSScrubberImageItemView.h>
#import <AppKit/NSImage.h>

@interface NSScrubberImageItemView ()
- (BOOL)_installOwnedImageView:(NSImageView *)decoded;
@end

@implementation NSScrubberImageItemView

- (BOOL)_installOwnedImageView:(NSImageView *)decoded {
    if (decoded != nil && [decoded superview] != nil && [decoded superview] != self)
        [NSException raise:NSInvalidUnarchiveOperationException format:@"Scrubber image view belongs to another parent"];
    if (decoded != nil) {
        _imageView = [decoded retain];
    } else {
        _imageView = [[NSImageView alloc] initWithFrame:[self bounds]];
        [_imageView setEditable:NO];
        [_imageView setImageFrameStyle:NSImageFrameNone];
        [_imageView setImageScaling:NSImageScaleProportionallyUpOrDown];
        [_imageView setImageAlignment:NSImageAlignCenter];
    }
    if (_imageView == nil)
        return NO;
    [_imageView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    if ([_imageView superview] != self)
        [self addSubview:_imageView];
    [_imageView setFrame:[self bounds]];
    return YES;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self != nil) {
        @try {
            if (![self _installOwnedImageView:nil]) {
                [self release];
                return nil;
            }
        } @catch (id exception) {
            [self release];
            @throw;
        }
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self != nil) {
        @try {
            id view = [coder allowsKeyedCoding]
                    ? [coder decodeObjectForKey:@"QvolutionScrubberImageView"] : nil;
            if (view != nil && ![view isKindOfClass:[NSImageView class]])
                [NSException raise:NSInvalidUnarchiveOperationException format:@"Expected scrubber image view"];
            if (![self _installOwnedImageView:view]) {
                [self release];
                return nil;
            }
        } @catch (id exception) {
            [self release];
            @throw;
        }
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [super encodeWithCoder:coder];
    if ([coder allowsKeyedCoding])
        [coder encodeObject:_imageView forKey:@"QvolutionScrubberImageView"];
}

- (NSImageView *)imageView { return [[_imageView retain] autorelease]; }
- (NSImage *)image { return [[[_imageView image] retain] autorelease]; }
- (NSImageAlignment)imageAlignment { return [_imageView imageAlignment]; }

- (void)setImage:(NSImage *)image {
    if (image != nil && ![image isKindOfClass:[NSImage class]])
        [NSException raise:NSInvalidArgumentException format:@"Expected scrubber image"];
    NSImage *copy = [image copy];
    if (image != nil && copy == nil)
        [NSException raise:NSMallocException format:@"Unable to copy scrubber image"];
    @try {
        [_imageView setImage:copy];
    } @finally {
        [copy release];
    }
}

- (void)setImageAlignment:(NSImageAlignment)value {
    [_imageView setImageAlignment:value];
}

- (void)resizeSubviewsWithOldSize:(NSSize)size {
    [super resizeSubviewsWithOldSize:size];
    [_imageView setFrame:[self bounds]];
}

- (void)setBounds:(NSRect)bounds {
    [super setBounds:bounds];
    [_imageView setFrame:[self bounds]];
}

- (void)layout {
    [super layout];
    [_imageView setFrame:[self bounds]];
}

- (void)dealloc {
    [_imageView release];
    [super dealloc];
}
@end
