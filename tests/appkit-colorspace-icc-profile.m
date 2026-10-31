#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
@interface NSColorSpace (QvolutionICCContract)
- (NSData *)ICCProfileData;
@end
#define CHECK(c, message) do { if(!(c)) {fprintf(stderr,"FAIL: %s\n",message);return 1;} } while(0)
int main(void) {
    NSAutoreleasePool *pool=[NSAutoreleasePool new];
    CGColorSpaceRef spaces[]={CGColorSpaceCreateDeviceRGB(),CGColorSpaceCreateDeviceGray(),
        CGColorSpaceCreateDeviceCMYK(),CGColorSpaceCreateWithName(kCGColorSpaceSRGB),
        CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3)};
    NSColorSpace *survivor=nil;
    for(unsigned i=0;i<sizeof(spaces)/sizeof(spaces[0]);i++) {
        CGColorSpaceRef source=spaces[i]; CHECK(source!=NULL,"existing profileless CG space creation");
        CGColorSpaceModel model=CGColorSpaceGetModel(source);
        size_t components=CGColorSpaceGetNumberOfComponents(source);
        CFStringRef name=CGColorSpaceCopyName(source);
        NSColorSpace *space=[[NSColorSpace alloc] initWithCGColorSpace:source];
        CHECK(space!=nil,"CG color-space wrapper");
        CGColorSpaceRelease(source);
        CHECK([space respondsToSelector:@selector(ICCProfileData)],"NSColorSpace ICCProfileData selector available");
        CHECK([space ICCProfileData]==nil && [space ICCProfileData]==nil,"profileless implementation reports absent ICC data");
        CGColorSpaceRef after=[space CGColorSpace];
        CHECK(after && CGColorSpaceGetModel(after)==model && CGColorSpaceGetNumberOfComponents(after)==components,"profile query preserves CG model/components");
        CFStringRef afterName=CGColorSpaceGetName(after);
        CHECK((!name&&!afterName)||(name&&afterName&&CFEqual(name,afterName)),"profile query preserves CG name");
        if(name) CFRelease(name);
        [survivor release];survivor=space;
    }
    [pool drain];
    CHECK([survivor ICCProfileData]==nil && [survivor CGColorSpace]!=NULL,"retained wrapper remains valid after pool drain");
    [survivor release];
    puts("PASS: optional ICC profile absence and color-space query ownership");return 0;
}
