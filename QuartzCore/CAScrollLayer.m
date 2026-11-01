/*
 This file is part of Darling.

 Copyright (C) 2019 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <QuartzCore/CAScrollLayer.h>

NSString *const kCAScrollNone = @"none";
NSString *const kCAScrollVertically = @"vertically";
NSString *const kCAScrollHorizontally = @"horizontally";
NSString *const kCAScrollBoth = @"both";

@implementation CAScrollLayer

- init {
    if ((self = [super init]) != nil)
        _scrollMode = [kCAScrollBoth copy];
    return self;
}

- (void) dealloc {
    [_scrollMode release];
    [super dealloc];
}

- (NSString *) scrollMode {
    return _scrollMode;
}

- (void) setScrollMode: (NSString *) value {
    value = [value copy];
    [_scrollMode release];
    _scrollMode = value;
}

- (void) scrollToPoint: (CGPoint) p {
    BOOL horizontal = [_scrollMode isEqualToString: kCAScrollBoth] ||
                      [_scrollMode isEqualToString: kCAScrollHorizontally];
    BOOL vertical = [_scrollMode isEqualToString: kCAScrollBoth] ||
                    [_scrollMode isEqualToString: kCAScrollVertically];
    CGRect bounds = [self bounds];
    if (horizontal) bounds.origin.x = p.x;
    if (vertical) bounds.origin.y = p.y;
    [self setBounds: bounds];
}

- (void) scrollToRect: (CGRect) r {
    CGRect bounds = [self bounds];
    CGPoint origin = bounds.origin;
    if (CGRectGetMaxX(r) > CGRectGetMaxX(bounds)) origin.x = CGRectGetMaxX(r) - bounds.size.width;
    if (CGRectGetMinX(r) < origin.x) origin.x = CGRectGetMinX(r);
    if (CGRectGetMaxY(r) > CGRectGetMaxY(bounds)) origin.y = CGRectGetMaxY(r) - bounds.size.height;
    if (CGRectGetMinY(r) < origin.y) origin.y = CGRectGetMinY(r);
    [self scrollToPoint: origin];
}

@end
