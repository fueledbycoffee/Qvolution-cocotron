/* Copyright (c) 2007 Christopher J. W. Lloyd <cjwl@objc.net>

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

/*  zlib decode is based on the public domain zlib decode v0.2 by Sean Barrett
 * 2006-11-18  http://www.nothings.org/stb_image.c  V 0.57 */

#import <Foundation/NSData.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#import <Onyx2D/O2ImageSource_JPEG.h>
#import <Onyx2D/O2LZW.h>
#import <Onyx2D/O2PDFDictionary.h>
#import <Onyx2D/O2PDFFilter.h>
#import <Onyx2D/O2PDFObject.h>
#import <Onyx2D/O2zlib.h>
#import <string.h>
#import <stdlib.h>

@implementation O2PDFFilter

+ (NSData *) FlateDecode_data: (NSData *) data
                   parameters: (O2PDFDictionary *) parameters
{
    int len;
    unsigned char *result =
            stbi_zlib_decode_malloc([data bytes], [data length], &len);

    if (result == NULL)
        return nil;

    return [NSData dataWithBytesNoCopy: result length: len];
}

+ (NSData *) LZWDecode_data: (NSData *) data
                 parameters: (O2PDFDictionary *) parameters
{
    return LZWDecodeWithExpectedResultLength(data, [data length] * 10);
}

+ (NSData *) decodeWithName: (const char *) name
                       data: (NSData *) data
                 parameters: (O2PDFDictionary *) parameters
                bytesPerRow: (size_t *) pBytesPerRow
{

    if ((strcmp(name, "FlateDecode") == 0) || (strcmp(name, "FL") == 0))
        data = [self FlateDecode_data: data parameters: parameters];
    else if ((strcmp(name, "DCTDecode") == 0) || (strcmp(name, "DCT") == 0)) {
        return O2DCTDecode(data, pBytesPerRow);
    } else if ((strcmp(name, "LZWDecode") == 0) || (strcmp(name, "LZW") == 0)) {
        data = LZWDecodeWithExpectedResultLength(data, [data length] * 10);
    } else {
        O2PDFError(__FILE__, __LINE__,
                   @"Unknown O2PDFFilter name = %s, parameters=%@", name,
                   parameters);
        return nil;
    }

    if (data == nil)
        return nil;
    O2PDFInteger predictor = 1;
    [parameters getIntegerForKey: "Predictor" value: &predictor];
    if (predictor == 1)
        return data;
    O2PDFInteger colors = 1, bits = 8, columns = 1;
    [parameters getIntegerForKey: "Colors" value: &colors];
    [parameters getIntegerForKey: "BitsPerComponent" value: &bits];
    [parameters getIntegerForKey: "Columns" value: &columns];
    if (colors <= 0 || columns <= 0 ||
            (bits != 1 && bits != 2 && bits != 4 && bits != 8 && bits != 16) ||
            (NSUInteger) colors > NSUIntegerMax / bits) {
        O2PDFError(__FILE__, __LINE__, @"Invalid PDF predictor dimensions");
        return nil;
    }
    NSUInteger pixelBits = (NSUInteger) colors * bits;
    if ((NSUInteger) columns > (NSUIntegerMax - 7) / pixelBits)
        return nil;
    NSUInteger rowBytes = (pixelBits * columns + 7) / 8;
    NSUInteger pixelBytes = ((NSUInteger) colors * bits + 7) / 8;
    const unsigned char *source = [data bytes];
    NSUInteger length = [data length];
    if (predictor == 2) {
        if (length % rowBytes)
            return nil;
        NSMutableData *output = [NSMutableData dataWithData: data];
        unsigned char *bytes = [output mutableBytes];
        for (NSUInteger row = 0; row < length; row += rowBytes) {
            for (NSUInteger sample = colors; sample < (NSUInteger) colors * columns; ++sample) {
                unsigned value = 0, previous = 0;
                for (unsigned bit = 0; bit < bits; ++bit) {
                    NSUInteger currentBit = sample * bits + bit;
                    NSUInteger previousBit = (sample - colors) * bits + bit;
                    value = (value << 1) | ((bytes[row + currentBit / 8] >> (7 - currentBit % 8)) & 1);
                    previous = (previous << 1) | ((bytes[row + previousBit / 8] >> (7 - previousBit % 8)) & 1);
                }
                value += previous;
                for (unsigned bit = 0; bit < bits; ++bit) {
                    NSUInteger currentBit = sample * bits + bit;
                    unsigned mask = 1u << (7 - currentBit % 8);
                    unsigned char *byte = bytes + row + currentBit / 8;
                    *byte = (*byte & ~mask) | (((value >> (bits - bit - 1)) & 1) ? mask : 0);
                }
            }
        }
        if (pBytesPerRow != NULL)
            *pBytesPerRow = rowBytes;
        return output;
    }
    if (predictor < 10 || predictor > 15 || rowBytes == NSUIntegerMax ||
            length % (rowBytes + 1)) {
        O2PDFError(__FILE__, __LINE__, @"Invalid PDF PNG predictor data");
        return nil;
    }
    NSUInteger rows = length / (rowBytes + 1);
    NSMutableData *output = [NSMutableData dataWithLength: rows * rowBytes];
    unsigned char *bytes = [output mutableBytes];
    for (NSUInteger row = 0; row < rows; ++row) {
        unsigned filter = *source++;
        if (filter > 4)
            return nil;
        for (NSUInteger i = 0; i < rowBytes; ++i) {
            int left = i >= pixelBytes ? bytes[row * rowBytes + i - pixelBytes] : 0;
            int above = row ? bytes[(row - 1) * rowBytes + i] : 0;
            int upperLeft = row && i >= pixelBytes ? bytes[(row - 1) * rowBytes + i - pixelBytes] : 0;
            int prediction = 0;
            if (filter == 1) prediction = left;
            else if (filter == 2) prediction = above;
            else if (filter == 3) prediction = (left + above) / 2;
            else if (filter == 4) {
                int p = left + above - upperLeft;
                int a = abs(p - left), b = abs(p - above), c = abs(p - upperLeft);
                prediction = a <= b && a <= c ? left : b <= c ? above : upperLeft;
            }
            bytes[row * rowBytes + i] = *source++ + prediction;
        }
    }
    if (pBytesPerRow != NULL)
        *pBytesPerRow = rowBytes;
    return output;
}

@end
