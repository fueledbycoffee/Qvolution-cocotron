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

#import <AppKit/NSScrubberLayoutAttributes.h>

@implementation NSScrubberLayoutAttributes
@synthesize frame = _frame;
@synthesize alpha = _alpha;
@synthesize itemIndex = _itemIndex;

- (instancetype)init {
    self = [super init];
    if (self != nil)
        _alpha = 1.0; // Project default: a new item's opacity is unchanged.
    return self;
}

+ (instancetype)layoutAttributesForItemAtIndex:(NSInteger)index {
    NSScrubberLayoutAttributes *value = [[[self alloc] init] autorelease];
    [value setItemIndex:index];
    return value;
}

- (id)copyWithZone:(NSZone *)zone {
    NSScrubberLayoutAttributes *value = [[[self class] allocWithZone:zone] init];
    if (value != nil) {
        value->_frame = _frame;
        value->_alpha = _alpha;
        value->_itemIndex = _itemIndex;
    }
    return value;
}
@end
