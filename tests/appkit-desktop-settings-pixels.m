// Original Qvolution CPU-raster fixture; only own AppKit/Onyx2D source and
// documented NSColor/portal interfaces. Run with the fake portal below.
#import <AppKit/AppKit.h>
#import <Onyx2D/O2Context_builtin.h>
#import <Onyx2D/O2Surface.h>
#import "NSGraphicsStyle.h"
#include <dbus/dbus.h>
#include <stdlib.h>
#include <stdio.h>
#define CHECK(x) do { if (!(x)) { fprintf(stderr,"FAIL %d %s\n",__LINE__,#x);exit(1); } } while(0)
static unsigned notifications;
@interface ThemeObserver : NSObject @end
@implementation ThemeObserver
- (void)changed:(NSNotification *)note { notifications++; }
@end
static void rgb(NSColor *color,int r,int g,int b) {
    CGFloat cr,cg,cb,ca;[[color colorUsingColorSpaceName:NSDeviceRGBColorSpace] getRed:&cr green:&cg blue:&cb alpha:&ca];
    CHECK(abs((int)lround(cr*255)-r)<=2);CHECK(abs((int)lround(cg*255)-g)<=2);CHECK(abs((int)lround(cb*255)-b)<=2);
}
static void sample(O2Surface *s,int x,int y,int r,int g,int b) {
    unsigned char *p=[s pixelBytes]+y*O2ImageGetBytesPerRow(s)+4*x;
    CHECK(abs(p[2]-r)<=2&&abs(p[1]-g)<=2&&abs(p[0]-b)<=2&&p[3]==255);
}
static void raster(int scale) {
    O2ColorSpaceRef cs=O2ColorSpaceCreateDeviceRGB();
    O2Surface *s=[[O2Surface alloc]initWithBytes:NULL width:80*scale height:24*scale bitsPerComponent:8 bytesPerRow:0
        colorSpace:cs bitmapInfo:kO2ImageAlphaPremultipliedFirst|kO2BitmapByteOrder32Little];
    O2ColorSpaceRelease(cs);CHECK(s);
    O2Context_builtin *context=[[O2Context_builtin alloc]initWithSurface:s flipped:NO];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithGraphicsPort:(CGContextRef)context flipped:NO]];
    O2ContextScaleCTM(context,scale,scale);
    [[NSColor whiteColor]setFill];NSRectFill(NSMakeRect(0,0,80,24));
    [[NSColor selectedTextBackgroundColor]setFill];NSRectFill(NSMakeRect(0,0,24,24));
    NSGraphicsStyle *style=[NSGraphicsStyle new];
    [style drawMenuSelectionInRect:NSMakeRect(28,0,24,24) enabled:YES];
    [style drawPushButtonNormalInRect:NSMakeRect(56,0,24,24) defaulted:YES];
    sample(s,12*scale,12*scale,240,200,219);sample(s,40*scale,12*scale,213,97,153);
    // P4 replaces P1's flat default fill with an 8%-white-to-accent
    // gradient. Its midpoint is a 4% white mix, still within +/-2/255.
    sample(s,68*scale,12*scale,215,103,157);
    [style drawDefaultButtonFaceInRect:NSMakeRect(56,0,24,24) pressed:YES];
    sample(s,68*scale,12*scale,187,85,135);
    [NSGraphicsContext restoreGraphicsState];[style release];[context release];[s release];
}
int main(int argc,char **argv) { @autoreleasepool {
    // A dark style left in the global domain by an earlier session.
    CFPreferencesSetValue(CFSTR("AppleInterfaceStyle"),CFSTR("Dark"),kCFPreferencesAnyApplication,kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
    CHECK([[[NSUserDefaults standardUserDefaults]stringForKey:@"AppleInterfaceStyle"]isEqualToString:@"Dark"]);
    [NSApplication sharedApplication];
    CHECK([[[NSApp effectiveAppearance]name]isEqualToString:NSAppearanceNameAqua]);
    CHECK([[NSUserDefaults standardUserDefaults]stringForKey:@"AppleInterfaceStyle"]==nil);
    if(argc>1 && !strcmp(argv[1],"--no-portal")) {
        rgb([NSColor controlAccentColor],10,122,255);puts("PASS no portal fallback, dark gate and startup interface style");return 0;
    }
    NSColor *retained=[[NSColor controlAccentColor]retain];
    rgb(retained,213,97,153);rgb([NSColor selectedContentBackgroundColor],213,97,153);
    rgb([NSColor selectedTextBackgroundColor],240,200,219);rgb([NSColor selectedMenuItemColor],213,97,153);
    rgb([NSColor headerColor],255,255,255);raster(1);raster(2);
    ThemeObserver *observer=[ThemeObserver new];
    [[NSNotificationCenter defaultCenter]addObserver:observer selector:@selector(changed:)name:NSSystemColorsDidChangeNotification object:nil];
    DBusError error;dbus_error_init(&error);DBusConnection *c=dbus_bus_get_private(DBUS_BUS_SESSION,&error);CHECK(c);
    dbus_connection_set_exit_on_disconnect(c,FALSE);
    DBusMessage *m=dbus_message_new_method_call("org.freedesktop.portal.Desktop","/org/freedesktop/portal/desktop","space.qvolution.ThemeFixture","SetBlue");
    DBusMessage *reply=dbus_connection_send_with_reply_and_block(c,m,1000,&error);CHECK(reply);
    dbus_message_unref(reply);dbus_message_unref(m);
    CFRunLoopRunInMode(kCFRunLoopDefaultMode,.2,false);
    CHECK(notifications==1);rgb(retained,0,0,255);rgb([NSColor selectedMenuItemColor],0,0,255);
    CHECK([[[NSApp effectiveAppearance]name]isEqualToString:NSAppearanceNameAqua]);
    // The cached system appearance follows the dark gate as soon as it changes.
    NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
    [defaults setBool:YES forKey:@"QvolutionFollowSystemAppearance"];
    CHECK([[[NSApp effectiveAppearance]name]isEqualToString:NSAppearanceNameDarkAqua]);
    [defaults removeObjectForKey:@"QvolutionFollowSystemAppearance"];
    CHECK([[[NSApp effectiveAppearance]name]isEqualToString:NSAppearanceNameAqua]);
    dbus_connection_close(c);dbus_connection_unref(c);[retained release];
    puts("RESULT theme-p1 failures=0 (1x/2x O2Surface, retained accent, notification, dark gate, cached gate change, startup interface style)");return 0;
}}
