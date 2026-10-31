// Project-private raw bitmap archive model, not a native AppKit archive schema.
#import <AppKit/NSBitmapImageRep.h>
#import <Foundation/Foundation.h>
#include <limits.h>
#include <math.h>

static inline void QVImageCodingRequire(BOOL condition, NSString *exception, NSString *message) {
    if (!condition) [NSException raise:exception format:@"%@",message];
}
static inline id QVImageCodingAllocated(id value, NSString *message) {
    QVImageCodingRequire(value!=nil,NSMallocException,message);
    return value;
}
static inline BOOL QVImageCodingValidSize(NSSize size) {
    return isfinite(size.width)&&isfinite(size.height)&&size.width>=0&&size.height>=0;
}
static inline BOOL QVImagePackedRGBExtent(NSUInteger width, NSUInteger height, NSUInteger samples,
        NSUInteger bits, NSUInteger stride, NSUInteger format, BOOL alpha) {
    return width&&height&&width<=INT_MAX&&height<=INT_MAX&&stride<=INT_MAX&&
        !(format&~(NSAlphaFirstBitmapFormat|NSAlphaNonpremultipliedBitmapFormat))&&
        samples==(alpha?4:3)&&(bits==samples*8||(!alpha&&bits==32))&&
        width<=(NSUInteger)INT_MAX/(bits/8)&&stride>=width*(bits/8)&&height<=(NSUInteger)INT_MAX/stride&&
        (alpha||!(format&NSAlphaNonpremultipliedBitmapFormat));
}
static inline BOOL QVImageCGBitmapLayout(NSUInteger bits, BOOL alpha, NSUInteger format, NSUInteger info) {
    NSUInteger order=info&kCGBitmapByteOrderMask,a=info&kCGBitmapAlphaInfoMask;
    BOOL cgAlpha=a==kCGImageAlphaFirst||a==kCGImageAlphaLast||a==kCGImageAlphaPremultipliedFirst||a==kCGImageAlphaPremultipliedLast;
    BOOL cgFirst=a==kCGImageAlphaFirst||a==kCGImageAlphaPremultipliedFirst;
    BOOL cgStraight=a==kCGImageAlphaFirst||a==kCGImageAlphaLast;
    return !(info&~(kCGBitmapAlphaInfoMask|kCGBitmapByteOrderMask))&&cgAlpha==alpha&&
        format==((cgFirst?NSAlphaFirstBitmapFormat:0)|(cgStraight?NSAlphaNonpremultipliedBitmapFormat:0))&&
        ((bits==24&&a==kCGImageAlphaNone&&order==kCGBitmapByteOrderDefault)||
         (bits==32&&(cgAlpha||a==kCGImageAlphaNoneSkipFirst||a==kCGImageAlphaNoneSkipLast)&&
          (order==kCGBitmapByteOrderDefault||order==kCGBitmapByteOrder32Big||order==kCGBitmapByteOrder32Little)));
}
static inline NSUInteger QVImageCodingInteger(id value, NSUInteger maximum, NSString *exception) {
    QVImageCodingRequire([value isKindOfClass:[NSNumber class]],exception,@"Expected bitmap archive integer");
    double number=[value doubleValue];
    QVImageCodingRequire(isfinite(number)&&number>=0&&number<=maximum&&floor(number)==number,exception,@"Invalid bitmap archive integer");
    return (NSUInteger)number;
}
static inline CGFloat QVImageCodingFloat(id value, NSString *exception) {
    QVImageCodingRequire([value isKindOfClass:[NSNumber class]],exception,@"Expected image archive number");
    CGFloat number=[value doubleValue];
    QVImageCodingRequire(isfinite(number),exception,@"Nonfinite image archive geometry");
    return number;
}
static inline NSArray *QVImageCodingArray(id value, NSUInteger count, NSString *exception) {
    QVImageCodingRequire([value isKindOfClass:[NSArray class]]&&[value count]==count,exception,@"Invalid image archive array");
    return value;
}
static inline NSSize QVImageCodingSize(id value, NSString *exception) {
    NSArray *array=QVImageCodingArray(value,2,exception);
    NSSize size=NSMakeSize(QVImageCodingFloat([array objectAtIndex:0],exception),QVImageCodingFloat([array objectAtIndex:1],exception));
    QVImageCodingRequire(QVImageCodingValidSize(size),exception,@"Invalid image archive size");
    return size;
}
static inline NSArray *QVImageCodingSizeRecord(NSSize size, NSString *exception) {
    NSArray *record=@[@(size.width),@(size.height)];
    QVImageCodingSize(record,exception);
    return record;
}

@interface NSBitmapImageRep (QvolutionCoding)
// A nonnull providerData receives a retained snapshot for CG-backed state.
- (void)_qvolutionValidateBitmapState:(NSString *)exception providerData:(CFDataRef *)providerData;
- (NSDictionary *)_qvolutionBitmapRecord;
- (id)_qvolutionInitWithBitmapRecord:(NSDictionary *)record;
@end
