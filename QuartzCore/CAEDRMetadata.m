#import <QuartzCore/CAEDRMetadata.h>
#include <math.h>

@implementation CAEDRMetadata
+ (BOOL)isAvailable { return NO; } // No HDR output path is implemented.
+ (instancetype)HDR10MetadataWithDisplayInfo:(NSData *)displayInfo contentInfo:(NSData *)contentInfo opticalOutputScale:(float)scale
{
    if (!isfinite(scale) || scale <= 0) return nil;
    CAEDRMetadata *metadata = [[[self alloc] init] autorelease];
    metadata->_displayInfo = [displayInfo copy];
    metadata->_contentInfo = [contentInfo copy];
    metadata->_opticalOutputScale = scale;
    return metadata;
}
+ (instancetype)HDR10MetadataWithMinLuminance:(float)minimum maxLuminance:(float)maximum opticalOutputScale:(float)scale
{
    if (!isfinite(minimum) || !isfinite(maximum) || minimum < 0 || maximum < minimum ||
        !isfinite(scale) || scale <= 0) return nil;
    CAEDRMetadata *metadata = [[[self alloc] init] autorelease];
    metadata->_minimumLuminance = minimum;
    metadata->_maximumLuminance = maximum;
    metadata->_opticalOutputScale = scale;
    return metadata;
}
+ (instancetype)HLGMetadata { return [self HLGMetadataWithAmbientViewingEnvironment:nil]; }
+ (instancetype)HLGMetadataWithAmbientViewingEnvironment:(NSData *)environment
{
    CAEDRMetadata *metadata = [[[self alloc] init] autorelease];
    metadata->_HLG = YES;
    metadata->_ambientViewingEnvironment = [environment copy];
    return metadata;
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (void)dealloc
{
    [_displayInfo release]; [_contentInfo release]; [_ambientViewingEnvironment release];
    [super dealloc];
}
@end
