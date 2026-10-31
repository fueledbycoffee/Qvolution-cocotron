#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdio.h>
static void finishScaleObservation(void) {
    [NSApp stop:nil];
    [NSApp postEvent:[NSEvent otherEventWithType:NSApplicationDefined location:NSZeroPoint
            modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0]
            atStart:YES];
}
@interface QVScaleObservation : NSObject { @public NSWindow *window; int result; }
- (void)observe:(NSTimer *)timer;
@end
@implementation QVScaleObservation
- (void)observe:(NSTimer *)timer {
    CGContextRef context=[[window graphicsContext] graphicsPort];
    if(!context){fprintf(stderr,"FAIL: mapped window has no CGContext\n");result=2;finishScaleObservation();return;}
    double reported=[window backingScaleFactor];
    CGPoint p=CGContextConvertPointToDeviceSpace(context,CGPointMake(0,0));
    CGPoint x=CGContextConvertPointToDeviceSpace(context,CGPointMake(1,0));
    CGPoint y=CGContextConvertPointToDeviceSpace(context,CGPointMake(0,1));
    double sx=hypot(x.x-p.x,x.y-p.y),sy=hypot(y.x-p.x,y.y-p.y);
    NSRect backing=[window convertRectToBacking:NSMakeRect(0,0,1,1)];
    printf("reported_scale=%.6f device_x_unit=%.6f device_y_unit=%.6f backing_x_unit=%.6f backing_y_unit=%.6f bitmap_width=%lu bitmap_height=%lu\n",reported,sx,sy,backing.size.width,backing.size.height,(unsigned long)CGBitmapContextGetWidth(context),(unsigned long)CGBitmapContextGetHeight(context));
    result=context&&isfinite(reported)&&reported>0&&fabs(sx-reported)<1./64&&fabs(sy-reported)<1./64&&fabs(backing.size.width-reported)<1./64&&fabs(backing.size.height-reported)<1./64?0:1;
    fprintf(result?stderr:stdout,"%s: mapped window backing scale vs actual CGContext device transform\n",result?"FAIL":"PASS");
    finishScaleObservation();
}
@end
int main(void) {
    NSAutoreleasePool *pool=[NSAutoreleasePool new];[NSApplication sharedApplication];
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,160,80) styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
    [window setTitle:@"Qvolution scale probe"];
    QVScaleObservation *probe=[QVScaleObservation new];probe->window=window;probe->result=2;
    [window orderFront:nil];
    [NSTimer scheduledTimerWithTimeInterval:2 target:probe selector:@selector(observe:) userInfo:nil repeats:NO];
    [NSApp run];int result=probe->result;[window orderOut:nil];[probe release];[window release];[pool drain];return result;
}
