#import <Foundation/Foundation.h>

@interface CAEDRMetadata : NSObject <NSCopying> {
    NSData *_displayInfo;
    NSData *_contentInfo;
    NSData *_ambientViewingEnvironment;
    float _minimumLuminance;
    float _maximumLuminance;
    float _opticalOutputScale;
    BOOL _HLG;
}
+ (instancetype)HDR10MetadataWithDisplayInfo:(NSData *)displayInfo contentInfo:(NSData *)contentInfo opticalOutputScale:(float)scale;
+ (instancetype)HDR10MetadataWithMinLuminance:(float)minimum maxLuminance:(float)maximum opticalOutputScale:(float)scale;
+ (instancetype)HLGMetadata;
+ (instancetype)HLGMetadataWithAmbientViewingEnvironment:(NSData *)environment;
+ (BOOL)isAvailable;
@end
