#import <Onyx2D/O2Encoder_JPG.h>
#import <Onyx2D/O2Encoder_PNG.h>
#import <Onyx2D/O2Encoder_TIFF.h>
#import <Onyx2D/O2Exceptions.h>
#import <Onyx2D/O2Image.h>
#import <Onyx2D/O2ImageDestination.h>

// Using the same value as CoreGraphics - that's removing the needs for
// conversion
const CFStringRef kO2ImageDestinationLossyCompressionQuality =
        (const CFStringRef) @"kCGImageDestinationLossyCompressionQuality";
const CFStringRef kO2ImageDestinationBackgroundColor =
        (const CFStringRef) @"kCGImageDestinationBackgroundColor";
const CFStringRef kO2ImageDestinationDPI =
        (const CFStringRef) @"kCGImageDestinationDPI";

@interface _O2ImageDestination : O2ImageDestination
@end

@implementation O2ImageDestination

typedef enum {
    O2ImageFileUnknown,
    O2ImageFileTIFF,
    O2ImageFileBMP,
    O2ImageFileGIF,
    O2ImageFileJPEG,
    O2ImageFilePNG,
    O2ImageFileJPEG2000,
} O2ImageFileType;

static O2ImageFileType fileTypeForUTI(CFStringRef uti) {

    if ([(NSString *) uti isEqualToString: @"public.tiff"])
        return O2ImageFileTIFF;

    if ([(NSString *) uti isEqualToString: @"com.microsoft.bmp"])
        return O2ImageFileBMP;

    if ([(NSString *) uti isEqualToString: @"com.compuserve.gif"])
        return O2ImageFileGIF;

    if ([(NSString *) uti isEqualToString: @"public.jpeg"])
        return O2ImageFileJPEG;

    if ([(NSString *) uti isEqualToString: @"public.png"])
        return O2ImageFilePNG;

    if ([(NSString *) uti isEqualToString: @"public.jpeg-2000"])
        return O2ImageFileJPEG2000;

    return O2ImageFileUnknown;
}

CFTypeID O2ImageDestinationGetTypeID(void) {
    return 0;
}

CFArrayRef O2ImageDestinationCopyTypeIdentifiers(void) {
    O2UnimplementedFunction();
    return NULL;
}

O2ImageDestinationRef O2ImageDestinationCreateWithData(CFMutableDataRef data,
                                                       CFStringRef type,
                                                       size_t imageCount,
                                                       CFDictionaryRef options)
{
    O2DataConsumerRef consumer = O2DataConsumerCreateWithCFData(data);
    O2ImageDestinationRef self = O2ImageDestinationCreateWithDataConsumer(
            consumer, type, imageCount, options);
    O2DataConsumerRelease(consumer);
    return self;
}

O2ImageDestinationRef
O2ImageDestinationCreateWithDataConsumer(O2DataConsumerRef dataConsumer,
                                         CFStringRef type, size_t imageCount,
                                         CFDictionaryRef options)
{
    O2ImageDestinationRef self =
            NSAllocateObject([O2ImageDestination class], 0, NULL);

    if (self) {

        self->_consumer = O2DataConsumerRetain(dataConsumer);
        self->_type = fileTypeForUTI(type);
        self->_imageCount = imageCount;
        self->_options = (options == NULL) ? NULL : CFRetain(options);

        switch (self->_type) {

        case O2ImageFileUnknown:
            break;

        case O2ImageFileTIFF:
            self->_encoder = O2TIFFEncoderCreate(self->_consumer);
            O2TIFFEncoderBegin(self->_encoder);
            break;

        case O2ImageFileBMP:
            break;

        case O2ImageFileGIF:
            break;

        case O2ImageFileJPEG:
#ifdef LIBJPEG_PRESENT
            self->_encoder = O2JPGEncoderCreate(self->_consumer);
#endif
            break;

        case O2ImageFilePNG:
            self->_encoder = O2PNGEncoderCreate(self->_consumer);
            break;

        case O2ImageFileJPEG2000:
            break;
        }
    }

    return self;
}

O2ImageDestinationRef O2ImageDestinationCreateWithURL(CFURLRef url,
                                                      CFStringRef type,
                                                      size_t imageCount,
                                                      CFDictionaryRef options)
{
    O2DataConsumerRef consumer = O2DataConsumerCreateWithURL(url);
    O2ImageDestinationRef self = O2ImageDestinationCreateWithDataConsumer(
            consumer, type, imageCount, options);
    O2DataConsumerRelease(consumer);
    return self;
}

void O2ImageDestinationSetProperties(O2ImageDestinationRef self,
                                     CFDictionaryRef properties)
{
}

void O2ImageDestinationAddImage(O2ImageDestinationRef self, O2ImageRef image,
                                CFDictionaryRef properties)
{
    if (self->_failed || self->_encoder == NULL || self->_imageCount == 0 ||
            image == nil) {
        self->_failed = YES;
        return;
    }
    if (self->_type == O2ImageFilePNG && self->_imageCount != 1) {
        self->_failed = YES;
        O2PNGEncoderWriteImage(self->_encoder, NULL, NULL);
        return;
    }
#ifdef LIBJPEG_PRESENT
    if (self->_type == O2ImageFileJPEG && !O2JPGEncoderCanWriteImage(image)) {
        self->_failed = YES;
        return;
    }
#endif
    O2ImageRef byteImage = O2ImageCreateCopyForByteExport(image);
    if (byteImage == nil) {
        self->_failed = YES;
        return;
    }
    image = byteImage;
    bool wroteImage = false;

    switch (self->_type) {

    case O2ImageFileUnknown:
        break;

    case O2ImageFileTIFF:
        wroteImage = O2TIFFEncoderWriteImage(self->_encoder, image, properties,
                                self->_imageCount == 1);
        break;

    case O2ImageFileBMP:
        break;

    case O2ImageFileGIF:
        break;

    case O2ImageFileJPEG:
#ifdef LIBJPEG_PRESENT
        wroteImage = O2JPGEncoderWriteImage(self->_encoder, image, properties);
#endif
        break;

    case O2ImageFilePNG:
        O2PNGEncoderWriteImage(self->_encoder, image, properties);
        wroteImage = O2PNGEncoderIsComplete(self->_encoder);
        break;

    case O2ImageFileJPEG2000:
        break;
    }
    if (wroteImage)
        self->_imageCount--;
    else
        self->_failed = YES;
    O2ImageRelease(byteImage);
}

void O2ImageDestinationAddImageFromSource(O2ImageDestinationRef self,
                                          O2ImageSourceRef imageSource,
                                          size_t index,
                                          CFDictionaryRef properties)
{
    O2ImageRef image =
            O2ImageSourceCreateImageAtIndex(imageSource, index, NULL);
    O2ImageDestinationAddImage(self, image, properties);
    O2ImageRelease(image);
}

bool O2ImageDestinationFinalize(O2ImageDestinationRef self) {
    if (self->_encoder == NULL)
        return false;
    bool success = !self->_failed && self->_imageCount == 0;
    switch (self->_type) {

    case O2ImageFileUnknown:
        break;

    case O2ImageFileTIFF:
        if (!self->_failed)
            O2TIFFEncoderEnd(self->_encoder);
        O2TIFFEncoderDealloc(self->_encoder);
        self->_encoder = NULL;
        break;

    case O2ImageFileBMP:
        break;

    case O2ImageFileGIF:
        break;

    case O2ImageFileJPEG:
#ifdef LIBJPEG_PRESENT
        O2JPGEncoderDealloc(self->_encoder);
        self->_encoder = NULL;
#endif
        break;

    case O2ImageFilePNG:
        success = success && O2PNGEncoderIsComplete(self->_encoder);
        O2PNGEncoderDealloc(self->_encoder);
        self->_encoder = NULL;
        break;

    case O2ImageFileJPEG2000:
        break;
    }
    [self->_consumer release]; // This is needed so the consumer can finalize
                               // its work before we exit this function
    self->_consumer = nil;
    if (self->_options)
        CFRelease(self->_options);
    self->_options = NULL;

    return success;
}

- (void) dealloc {
    switch (self->_type) {
    case O2ImageFileTIFF: O2TIFFEncoderDealloc(self->_encoder); break;
#ifdef LIBJPEG_PRESENT
    case O2ImageFileJPEG: O2JPGEncoderDealloc(self->_encoder); break;
#endif
    case O2ImageFilePNG: O2PNGEncoderDealloc(self->_encoder); break;
    default: break;
    }
    [self->_consumer release];
    if (self->_options) CFRelease(self->_options);
    [super dealloc];
}

@end
