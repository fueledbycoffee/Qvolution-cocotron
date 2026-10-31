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

#import <AppKit/NSBitmapImageRep-Private.h>
#import "NSImageCoding.h"
#ifdef DARLING
#import <Onyx2D/O2Image.h>
#endif
#import <AppKit/NSColor.h>
#import <AppKit/NSGraphicsContextFunctions.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSView.h>

NSBitmapImageRepPropertyKey NSImageCompressionFactor =
        @"NSImageCompressionFactor";
NSBitmapImageRepPropertyKey NSImageCompressionMethod =
        @"NSImageCompressionMethod";
NSBitmapImageRepPropertyKey NSImageDitherTransparency =
        @"NSImageDitherTransparency";
NSBitmapImageRepPropertyKey NSImageInterlaced = @"NSImageInterlaced";
NSBitmapImageRepPropertyKey NSImageRGBColorTable = @"NSImageRGBColorTable";
NSBitmapImageRepPropertyKey NSImageFrameCount = @"NSImageFrameCount";
NSBitmapImageRepPropertyKey NSImageColorSyncProfileData =
        @"NSImageColorSyncProfileData";
NSBitmapImageRepPropertyKey NSImageFallbackBackgroundColor =
        @"NSImageFallbackBackgroundColor";
NSBitmapImageRepPropertyKey NSImageEXIFData = @"NSImageEXIFData";
NSBitmapImageRepPropertyKey NSImageProgressive = @"NSImageProgressive";
NSBitmapImageRepPropertyKey NSImageGamma = @"NSImageGamma";
NSBitmapImageRepPropertyKey NSImageLoopCount = @"NSImageLoopCount";
NSBitmapImageRepPropertyKey NSImageCurrentFrameDuration =
        @"NSImageCurrentFrameDuration";
NSBitmapImageRepPropertyKey NSImageCurrentFrame = @"NSImageCurrentFrame";

@implementation NSBitmapImageRep

+ (NSArray *) imageUnfilteredFileTypes {
    return [NSArray arrayWithObjects:
                            // Try to order them so the most used ones are at
                            // the top of the list
                            @"png", @"tiff", @"tif", @"jpg", @"jpeg", @"icns",
                            @"gif", @"bmp", @"PNG", @"TIFF", @"TIF", @"JPG",
                            @"JPEG", @"ICNS", @"jpe", @"JPE", @"GIF", @"BMP",
                            nil];
}

+ (NSArray *) imageRepsWithContentsOfFile: (NSString *) path {
    NSData *data = [NSData dataWithContentsOfFile: path];

    if (data == nil)
        return nil;

    if ([self canInitWithData: data])
        return [self imageRepsWithData: data];

    return nil;
}

+ (void) getTIFFCompressionTypes: (const NSTIFFCompression **) types
                           count: (int *) count
{
    NSUnimplementedMethod();
}

+ (NSString *) localizedNameForTIFFCompressionType: (NSTIFFCompression) type {
    NSUnimplementedMethod();
    return nil;
}

+ (NSData *) TIFFRepresentationOfImageRepsInArray: (NSArray *) array {
    return [self TIFFRepresentationOfImageRepsInArray: array
                                     usingCompression: NSTIFFCompressionNone
                                               factor: 0.0];
}

+ (NSData *) TIFFRepresentationOfImageRepsInArray: (NSArray *) array
                                 usingCompression:
                                         (NSTIFFCompression) compression
                                           factor: (float) factor
{
    NSMutableData *result = [NSMutableData data];
    CGImageDestinationRef dest = CGImageDestinationCreateWithData(
            (CFMutableDataRef) result, (CFStringRef) @"public.tiff",
            [array count], NULL);

    for (NSBitmapImageRep *bitmap in array) {
        CGImageDestinationAddImage(dest, [bitmap CGImage], NULL);
    }

    CGImageDestinationFinalize(dest);
    CFRelease(dest);

    return result;
}

+ (NSData *) representationOfImageRepsInArray: (NSArray *) array
                                    usingType: (NSBitmapImageFileType) type
                                   properties: (NSDictionary *) properties
{
    NSUnimplementedMethod();
    return nil;
}

+ (NSArray *) imageUnfilteredPasteboardTypes {
    return [NSArray arrayWithObjects: NSTIFFPboardType, nil];
}

+ (BOOL) canInitWithData: (NSData *) data {
    CGImageSourceRef imageSource =
            CGImageSourceCreateWithData((CFDataRef) data, nil);
    if (imageSource == NULL)
        return NO;
    CFRelease(imageSource);
    return YES;
}

+ (NSArray *) imageRepsWithData: (NSData *) data {
    NSMutableArray *result = [NSMutableArray array];
    CGImageSourceRef imageSource =
            CGImageSourceCreateWithData((CFDataRef) data, nil);

    if (imageSource == nil)
        return nil;

    size_t i, count = CGImageSourceGetCount(imageSource);

    for (i = 0; i < count; i++) {
        CGImageRef cgImage =
                CGImageSourceCreateImageAtIndex(imageSource, i, nil);

        if (cgImage == nil)
            break;

        CFDictionaryRef properties =
                CGImageSourceCopyPropertiesAtIndex(imageSource, i, nil);
        NSNumber *xres = properties ? [[(id) CFDictionaryGetValue(
                properties, kCGImagePropertyDPIWidth) copy] autorelease] : nil;
        NSNumber *yres = properties ? [[(id) CFDictionaryGetValue(
                properties, kCGImagePropertyDPIHeight) copy] autorelease] : nil;

        if (properties)
            CFRelease(properties);

        NSBitmapImageRep *imageRep = [[self alloc] initWithCGImage: cgImage];
        NSSize size = {CGImageGetWidth(cgImage), CGImageGetHeight(cgImage)};

        CGImageRelease(cgImage);

        if (xres != nil && [xres doubleValue] > 0)
            size.width *= 72.0 / [xres doubleValue];

        if (yres != nil && [yres doubleValue] > 0)
            size.height *= 72.0 / [yres doubleValue];

        [imageRep setSize: size];

        if (imageRep != nil)
            [result addObject: imageRep];

        [imageRep release];
    }

    CFRelease(imageSource);

    return result;
}

+ imageRepWithData: (NSData *) data {
    return [[[self alloc] initWithData: data] autorelease];
}

- initWithBitmapDataPlanes: (unsigned char **) planes
                pixelsWide: (int) width
                pixelsHigh: (int) height
             bitsPerSample: (int) bitsPerSample
           samplesPerPixel: (int) samplesPerPixel
                  hasAlpha: (BOOL) hasAlpha
                  isPlanar: (BOOL) isPlanar
            colorSpaceName: (NSString *) colorSpaceName
              bitmapFormat: (NSBitmapFormat) bitmapFormat
               bytesPerRow: (int) bytesPerRow
              bitsPerPixel: (int) bitsPerPixel
{
    int i, numberOfPlanes = isPlanar ? samplesPerPixel : 1;

    _size = NSMakeSize(width, height);
    _colorSpaceName = [colorSpaceName copy];
    _bitsPerSample = bitsPerSample;
    _pixelsWide = width;
    _pixelsHigh = height;
    _hasAlpha = hasAlpha;

    _samplesPerPixel = samplesPerPixel;
    _isPlanar = isPlanar;
    _bitmapFormat = bitmapFormat;

    if (bitsPerPixel != 0)
        _bitsPerPixel = bitsPerPixel;
    else
        _bitsPerPixel = _bitsPerSample * _samplesPerPixel;

    if (bytesPerRow != 0)
        _bytesPerRow = bytesPerRow;
    else
        _bytesPerRow = (_bitsPerPixel * _pixelsWide + 7) / 8;

    _freeWhenDone = NO;
    if (planes == NULL)
        _freeWhenDone = YES;
    else {
        int i;

        for (i = 0; i < numberOfPlanes; i++)
            if (planes[i] != NULL)
                break;

        if (i == numberOfPlanes)
            _freeWhenDone = YES;
    }

    _bitmapPlanes = NSZoneCalloc(NULL, numberOfPlanes, sizeof(unsigned char *));
    if (_bitmapPlanes == NULL) {
        [self release];
        return nil;
    }
    for (i = 0; i < numberOfPlanes; i++) {
        if (!_freeWhenDone)
            _bitmapPlanes[i] = planes[i];
        else {
            _bitmapPlanes[i] =
                    NSZoneCalloc(NULL, _bytesPerRow * _pixelsHigh, 1);
            if (_bitmapPlanes[i] == NULL) {
                // The table is zero-initialized: dealloc safely frees only
                // the owned planes allocated before this failure.
                [self release];
                return nil;
            }
        }
    }

    return self;
}

- initWithBitmapDataPlanes: (unsigned char **) planes
                pixelsWide: (int) width
                pixelsHigh: (int) height
             bitsPerSample: (int) bitsPerSample
           samplesPerPixel: (int) samplesPerPixel
                  hasAlpha: (BOOL) hasAlpha
                  isPlanar: (BOOL) isPlanar
            colorSpaceName: (NSString *) colorSpaceName
               bytesPerRow: (int) bytesPerRow
              bitsPerPixel: (int) bitsPerPixel
{
    return [self initWithBitmapDataPlanes: planes
                               pixelsWide: width
                               pixelsHigh: height
                            bitsPerSample: bitsPerSample
                          samplesPerPixel: samplesPerPixel
                                 hasAlpha: hasAlpha
                                 isPlanar: isPlanar
                           colorSpaceName: colorSpaceName
                             bitmapFormat: 0
                              bytesPerRow: bytesPerRow
                             bitsPerPixel: bitsPerPixel];
}

- initForIncrementalLoad {
    NSUnimplementedMethod();
    return nil;
}

- initWithFocusedViewRect: (NSRect) rect {
    CGContextRef graphicsPort = NSCurrentGraphicsPort();

    if (graphicsPort == NULL) {
        [self dealloc];
        return nil;
    }

    [self initWithData: (NSData *) CGContextCaptureBitmap(graphicsPort, rect)];

    return self;
}

- initWithData: (NSData *) data {
    CGImageSourceRef imageSource =
            CGImageSourceCreateWithData((CFDataRef) data, nil);

    if (imageSource == nil) {
        [self dealloc];
        return nil;
    }

    CGImageRef cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil);

    if (cgImage == nil) {
        CFRelease(imageSource);
        [self dealloc];
        return nil;
    }

    CFDictionaryRef properties =
            CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil);
    NSNumber *xres = properties ?
            [[(id) CFDictionaryGetValue(properties, kCGImagePropertyDPIWidth)
                    copy] autorelease] : nil;
    NSNumber *yres = properties ?
            [[(id) CFDictionaryGetValue(properties, kCGImagePropertyDPIHeight)
                    copy] autorelease] : nil;

    if (properties)
        CFRelease(properties);
    CFRelease(imageSource);

    if (cgImage == nil) {
        [self dealloc];
        return nil;
    }

    if ((self = [self initWithCGImage: cgImage]) == nil)
        return nil;

    CGImageRelease(cgImage);

    if (xres != nil && [xres doubleValue] > 0)
        _size.width *= 72.0 / [xres doubleValue];

    if (yres != nil && [yres doubleValue] > 0)
        _size.height *= 72.0 / [yres doubleValue];

    return self;
}

- initWithContentsOfFile: (NSString *) path {
    NSData *data = [NSData dataWithContentsOfFile: path];

    if (data == nil) {
        [self dealloc];
        return nil;
    }

    return [self initWithData: data];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    // The preserved legacy >=17 reader expects a DataObject, not this record.
    QVImageCodingRequire([coder allowsKeyedCoding]||[coder versionForClassName:@"NSImageRep"]<17,NSInvalidArchiveOperationException,@"Unkeyed project bitmap coding requires NSImageRep archive version below17");
    NSDictionary *record=[self _qvolutionBitmapRecord];
    if([coder allowsKeyedCoding])[coder encodeObject:record forKey:@"QvolutionNSBitmapImageRepArchive"];
    else[coder encodeObject:record];
}

- (instancetype) initWithCoder:(NSCoder *) coder {
    if ([coder allowsKeyedCoding]) {
        if([coder containsValueForKey:@"QvolutionNSBitmapImageRepArchive"]) {
            id record=nil;
            @try { record=[coder decodeObjectForKey:@"QvolutionNSBitmapImageRepArchive"]; }
            @catch(NSException *error){[self release];@throw;}
            return [self _qvolutionInitWithBitmapRecord:record];
        }
        [NSException raise: NSInvalidArgumentException
                    format: @"-[%@ %s] is not implemented for coder %@",
                            [self class], sel_getName(_cmd), coder];
        return nil;
    } else {
        NSInteger version = [coder versionForClassName: @"NSImageRep"];

        if (version >= 17) {
            NSData *data = [coder decodeDataObject];
            return [self initWithData: data];
        } else {
            id record=nil;
            @try { record=[coder decodeObject]; }
            @catch(NSException *error){[self release];@throw;}
            return [self _qvolutionInitWithBitmapRecord:record];
        }
    }
}

- (void) createBitmapIfNeeded {
    if (_bitmapPlanes == NULL) {
        _freeWhenDone = YES;
        _bitmapPlanes = NSZoneCalloc(NULL, 1, sizeof(unsigned char *));
        _bitmapPlanes[0] = NSZoneCalloc(NULL, _bytesPerRow * _pixelsHigh, 1);

        if (_cgImage != NULL) {
            CGBitmapInfo bitmapInfo = CGImageGetBitmapInfo(_cgImage);
            CGDataProviderRef provider = CGImageGetDataProvider(_cgImage);
            // FIXME: inefficient but there is no API to get mutable bytes out
            // of an image or image source
            CFDataRef bitmapData = CGDataProviderCopyData(provider);
            const unsigned char *bytes = CFDataGetBytePtr(bitmapData);
            int i, length = _bytesPerRow * _pixelsHigh;

            // The planes use component order, with alpha first when
            // _bitmapFormat says so (see -CGBitmapInfo). Big-endian
            // premultiplied sources are already in that order.
            BOOL alphaFirst = (_bitmapFormat & NSAlphaFirstBitmapFormat) != 0;

            if (bitmapInfo ==
                        (kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big) ||
                bitmapInfo ==
                        (kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Big)) {
                for (i = 0; i < length; i++)
                    _bitmapPlanes[0][i] = bytes[i];
            } else {
                for (i = 0; i < length; i += 4) {
                    unsigned char b = bytes[i + 0];
                    unsigned char g = bytes[i + 1];
                    unsigned char r = bytes[i + 2];
                    unsigned char a = bytes[i + 3];

                    if (alphaFirst) {
                        _bitmapPlanes[0][i + 0] = a;
                        _bitmapPlanes[0][i + 1] = r;
                        _bitmapPlanes[0][i + 2] = g;
                        _bitmapPlanes[0][i + 3] = b;
                    } else {
                        _bitmapPlanes[0][i + 0] = r;
                        _bitmapPlanes[0][i + 1] = g;
                        _bitmapPlanes[0][i + 2] = b;
                        _bitmapPlanes[0][i + 3] = a;
                    }
                }
            }
            CFRelease(bitmapData);
        }
    }
}

- initWithCGImage: (CGImageRef) cgImage {
    _cgImage = CGImageRetain(cgImage);
    _size.width = CGImageGetWidth(_cgImage);
    _size.height = CGImageGetHeight(_cgImage);

    CGColorSpaceRef colorSpace = CGImageGetColorSpace(_cgImage);

    // FIXME:
    _colorSpaceName = NSDeviceRGBColorSpace;
    _bitsPerSample = CGImageGetBitsPerComponent(_cgImage);
    _pixelsWide = CGImageGetWidth(_cgImage);
    _pixelsHigh = CGImageGetHeight(_cgImage);

    switch (CGImageGetAlphaInfo(_cgImage)) {
    case kCGImageAlphaPremultipliedLast:
    case kCGImageAlphaPremultipliedFirst:
    case kCGImageAlphaLast:
    case kCGImageAlphaFirst:
        _hasAlpha = YES;
        break;
    default:
        _hasAlpha = NO;
        break;
    }

    _samplesPerPixel = CGColorSpaceGetNumberOfComponents(colorSpace);
    if (_hasAlpha)
        _samplesPerPixel++;
    _isPlanar = NO;
    _bitmapFormat = 0;
    if (CGImageGetBitmapInfo(_cgImage) & kCGBitmapFloatComponents) {
        _bitmapFormat |= NSFloatingPointSamplesBitmapFormat;
    }
    switch (CGImageGetAlphaInfo(_cgImage)) {
    case kCGImageAlphaNone:
        break;
    case kCGImageAlphaPremultipliedLast:
        break;
    case kCGImageAlphaPremultipliedFirst:
        _bitmapFormat |= NSAlphaFirstBitmapFormat;
        break;
    case kCGImageAlphaLast:
        _bitmapFormat |= NSAlphaNonpremultipliedBitmapFormat;
        break;
    case kCGImageAlphaFirst:
        _bitmapFormat |= NSAlphaFirstBitmapFormat;
        _bitmapFormat |= NSAlphaNonpremultipliedBitmapFormat;
        break;
    case kCGImageAlphaNoneSkipLast:
    case kCGImageAlphaNoneSkipFirst:
        break;
    case kCGImageAlphaOnly:
        break;
    }

    _bitsPerPixel = CGImageGetBitsPerPixel(_cgImage);
    _bytesPerRow = CGImageGetBytesPerRow(_cgImage);
    _freeWhenDone = NO;

    //   [self createBitmapIfNeeded];

    return self;
}

- copyWithZone:(NSZone *)zone {
    int count=_isPlanar?_samplesPerPixel:1;
    NSUInteger length=0;
    if (_bitmapPlanes) {
        if (count<=0||_bytesPerRow<=0||_pixelsHigh<=0||
                (NSUInteger)count>NSUIntegerMax/sizeof(unsigned char *)||
                (NSUInteger)_pixelsHigh>NSUIntegerMax/(NSUInteger)_bytesPerRow)
            [NSException raise:NSInvalidArgumentException format:@"Invalid bitmap copy plane extent"];
        length=(NSUInteger)_bytesPerRow*(NSUInteger)_pixelsHigh;
        for(int i=0;i<count;i++)if(!_bitmapPlanes[i])
            [NSException raise:NSInvalidArgumentException format:@"Missing bitmap copy plane"];
    }
    NSBitmapImageRep *result=NSCopyObject(self,0,zone);
    if(!result)return nil;
    // NSCopyObject initially aliases these pointers. Detach all of them before
    // copying/retaining anything that can throw, so cleanup owns only new state.
    result->_colorSpaceName=nil;result->_bitmapPlanes=NULL;result->_cgImage=NULL;result->_properties=nil;result->_freeWhenDone=YES;
    @try {
        result->_colorSpaceName=[_colorSpaceName copyWithZone:zone];
        if(_colorSpaceName&&!result->_colorSpaceName)[NSException raise:NSMallocException format:@"Cannot copy bitmap color space"];
        result->_cgImage=CGImageRetain(_cgImage);
        result->_properties=[_properties mutableCopyWithZone:zone];
        if(_properties&&!result->_properties)[NSException raise:NSMallocException format:@"Cannot copy bitmap properties"];
        if(_bitmapPlanes){
            result->_bitmapPlanes=NSZoneCalloc(NULL,count,sizeof(unsigned char *));
            if(!result->_bitmapPlanes)[NSException raise:NSMallocException format:@"Cannot allocate bitmap copy plane table"];
            for(int i=0;i<count;i++){
                result->_bitmapPlanes[i]=NSZoneMalloc(NULL,length);
                if(!result->_bitmapPlanes[i])[NSException raise:NSMallocException format:@"Cannot allocate bitmap copy plane"];
                memcpy(result->_bitmapPlanes[i],_bitmapPlanes[i],length);
            }
        }
    } @catch(NSException *error){[result release];@throw;}
    return result;
}

- (void) dealloc {
    if (_freeWhenDone) {
        if (_bitmapPlanes != NULL) {
            int i, numberOfPlanes = [self numberOfPlanes];

            for (i = 0; i < numberOfPlanes; i++)
                if (_bitmapPlanes[i] != NULL)
                    NSZoneFree(NULL, _bitmapPlanes[i]);
        }
    }
    if (_bitmapPlanes != NULL) {
        NSZoneFree(NULL, _bitmapPlanes);
    }
    CGImageRelease(_cgImage);
    [_properties release];
    [_colorSpaceName release];
    [super dealloc];
}

- (int) incrementalLoadFromData: (NSData *) data complete: (BOOL) complete {
    NSUnimplementedMethod();
    return 0;
}

- (int) bitsPerPixel {
    return _bitsPerPixel;
}

- (int) samplesPerPixel {
    return _samplesPerPixel;
}

- (int) bytesPerRow {
    return _bytesPerRow;
}

- (BOOL) isPlanar {
    return _isPlanar;
}

- (int) numberOfPlanes {
    return _isPlanar ? _samplesPerPixel : 1;
}

- (int) bytesPerPlane {
    return _bytesPerPlane;
}

- (NSBitmapFormat) bitmapFormat {
    return _bitmapFormat;
}

- (unsigned char *) bitmapData {
    [self createBitmapIfNeeded];

    return _bitmapPlanes[0];
}

- (void) getBitmapDataPlanes: (unsigned char **) planes {
    [self createBitmapIfNeeded];

    int i, numberOfPlanes = [self numberOfPlanes];

    for (i = 0; i < numberOfPlanes; i++)
        planes[i] = _bitmapPlanes[i];

    for (; i < 5; i++)
        planes[i] = NULL;
}

- (void) getPixel: (NSUInteger[]) pixel atX: (NSInteger) x y: (NSInteger) y {
    NSUnimplementedMethod();
}

- (void) setPixel: (NSUInteger[]) pixel atX: (NSInteger) x y: (NSInteger) y {
    NSAssert(x >= 0 && x < [self pixelsWide], @"x out of bounds");
    NSAssert(y >= 0 && y < [self pixelsHigh], @"y out of bounds");

    [self createBitmapIfNeeded];

    if (_isPlanar) {
        NSUnimplementedMethod();
    } else {
        if (_bitsPerPixel / _samplesPerPixel != 8) {
            NSUnimplementedMethod();
        }
        unsigned char *bits =
                _bitmapPlanes[0] + _bytesPerRow * y + (x * _bitsPerPixel) / 8;

        int i;

        for (i = 0; i < _samplesPerPixel; i++) {
            bits[i] = pixel[i];
        }
    }
}

- (NSColor *) colorAtX: (NSInteger) x y: (NSInteger) y {
    NSUnimplementedMethod();
    return nil;
}

- (void) setColor: (NSColor *) color atX: (NSInteger) x y: (NSInteger) y {
    // Convert the color to a compatible format
    color = [color colorUsingColorSpaceName: [self colorSpaceName]];

    NSInteger i, numberOfComponents = [color numberOfComponents];
    CGFloat components[numberOfComponents];
    NSUInteger pixels[numberOfComponents];

    // Extract the RGBA components
    [color getComponents: components];

    if (!_hasAlpha) {
        // No alpha - then drop the component count
        numberOfComponents--;
    } else {
        // Deal with the alpha component
        if ((_bitmapFormat & NSAlphaNonpremultipliedBitmapFormat) ==
            NO) { // premultiplied
            CGFloat alpha = components[numberOfComponents - 1];

            // Multiply through the alpha
            for (i = 0; i < numberOfComponents - 1; i++) {
                components[i] *= alpha;
            }
        }

        if (_bitmapFormat & NSAlphaFirstBitmapFormat) {
            // Swap the location of the alpha component
            CGFloat alpha = components[numberOfComponents - 1];

            for (i = numberOfComponents; --i >= 1;) {
                components[i] = components[i - 1];
            }
            components[0] = alpha;
        }
    }

    if (_bitmapFormat & NSFloatingPointSamplesBitmapFormat) {
        for (i = 0; i < numberOfComponents; i++) {
            ((CGFloat *) pixels)[i] =
                    MAX(0.0f, MIN(1.0f, components[i])); // clamp just in case
        }
    } else {
        int maxValue = (1 << [self bitsPerSample]) - 1;

        for (i = 0; i < numberOfComponents; i++) {
#ifdef __LITTLE_ENDIAN__
            pixels[i] =
                    MAX(0, MIN(maxValue,
                               (int) (components[(numberOfComponents - 1) - i] *
                                      maxValue))); // clamp just in case
#else
            pixels[i] = MAX(
                    0, MIN(maxValue, (int) (components[i] *
                                            maxValue))); // clamp just in case
#endif
        }
    }

    [self setPixel: pixels atX: x y: y];
}

- valueForProperty: (NSString *) property {
    return [_properties objectForKey: property];
}

- (void) setProperty: (NSString *) property withValue: value {
    if(value){
        if(!_properties)_properties=[NSMutableDictionary new];
        [_properties setObject:value forKey:property];
    }else [_properties removeObjectForKey:property];
}

- (void) colorizeByMappingGray: (CGFloat) gray
                       toColor: (NSColor *) color
                  blackMapping: (NSColor *) blackMapping
                  whiteMapping: (NSColor *) whiteMapping
{
    NSUnimplementedMethod();
}

- (void) getCompression: (NSTIFFCompression *) compression
                 factor: (float *) factor
{
    NSUnimplementedMethod();
}

- (void) setCompression: (NSTIFFCompression) compression
                 factor: (float) factor
{
    NSUnimplementedMethod();
}

- (BOOL) canBeCompressedUsing: (NSTIFFCompression) compression {
    NSUnimplementedMethod();
    return NO;
}

- (NSData *) representationUsingType: (NSBitmapImageFileType) type
                          properties: (NSDictionary *) properties
{
    CFStringRef uti;

    switch (type) {

    case NSTIFFFileType:
        uti = (CFStringRef) @"public.tiff";
        break;

    case NSBMPFileType:
        uti = (CFStringRef) @"com.microsoft.bmp";
        break;

    case NSGIFFileType:
        uti = (CFStringRef) @"com.compuserve.gif";
        break;

    case NSJPEGFileType:
        uti = (CFStringRef) @"public.jpeg";
        break;

    case NSPNGFileType:
        uti = (CFStringRef) @"public.png";
        break;

    case NSJPEG2000FileType:
        uti = (CFStringRef) @"public.jpeg-2000";
        break;

    default:
        return nil;
    }

    int dpi = 72;
    if (_size.width > 0) {
        dpi = ceilf(72 * _pixelsWide / _size.width);
    }
    NSMutableData *result = [NSMutableData data];
    // Convert the NS options to CG options - just NSImageCompressionFactor for
    // now
    NSDictionary *CGProperties = [NSMutableDictionary dictionary];

    [CGProperties setValue: [NSNumber numberWithInt: dpi]
                    forKey: (id) kCGImageDestinationDPI];

    if ([properties count]) {
        id compressionFactor =
                [properties valueForKey: NSImageCompressionFactor];
        if (compressionFactor) {
            [CGProperties
                    setValue: compressionFactor
                      forKey: (id) kCGImageDestinationLossyCompressionQuality];
        }
    }
    CGImageDestinationRef dest = CGImageDestinationCreateWithData(
            (CFMutableDataRef) result, uti, 1, (CFDictionaryRef) CGProperties);

    CGImageDestinationAddImage(dest, [self CGImage],
                               (CFDictionaryRef) CGProperties);

    CGImageDestinationFinalize(dest);
    CFRelease(dest);

    return result;
}

- (NSData *) TIFFRepresentation {
    return [self TIFFRepresentationUsingCompression: NSTIFFCompressionNone
                                             factor: 0.0];
}

- (NSData *) TIFFRepresentationUsingCompression: (NSTIFFCompression) compression
                                         factor: (float) factor
{
    return [[self class]
            TIFFRepresentationOfImageRepsInArray: [NSArray
                                                          arrayWithObject: self]
                                usingCompression: compression
                                          factor: factor];
}

- (CGImageRef) createCGImageIfNeeded {
    if (_cgImage != NULL)
        return CGImageRetain(_cgImage);

    if (_isPlanar) {
        if (_bitsPerSample == 1 && _samplesPerPixel == 2 && _bitmapPlanes[0] && _bitmapPlanes[1]) {
            size_t pixelCount = (size_t)_pixelsWide * (size_t)_pixelsHigh;
            uint32_t *rgba = (uint32_t *)NSZoneMalloc(NULL, pixelCount * sizeof(uint32_t));
            const BOOL blackSpace = [_colorSpaceName isEqualToString:NSDeviceBlackColorSpace]
                    || [_colorSpaceName isEqualToString:NSCalibratedBlackColorSpace];
            const uint8_t *dataPlane = _bitmapPlanes[0];
            const uint8_t *maskPlane = _bitmapPlanes[1];

            for (int y = 0; y < _pixelsHigh; y++) {
                for (int x = 0; x < _pixelsWide; x++) {
                    int byteIdx = y * _bytesPerRow + (x / 8);
                    int bitIdx = 7 - (x % 8);
                    uint8_t dBit = (dataPlane[byteIdx] >> bitIdx) & 1;
                    uint8_t mBit = (maskPlane[byteIdx] >> bitIdx) & 1;

                    // Grayscale samples use the declared color space: 1 is white
                    // in white spaces and black in black spaces. Alpha 1 is opaque.
                    uint8_t a = mBit ? 0xFF : 0x00;
                    uint8_t rgb = (dBit != blackSpace) ? 0xFF : 0x00;
                    uint8_t r = (rgb * a) / 255;
                    uint8_t g = (rgb * a) / 255;
                    uint8_t b = (rgb * a) / 255;

                    rgba[y * _pixelsWide + x] = (a << 24) | (r << 16) | (g << 8) | b;
                }
            }

            NSData *data = [[NSData alloc] initWithBytesNoCopy: rgba
                                                        length: pixelCount * sizeof(uint32_t)
                                                  freeWhenDone: YES];
            CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef) data);
            [data release];

            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
            CGImageRef image = CGImageCreate(
                    _pixelsWide, _pixelsHigh, 8, 32, _pixelsWide * 4,
                    colorSpace,
                    kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host,
                    provider, NULL, NO, kCGRenderingIntentDefault);

            CGColorSpaceRelease(colorSpace);
            CGDataProviderRelease(provider);
            return image;
        } else {
            NSUnimplementedMethod();
        }
    }

    CGDataProviderRef provider = CGDataProviderCreateWithData(
            NULL, _bitmapPlanes[0], _bytesPerRow * _pixelsHigh, NULL);

    size_t bpc = _bitsPerSample ? _bitsPerSample : (_bitsPerPixel / _samplesPerPixel);

    CGImageRef image = CGImageCreate(
            _pixelsWide, _pixelsHigh, bpc,
            _bitsPerPixel, _bytesPerRow, [self CGColorSpace],
            [self CGBitmapInfo], provider, NULL, NO, kCGRenderingIntentDefault);

    CGDataProviderRelease(provider);

    return image;
}

- (CGImageRef) CGImage {
    if (_cgImage != NULL)
        return _cgImage;

    return (CGImageRef)[(id)[self createCGImageIfNeeded] autorelease];
}

- (BOOL) draw {
    CGContextRef context = NSCurrentGraphicsPort();
    if (context == NULL)
        return NO;
    NSSize size = [self size];
    CGImageRef image = [self createCGImageIfNeeded];
    if (image == NULL)
        return NO;

    CGContextDrawImage(context, NSMakeRect(0, 0, size.width, size.height),
                       image);

    CGImageRelease(image);

    return YES;
}

- (CGColorSpaceRef) CGColorSpace {
    if ([_colorSpaceName isEqualToString: NSDeviceRGBColorSpace])
        return (CGColorSpaceRef)[(id) CGColorSpaceCreateDeviceRGB()
                                         autorelease];
    if ([_colorSpaceName isEqualToString: NSCalibratedRGBColorSpace])
        return (CGColorSpaceRef)[(id) CGColorSpaceCreateDeviceRGB()
                                         autorelease];

    return NULL;
}

- (CGBitmapInfo) CGBitmapInfo {
    // The bitmap planes store samples in component order (RGBA, ARGB with NSAlphaFirstBitmapFormat), i.e. big-endian
    // for 8-bit samples; createBitmapIfNeeded copies CGImage data in that layout. Say so explicitly: Onyx2D treats
    // kCGBitmapByteOrderDefault as host (little) endian and would read and encode the channels reversed.
    CGBitmapInfo result = (_bitsPerSample == 8) ? kCGBitmapByteOrder32Big : kCGBitmapByteOrderDefault;

    if (![self hasAlpha]) {
        if (_bitsPerPixel == 32 && _samplesPerPixel == 3) {
            result |= (_bitmapFormat & NSAlphaFirstBitmapFormat) ? kCGImageAlphaNoneSkipFirst : kCGImageAlphaNoneSkipLast;
        } else {
            result |= kCGImageAlphaNone;
        }
    } else {
        if (_bitmapFormat & NSAlphaFirstBitmapFormat) {
            if (_bitmapFormat & NSAlphaNonpremultipliedBitmapFormat)
                result |= kCGImageAlphaFirst;
            else
                result |= kCGImageAlphaPremultipliedFirst;
        } else {
            if (_bitmapFormat & NSAlphaNonpremultipliedBitmapFormat)
                result |= kCGImageAlphaLast;
            else
                result |= kCGImageAlphaPremultipliedLast;
        }
    }
    if (_bitmapFormat & NSFloatingPointSamplesBitmapFormat)
        result |= kCGBitmapFloatComponents;

    return result;
}

- (NSBitmapImageRep *) bitmapImageRepByRetaggingWithColorSpace: (NSColorSpace *) newSpace {
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}


// Validate without recursively serializing or copying children: Foundation's
// object graph must preserve their identity and mutable classes.
static void QVImageValidateMetadata(id root, NSString *exception) {
    if (!root) return;
    QVImageCodingRequire([root isKindOfClass:[NSDictionary class]],exception,@"Expected bitmap metadata dictionary");
    NSMutableArray *nodes=[NSMutableArray arrayWithObject:root], *exits=[NSMutableArray arrayWithObject:@NO];
    NSMutableSet *active=[NSMutableSet set], *visited=[NSMutableSet set];
    QVImageCodingAllocated(nodes,@"Cannot allocate bitmap metadata traversal");QVImageCodingAllocated(exits,@"Cannot allocate bitmap metadata traversal");
    QVImageCodingAllocated(active,@"Cannot allocate bitmap metadata cycle guard");QVImageCodingAllocated(visited,@"Cannot allocate bitmap metadata validation");
    while ([nodes count]) {
        id node=[[[nodes lastObject]retain]autorelease];BOOL exit=[[exits lastObject]boolValue];
        [nodes removeLastObject];[exits removeLastObject];
        NSValue *identity=[NSValue valueWithPointer:node];
        if ([visited containsObject:identity]) continue;
        BOOL dictionary=[node isKindOfClass:[NSDictionary class]], array=[node isKindOfClass:[NSArray class]];
        if (!dictionary&&!array) {
            BOOL leaf=[node isKindOfClass:[NSString class]]||[node isKindOfClass:[NSData class]]||[node isKindOfClass:[NSNumber class]]||[node isKindOfClass:[NSDate class]];
            QVImageCodingRequire(leaf&&[NSPropertyListSerialization propertyList:node isValidForFormat:NSPropertyListBinaryFormat_v1_0],exception,@"Unsupported bitmap metadata value");
            [visited addObject:identity];
        } else if (!exit) {
            QVImageCodingRequire(![active containsObject:identity],exception,@"Cyclic bitmap metadata");
            [active addObject:identity];[nodes addObject:node];[exits addObject:@YES];
            for (id key in node) {
                if (dictionary) QVImageCodingRequire([key isKindOfClass:[NSString class]],exception,@"Non-string bitmap metadata key");
                [nodes addObject:dictionary?[node objectForKey:key]:key];[exits addObject:@NO];
            }
        } else {
            [active removeObject:identity];[visited addObject:identity];
        }
    }
}

static void QVImageValidateBitmapRecord(NSDictionary *record, NSString *exception) {
    QVImageCodingRequire([record isKindOfClass:[NSDictionary class]]&&[[record objectForKey:@"tag"]isEqual:@"QvolutionBitmap"]&&QVImageCodingInteger([record objectForKey:@"version"],INT_MAX,exception)==1,exception,@"Unknown bitmap archive version");
    NSUInteger width=QVImageCodingInteger([record objectForKey:@"width"],INT_MAX,exception),height=QVImageCodingInteger([record objectForKey:@"height"],INT_MAX,exception);
    NSUInteger samples=QVImageCodingInteger([record objectForKey:@"samples"],4,exception),bits=QVImageCodingInteger([record objectForKey:@"bits"],32,exception),stride=QVImageCodingInteger([record objectForKey:@"stride"],INT_MAX,exception);
    NSUInteger format=QVImageCodingInteger([record objectForKey:@"format"],NSAlphaFirstBitmapFormat|NSAlphaNonpremultipliedBitmapFormat,exception);
    BOOL alpha=QVImageCodingInteger([record objectForKey:@"alpha"],1,exception);
    QVImageCodingInteger([record objectForKey:@"opaque"],1,exception);
    QVImageCodingInteger([record objectForKey:@"bytesPerPlane"],INT_MAX,exception);
    NSString *space=[record objectForKey:@"colorSpace"], *storage=[record objectForKey:@"storage"];
    QVImageCodingRequire([space isKindOfClass:[NSString class]]&&([space isEqual:NSDeviceRGBColorSpace]||[space isEqual:NSCalibratedRGBColorSpace]),exception,@"Unsupported bitmap archive color space");
    QVImageCodingSize([record objectForKey:@"size"],exception);
    QVImageCodingRequire(QVImagePackedRGBExtent(width,height,samples,bits,stride,format,alpha),exception,@"Invalid packed8 RGB bitmap archive extent");
    BOOL planes=[storage isEqual:@"plane"]||[storage isEqual:@"both"], cg=[storage isEqual:@"cg"]||[storage isEqual:@"both"];
    QVImageCodingRequire(planes||cg,exception,@"Unknown bitmap archive storage");
    if (planes) {
        NSData *data=[record objectForKey:@"planeData"];
        QVImageCodingRequire([data isKindOfClass:[NSData class]]&&[data length]==stride*height,exception,@"Truncated bitmap archive plane");
    }
    if (cg) {
        NSData *data=[record objectForKey:@"cgData"];
        QVImageCodingRequire([data isKindOfClass:[NSData class]]&&[data length]>=(height-1)*stride+width*(bits/8),exception,@"Truncated CG bitmap archive bytes");
        NSUInteger info=QVImageCodingInteger([record objectForKey:@"cgInfo"],UINT_MAX,exception);
        QVImageCodingRequire(QVImageCGBitmapLayout(bits,alpha,format,info),exception,@"Unsupported CG bitmap archive layout");
        QVImageCodingInteger([record objectForKey:@"cgInterpolate"],1,exception);
        QVImageCodingInteger([record objectForKey:@"cgIntent"],kCGRenderingIntentPerceptual,exception);
        id name=[record objectForKey:@"cgColorSpace"];
        QVImageCodingRequire(!name||[name isKindOfClass:[NSString class]],exception,@"Invalid CG bitmap archive color-space name");
    }
    QVImageValidateMetadata([record objectForKey:@"properties"],exception);
}

- (void)_qvolutionValidateBitmapState:(NSString *)exception providerData:(CFDataRef *)providerData {
    if(providerData)*providerData=NULL;
    QVImageCodingRequire([self class]==[NSBitmapImageRep class]&&!_isPlanar&&_bitsPerSample==8,exception,@"Unsupported bitmap archive representation");
    QVImageCodingRequire(QVImagePackedRGBExtent(_pixelsWide,_pixelsHigh,_samplesPerPixel,_bitsPerPixel,_bytesPerRow,_bitmapFormat,_hasAlpha!=NO)&&_bytesPerPlane>=0,exception,@"Invalid packed8 bitmap state");
    QVImageCodingRequire([_colorSpaceName isKindOfClass:[NSString class]]&&([_colorSpaceName isEqual:NSDeviceRGBColorSpace]||[_colorSpaceName isEqual:NSCalibratedRGBColorSpace])&&QVImageCodingValidSize(_size),exception,@"Unsupported bitmap geometry or color space");
    QVImageCodingRequire(_bitmapPlanes||_cgImage,exception,@"Missing bitmap archive storage");
    if(_bitmapPlanes)QVImageCodingRequire(_bitmapPlanes[0]!=NULL,exception,@"Missing bitmap archive plane");
    CFDataRef bytes=NULL;
    @try {
        if(_cgImage){
#ifdef DARLING
            QVImageCodingRequire(!O2ImageGetMask((O2ImageRef)_cgImage),exception,@"Unsupported masked CG bitmap archive");
#else
            QVImageCodingRequire(NO,exception,@"CG-backed archive requires lossless mask-state inspection");
#endif
            QVImageCodingRequire(CGImageGetWidth(_cgImage)==_pixelsWide&&CGImageGetHeight(_cgImage)==_pixelsHigh&&CGImageGetBitsPerComponent(_cgImage)==8&&
                CGImageGetBitsPerPixel(_cgImage)==_bitsPerPixel&&CGImageGetBytesPerRow(_cgImage)==_bytesPerRow&&CGColorSpaceGetModel(CGImageGetColorSpace(_cgImage))==kCGColorSpaceModelRGB&&
                !CGImageIsMask(_cgImage)&&!CGImageGetDecode(_cgImage)&&QVImageCGBitmapLayout(_bitsPerPixel,_hasAlpha!=NO,_bitmapFormat,CGImageGetBitmapInfo(_cgImage)),exception,@"Unsupported CG-backed bitmap state");
            QVImageCodingRequire(CGImageGetRenderingIntent(_cgImage)>=kCGRenderingIntentDefault&&CGImageGetRenderingIntent(_cgImage)<=kCGRenderingIntentPerceptual,exception,@"Invalid CG bitmap rendering intent");
            CFStringRef name=CGColorSpaceGetName(CGImageGetColorSpace(_cgImage));
            QVImageCodingRequire(!name||[(id)name isKindOfClass:[NSString class]],exception,@"Invalid CG bitmap color-space name");
            bytes=CGDataProviderCopyData(CGImageGetDataProvider(_cgImage));
            NSUInteger needed=(NSUInteger)_bytesPerRow*(_pixelsHigh-1)+(NSUInteger)_pixelsWide*(_bitsPerPixel/8);
            QVImageCodingRequire(bytes&&CFDataGetLength(bytes)>=0&&(NSUInteger)CFDataGetLength(bytes)>=needed,exception,@"Truncated CG bitmap provider");
        }
        QVImageValidateMetadata(_properties,exception);
        if(providerData){*providerData=bytes;bytes=NULL;}
    } @finally {if(bytes)CFRelease(bytes);}
}

- (NSDictionary *)_qvolutionBitmapRecord {
    NSString *exception=NSInvalidArchiveOperationException;CFDataRef provider=NULL;
    [self _qvolutionValidateBitmapState:exception providerData:&provider];
    @try {
        NSMutableDictionary *record=[NSMutableDictionary dictionaryWithDictionary:@{@"tag":@"QvolutionBitmap",@"version":@1,
            @"width":@(_pixelsWide),@"height":@(_pixelsHigh),@"samples":@(_samplesPerPixel),@"bits":@(_bitsPerPixel),@"stride":@(_bytesPerRow),@"format":@(_bitmapFormat),
            @"alpha":@(_hasAlpha!=NO),@"opaque":@(_isOpaque!=NO),@"bytesPerPlane":@(_bytesPerPlane),@"size":QVImageCodingSizeRecord(_size,exception),@"colorSpace":_colorSpaceName,
            @"storage":(_bitmapPlanes?(_cgImage?@"both":@"plane"):@"cg")}];
        QVImageCodingAllocated(record,@"Cannot allocate bitmap archive record");
        if(_bitmapPlanes)[record setObject:[NSData dataWithBytes:_bitmapPlanes[0]length:(NSUInteger)_bytesPerRow*_pixelsHigh]forKey:@"planeData"];
        if(_cgImage){
            [record setObject:(NSData *)provider forKey:@"cgData"];
            [record setObject:@(CGImageGetBitmapInfo(_cgImage))forKey:@"cgInfo"];
            [record setObject:@(CGImageGetShouldInterpolate(_cgImage)!=NO)forKey:@"cgInterpolate"];
            [record setObject:@(CGImageGetRenderingIntent(_cgImage))forKey:@"cgIntent"];
            CFStringRef name=CGColorSpaceGetName(CGImageGetColorSpace(_cgImage));if(name)[record setObject:(NSString *)name forKey:@"cgColorSpace"];
        }
        if(_properties)[record setObject:QVImageCodingAllocated([[_properties copy]autorelease],@"Cannot snapshot bitmap property dictionary")forKey:@"properties"];
        QVImageValidateBitmapRecord(record,exception);
        return QVImageCodingAllocated([[record copy]autorelease],@"Cannot snapshot bitmap archive record");
    } @finally {if(provider)CFRelease(provider);}
}

- (id)_qvolutionInitWithBitmapRecord:(NSDictionary *)record {
    NSString *exception=NSInvalidUnarchiveOperationException;
    NSBitmapImageRep *rep=self;
    @try {
        QVImageCodingRequire([self class]==[NSBitmapImageRep class],exception,@"Unsupported decoded bitmap subclass");
        QVImageValidateBitmapRecord(record,exception);
        int width=[[record objectForKey:@"width"]intValue],height=[[record objectForKey:@"height"]intValue],bits=[[record objectForKey:@"bits"]intValue],stride=[[record objectForKey:@"stride"]intValue];
        NSString *storage=[record objectForKey:@"storage"];
        if (![storage isEqual:@"cg"]) {
            NSData *data=[record objectForKey:@"planeData"];
            rep=[rep initWithBitmapDataPlanes:NULL pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:[[record objectForKey:@"samples"]intValue]
                hasAlpha:[[record objectForKey:@"alpha"]boolValue] isPlanar:NO colorSpaceName:[record objectForKey:@"colorSpace"] bitmapFormat:[[record objectForKey:@"format"]unsignedIntegerValue] bytesPerRow:stride bitsPerPixel:bits];
            QVImageCodingAllocated(rep,@"Cannot allocate decoded bitmap plane");
            QVImageCodingAllocated(rep->_colorSpaceName,@"Cannot copy decoded bitmap color space");
            memcpy(rep->_bitmapPlanes[0],[data bytes],[data length]);
        }
        if (![storage isEqual:@"plane"]) {
            NSData *data=[record objectForKey:@"cgData"];
            id name=[record objectForKey:@"cgColorSpace"];
            CGColorSpaceRef space=name?CGColorSpaceCreateWithName((CFStringRef)name):CGColorSpaceCreateDeviceRGB();
            CGDataProviderRef provider=NULL;CGImageRef image=NULL;
            @try {
                QVImageCodingRequire(space&&CGColorSpaceGetModel(space)==kCGColorSpaceModelRGB,exception,@"Cannot restore CG bitmap color space");
                NSData *owned=QVImageCodingAllocated([[data copy]autorelease],@"Cannot copy decoded CG provider bytes");
                QVImageCodingRequire([owned isKindOfClass:[NSData class]]&&[owned length]==[data length],exception,@"Inconsistent decoded CG provider copy");
                provider=CGDataProviderCreateWithCFData((CFDataRef)owned);
                QVImageCodingRequire(provider!=NULL,NSMallocException,@"Cannot create decoded CG provider");
                image=CGImageCreate(width,height,8,bits,stride,space,[[record objectForKey:@"cgInfo"]unsignedIntValue],provider,NULL,[[record objectForKey:@"cgInterpolate"]boolValue],[[record objectForKey:@"cgIntent"]unsignedIntValue]);
                QVImageCodingRequire(image!=NULL,exception,@"Cannot restore CG bitmap image");
                if ([storage isEqual:@"both"]) rep->_cgImage=CGImageRetain(image);
                else rep=[rep initWithCGImage:image];
            } @finally { if(image)CGImageRelease(image);if(provider)CGDataProviderRelease(provider);if(space)CGColorSpaceRelease(space); }
            QVImageCodingRequire(rep!=nil,exception,@"Cannot restore CG-backed bitmap representation");
            [rep->_colorSpaceName release];rep->_colorSpaceName=[[record objectForKey:@"colorSpace"]copy];
            QVImageCodingAllocated(rep->_colorSpaceName,@"Cannot copy decoded bitmap color space");
        }
        rep->_size=QVImageCodingSize([record objectForKey:@"size"],exception);
        rep->_isOpaque=[[record objectForKey:@"opaque"]boolValue];
        rep->_bytesPerPlane=[[record objectForKey:@"bytesPerPlane"]intValue];
        id metadata=[record objectForKey:@"properties"];
        rep->_properties=[metadata mutableCopy];
        if(metadata)QVImageCodingAllocated(rep->_properties,@"Cannot copy decoded bitmap metadata");
    } @catch(NSException *error) { [rep release];@throw; }
    return rep;
}

@end
