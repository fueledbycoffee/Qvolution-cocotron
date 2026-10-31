/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <AppKit/NSAppearance.h>
#import <Foundation/NSNumber.h>
#import <AppKit/NSColor_CGColor.h>
#import <AppKit/NSColor_catalog.h>
#import <AppKit/NSDisplay.h>
#import <AppKit/NSGraphics.h>

@interface NSColor (NSAppKitPrivate)
- (CGColorRef) CGColorRef;
@end

void NSColorSetCatalogColor(NSColorListName catalogName, NSColorName colorName,
                            NSColor *color);
NSColor *NSColorGetCatalogColor(NSColorListName catalogName,
                                NSColorName colorName);

// Original fallback palette for semantic roles; these are not native macOS samples.
static NSColor *systemAppearanceColor(NSColorName name, NSColor *light) {
    CGFloat white;
    if ([name isEqualToString:@"textBackgroundColor"] ||
        [name isEqualToString:@"controlBackgroundColor"])
        white = 0.12;
    else if ([name isEqualToString:@"controlColor"])
        white = 0.18;
    else if ([name isEqualToString:@"placeholderTextColor"])
        white = 0.60;
    else if ([name isEqualToString:@"textColor"] ||
             [name isEqualToString:@"controlTextColor"] ||
             [name isEqualToString:@"labelColor"])
        white = 0.92;
    else
        return light;
    NSColor *dark = [NSColor colorWithCalibratedWhite:white alpha:1];
    return [NSColor colorWithName:name dynamicProvider:^NSColor *(NSAppearance *appearance) {
        NSAppearanceName appearanceName = [appearance name];
        if ([appearanceName isEqualToString:NSAppearanceNameDarkAqua] ||
            [appearanceName isEqualToString:NSAppearanceNameVibrantDark])
            return dark;
        return light;
    }];
}

@interface NSColor_catalog ()
- initWithCatalogName:(NSColorListName)catalogName colorName:(NSColorName)colorName
                color:(NSColor *)color alphaOverride:(NSNumber *)alphaOverride;
@end

@implementation NSColor_catalog

- (NSColorType) type {
    return NSColorTypeCatalog;
}

- initWithCatalogName: (NSColorListName) catalogName
            colorName: (NSColorName) colorName
                color: (NSColor *) color
{
    return [self initWithCatalogName:catalogName colorName:colorName
                              color:color alphaOverride:nil];
}

- initWithCatalogName:(NSColorListName)catalogName colorName:(NSColorName)colorName
                color:(NSColor *)color alphaOverride:(NSNumber *)alphaOverride {
    _catalogName = [catalogName copy];
    _colorName = [colorName copy];
    // Derived backing already contains the requested opacity and dynamic provider.
    if (alphaOverride == nil && [catalogName isEqualToString:@"System"] && color != nil)
        color = systemAppearanceColor(colorName, color);
    _color = [color copy];
    _alphaOverride = [alphaOverride copy];
    return self;
}

- (void) dealloc {
    [_colorName release];
    [_catalogName release];
    [_color release];
    [_alphaOverride release];
    NSDeallocateObject(self);
    return;
    [super dealloc];
}

- (BOOL) isEqual: otherObject {
    if (self == otherObject)
        return YES;

    if ([otherObject isKindOfClass: [self class]]) {
        NSColor_catalog *other = otherObject;

        return ([_catalogName isEqualToString: other->_catalogName] &&
                [_colorName isEqualToString: other->_colorName] &&
                (_alphaOverride == other->_alphaOverride ||
                 [_alphaOverride isEqual:other->_alphaOverride]));
    }

    return NO;
}

- (NSUInteger)hash {
    return [_catalogName hash] ^ [_colorName hash] ^ [_alphaOverride hash];
}

- (CGFloat)alphaComponent {
    return [_color alphaComponent];
}

- (NSColor *)colorWithAlphaComponent:(CGFloat)alpha {
    NSColor *modified = [_color colorWithAlphaComponent:alpha];
    if (modified == nil)
        return nil;
    return [[[[self class] alloc] initWithCatalogName:_catalogName
            colorName:_colorName color:modified
            alphaOverride:[NSNumber numberWithDouble:alpha]] autorelease];
}

- (NSString *) description {
    return [NSString stringWithFormat: @"<%@ catalogName: %@ colorName: %@>",
                                       [[self class] description], _catalogName,
                                       _colorName];
}

+ (NSColor *) colorWithCatalogName: (NSColorListName) catalogName
                         colorName: (NSColorName) colorName
{
    return [[[self alloc]
            initWithCatalogName: catalogName
                      colorName: colorName
                          color: [[NSDisplay currentDisplay]
                                         colorWithName: colorName]]
            autorelease];
}

+ (NSColor *) colorWithCatalogName: (NSColorListName) catalogName
                         colorName: (NSColorName) colorName
                             color: (NSColor *) color
{
    if (NSColorGetCatalogColor(catalogName, colorName) == nil)
        NSColorSetCatalogColor(catalogName, colorName, color);

    return [[[self alloc] initWithCatalogName: catalogName
                                    colorName: colorName
                                        color: color] autorelease];
}

- (NSColorSpaceName) colorSpaceName {
    return NSNamedColorSpace;
}

- (NSColorListName) catalogNameComponent {
    return _catalogName;
}

- (NSColorName) colorNameComponent {
    return _colorName;
}

- (NSImage *) patternImage {
    return [_color patternImage];
}

- (CGColorRef) CGColor {
    if (_color != nil)
        return [_color CGColor];

    return nil;
}

- (NSColor *) colorUsingColorSpaceName: (NSColorSpaceName) colorSpace {
    return [self colorUsingColorSpaceName: colorSpace device: nil];
}

- (NSColor *) colorUsingColorSpaceName: (NSColorSpaceName) colorSpace
                                device: (NSDictionary *) device
{
    if ([colorSpace isEqualToString: [self colorSpaceName]])
        return self;

    // Return the converted color without replacing _color: the result is
    // autoreleased, so storing it would leave this color with a dangling
    // backing color once the pool drains.
    return [_color colorUsingColorSpaceName: colorSpace device: device];
}

- (CGColorRef) CGColorRef {
    return [self CGColor];
}

- (void) setFill {
    [_color setFill];
}

- (void) setStroke {
    [_color setStroke];
}

- (NSColor *) highlightWithLevel: (CGFloat) level {
    level = MIN(1.0, MAX(0.0, level));

    return self;
}

@end
