#import <Onyx2D/O2ColorSpace+PDF.h>
#import <Onyx2D/O2DataProvider.h>
#import <Onyx2D/O2Image+PDF.h>
#import <Onyx2D/O2PDFArray.h>
#import <Onyx2D/O2PDFContext.h>
#import <Onyx2D/O2PDFDictionary.h>
#import <Onyx2D/O2PDFStream.h>

#if defined(__APPLE__) && !defined(DARLING)
#else
#import <Onyx2D/O2Defines_zlib.h>
#endif

#if ZLIB_PRESENT
#import <zlib.h>
#endif

// Image-paint masks use their red sample as coverage. Scale nested masks to
// their parent image just as a full-image draw does; byte-export preflight has
// already bounded and converted this graph.
static unsigned O2PDFImageMaskCoverage(O2Image *mask, size_t x, size_t y,
        size_t parentWidth, size_t parentHeight) {
    size_t u = ((uint64_t)x * 2 + 1) * O2ImageGetWidth(mask) / ((uint64_t)parentWidth * 2);
    size_t v = ((uint64_t)y * 2 + 1) * O2ImageGetHeight(mask) / ((uint64_t)parentHeight * 2);
    O2argb8u sample;
    O2argb8u *direct = O2Image_read_argb8u(mask, u, v, &sample, 1);
    if (direct != NULL) sample = *direct;
    unsigned coverage = sample.r;
    if (O2ImageGetMask(mask) != nil)
        coverage = (coverage * O2PDFImageMaskCoverage(O2ImageGetMask(mask), x, y,
                parentWidth, parentHeight) + 127) / 255;
    return coverage;
}

static void O2PDFImageCopyDecode(O2PDFDictionary *dictionary, O2Image *image) {
    const O2Float *decode = O2ImageGetDecode(image);
    if (decode != NULL) {
        size_t components = O2ImageIsMask(image) ? 1 :
                O2ColorSpaceGetNumberOfComponents(O2ImageGetColorSpace(image));
        [dictionary setObjectForKey: "Decode"
                value: [O2PDFArray pdfArrayWithNumbers: decode count: components * 2]];
    }
}

@implementation O2Image (PDF)

O2ColorRenderingIntent O2ImageRenderingIntentWithName(const char *name) {
    if (name == NULL)
        return kO2RenderingIntentDefault;

    if (strcmp(name, "AbsoluteColorimetric") == 0)
        return kO2RenderingIntentAbsoluteColorimetric;
    else if (strcmp(name, "RelativeColorimetric") == 0)
        return kO2RenderingIntentRelativeColorimetric;
    else if (strcmp(name, "Saturation") == 0)
        return kO2RenderingIntentSaturation;
    else if (strcmp(name, "Perceptual") == 0)
        return kO2RenderingIntentPerceptual;
    else
        return kO2RenderingIntentDefault; // unknown
}

const char *O2ImageNameWithIntent(O2ColorRenderingIntent intent) {
    switch (intent) {

    case kO2RenderingIntentAbsoluteColorimetric:
        return "AbsoluteColorimetric";

    case kO2RenderingIntentRelativeColorimetric:
        return "RelativeColorimetric";

    case kO2RenderingIntentSaturation:
        return "Saturation";

    default:
    case kO2RenderingIntentDefault:
    case kO2RenderingIntentPerceptual:
        return "Perceptual";
    }
}

- (O2PDFObject *) encodeReferenceWithContext: (O2PDFContext *) context {
    O2ImageRef byteImage = O2ImageCreateCopyForByteExport(self);
    if (byteImage == nil)
        return nil;
    if (byteImage != self) {
        O2PDFObject *converted = [byteImage encodeReferenceWithContext: context];
        O2ImageRelease(byteImage);
        return converted;
    }
    O2ImageRelease(byteImage);
    if (_mask == nil && O2ImageDecoderGetCompressionType(_decoder) == O2ImageCompressionJPEG) {
        O2PDFStream *result = [O2PDFStream pdfStream];
        O2PDFDictionary *dictionary = [result dictionary];
        [dictionary setNameForKey: "Type" value: "XObject"];
        [dictionary setNameForKey: "Subtype" value: "Image"];
        [dictionary setIntegerForKey: "Width" value: _width];
        [dictionary setIntegerForKey: "Height" value: _height];
        [dictionary setIntegerForKey: "BitsPerComponent" value: _bitsPerComponent];
        [dictionary setNameForKey: "Intent" value: O2ImageNameWithIntent(_renderingIntent)];
        [dictionary setBooleanForKey: "Interpolate" value: _interpolate];
        O2PDFImageCopyDecode(dictionary, self);
        [dictionary setObjectForKey: "ColorSpace"
                value: [_colorSpace encodeReferenceWithContext: context]];
        [dictionary setNameForKey: "Filter" value: "DCTDecode"];
        CFDataRef data = O2DataProviderCopyData(O2ImageDecoderGetDataProvider(_decoder));
        [[result mutableData] appendData: (NSData *)data];
        CFRelease(data);
        return [context encodeIndirectPDFObject: result];
    }
    O2ColorSpaceModel model = O2ColorSpaceGetModel(_colorSpace);
    BOOL packedGray = model == kO2ColorSpaceModelMonochrome &&
            (_bitsPerComponent == 1 || _bitsPerComponent == 8) &&
            _bitsPerPixel == _bitsPerComponent;
    BOOL packedIndexed = model == kO2ColorSpaceModelIndexed &&
            _bitsPerComponent == 8 && _bitsPerPixel == 8;
    BOOL packedCMYK = model == kO2ColorSpaceModelCMYK &&
            _bitsPerComponent == 8 && _bitsPerPixel == 32;
    if ((packedGray || packedIndexed || packedCMYK) && _mask == nil &&
            (!_isMask || _bitsPerComponent == 1)) {
        O2PDFStream *result = [O2PDFStream pdfStream];
        O2PDFDictionary *dictionary = [result dictionary];
        [dictionary setNameForKey: "Type" value: "XObject"];
        [dictionary setNameForKey: "Subtype" value: "Image"];
        [dictionary setIntegerForKey: "Width" value: _width];
        [dictionary setIntegerForKey: "Height" value: _height];
        [dictionary setIntegerForKey: "BitsPerComponent" value: _bitsPerComponent];
        [dictionary setNameForKey: "Intent" value: O2ImageNameWithIntent(_renderingIntent)];
        [dictionary setBooleanForKey: "Interpolate" value: _interpolate];
        O2PDFImageCopyDecode(dictionary, self);
        [dictionary setBooleanForKey: "ImageMask" value: _isMask];
        if (!_isMask)
            [dictionary setObjectForKey: "ColorSpace"
                    value: [_colorSpace encodeReferenceWithContext: context]];
        const uint8_t *bytes = [self directBytes];
        size_t rowLength = (_width * _bitsPerPixel + 7) / 8;
        for (size_t y = 0; y < _height; y++)
            [[result mutableData] appendBytes: bytes + y * _bytesPerRow length: rowLength];
        return [context encodeIndirectPDFObject: result];
    }
    // The RGB sampler exposes premultiplied components. PDF color samples are
    // unassociated; preserve alpha in a separate gray soft-mask stream.
    if (!_isMask) {
        O2PDFStream *rgb = [O2PDFStream pdfStream];
        O2PDFStream *alpha = [O2PDFStream pdfStream];
        O2PDFDictionary *dictionary = [rgb dictionary];
        [dictionary setNameForKey: "Type" value: "XObject"];
        [dictionary setNameForKey: "Subtype" value: "Image"];
        [dictionary setIntegerForKey: "Width" value: _width];
        [dictionary setIntegerForKey: "Height" value: _height];
        [dictionary setIntegerForKey: "BitsPerComponent" value: 8];
        if (O2ColorSpaceGetModel(_colorSpace) == kO2ColorSpaceModelRGB)
            [dictionary setObjectForKey: "ColorSpace"
                    value: [_colorSpace encodeReferenceWithContext: context]];
        else
            [dictionary setNameForKey: "ColorSpace" value: "DeviceRGB"];
        [dictionary setBooleanForKey: "Interpolate" value: _interpolate];
        [dictionary setNameForKey: "Intent" value: O2ImageNameWithIntent(_renderingIntent)];
        if (O2ColorSpaceGetModel(_colorSpace) == kO2ColorSpaceModelRGB)
            O2PDFImageCopyDecode(dictionary, self);
        BOOL needsAlpha = NO;
        O2argb8u span[256];
        uint8_t colors[256 * 3], coverage[256];
        for (size_t y = 0; y < _height; y++) {
            for (size_t x = 0; x < _width;) {
                int chunk = MIN(256, _width - x);
                O2argb8u *samples = O2Image_read_argb8u(self, x, y, span, chunk);
                if (samples == NULL) samples = span;
                for (int i = 0; i < chunk; i++) {
                    O2argb8u sample = samples[i];
                    unsigned a = sample.a;
                    unsigned r = a ? (sample.r * 255 + a / 2) / a : 0;
                    unsigned g = a ? (sample.g * 255 + a / 2) / a : 0;
                    unsigned b = a ? (sample.b * 255 + a / 2) / a : 0;
                    colors[i * 3] = MIN(r, 255);
                    colors[i * 3 + 1] = MIN(g, 255);
                    colors[i * 3 + 2] = MIN(b, 255);
                    if (_mask != nil)
                        a = (a * O2PDFImageMaskCoverage(_mask, x + i, y,
                                _width, _height) + 127) / 255;
                    coverage[i] = a;
                    needsAlpha |= a != 255;
                }
                [[rgb mutableData] appendBytes: colors length: chunk * 3];
                [[alpha mutableData] appendBytes: coverage length: chunk];
                x += chunk;
            }
        }
        if (needsAlpha) {
            O2PDFDictionary *maskDictionary = [alpha dictionary];
            [maskDictionary setNameForKey: "Type" value: "XObject"];
            [maskDictionary setNameForKey: "Subtype" value: "Image"];
            [maskDictionary setIntegerForKey: "Width" value: _width];
            [maskDictionary setIntegerForKey: "Height" value: _height];
            [maskDictionary setIntegerForKey: "BitsPerComponent" value: 8];
            [maskDictionary setBooleanForKey: "Interpolate" value: _interpolate];
            [maskDictionary setNameForKey: "ColorSpace" value: "DeviceGray"];
            [dictionary setObjectForKey: "SMask"
                    value: [context encodeIndirectPDFObject: alpha]];
        }
        return [context encodeIndirectPDFObject: rgb];
    }
    return nil;
}

+ (O2Image *) imageWithPDFObject: (O2PDFObject *) object {
    O2PDFStream *stream = (O2PDFStream *) object;
    O2PDFDictionary *dictionary = [stream dictionary];
    O2PDFInteger width;
    O2PDFInteger height;
    O2PDFObject *colorSpaceObject = NULL;
    O2PDFInteger bitsPerComponent;
    const char *intent;
    O2PDFBoolean isImageMask = NO;
    O2PDFObject *imageMaskObject = NULL;
    O2ColorSpaceRef colorSpace = NULL;
    int componentsPerPixel;
    O2PDFArray *decodeArray;
    O2Float *decode = NULL;
    BOOL interpolate;
    O2PDFStream *softMaskStream = nil;
    O2Image *softMask = NULL;

    if (![dictionary getIntegerForKey: "Width" value: &width]) {
        O2PDFError(__FILE__, __LINE__, @"Image has no Width");
        return NULL;
    }
    if (![dictionary getIntegerForKey: "Height" value: &height]) {
        O2PDFError(__FILE__, __LINE__, @"Image has no Height");
        return NULL;
    }

    if (![dictionary getIntegerForKey: "BitsPerComponent"
                                value: &bitsPerComponent]) {
        O2PDFError(__FILE__, __LINE__, @"Image has no BitsPerComponent");
        return NULL;
    }

    if (![dictionary getNameForKey: "Intent" value: &intent])
        intent = NULL;

    [dictionary getBooleanForKey: "ImageMask" value: &isImageMask];

    if (isImageMask)
        O2PDFFix(__FILE__, __LINE__, @"ImageMask present");

    if ([dictionary getObjectForKey: "Mask" value: &imageMaskObject]) {
        O2PDFFix(__FILE__, __LINE__, @"Mask present");
    }

    if ([dictionary getObjectForKey: "ColorSpace" value: &colorSpaceObject]) {
        if ((colorSpace = [O2ColorSpace
                     createColorSpaceFromPDFObject: colorSpaceObject]) ==
            NULL) {
            O2PDFError(__FILE__, __LINE__, @"Unable to create ColorSpace %@",
                       colorSpaceObject);
            return NULL;
        }
    }

    if (!isImageMask && colorSpace == NULL) {
        O2PDFError(__FILE__, __LINE__, @"Image has no ColorSpace %@",
                   dictionary);
        return NULL;
    }

    if (colorSpace == NULL)
        componentsPerPixel = 1;
    else
        componentsPerPixel = O2ColorSpaceGetNumberOfComponents(colorSpace);

    if (![dictionary getArrayForKey: "Decode" value: &decodeArray])
        decode = NULL;
    else {
        NSUInteger count;

        if (![decodeArray getNumbers: &decode count: &count]) {
            O2PDFError(__FILE__, __LINE__, @"Unable to read decode array %@",
                       decodeArray);
            return NULL;
        }

        if (count != componentsPerPixel * 2) {
            O2PDFError(__FILE__, __LINE__,
                       @"Invalid decode array, count=%d, should be %d", count,
                       componentsPerPixel * 2);
            return NULL;
        }
    }

    if (![dictionary getBooleanForKey: "Interpolate" value: &interpolate])
        interpolate = NO;

    if ([dictionary getStreamForKey: "SMask" value: &softMaskStream]) {
        softMask = [self imageWithPDFObject: softMaskStream];
    }

    NSData *data = [stream data];
    int bitsPerPixel = componentsPerPixel * bitsPerComponent;
    int bytesPerRow = ([stream bytesPerRow] != 0)
                              ? [stream bytesPerRow]
                              : ((width * bitsPerPixel) + 7) / 8;
    O2DataProvider *provider;
    O2Image *image = NULL;

    //     NSLog(@"width=%d,height=%d,bpc=%d,bpp=%d,bpr=%d,cpp=%d",width,height,bitsPerComponent,bitsPerPixel,bytesPerRow,componentsPerPixel);

    if (height * bytesPerRow != [data length]) {
        O2PDFError(__FILE__, __LINE__,
                   @"Invalid data length=%d,should be %d=%d", [data length],
                   height * bytesPerRow, [data length] - height * bytesPerRow);
    }

    if (height * bytesPerRow > [data length]) {
        // provide some gray data
        NSMutableData *mutable =
                [NSMutableData dataWithLength: height * bytesPerRow];
        char *mbytes = [mutable mutableBytes];
        int i;
        for (i = 0; i < height * bytesPerRow; i++)
            mbytes[i] = i;

        data = mutable;
    }

    provider = O2DataProviderCreateWithCFData((CFDataRef) data);
    if (isImageMask) {
        image = [[O2Image alloc] initMaskWithWidth: width
                                            height: height
                                  bitsPerComponent: bitsPerComponent
                                      bitsPerPixel: bitsPerPixel
                                       bytesPerRow: bytesPerRow
                                          provider: provider
                                            decode: decode
                                       interpolate: interpolate];
    } else {
        image = [[O2Image alloc]
                   initWithWidth: width
                          height: height
                bitsPerComponent: bitsPerComponent
                    bitsPerPixel: bitsPerPixel
                     bytesPerRow: bytesPerRow
                      colorSpace: colorSpace
                      bitmapInfo: 0
                         decoder: NULL
                        provider: provider
                          decode: decode
                     interpolate: interpolate
                 renderingIntent: O2ImageRenderingIntentWithName(intent)];

        if (softMask != NULL)
            [image setMask: softMask];
    }

    if (decode != NULL)
        NSZoneFree(NULL, decode);

    O2DataProviderRelease(provider);
    O2ColorSpaceRelease(colorSpace);

    return image;
}

@end
