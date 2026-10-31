#import <Onyx2D/O2Decoder_TIFF.h>
#import <Onyx2D/O2Encoder_TIFF.h>
#include <limits.h>
#include <stdlib.h>

O2TIFFEncoderRef O2TIFFEncoderCreate(O2DataConsumerRef consumer) {
    O2TIFFEncoderRef self = NSZoneCalloc(NULL, 1, sizeof(struct O2TIFFEncoder));
    self->_bigEndian = YES;
    self->_consumerOffset = 0;
    self->_consumerPosition = 0;
    self->_bufferCapacity = 0;
    self->_bufferCount = 0;
    self->_mutableBytes = NULL;
    self->_consumer = (id) CFRetain(consumer);
    return self;
}

void O2TIFFEncoderDealloc(O2TIFFEncoderRef self) {
    if (self == NULL) return;
    if (self->_mutableBytes != NULL)
        NSZoneFree(NULL, self->_mutableBytes);
    if (self->_consumer != NULL)
        CFRelease(self->_consumer);
    NSZoneFree(NULL, self);
}

static void beginBuffering(O2TIFFEncoderRef self) {
    self->_bufferCapacity = 256;
    self->_bufferCount = 0;
    self->_mutableBytes = NSZoneMalloc(NULL, self->_bufferCapacity);
    if (self->_mutableBytes == NULL) self->_failed = true;
}

static void endBuffering(O2TIFFEncoderRef self) {
    if (!self->_failed && O2DataConsumerPutBytes(self->_consumer,
            self->_mutableBytes, self->_bufferCount) != self->_bufferCount)
        self->_failed = true;

    NSZoneFree(NULL, self->_mutableBytes);
    self->_mutableBytes = NULL;
    self->_consumerOffset += self->_bufferCount;
}

static uint32_t currentPosition(O2TIFFEncoderRef self) {
    return self->_consumerPosition;
}

static uint32_t setPosition(O2TIFFEncoderRef self, uint32_t value) {
    uint32_t result = self->_consumerPosition;

    self->_consumerPosition = value;
    self->_bufferCount = value - self->_consumerOffset;

    return result;
}

static void putBytes(O2TIFFEncoderRef self, uint8_t *values, uint32_t count) {
    if (self->_failed) return;
    if (count > SIZE_MAX - self->_bufferCount) {
        self->_failed = true;
        return;
    }
    size_t needed = self->_bufferCount + count;
    if (needed > self->_bufferCapacity) {
        size_t capacity = self->_bufferCapacity;
        while (capacity < needed) {
            if (capacity > SIZE_MAX / 2) { capacity = needed; break; }
            capacity *= 2;
        }
        uint8_t *bytes = NSZoneRealloc(NULL, self->_mutableBytes, capacity);
        if (bytes == NULL) { self->_failed = true; return; }
        self->_mutableBytes = bytes;
        self->_bufferCapacity = capacity;
    }
    memcpy(self->_mutableBytes + self->_bufferCount, values, count);
    self->_bufferCount += count;
    self->_consumerPosition += count;
}

static void putUnsigned8(O2TIFFEncoderRef self, uint8_t value) {
    putBytes(self, &value, 1);
}

static void putUnsigned16(O2TIFFEncoderRef self, uint16_t value) {
    uint8_t bytes[2];

    if (self->_bigEndian) {
        bytes[0] = value >> 8;
        bytes[1] = value & 0xFF;
    } else {
        bytes[1] = value >> 8;
        bytes[0] = value & 0xFF;
    }

    putBytes(self, bytes, 2);
}

static void putUnsigned32(O2TIFFEncoderRef self, uint32_t value) {
    uint8_t bytes[4];

    if (self->_bigEndian) {
        bytes[0] = value >> 24;
        bytes[1] = value >> 16;
        bytes[2] = value >> 8;
        bytes[3] = value & 0xFF;
    } else {
        bytes[3] = (value >> 24) & 0xFF;
        bytes[2] = (value >> 16) & 0xFF;
        bytes[1] = (value >> 8);
        bytes[0] = value & 0xFF;
    }

    putBytes(self, bytes, 4);
}

static void putUnsigned32AtPosition(O2TIFFEncoderRef self, uint32_t value,
                                    uint32_t position)
{
    uint32_t save = setPosition(self, position);
    putUnsigned32(self, value);
    setPosition(self, save);
}

static void encodeUnsigned16(O2TIFFEncoderRef self, uint16_t value) {
    putUnsigned16(self, NSTIFFTypeSHORT);
    putUnsigned32(self, 1);
    putUnsigned16(self, value);
    putUnsigned16(self, 0); // pad
}

static void encodeUnsigned32(O2TIFFEncoderRef self, uint32_t value) {
    putUnsigned16(self, NSTIFFTypeLONG);
    putUnsigned32(self, 1);
    putUnsigned32(self, value);
}

static uint32_t reserveRational(O2TIFFEncoderRef self) {
    uint32_t result = currentPosition(self);
    putUnsigned16(self, NSTIFFTypeRATIONAL);
    putUnsigned32(self, 1);
    putUnsigned32(self, 0);
    return result;
}

static void encodeRationalAtPosition(O2TIFFEncoderRef self, double value,
                                     uint32_t position)
{
    uint32_t save = setPosition(self, position);

    putUnsigned16(self, NSTIFFTypeRATIONAL);
    putUnsigned32(self, 1);
    putUnsigned32(self, save);
    setPosition(self, save);

    uint32_t denominator = 1000000;

    value *= denominator;
    putUnsigned32(self, value);
    putUnsigned32(self, denominator);
}

static void encodeUnsigned16OrUnsigned32(O2TIFFEncoderRef self, uint32_t value)
{
    if ((value & 0xFFFF) == 0)
        encodeUnsigned16(self, value);
    else
        encodeUnsigned32(self, value);
}

#if 0
static void encodeUnsigned32AtPosition(O2TIFFEncoderRef self,uint32_t value,uint32_t position){
   uint32_t save=setPosition(self,position);
   
   putUnsigned16(self,NSTIFFTypeLONG);
   putUnsigned32(self,value);
   
   setPosition(self,save);
}


static void encodeArrayOfUnsigned8(O2TIFFEncoderRef self,uint8_t *values,uint32_t count){
   putUnsigned32(self,count);
   if(count==1)
    putUnsigned8(self,values[0]);
   else if(count==2){
    putUnsigned8(self,values[0]);
    putUnsigned8(self,values[1]);
   }
   else {
    uint32_t offset=self->_consumerPosition+4;
    
    putUnsigned32(self,offset);
    
    uint32_t i;
    for(i=0;i<count;i++)
     putUnsigned32(self,values[i]);
   }
}
#endif

static uint32_t reserveArrayOfUnsigned16(O2TIFFEncoderRef self) {
    uint32_t result = currentPosition(self);

    putUnsigned16(self, NSTIFFTypeSHORT);
    putUnsigned32(self, 0);
    putUnsigned32(self, 0);

    return result;
}

static void encodeArrayOfUnsigned16AtPosition(O2TIFFEncoderRef self,
                                              uint16_t *values, size_t count,
                                              uint32_t position)
{
    uint32_t save = setPosition(self, position);

    putUnsigned16(self, NSTIFFTypeSHORT);
    putUnsigned32(self, count);

    if (count == 1) {
        putUnsigned16(self, values[0]);
        setPosition(self, save);
    } else if (count == 2) {
        putUnsigned16(self, values[0]);
        putUnsigned16(self, values[1]);
        setPosition(self, save);
    } else {
        int i;

        putUnsigned32(self, save);
        setPosition(self, save);

        for (i = 0; i < count; i++)
            putUnsigned16(self, values[i]);
    }
}

static size_t reserveArrayOfUnsigned32(O2TIFFEncoderRef self) {
    size_t result = currentPosition(self);

    putUnsigned16(self, NSTIFFTypeLONG);
    putUnsigned32(self, 0);
    putUnsigned32(self, 0);

    return result;
}

static void encodeArrayOfUnsigned32AtPosition(O2TIFFEncoderRef self,
                                              uint32_t *values, size_t count,
                                              uint32_t position)
{
    uint32_t save = setPosition(self, position);

    putUnsigned16(self, NSTIFFTypeLONG);
    putUnsigned32(self, count);
    if (count == 1) {
        putUnsigned32(self, values[0]);
        setPosition(self, save);
    } else {
        int i;

        putUnsigned32(self, save);
        setPosition(self, save);

        for (i = 0; i < count; i++)
            putUnsigned32(self, values[i]);
    }
}

void O2TIFFEncoderBegin(O2TIFFEncoderRef self) {
    beginBuffering(self);
    if (self->_bigEndian) {
        putUnsigned8(self, 'M');
        putUnsigned8(self, 'M');
    } else {
        putUnsigned8(self, 'I');
        putUnsigned8(self, 'I');
    }
    putUnsigned16(self, 42);
    endBuffering(self);
}

void pack_argb8u_as_rgb8u(O2argb8u *imageRow, size_t width, uint8_t *tiffRow) {
    int i, byteIndex = 0;

    for (i = 0; i < width; i++) {
        O2argb8u pixel = imageRow[i];
        tiffRow[byteIndex++] = pixel.r;
        tiffRow[byteIndex++] = pixel.g;
        tiffRow[byteIndex++] = pixel.b;
    }
}

void pack_argb8u_as_rgba8u(O2argb8u *imageRow, size_t width, uint8_t *tiffRow) {
    int i, byteIndex = 0;

    for (i = 0; i < width; i++) {
        O2argb8u pixel = imageRow[i];
        tiffRow[byteIndex++] = pixel.r;
        tiffRow[byteIndex++] = pixel.g;
        tiffRow[byteIndex++] = pixel.b;
        tiffRow[byteIndex++] = pixel.a;
    }
}

bool O2TIFFEncoderWriteImage(O2TIFFEncoderRef self, O2ImageRef image,
                             CFDictionaryRef properties, bool lastImage)
{
    if (self == NULL || self->_failed)
        return false;
    O2ImageRef byteImage = O2ImageCreateCopyForByteExport(image);
    if (byteImage == nil)
        return false;
    image = byteImage;
    size_t imageWidth = O2ImageGetWidth(image);
    size_t imageHeight = O2ImageGetHeight(image);
    O2ImageAlphaInfo imageAlphaInfo = O2ImageGetAlphaInfo(image);
    // FIX, needs to premultiply
    bool imageHasAlpha = (imageAlphaInfo == kO2ImageAlphaPremultipliedLast ||
                          imageAlphaInfo == kO2ImageAlphaPremultipliedFirst ||
                          imageAlphaInfo == kO2ImageAlphaLast ||
                          imageAlphaInfo == kO2ImageAlphaFirst);

    int tiffBitsPerComponent = 8;
    int tiffSamplesPerPixel = imageHasAlpha ? 4 : 3;
    int tiffBitsPerPixel = tiffBitsPerComponent * tiffSamplesPerPixel;
    if (imageWidth > INT_MAX / tiffSamplesPerPixel ||
            imageHeight > INT_MAX / (imageWidth * tiffSamplesPerPixel)) {
        O2ImageRelease(byteImage);
        return false;
    }
    int tiffBytesPerRow = (tiffBitsPerPixel * imageWidth) / 8;
    size_t tiffPixelByteCount = imageHeight * tiffBytesPerRow;

    uint32_t idealStripSize =
            MAX(8192, tiffBytesPerRow); // 8k recommended by spec.
    uint32_t rowsPerStrip = (idealStripSize / tiffBytesPerRow);
    uint32_t stripSize = rowsPerStrip * tiffBytesPerRow;
    uint32_t stripCount = (tiffPixelByteCount + (stripSize - 1)) / stripSize;
    uint32_t stripOffsetsPosition;
    uint32_t *stripOffsets = malloc(stripCount * sizeof(*stripOffsets));
    uint32_t stripByteCountsPosition;
    uint32_t *stripByteCounts = malloc(stripCount * sizeof(*stripByteCounts));
    O2argb8u *imageRowBuffer = malloc(imageWidth * sizeof(*imageRowBuffer));
    O2argb8u *imageRow;
    uint8_t *tiffRowBuffer = malloc(tiffBytesPerRow);
    if (!stripOffsets || !stripByteCounts || !imageRowBuffer || !tiffRowBuffer) {
        free(stripOffsets); free(stripByteCounts);
        free(imageRowBuffer); free(tiffRowBuffer);
        O2ImageRelease(byteImage);
        return false;
    }

    int strip, y = 0;

    for (strip = 0; strip < stripCount; strip++)
        stripOffsets[strip] = stripByteCounts[strip] = 0;

    beginBuffering(self);

    putUnsigned32(self, currentPosition(self) + 4);

    putUnsigned16(self, imageHasAlpha ? 13 : 12);
    putUnsigned16(self, NSTIFFTagImageWidth);
    encodeUnsigned16OrUnsigned32(self, imageWidth);
    putUnsigned16(self, NSTIFFTagImageLength);
    encodeUnsigned16OrUnsigned32(self, imageHeight);
    putUnsigned16(self, NSTIFFTagBitsPerSample);
    uint32_t bpsPosition = reserveArrayOfUnsigned16(self);
    putUnsigned16(self, NSTIFFTagCompression);
    encodeUnsigned16(self, NSTIFFCompression_none);
    if (imageHasAlpha) {
        putUnsigned16(self, NSTIFFTagExtraSamples);
        encodeUnsigned16(self, NSTIFFExtraSamples_associatedAlpha);
    }
    putUnsigned16(self, NSTIFFTagPhotometricInterpretation);
    encodeUnsigned16(self, NSTIFFPhotometricInterpretationRGB);
    putUnsigned16(self, NSTIFFTagStripOffsets);
    stripOffsetsPosition = reserveArrayOfUnsigned32(self);
    putUnsigned16(self, NSTIFFTagSamplesPerPixel);
    encodeUnsigned16(self, tiffSamplesPerPixel);
    putUnsigned16(self, NSTIFFTagRowsPerStrip);
    encodeUnsigned32(self, rowsPerStrip);
    putUnsigned16(self, NSTIFFTagStripByteCounts);
    stripByteCountsPosition = reserveArrayOfUnsigned32(self);
    putUnsigned16(self, NSTIFFTagXResolution);
    uint32_t xResolutionPosition = reserveRational(self);
    putUnsigned16(self, NSTIFFTagYResolution);
    uint32_t yResolutionPosition = reserveRational(self);
    putUnsigned16(self, NSTIFFTagResolutionUnit);
    encodeUnsigned16(self, NSTIFFResolutionUnit_inch);

    uint32_t nextEntryOffsetPosition = currentPosition(self);
    putUnsigned32(self, 0);

    for (strip = 0; strip < stripCount; strip++) {
        int row, rowCount = MIN(rowsPerStrip,
                                imageHeight - (strip * rowsPerStrip));

        stripOffsets[strip] = currentPosition(self);

        uint32_t compressedSize = rowCount * tiffBytesPerRow;

        for (row = 0; row < rowCount; row++, y++) {

            imageRow = image->_read_argb8u(image, 0, y, imageRowBuffer,
                                           imageWidth);
            if (imageRow == NULL)
                imageRow = imageRowBuffer;

            if (imageHasAlpha)
                pack_argb8u_as_rgba8u(imageRow, imageWidth, tiffRowBuffer);
            else
                pack_argb8u_as_rgb8u(imageRow, imageWidth, tiffRowBuffer);

            putBytes(self, tiffRowBuffer, tiffBytesPerRow);
        };

        stripByteCounts[strip] = compressedSize;
    }

    encodeArrayOfUnsigned32AtPosition(self, stripOffsets, stripCount,
                                      stripOffsetsPosition);
    encodeArrayOfUnsigned32AtPosition(self, stripByteCounts, stripCount,
                                      stripByteCountsPosition);
    uint16_t bps[4] = {8, 8, 8, 8};
    encodeArrayOfUnsigned16AtPosition(self, bps, tiffSamplesPerPixel,
                                      bpsPosition);
    encodeRationalAtPosition(self, 72.0, xResolutionPosition);
    encodeRationalAtPosition(self, 72.0, yResolutionPosition);

    if (!lastImage)
        putUnsigned32AtPosition(self, currentPosition(self),
                                nextEntryOffsetPosition);

    endBuffering(self);
    free(stripOffsets); free(stripByteCounts);
    free(imageRowBuffer); free(tiffRowBuffer);
    O2ImageRelease(byteImage);
    return !self->_failed;
}

void O2TIFFEncoderEnd(O2TIFFEncoderRef self) {
}
