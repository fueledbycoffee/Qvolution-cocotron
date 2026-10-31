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
#import <Foundation/NSString.h>
#import <Onyx2D/O2Exceptions.h>
#import <Onyx2D/O2PDFContext.h>
#import <Onyx2D/O2PDFDictionary.h>
#import <Onyx2D/O2PDFObject_const.h>
#import <Onyx2D/O2PDFScanner.h>
#import <Onyx2D/O2PDFStream.h>
#import <limits.h>
#import <Onyx2D/O2PDFxref.h>
#import <Onyx2D/O2PDFxrefEntry.h>

@implementation O2PDFxref

- initWithData: (NSData *) data {
    _data = [data retain];
    _previous = nil;
    _numberToEntries = NSCreateMapTable(
            NSIntegerMapKeyCallBacks, NSNonRetainedObjectMapValueCallBacks, 0);
    _entryToObject = NSCreateMapTable(NSNonRetainedObjectMapKeyCallBacks,
                                      NSObjectMapValueCallBacks, 0);
    _entriesInOrder = [NSMutableArray new];
    _trailer = nil;
    return self;
}

- (void) dealloc {
    [_data release];
    [_previous release];
    NSFreeMapTable(_numberToEntries);
    NSFreeMapTable(_entryToObject);
    [_entriesInOrder release];
    [_trailer release];
    [super dealloc];
}

- (BOOL) isByReference {
    return NO;
}

- (NSData *) data {
    return _data;
}

- (O2PDFxref *) previous {
    return _previous;
}

- (NSArray *) allEntries {
    NSMutableArray *result = [NSMutableArray array];
    NSMapEnumerator state = NSEnumerateMapTable(_numberToEntries);
    int key;
    id value;

    while (NSNextMapEnumeratorPair(&state, (void **) &key, (void **) &value)) {
        if ([value isKindOfClass: [NSArray class]])
            [result addObjectsFromArray: value];
        else
            [result addObject: value];
    }

    return result;
}

- (O2PDFxrefEntry *) entryWithNumber: (O2PDFInteger) number
                          generation: (O2PDFInteger) generation
{
    void *key = (void *) number;
    id check = NSMapGet(_numberToEntries, key);

    if (check == nil)
        return [_previous entryWithNumber: number generation: generation];

    if ([check isKindOfClass: [NSArray class]]) {
        NSArray *array = check;
        int i, count = [check count];

        for (i = 0; i < count; i++) {
            O2PDFxrefEntry *entry = [array objectAtIndex: i];

            if ([entry generation] == generation)
                return entry;
        }
    }

    if ([check isKindOfClass: [NSArray class]] || [check generation] != generation)
        return nil;
    return check;
}

- (BOOL) parseCompressedEntry: (O2PDFxrefEntry *) entry object: (O2PDFObject **) result {
    O2PDFxrefEntry *container = [self entryWithNumber: [entry position] generation: 0];
    if (container == nil || [container type] != 1 || [container number] == [entry number])
        return NO;
    O2PDFStream *stream;
    if (![[self objectAtNumber: [entry position] generation: 0]
            checkForType: kO2PDFObjectTypeStream value: &stream])
        return NO;
    O2PDFDictionary *dictionary = [stream dictionary];
    O2PDFInteger count, first, index = [entry objectStreamIndex];
    const char *type;
    NSData *data = [stream data];
    NSUInteger length = [data length];
    if (![dictionary getNameForKey: "Type" value: &type] || strcmp(type, "ObjStm") ||
            ![dictionary getIntegerForKey: "N" value: &count] || count <= 0 ||
            ![dictionary getIntegerForKey: "First" value: &first] || first < 0 ||
            (NSUInteger) first > length || length >= UINT_MAX || length >= NSIntegerMax ||
            index < 0 || index >= count || (NSUInteger) count > ((NSUInteger) first + 1) / 4)
        return NO;
    NSMutableData *header = [NSMutableData dataWithBytes: [data bytes] length: first];
    [header appendBytes: "\n" length: 1];
    O2PDFInteger cursor = 0, start = -1, end = length - first, previous = -1;
    const char *bytes = [header bytes];
    for (O2PDFInteger i = 0; i < count; ++i) {
        O2PDFInteger number, offset;
        if (!O2PDFScanInteger(bytes, first + 1, cursor, &cursor, &number) || number <= 0 ||
                !O2PDFScanInteger(bytes, first + 1, cursor, &cursor, &offset) ||
                offset < 0 || offset <= previous || (NSUInteger) offset >= length - first)
            return NO;
        previous = offset;
        if (i == index) {
            if (number != [entry number])
                return NO;
            start = offset;
        } else if (i == index + 1) {
            end = offset;
        }
    }
    O2PDFObject *trailing;
    if (!O2PDFScanObject(bytes, first + 1, cursor, &cursor, &trailing) || trailing != nil || start < 0)
        return NO;
    // Close a final scalar token without admitting the next object's bytes.
    NSMutableData *body = [NSMutableData dataWithBytes: (const char *) [data bytes] + first + start
            length: end - start];
    [body appendBytes: "\n" length: 1];
    bytes = [body bytes];
    O2PDFInteger parsedEnd;
    if (!O2PDFParseObject(bytes, [body length], 0, &parsedEnd, result, self) || *result == nil ||
            [*result objectTypeNoParsing] < kO2PDFObjectTypeNull ||
            [*result objectTypeNoParsing] > kO2PDFObjectTypeDictionary)
        return NO;
    return O2PDFScanObject(bytes, [body length], parsedEnd, &parsedEnd, &trailing) && trailing == nil;
}

- (O2PDFObject *) objectAtNumber: (O2PDFInteger) number
                      generation: (O2PDFInteger) generation
{
    O2PDFxrefEntry *lookup = [self entryWithNumber: number
                                        generation: generation];

    if (lookup == nil || ([lookup type] != 1 && [lookup type] != 2))
        return [O2PDFObject_const pdfObjectWithNull];
    else {
        O2PDFObject *result = NSMapGet(_entryToObject, lookup);

        if (result == nil) {
            NSMapInsert(_entryToObject, lookup, [O2PDFObject_const pdfObjectWithNull]);
            BOOL parsed = [lookup type] == 2
                    ? [self parseCompressedEntry: lookup object: &result]
                    : O2PDFParseIndirectObject(_data, [lookup position], &result,
                            number, generation, self);
            if (!parsed) {
                O2PDFError(__FILE__, __LINE__, @"Invalid PDF object %ld generation %ld",
                        (long) number, (long) generation);
                return nil;
            }

            NSMapInsert(_entryToObject, lookup, result);
        }

        return result;
    }
}

- (O2PDFDictionary *) trailer {
    return _trailer;
}

- (void) setPreviousTable: (O2PDFxref *) table {
    [_previous autorelease];
    _previous = [table retain];
}

- (void) addEntry: (O2PDFxrefEntry *) entry {
    void *key = (void *) [entry number];
    id check = NSMapGet(_numberToEntries, key);

    [_entriesInOrder addObject: entry];

    if (check == nil)
        NSMapInsert(_numberToEntries, key, entry);
    if ([check isKindOfClass: [NSMutableArray class]])
        [check addObject: entry];
    else if ([check isKindOfClass: [O2PDFxrefEntry class]])
        NSMapInsert(_numberToEntries, key,
                    [NSMutableArray arrayWithObject: entry]);
}

- (void) addEntry: (O2PDFxrefEntry *) entry object: (O2PDFObject *) object {
    [self addEntry: entry];
    NSMapInsert(_entryToObject, entry, object);
}

- (void) setTrailer: (O2PDFDictionary *) trailer {
    [_trailer autorelease];
    _trailer = [trailer retain];
}

- (void) encodeWithPDFContext: (O2PDFContext *) encoder {
    unsigned startxref = [encoder length];
    int i, count = [_entriesInOrder count];

    [encoder appendCString: "xref\n"];
    [encoder appendFormat: @"%d %d\n", 1, count];
    for (i = 0; i < count; i++) {
        O2PDFxrefEntry *entry = [_entriesInOrder objectAtIndex: i];

        [encoder appendFormat: @"%010d %05d n \n", [entry position],
                               [entry generation]];
    }
    [_trailer setIntegerForKey: "Size"
                         value: [[_entriesInOrder lastObject] number] + 1];
    [encoder appendCString: "trailer\n"];
    [encoder encodePDFObject: _trailer];
    [encoder appendCString: "startxref\n"];
    [encoder appendFormat: @"%d\n", startxref];
    [encoder appendCString: "%%EOF\n"];
}

@end
