/* Copyright (c) 2007 Christopher J. W. Lloyd

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

#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#import <Onyx2D/O2PDFArray.h>
#import <Onyx2D/O2PDFContentStream.h>
#import <Onyx2D/O2PDFDictionary.h>
#import <Onyx2D/O2PDFObject_Boolean.h>
#import <Onyx2D/O2PDFObject_Integer.h>
#import <Onyx2D/O2PDFObject_Name.h>
#import <Onyx2D/O2PDFObject_R.h>
#import <Onyx2D/O2PDFObject_Real.h>
#import <Onyx2D/O2PDFObject_const.h>
#import <Onyx2D/O2PDFObject_identifier.h>
#import <Onyx2D/O2PDFOperatorTable.h>
#import <Onyx2D/O2PDFScanner.h>
#import <Onyx2D/O2PDFStream.h>
#import <Onyx2D/O2PDFString.h>
#import <Onyx2D/O2PDFxref.h>
#import <Onyx2D/O2PDFxrefEntry.h>

#import <stddef.h>
#import <limits.h>
#import <stdlib.h>
#import <errno.h>
#import <math.h>
#import <xlocale.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSValue.h>

static BOOL O2PDFScannerDumpStream = NO;

#define LF 10
#define FF 12
#define CR 13

typedef struct {
    unsigned capacity;
    unsigned length;
    uint8_t *bytes;
} O2PDFByteBuffer;

static inline O2PDFByteBuffer *O2PDFByteBufferCreate() {
    O2PDFByteBuffer *result = NSZoneMalloc(NULL, sizeof(O2PDFByteBuffer));

    result->capacity = 0;
    result->length = 0;
    result->bytes = NULL;

    return result;
}

static inline void O2PDFByteBufferFree(O2PDFByteBuffer *buffer) {
    if (buffer->bytes != NULL)
        NSZoneFree(NULL, buffer->bytes);
    NSZoneFree(NULL, buffer);
}

static inline void O2PDFByteBufferReset(O2PDFByteBuffer *buffer) {
    buffer->length = 0;
}

static inline void O2PDFByteBufferAppend(O2PDFByteBuffer *buffer,
                                         unsigned char c)
{
    if (buffer->length >= buffer->capacity) {
        if (buffer->capacity == 0) {
            buffer->capacity = 128;
            buffer->bytes = NSZoneMalloc(NULL, buffer->capacity);
        } else {
            buffer->capacity *= 2;
            buffer->bytes =
                    NSZoneRealloc(NULL, buffer->bytes, buffer->capacity);
        }
    }
    buffer->bytes[buffer->length++] = c;
}

static inline unsigned char O2PDFByteBufferDecodeNibble(unsigned char nibble) {
    if (nibble >= 'a' && nibble <= 'f')
        return (nibble - 'a') + 10;
    else if (nibble >= 'A' && nibble <= 'F')
        return (nibble - 'A') + 10;
    else if (nibble >= '0' && nibble <= '9')
        return nibble - '0';

    return 0xFF;
}

static inline BOOL O2PDFByteBufferAppendHighNibble(O2PDFByteBuffer *buffer,
                                                   unsigned char nibble)
{
    if ((nibble = O2PDFByteBufferDecodeNibble(nibble)) == 0xFF)
        return NO;

    nibble <<= 4;
    O2PDFByteBufferAppend(buffer, nibble);
    return YES;
}

static inline BOOL O2PDFByteBufferAppendLowNibble(O2PDFByteBuffer *buffer,
                                                  unsigned char nibble)
{
    if ((nibble = O2PDFByteBufferDecodeNibble(nibble)) == 0xFF)
        return NO;

    buffer->bytes[buffer->length - 1] |= nibble;

    return YES;
}

static inline BOOL O2PDFByteBufferAppendOctal(O2PDFByteBuffer *buffer,
                                              uint8_t octal)
{
    octal -= '0';
    O2PDFByteBufferAppend(buffer, octal);

    return YES;
}

static inline BOOL O2PDFByteBufferAddOctal(O2PDFByteBuffer *buffer,
                                           uint8_t octal)
{
    octal -= '0';
    buffer->bytes[buffer->length - 1] *= 8;
    buffer->bytes[buffer->length - 1] |= octal;

    return YES;
}

static void debugTracev(const char *bytes, unsigned length,
                        O2PDFInteger position, NSString *format,
                        va_list arguments)
{
    if (position < 0)
        position = 0;
    if ((NSUInteger) position > length)
        position = length;
    NSString *dump = [[[NSString alloc]
            initWithBytes: bytes + position
                   length: MIN(80, (length - position))
                 encoding: NSISOLatin1StringEncoding] autorelease];

    NSLogv(format, arguments);
    NSLog(@"position=%ld,dump=[%@]", (long) position, dump);
}

static void debugTrace(const char *bytes, unsigned length,
                       O2PDFInteger position, NSString *format, ...)
{
    va_list arguments;

    va_start(arguments, format);
    return;
    debugTracev(bytes, length, position, format, arguments);
}

static BOOL debugError(const char *bytes, unsigned length,
                       O2PDFInteger position, NSString *format, ...)
{
    va_list arguments;

    va_start(arguments, format);
    debugTracev(bytes, length, position, format, arguments);
    va_end(arguments);
    return NO;
}

BOOL O2PDFScanBackwardsToEOF(const char *bytes, unsigned length,
                             O2PDFInteger position, O2PDFInteger *lastPosition)
{
    enum {
        STATE_F,
        STATE_O,
        STATE_E,
        STATE_PERCENT,
        STATE_PERCENT_PERCENT,
    } state = STATE_F;

    while (--position >= 0) {
        char c = bytes[position];

        *lastPosition = position;

        switch (state) {

        case STATE_F:
            if (c == 'F')
                state = STATE_O;
            else if (c >= ' ')
                return NO;
            break;

        case STATE_O:
            if (c == 'O')
                state = STATE_E;
            else
                return NO;
            break;

        case STATE_E:
            if (c == 'E')
                state = STATE_PERCENT;
            else
                return NO;
            break;

        case STATE_PERCENT:
            if (c == '%')
                state = STATE_PERCENT_PERCENT;
            else
                return NO;
            break;

        case STATE_PERCENT_PERCENT:
            if (c == '%')
                return YES;
            else
                return NO;
            break;
        }
    }
    return NO;
}

BOOL O2PDFScanBackwardsByLines(const char *bytes, unsigned length,
                               O2PDFInteger position,
                               O2PDFInteger *lastPosition, int delta)
{
    enum {
        STATE_LF_OR_CR,
        STATE_CR_OR_LINE,
        STATE_LINE
    } state = STATE_LF_OR_CR;

    debugTrace(bytes, length, position, @"O2PDFScanBackwardsByLines %d", delta);

    while (--position >= 0) {
        char c = bytes[position];

        switch (state) {

        case STATE_LF_OR_CR:
            if (c == LF)
                state = STATE_CR_OR_LINE;
            else
                state = STATE_LINE;
            break;

        case STATE_CR_OR_LINE:
            if (c == CR) {
                state = STATE_LINE;
                break;
            }
            // fallthru
        case STATE_LINE:
            if (c == CR || c == LF) {
                delta--;
                if (delta <= 0) {
                    *lastPosition = position + 1;
                    return YES;
                }
                state = (c == CR) ? STATE_LINE : STATE_CR_OR_LINE;
            }
            break;
        }
    }

    return NO;
}

#if 0
-(BOOL)scanData:(NSData *)data position:(O2PDFInteger)position lastPosition:(O2PDFInteger *)lastPosition linesForward:(int)delta {
   const char *bytes=[data bytes];
   unsigned    length=[bytes length];
   enum {
    STATE_LINE,
    STATE_CR
   } state=STATE_LINE;

   for(;position<length;position++){
    char c=byteAtOffset(bytes,position);
    switch(state){

     case STATE_LINE:
      if(c==CR)
       state=STATE_CR;
      else if(c==LF){
       *lastPosition=position++;
       return YES;
      }
      break;

     case STATE_CR:
      if(c==LF)
       *lastPosition=position++;
      return YES;
    }
   }
   return NO;
}
#endif

BOOL O2PDFScanVersion(const char *bytes, unsigned length,
                      O2PDFString **versionp)
{
    O2PDFInteger position = length;

    if (length < 8)
        return NO;

    if (strncmp(bytes, "%PDF-", 5) != 0)
        return debugError(bytes, length, 0, @"Does not begin with %%PDF-");

    *versionp =
            [O2PDFString pdfObjectWithBytes: (const unsigned char *) bytes + 5
                                     length: 3];

    position = length;

    if (!O2PDFScanBackwardsToEOF(bytes, length, position, &position))
        return debugError(bytes, length, position, @"Does not end with %%EOF");

    return YES;
}

static BOOL O2PDFNumber(const char *bytes, O2PDFInteger start, O2PDFInteger end,
        BOOL real, O2PDFObject **object) {
    unsigned char next=bytes[end];
    if (next && next!=' ' && next!='\t' && next!=LF && next!=CR && next!=FF &&
            !strchr("()<>[]{}/%",next)) return NO;
    NSString *token=[[NSString alloc] initWithBytes:bytes+start length:end-start encoding:NSASCIIStringEncoding];
    const char *text=[token UTF8String]; char *last=NULL;
    BOOL valid=NO; errno=0;
    if (real) {
        double value=strtod_l(text,&last,LC_C_LOCALE);
        valid=last!=text && *last=='\0' && isfinite(value);
        if (valid) *object=[O2PDFObject_Real pdfObjectWithReal:value];
    } else {
        long long value=strtoll_l(text,&last,10,LC_C_LOCALE);
        valid=last!=text && *last=='\0' && errno!=ERANGE && value>=NSIntegerMin && value<=NSIntegerMax;
        if (valid) *object=[O2PDFObject_Integer pdfObjectWithInteger:value];
    }
    [token release]; return valid;
}

// Returns YES and *objectp==NULL on end of stream
BOOL O2PDFScanObject(const char *bytes, unsigned length, O2PDFInteger position,
                     O2PDFInteger *lastPosition, O2PDFObject **objectp)
{
    O2PDFInteger inlineLocation = 0;
    O2PDFByteBuffer *byteBuffer = NULL;

    enum {
        STATE_SCANNING,
        STATE_COMMENT,
        STATE_INTEGER,
        STATE_REAL,
        STATE_STRING_NOFREE,
        STATE_STRING_FREE,
        STATE_STRING_ESCAPE,
        STATE_STRING_0XX,
        STATE_STRING_00X,
        STATE_OPEN_ANGLE,
        STATE_HEX_STRING_NIBBLE1,
        STATE_HEX_STRING_NIBBLE2,
        STATE_NAME,
        STATE_CLOSE_ANGLE,
        STATE_IDENTIFIER,
    } state = STATE_SCANNING;

    debugTrace(bytes, length, position, @"O2PDFScanObject");

    *objectp = NULL;

    for (; position < length; position++) {
        unsigned char code = bytes[position];

        switch (state) {

        case STATE_SCANNING:
            switch (code) {

            case ' ':
            case CR:
            case FF:
            case LF:
            case '\t':
                break;

            case '%':
                state = STATE_COMMENT;
                break;

            case '-':
                state = STATE_INTEGER;
                inlineLocation = position;
                break;

            case '+':
                state = STATE_INTEGER;
                inlineLocation = position;
                break;

            case '0':
            case '1':
            case '2':
            case '3':
            case '4':
            case '5':
            case '6':
            case '7':
            case '8':
            case '9':
                state = STATE_INTEGER;
                inlineLocation = position;
                break;

            case '.':
                state = STATE_REAL;
                inlineLocation = position;
                break;

            case '(':
                inlineLocation = position + 1;
                state = STATE_STRING_NOFREE;
                break;

            case '<':
                state = STATE_OPEN_ANGLE;
                break;

            case '/':
                state = STATE_NAME;
                inlineLocation = position + 1;
                break;

            case '[':
                *objectp = [O2PDFObject_const pdfObjectArrayMark];
                *lastPosition = position + 1;
                return YES;

            case ']':
                *objectp = [O2PDFObject_const pdfObjectArrayMarkEnd];
                *lastPosition = position + 1;
                return YES;

            case '>':
                state = STATE_CLOSE_ANGLE;
                break;

            case ')':
            case '{':
            case '}':
                return debugError(bytes, length, position,
                                  @"Unexpected character \'%c\'", code);

            default:
                state = STATE_IDENTIFIER;
                inlineLocation = position;
                break;
            }
            break;

        case STATE_COMMENT:
            if (code == CR || code == LF || code == FF)
                state = STATE_SCANNING;
            break;

        case STATE_INTEGER:
            if (code == '.') state = STATE_REAL;
            else if (code < '0' || code > '9') {
                *lastPosition = position;
                return O2PDFNumber(bytes, inlineLocation, position, NO, objectp);
            }
            break;

        case STATE_REAL:
            if (code < '0' || code > '9') {
                *lastPosition = position;
                return O2PDFNumber(bytes, inlineLocation, position, YES, objectp);
            }
            break;

        case STATE_STRING_NOFREE:
            if (code == ')') {
                *objectp = [O2PDFString
                        pdfObjectWithBytesNoCopyNoFree: (const unsigned char *)
                                                                bytes +
                                                        inlineLocation
                                                length: position -
                                                        inlineLocation];
                *lastPosition = position + 1;
                return YES;
            } else if (code == '\\') {
                O2PDFInteger pos;

                byteBuffer = O2PDFByteBufferCreate();
                for (pos = inlineLocation; pos < position; pos++)
                    O2PDFByteBufferAppend(byteBuffer, bytes[pos]);

                state = STATE_STRING_ESCAPE;
                break;
            }
            break;

        case STATE_STRING_FREE:
            if (code == ')') {
                *objectp = [O2PDFString pdfObjectWithBytes: byteBuffer->bytes
                                                    length: byteBuffer->length];
                O2PDFByteBufferFree(byteBuffer);
                *lastPosition = position + 1;
                return YES;
            } else if (code == '\\') {
                state = STATE_STRING_ESCAPE;
                break;
            } else {
                O2PDFByteBufferAppend(byteBuffer, bytes[position]);
            }
            break;

        case STATE_STRING_ESCAPE:
            if (code == 'n') {
                O2PDFByteBufferAppend(byteBuffer, '\n');
                state = STATE_STRING_FREE;
            } else if (code == 'r') {
                O2PDFByteBufferAppend(byteBuffer, '\r');
                state = STATE_STRING_FREE;
            } else if (code == 't') {
                O2PDFByteBufferAppend(byteBuffer, '\t');
                state = STATE_STRING_FREE;
            } else if (code == 'b') {
                O2PDFByteBufferAppend(byteBuffer, '\b');
                state = STATE_STRING_FREE;
            } else if (code == 'f') {
                O2PDFByteBufferAppend(byteBuffer, '\f');
                state = STATE_STRING_FREE;
            } else if (code == '\\') {
                O2PDFByteBufferAppend(byteBuffer, '\\');
                state = STATE_STRING_FREE;
            } else if (code == '(') {
                O2PDFByteBufferAppend(byteBuffer, '(');
                state = STATE_STRING_FREE;
            } else if (code == ')') {
                O2PDFByteBufferAppend(byteBuffer, ')');
                state = STATE_STRING_FREE;
            } else if (code == CR)
                state = STATE_STRING_FREE;
            else if (code == LF)
                state = STATE_STRING_FREE;
            else if (code >= '0' && code <= '7') {
                O2PDFByteBufferAppendOctal(byteBuffer, code);
                state = STATE_STRING_0XX;
            } else {
                O2PDFByteBufferFree(byteBuffer);
                return debugError(bytes, length, position,
                                  @"Invalid escape sequence code=0x%02X", code);
            }
            break;

        case STATE_STRING_0XX:
            if (code >= '0' && code <= '7') {
                O2PDFByteBufferAddOctal(byteBuffer, code);
                state = STATE_STRING_00X;
            } else {
                position--;
                state = STATE_STRING_FREE;
            }
            break;

        case STATE_STRING_00X:
            if (code >= '0' && code <= '7') {
                O2PDFByteBufferAddOctal(byteBuffer, code);
            } else
                position--;

            state = STATE_STRING_FREE;
            break;

        case STATE_OPEN_ANGLE:
            if (code == '<') {
                *objectp = [O2PDFObject_const pdfObjectDictionaryMark];
                *lastPosition = position + 1;
                return YES;
            } else {
                byteBuffer = O2PDFByteBufferCreate();
                state = STATE_HEX_STRING_NIBBLE1;
                position--;
            }
            break;

        case STATE_HEX_STRING_NIBBLE1:
        case STATE_HEX_STRING_NIBBLE2:
            if (code == '>') {
                *objectp = [O2PDFString pdfObjectWithBytes: byteBuffer->bytes
                                                    length: byteBuffer->length];
                O2PDFByteBufferFree(byteBuffer);
                *lastPosition = position + 1;
                return YES;
            } else if (code == ' ' || code == CR || code == FF || code == LF ||
                       code == '\t' || code == '\0')
                break;
            else if (state == STATE_HEX_STRING_NIBBLE1) {
                if (O2PDFByteBufferAppendHighNibble(byteBuffer, code)) {
                    state = STATE_HEX_STRING_NIBBLE2;
                    break;
                }
            } else if (state == STATE_HEX_STRING_NIBBLE2) {
                if (O2PDFByteBufferAppendLowNibble(byteBuffer, code)) {
                    state = STATE_HEX_STRING_NIBBLE1;
                    break;
                }
            }
            O2PDFByteBufferFree(byteBuffer);
            return debugError(bytes, length, position,
                              @"Invalid hex character code=0x%02X", code);

        case STATE_NAME:
            if (code == ' ' || code == CR || code == FF || code == LF ||
                code == '\t' || code == '\0' || code == '%' || code == '(' ||
                code == ')' || code == '<' || code == '>' || code == ']' ||
                code == '[' || code == '{' || code == '}' || code == '/') {
                if (inlineLocation == position)
                    return debugError(bytes, length, position,
                                      @"Invalid character in name, code=0x%02X",
                                      code);

                byteBuffer = O2PDFByteBufferCreate();
                for (O2PDFInteger i=inlineLocation; i<position; i++) {
                    unsigned char value=bytes[i];
                    if (value=='#') {
                        if (i+2>=position) { O2PDFByteBufferFree(byteBuffer); return NO; }
                        unsigned char high=O2PDFByteBufferDecodeNibble(bytes[++i]);
                        unsigned char low=O2PDFByteBufferDecodeNibble(bytes[++i]);
                        if (high==0xFF || low==0xFF || (high==0 && low==0)) {
                            O2PDFByteBufferFree(byteBuffer); return NO;
                        }
                        value=(high<<4)|low;
                    }
                    O2PDFByteBufferAppend(byteBuffer,value);
                }
                *objectp = [O2PDFObject_Name pdfObjectWithBytes:(const char *)byteBuffer->bytes length:byteBuffer->length];
                O2PDFByteBufferFree(byteBuffer);
                *lastPosition = position;
                return YES;
            }
            break;

        case STATE_CLOSE_ANGLE:
            if (code == '>') {
                *objectp = [O2PDFObject_const pdfObjectDictionaryMarkEnd];
                *lastPosition = position + 1;
                return YES;
            }
            return debugError(bytes, length, position,
                              @"Expecting > after first >, code=0x02X", code);

        case STATE_IDENTIFIER:
            if (code == ' ' || code == CR || code == FF || code == LF ||
                code == '\t' || code == '\0' || code == '%' || code == '(' ||
                code == ')' || code == '<' || code == '>' || code == ']' ||
                code == '[' || code == '{' || code == '}' || code == '/') {
                const char *name = bytes + inlineLocation;
                unsigned length = position - inlineLocation;
                O2PDFIdentifier identifier =
                        O2PDFClassifyIdentifier(name, length);

                if (identifier == O2PDFIdentifier_true)
                    *objectp = [O2PDFObject_Boolean pdfObjectWithTrue];
                else if (identifier == O2PDFIdentifier_false)
                    *objectp = [O2PDFObject_Boolean pdfObjectWithFalse];
                else if (identifier == O2PDFIdentifier_null)
                    *objectp = [O2PDFObject_const pdfObjectWithNull];
                else
                    *objectp = [O2PDFObject_identifier
                            pdfObjectWithIdentifier: identifier
                                               name: name
                                             length: length];

                *lastPosition = position;
                return YES;
            }
            break;
        }
    }

    if (byteBuffer != NULL)
        O2PDFByteBufferFree(byteBuffer);

    *lastPosition = position;

    return (state == STATE_SCANNING) ? YES : NO;
}

BOOL O2PDFScanIdentifier(const char *bytes, unsigned length,
                         O2PDFInteger position, O2PDFInteger *lastPosition,
                         O2PDFObject_identifier **identifier)
{
    O2PDFObject *object;

    if (!O2PDFScanObject(bytes, length, position, lastPosition, &object))
        return NO;

    if (object == NULL)
        return NO;

    if ([object objectType] != O2PDFObjectType_identifier)
        return NO;

    *identifier = (O2PDFObject_identifier *) object;
    return YES;
}

BOOL O2PDFScanInteger(const char *bytes, unsigned length, O2PDFInteger position,
                      O2PDFInteger *lastPosition, O2PDFInteger *value)
{
    O2PDFObject *object;

    if (!O2PDFScanObject(bytes, length, position, lastPosition, &object))
        return NO;

    if (object == NULL)
        return NO;

    return [object checkForType: kO2PDFObjectTypeInteger value: value];
}

BOOL O2PDFParseObject(const char *bytes, unsigned length, O2PDFInteger position,
                      O2PDFInteger *lastPosition, O2PDFObject **objectp,
                      O2PDFxref *xref)
{
    NSMutableArray *stack = nil;
    O2PDFObject *check;

    debugTrace(bytes, length, position, @"O2PDFParseObject");
    while (YES) {

        if (!O2PDFScanObject(bytes, length, position, &position, &check))
            return NO;

        if (check == NULL) {
            *objectp = NULL;
            *lastPosition = position;
            return (stack == nil) ? YES : NO;
        }

        debugTrace(bytes, length, position, @"check=%@", check);

        switch ([check objectType]) {

        case kO2PDFObjectTypeNull:
        case kO2PDFObjectTypeBoolean:
        case kO2PDFObjectTypeInteger:
        case kO2PDFObjectTypeReal:
        case kO2PDFObjectTypeName:
        case kO2PDFObjectTypeString:
            if (stack != nil)
                [stack addObject: check];
            else {
                *objectp = check;
                *lastPosition = position;
                return YES;
            }
            break;

        case O2PDFObjectTypeMark_array_open:
        case O2PDFObjectTypeMark_dictionary_open:
            if (stack == nil)
                stack = [NSMutableArray array];
            [stack addObject: check];
            break;

        case O2PDFObjectTypeMark_array_close: {
            O2PDFArray *array = [O2PDFArray pdfArray];
            int count = [stack count];
            int index = count;
            NSRange remove;

            while (--index >= 0) {
                O2PDFObject *check = [stack objectAtIndex: index];

                if ([check objectTypeNoParsing] ==
                    O2PDFObjectTypeMark_array_open)
                    break;
            }
            if (index < 0)
                return debugError(bytes, length, position,
                                  @"array ] with no [");

            remove = NSMakeRange(index, count - index);
            index++;
            for (; index < count; index++)
                [array addObject: [stack objectAtIndex: index]];

            [stack removeObjectsInRange: remove];
            [stack addObject: array];

            if ([stack count] == 1) {
                *objectp = (O2PDFObject *) array;
                *lastPosition = position;
                return YES;
            }
        } break;

        case O2PDFObjectTypeMark_dictionary_close: {
            O2PDFDictionary *dictionary = [O2PDFDictionary pdfDictionary];

            while ((check = [stack lastObject]) != nil) {
                const char *key;

                if ([check objectTypeNoParsing] ==
                    O2PDFObjectTypeMark_dictionary_open) {
                    if ([stack count] == 1) {
                        *objectp = dictionary;
                        *lastPosition = position;
                        return YES;
                    } else {
                        [stack removeLastObject];
                        [stack addObject: dictionary];
                        break;
                    }
                }

                [[check retain] autorelease];
                [stack removeLastObject];
                if (![[stack lastObject] checkForType: kO2PDFObjectTypeName
                                                value: &key])
                    return debugError(
                            bytes, length, position,
                            @"Expecting name on stack for dictionary");

                [dictionary setObjectForKey: key value: check];
                [stack removeLastObject];
            }
            if ([stack count] == 0)
                return debugError(bytes, length, position,
                                  @"dictionary >> with no <<");
        } break;

        case O2PDFObjectType_identifier: {
            O2PDFIdentifier identifier =
                    [(O2PDFObject_identifier *) check identifier];

            if (identifier == O2PDFIdentifier_R) {
                O2PDFInteger generation;
                O2PDFInteger number;
                O2PDFObject *object;

                if (![[stack lastObject] checkForType: kO2PDFObjectTypeInteger
                                                value: &generation])
                    return NO;
                [stack removeLastObject];
                if (![[stack lastObject] checkForType: kO2PDFObjectTypeInteger
                                                value: &number])
                    return NO;
                [stack removeLastObject];

                object = [O2PDFObject_R pdfObjectWithNumber: number
                                                 generation: generation
                                                       xref: xref];

                if (stack != nil)
                    [stack addObject: object];
                else {
                    *objectp = object;
                    *lastPosition = position;
                    return YES;
                }
            } else {
                if ([stack count] > 0)
                    return debugError(bytes, length, position,
                                      @"stack size=%d,unexpected identifier %@",
                                      [stack count], check);
                *objectp = check;
                *lastPosition = position;
                return YES;
            }
        } break;

        default:
            return NO;
        }
    }

    return NO;
}

BOOL O2PDFParseDictionary(const char *bytes, unsigned length,
                          O2PDFInteger position, O2PDFInteger *lastPosition,
                          O2PDFDictionary **dictionaryp, O2PDFxref *xref)
{
    O2PDFObject *object;

    if (!O2PDFParseObject(bytes, length, position, lastPosition, &object, xref))
        return NO;

    if (object == NULL)
        return NO;

    return [object checkForType: kO2PDFObjectTypeDictionary value: dictionaryp];
}

static BOOL O2PDFParseXrefStream(NSData *data, O2PDFInteger position,
        O2PDFxref **result) {
    const char *bytes = [data bytes];
    unsigned length = [data length];
    O2PDFInteger cursor = position, number, generation;
    O2PDFObject *object;
    if (!O2PDFScanInteger(bytes, length, cursor, &cursor, &number) || number <= 0 ||
            !O2PDFScanInteger(bytes, length, cursor, &cursor, &generation) ||
            generation < 0 || generation > 65535)
        return NO;
    O2PDFxref *table = [[[O2PDFxref alloc] initWithData: data] autorelease];
    if (!O2PDFParseIndirectObject(data, position, &object, number, generation, table))
        return NO;
    O2PDFStream *stream;
    if (![object checkForType: kO2PDFObjectTypeStream value: &stream])
        return NO;
    O2PDFDictionary *dictionary = [stream dictionary];
    const char *directKeys[] = {"Length", "Filter", "DecodeParms", "Prev"};
    for (NSUInteger key = 0; key < sizeof(directKeys) / sizeof(directKeys[0]); ++key) {
        O2PDFObject *value = [dictionary objectForKeyNoParsing: directKeys[key]];
        if ([value objectTypeNoParsing] == O2PDFObjectType_R)
            return NO;
        if ([value objectTypeNoParsing] == kO2PDFObjectTypeArray) {
            O2PDFArray *array = (O2PDFArray *) value;
            for (NSUInteger i = 0; i < [array count]; ++i)
                if ([[array objectAtIndex: i] objectTypeNoParsing] == O2PDFObjectType_R)
                    return NO;
        }
    }
    O2PDFObject *previous = [dictionary objectForKeyNoParsing: "Prev"];
    if (previous != nil && [previous objectTypeNoParsing] != kO2PDFObjectTypeInteger)
        return NO;
    const char *type;
    O2PDFInteger size, widths[3];
    O2PDFArray *w, *index;
    if (![[dictionary objectForKeyNoParsing: "Type"] checkForType: kO2PDFObjectTypeName value: &type] ||
            strcmp(type, "XRef") ||
            [[dictionary objectForKeyNoParsing: "Size"] objectTypeNoParsing] != kO2PDFObjectTypeInteger ||
            ![dictionary getIntegerForKey: "Size" value: &size] || size <= 0 || number >= size ||
            ![[dictionary objectForKeyNoParsing: "W"] checkForType: kO2PDFObjectTypeArray value: &w] ||
            [w count] != 3)
        return NO;
    NSUInteger rowWidth = 0;
    for (NSUInteger i = 0; i < 3; ++i) {
        if ([[w objectAtIndex: i] objectTypeNoParsing] != kO2PDFObjectTypeInteger ||
                ![w getIntegerAtIndex: i value: &widths[i]] || widths[i] < 0 ||
                widths[i] > sizeof(O2PDFInteger))
            return NO;
        rowWidth += widths[i];
    }
    if (rowWidth == 0)
        return NO;
    O2PDFObject *rawIndex = [dictionary objectForKeyNoParsing: "Index"];
    if (rawIndex == nil) {
        O2PDFInteger values[] = {0, size};
        index = [O2PDFArray pdfArrayWithIntegers: values count: 2];
    } else if (![rawIndex checkForType: kO2PDFObjectTypeArray value: &index]) {
        return NO;
    }
    if ([index count] == 0 || [index count] % 2)
        return NO;
    O2PDFInteger previousEnd = 0;
    NSUInteger entries = 0;
    for (NSUInteger i = 0; i < [index count]; i += 2) {
        O2PDFInteger first, count;
        if ([[index objectAtIndex: i] objectTypeNoParsing] != kO2PDFObjectTypeInteger ||
                [[index objectAtIndex: i + 1] objectTypeNoParsing] != kO2PDFObjectTypeInteger ||
                ![index getIntegerAtIndex: i value: &first] ||
                ![index getIntegerAtIndex: i + 1 value: &count] ||
                first < previousEnd || count < 0 || first > size || count > size - first)
            return NO;
        previousEnd = first + count;
        entries += count;
    }
    NSData *decoded = [stream data];
    if (decoded == nil || [decoded length] % rowWidth || entries != [decoded length] / rowWidth)
        return NO;
    const unsigned char *input = [decoded bytes];
    for (NSUInteger range = 0; range < [index count]; range += 2) {
        O2PDFInteger first, count;
        [index getIntegerAtIndex: range value: &first];
        [index getIntegerAtIndex: range + 1 value: &count];
        for (O2PDFInteger n = first; n < first + count; ++n) {
            O2PDFInteger fields[3] = {1, 0, 0};
            for (NSUInteger field = 0; field < 3; ++field) {
                if (widths[field] == 0)
                    continue;
                NSUInteger value = 0;
                for (O2PDFInteger byte = 0; byte < widths[field]; ++byte)
                    value = (value << 8) | *input++;
                if (value > NSIntegerMax)
                    return NO;
                fields[field] = value;
            }
            if ((fields[0] == 1 && (fields[1] <= 0 || fields[1] >= length || fields[2] > 65535)) ||
                    (fields[0] == 2 && (fields[1] <= 0 || fields[1] >= size)))
                return NO;
            if ((const void *) n == NSNotAnIntMapKey)
                return NO;
            [table addEntry: [O2PDFxrefEntry xrefEntryWithType: fields[0] number: n
                    fieldTwo: fields[1] fieldThree: fields[2]]];
        }
    }
    [table setTrailer: dictionary];
    *result = table;
    return YES;
}

BOOL O2PDFParse_xrefAtPosition(NSData *data, O2PDFInteger position,
                               O2PDFxref **xrefp)
{
    if ([data length] > UINT_MAX || [data length] > NSIntegerMax || position < 0 || (NSUInteger) position >= [data length])
        return NO;
    O2PDFObject *firstObject;
    O2PDFInteger next;
    if (!O2PDFScanObject([data bytes], [data length], position, &next, &firstObject))
        return NO;
    if ([firstObject objectTypeNoParsing] == kO2PDFObjectTypeInteger)
        return O2PDFParseXrefStream(data, position, xrefp);
    const char *bytes = [data bytes];
    unsigned length = [data length];
    O2PDFxref *table;
    O2PDFDictionary *trailer;
    O2PDFObject_identifier *identifier = nil;

    if (!O2PDFScanIdentifier(bytes, length, position, &position, &identifier))
        return debugError(bytes, length, position, @"Expecting xref identifier",
                          identifier);

    if ([identifier identifier] != O2PDFIdentifier_xref)
        return debugError(bytes, length, position, @"Expecting xref, got %@",
                          identifier);

    *xrefp = table = [[[O2PDFxref alloc] initWithData: data] autorelease];
    do {
        O2PDFObject *object;
        O2PDFInteger number;
        O2PDFInteger count;

        if (!O2PDFScanObject(bytes, length, position, &position, &object))
            return debugError(bytes, length, position, @"Expecting object");

        if (object == NULL)
            return debugError(bytes, length, position, @"Expecting object");

        if ([object objectType] == O2PDFObjectType_identifier) {
            if ([(O2PDFObject_identifier *) object identifier] !=
                O2PDFIdentifier_trailer)
                return debugError(bytes, length, position,
                                  @"Expecting trailer identifier,got %@",
                                  object);
            else {
                if (!O2PDFParseDictionary(bytes, length, position, &position,
                                          &trailer, table))
                    return NO;

                [table setTrailer: trailer];
                return YES;
            }
        }

        if (![object checkForType: kO2PDFObjectTypeInteger value: &number])
            return debugError(bytes, length, position,
                              @"Expecting integer,got %@", object);

        if (!O2PDFScanInteger(bytes, length, position, &position, &count))
            return debugError(bytes, length, position, @"Expecting integer");

        if (number < 0 || count < 0 || count > NSIntegerMax - number)
            return NO;
        for (; --count >= 0; number++) {
            O2PDFInteger fieldOne, fieldTwo;
            if ((const void *) number == NSNotAnIntMapKey)
                return NO;

            if (!O2PDFScanInteger(bytes, length, position, &position,
                                  &fieldOne))
                return debugError(bytes, length, position,
                                  @"Expecting integer");
            if (!O2PDFScanInteger(bytes, length, position, &position,
                                  &fieldTwo))
                return debugError(bytes, length, position,
                                  @"Expecting integer");
            if (!O2PDFScanIdentifier(bytes, length, position, &position,
                                     &identifier))
                return debugError(bytes, length, position,
                                  @"Expecting identifier");

            switch ([identifier identifier]) {

            case O2PDFIdentifier_f:
                [table addEntry: [O2PDFxrefEntry xrefEntryWithType: 0 number: number
                        fieldTwo: fieldOne fieldThree: fieldTwo]];
                break;

            case O2PDFIdentifier_n:
                [table addEntry: [O2PDFxrefEntry
                                         xrefEntryWithPosition: fieldOne
                                                        number: number
                                                    generation: fieldTwo]];
                break;

            default:
                return debugError(bytes, length, position, @"Expecting f or n");
            }
        }
    } while (YES);
}

BOOL O2PDFParse_xref(NSData *data, O2PDFxref **xrefp) {
    const char *bytes = [data bytes];
    unsigned length = [data length];
    O2PDFInteger position, ignore;
    O2PDFObject_identifier *identifier;
    O2PDFxref *lastTable = nil;
    NSMutableSet *visited = [NSMutableSet set];
    if ([data length] > UINT_MAX || [data length] > NSIntegerMax)
        return NO;

    if (!O2PDFScanBackwardsToEOF(bytes, length, length, &position))
        return debugError(bytes, length, position,
                          @"Unable to back up over %%EOF");

    if (!O2PDFScanBackwardsByLines(bytes, length, length, &position, 3))
        return debugError(bytes, length, position,
                          @"Unable to back up 3 lines to find startxref");

    if (!O2PDFScanIdentifier(bytes, length, position, &position, &identifier))
        return debugError(bytes, length, position,
                          @"Expecting startxref identifier");

    if ([identifier identifier] != O2PDFIdentifier_startxref)
        return debugError(bytes, length, position,
                          @"Expecting startxref, got %@", identifier);

    if (!O2PDFScanInteger(bytes, length, position, &ignore, &position))
        return debugError(bytes, length, position, @"Expecting integer");

    do {
        O2PDFxref *table;
        NSNumber *offset = [NSNumber numberWithInteger: position];
        if ([visited containsObject: offset]) {
            O2PDFError(__FILE__, __LINE__, @"Cyclic PDF cross-reference chain");
            return NO;
        }
        [visited addObject: offset];

        if (!O2PDFParse_xrefAtPosition(data, position, &table))
            return NO;

        if (lastTable == nil)
            *xrefp = table;
        else
            [lastTable setPreviousTable: table];

        lastTable = table;
        O2PDFInteger hybridPosition;
        if ([[table trailer] getIntegerForKey: "XRefStm" value: &hybridPosition]) {
            NSNumber *hybridOffset = [NSNumber numberWithInteger: hybridPosition];
            O2PDFxref *hybrid;
            if ([visited containsObject: hybridOffset] || hybridPosition < 0 ||
                    (NSUInteger) hybridPosition >= [data length] ||
                    !O2PDFParseXrefStream(data, hybridPosition, &hybrid))
                return NO;
            [visited addObject: hybridOffset];
            [table setPreviousTable: hybrid];
            lastTable = hybrid;
        }

        if (![[table trailer] getIntegerForKey: "Prev" value: &position])
            break;

    } while (YES);

    O2PDFDictionary *catalog;
    return [[*xrefp trailer] getDictionaryForKey: "Root" value: &catalog];
}

BOOL O2PDFParseIndirectObject(NSData *data, O2PDFInteger position,
                              O2PDFObject **objectp, O2PDFInteger number,
                              O2PDFInteger generation, O2PDFxref *xref)
{
    const char *bytes = [data bytes];
    unsigned length = [data length];
    O2PDFInteger check;
    O2PDFObject_identifier *identifier;
    O2PDFObject *object;

    if ([data length] > UINT_MAX || [data length] > NSIntegerMax || position < 0 || (NSUInteger) position >= [data length])
        return NO;
    debugTrace(bytes, length, position, @"O2PDFParseIndirectObject");

    if (!O2PDFScanInteger(bytes, length, position, &position, &check))
        return debugError(bytes, length, position, @"Expecting integer");
    if (check != number)
        return debugError(
                bytes, length, position,
                @"Object number %d does not match indirect reference %d", check,
                number);

    if (!O2PDFScanInteger(bytes, length, position, &position, &check))
        return debugError(bytes, length, position, @"Expecting integer");
    if (check != generation)
        return debugError(
                bytes, length, position,
                @"Generation number %d does not match indirect reference %d",
                check, number);

    if (!O2PDFScanIdentifier(bytes, length, position, &position, &identifier))
        return debugError(bytes, length, position, @"Expecting obj identifier");
    if ([identifier identifier] != O2PDFIdentifier_obj)
        return debugError(bytes, length, position,
                          @"Expecting obj identifier, got %@", identifier);

    if (!O2PDFParseObject(bytes, length, position, &position, &object, xref))
        return debugError(bytes, length, position, @"Expecting object");

    if (object == NULL)
        return debugError(bytes, length, position,
                          @"Expecting object, got end of stream");

    if (!O2PDFScanIdentifier(bytes, length, position, &position, &identifier))
        return debugError(bytes, length, position, @"Expecting identifier");

    if ([identifier identifier] == O2PDFIdentifier_stream) {
        O2PDFDictionary *dictionary;
        O2PDFInteger streamLength;

        if (![object checkForType: kO2PDFObjectTypeDictionary
                            value: &dictionary])
            return debugError(bytes, length, position,
                              @"Expecting dictionary for stream, got %@",
                              object);

        if (![dictionary getIntegerForKey: "Length" value: &streamLength])
            return debugError(bytes, length, position,
                              @"stream dictionary does not contain /Length");

        if (position >= length || streamLength < 0)
            return NO;
        if (bytes[position] == CR)
            position++;
        if (position < length && bytes[position] == LF)
            position++;
        if ((NSUInteger) streamLength > length - position)
            return NO;

        object = [[[O2PDFStream alloc] initWithDictionary: dictionary
                                                     xref: xref
                                                 position: position]
                autorelease];

        position += streamLength;

        if (!O2PDFScanIdentifier(bytes, length, position, &position,
                                 &identifier))
            return debugError(bytes, length, position, @"Expecting identifier");
        if ([identifier identifier] != O2PDFIdentifier_endstream)
            return debugError(bytes, length, position,
                              @"Expecting endstream identifier, got %@",
                              identifier);

        if (!O2PDFScanIdentifier(bytes, length, position, &position,
                                 &identifier))
            return debugError(bytes, length, position, @"Expecting identifier");
    }

    if ([identifier identifier] != O2PDFIdentifier_endobj)
        return debugError(bytes, length, position,
                          @"Expecting endobj identifier, got %@", identifier);

    *objectp = object;
    return YES;
}

@implementation O2PDFScanner

+ (void) initialize {
    O2PDFScannerDumpStream = [[NSUserDefaults standardUserDefaults]
            boolForKey: @"O2PDFScannerDumpStream"];
}

- initWithContentStream: (O2PDFContentStream *) stream
          operatorTable: (O2PDFOperatorTable *) operatorTable
                   info: (void *) info
{
    _stack = [NSMutableArray new];
    _stream = [stream retain];
    _operatorTable = [operatorTable retain];
    _info = info;
    return self;
}

- (void) dealloc {
    [_stack release];
    [_stream release];
    [_operatorTable release];
    [super dealloc];
}

- (O2PDFContentStream *) contentStream {
    return _stream;
}

BOOL O2PDFScannerPopObject(O2PDFScanner *self, O2PDFObject **value) {
    id lastObject = [[[self->_stack lastObject] retain] autorelease];

    if (lastObject == nil)
        return NO;

    [self->_stack removeLastObject];

    *value = lastObject;
    return YES;
}

BOOL O2PDFScannerPopBoolean(O2PDFScanner *self, O2PDFBoolean *value) {
    BOOL result =
            [[self->_stack lastObject] checkForType: kO2PDFObjectTypeBoolean
                                              value: value];

    [self->_stack removeLastObject];

    return result;
}

BOOL O2PDFScannerPopInteger(O2PDFScanner *self, O2PDFInteger *value) {
    BOOL result =
            [[self->_stack lastObject] checkForType: kO2PDFObjectTypeInteger
                                              value: value];

    [self->_stack removeLastObject];

    return result;
}

BOOL O2PDFScannerPopNumber(O2PDFScanner *self, O2PDFReal *value) {
    BOOL result = [[self->_stack lastObject] checkForType: kO2PDFObjectTypeReal
                                                    value: value];

    [self->_stack removeLastObject];

    return result;
}

BOOL O2PDFScannerPopName(O2PDFScanner *self, const char **value) {
    id lastObject = [[[self->_stack lastObject] retain] autorelease];

    if (lastObject == nil)
        return NO;

    [self->_stack removeLastObject];

    return [lastObject checkForType: kO2PDFObjectTypeName value: value];
}

BOOL O2PDFScannerPopString(O2PDFScanner *self, O2PDFString **value) {
    id lastObject = [[[self->_stack lastObject] retain] autorelease];

    if (lastObject == nil)
        return NO;

    [self->_stack removeLastObject];

    return [lastObject checkForType: kO2PDFObjectTypeString value: value];
}

BOOL O2PDFScannerPopArray(O2PDFScanner *self, O2PDFArray **value) {
    id lastObject = [[[self->_stack lastObject] retain] autorelease];

    if (lastObject == nil)
        return NO;

    [self->_stack removeLastObject];

    return [lastObject checkForType: kO2PDFObjectTypeArray value: value];
}

BOOL O2PDFScannerPopDictionary(O2PDFScanner *self, O2PDFDictionary **value) {
    id lastObject = [[[self->_stack lastObject] retain] autorelease];

    if (lastObject == nil)
        return NO;

    [self->_stack removeLastObject];

    return [lastObject checkForType: kO2PDFObjectTypeDictionary value: value];
}

BOOL O2PDFScannerPopStream(O2PDFScanner *self, O2PDFStream **value) {
    id lastObject = [[[self->_stack lastObject] retain] autorelease];

    if (lastObject == nil)
        return NO;

    [self->_stack removeLastObject];

    return [lastObject checkForType: kO2PDFObjectTypeStream value: value];
}

NSData *O2PDFScannerCreateDataWithLength(O2PDFScanner *self, size_t length) {
    NSArray *streams = [self->_stream streams];
    O2PDFObject *object = [streams objectAtIndex: self->_currentStream];
    O2PDFStream *stream;

    if (![object checkForType: kO2PDFObjectTypeStream value: &stream])
        return nil;

    NSData *data = [stream data];

    NSData *result =
            [data subdataWithRange: NSMakeRange(self->_position, length)];

    self->_position += length;

    return result;
}

- (BOOL) scanStream: (O2PDFStream *) stream {
    O2PDFxref *xref = [stream xref];
    NSData *data = [stream data];
    const char *bytes = [data bytes];
    unsigned length = [data length];

    _position = 0;

    if (O2PDFScannerDumpStream)
        NSLog(@"data[%d]=%@", [data length],
              [[[NSString alloc] initWithData: data
                                     encoding: NSISOLatin1StringEncoding]
                      autorelease]);

    while (_position < length) {
        O2PDFObject *object;

        if (!O2PDFParseObject(bytes, length, _position, &_position, &object,
                              xref))
            return NO;

        if (object == NULL)
            return YES;

        if ([object objectTypeNoParsing] != O2PDFObjectType_identifier)
            [_stack addObject: object];
        else {
            O2PDFOperatorCallback callback = [_operatorTable
                    callbackForName: [(O2PDFObject_identifier *) object name]];

            if (callback != NULL) {
                callback(self, _info);
            } else {
                NSLog(@"unhandled identifier %@", object);
                [NSException raise: @"" format: @""];
            }
        }
    }

    return YES;
}

- (BOOL) scan {
    BOOL result = YES;
    NSArray *streams = [_stream streams];
    int count = [streams count];

    for (_currentStream = 0; (_currentStream < count) && result;
         _currentStream++) {
        O2PDFObject *object = [streams objectAtIndex: _currentStream];
        O2PDFStream *scan;

        if (![object checkForType: kO2PDFObjectTypeStream value: &scan])
            return NO;

        if (![self scanStream: scan])
            return NO;
    }

    return result;
}

@end
