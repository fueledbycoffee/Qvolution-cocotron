// Internal diagnostic: CPU client raster only, never a compositor screenshot.
#import <Foundation/Foundation.h>
@class O2Surface;
@interface WaylandClientCapture : NSObject {
    int _directory;
    unsigned _attempts, _written, _error;
    unsigned long long _window;
}
- initWithDirectory:(NSString *)directory;
- (void)captureSurface:(O2Surface *)surface opaque:(BOOL)opaque scale120:(unsigned)scale;
- (unsigned)writtenCount;
- (unsigned)errorCode;
@end
