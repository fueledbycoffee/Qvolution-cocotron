#import <AppKit/AppKit.h>
#import <Onyx2D/O2Context.h>
#import <Onyx2D/O2Surface.h>
#import <OpenGL/OpenGL.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef NDEBUG
#error Assertions required
#endif
@interface NSObject (EGLPresentationProbe)
- (NSDictionary *)eglPresentationStatistics;
- (O2Context *)cgContext;
@end
static void checkPresentation(BOOL value, const char *message) {
    if (!value) { fprintf(stderr,"FAIL: %s\n",message); exit(1); }
}
static void stopApp(void) {
    [NSApp stop:nil];
    [NSApp postEvent:[NSEvent otherEventWithType:NSApplicationDefined location:NSZeroPoint
        modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0] atStart:NO];
}
@interface AsymmetricView : NSView { @public BOOL changed; }
@end
@implementation AsymmetricView
- (void)drawRect:(NSRect)dirty {
    NSRect b=[self bounds]; CGFloat w=b.size.width/2,h=b.size.height/2;
    NSArray *colors=changed ? @[[NSColor yellowColor],[NSColor cyanColor],[NSColor magentaColor],[NSColor blackColor]] :
        @[[NSColor redColor],[NSColor colorWithCalibratedRed:0 green:1 blue:0 alpha:0.5],[NSColor blueColor],[NSColor whiteColor]];
    for (int i=0;i<4;i++) {
        [colors[i] set];
        NSRectFillUsingOperation(NSMakeRect((i%2)*w,(i/2)*h,w,h),NSCompositeCopy);
    }
}
@end
@interface PresentationDriver : NSObject { @public NSWindow *window,*opaqueWindow; AsymmetricView *view; CGLContextObj caller; NSUInteger stage,ticks,waitTicks; uint64_t before; }
- (void)tick:(NSTimer *)timer;
@end
@implementation PresentationDriver
- (NSDictionary *)stats:(NSWindow *)target {
    id platform=[target platformWindow];
    checkPresentation([NSStringFromClass([platform class]) isEqualToString:@"WaylandWindow"],"actual native Wayland root window");
    checkPresentation([platform respondsToSelector:@selector(eglPresentationStatistics)],"EGL presenter exists in actual backend");
    NSDictionary *s=[platform eglPresentationStatistics];
    checkPresentation([s[@"renderer"] isEqualToString:@"egl"],"strict requested renderer selected");
    checkPresentation([s[@"failures"] unsignedLongLongValue]==0,"no EGL presentation failure");
    return s;
}
- (void)checkCPUColors {
    O2Surface *s=[(O2Context *)[[window platformWindow] cgContext] surface];
    size_t w=O2SurfaceGetWidth(s),h=O2SurfaceGetHeight(s),stride=O2SurfaceGetBytesPerRow(s);
    const unsigned char *bytes=O2SurfaceGetPixelBytes(s);
    checkPresentation(w>2&&h>2&&stride>=w*4,"real CPU backing dimensions");
    // NSView bottom-left coordinates become top-row-first CPU storage.
    const unsigned char expected[4][4]={{255,0,0,255},{255,255,255,255},{0,0,255,255},{0,128,0,128}};
    for (int i=0;i<4;i++) {
        const unsigned char *p=bytes+(i/2 ? h*3/4:h/4)*stride+(i%2 ? w*3/4:w/4)*4;
        for(int c=0;c<4;c++) checkPresentation(abs((int)p[c]-expected[i][c])<=1,"asymmetric NSView CPU raster colors and premultiplied alpha");
    }
}
- (void)tick:(NSTimer *)timer {
    checkPresentation(++ticks<240,"bounded native frame/configure progress");
    checkPresentation(CGLGetCurrentContext()==caller,"caller CGL context preserved across AppKit presentation");
    NSDictionary *s=[self stats:window]; uint64_t swaps=[s[@"swaps"] unsignedLongLongValue];
    if (stage==0 && swaps) {
        checkPresentation([s[@"checks"] unsignedLongLongValue]==swaps,"every submitted frame verified before swap");
        [self checkCPUColors]; before=swaps;
        [window disableFlushWindow]; view->changed=YES; [view setNeedsDisplay:YES]; [window display];
        [[window platformWindow] flushBuffer]; // Queue backing content while presentation is paused.
        checkPresentation([[[self stats:window] objectForKey:@"swaps"] unsignedLongLongValue]==before,"flush pause suppresses swap");
        stage=1;waitTicks=ticks;
    } else if(stage==1 && ticks-waitTicks>=3) {
        checkPresentation(swaps==before,"frame callback does not bypass flush pause");
        [window enableFlushWindow]; [window flushWindow]; stage=2;
    } else if(stage==2 && swaps>before) {
        before=swaps;[window setContentSize:NSMakeSize(137,83)];[view setNeedsDisplay:YES];[window display];stage=3;
    } else if(stage==3 && swaps>before && [s[@"width"] intValue]>96 && [s[@"height"] intValue]>64) {
        printf("RESIZE %s\n",[[s description] UTF8String]);before=swaps;
        [window orderOut:nil];
        checkPresentation([[[self stats:window] objectForKey:@"width"] intValue]==0,"unmap tears down EGL drawable");
        [window orderFront:nil];[window display];stage=4;
    } else if(stage==4 && swaps>before) {
        opaqueWindow=[[NSWindow alloc] initWithContentRect:NSMakeRect(260,180,96,64) styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
        [opaqueWindow setReleasedWhenClosed:NO]; [opaqueWindow setOpaque:YES];
        AsymmetricView *other=[[[AsymmetricView alloc] initWithFrame:NSMakeRect(0,0,96,64)] autorelease];
        [opaqueWindow setContentView:other];[opaqueWindow orderFront:nil];[opaqueWindow display];stage=5;
    } else if(stage==5 && [[[self stats:opaqueWindow] objectForKey:@"swaps"] unsignedLongLongValue]) {
        NSDictionary *o=[self stats:opaqueWindow];
        checkPresentation([s[@"checks"] unsignedLongLongValue]==swaps && [o[@"checks"] unsignedLongLongValue]==[o[@"swaps"] unsignedLongLongValue],"alpha and opaque roots both checked");
        printf("ROOT %s\nOPAQUE %s\n",[[s description] UTF8String],[[o description] UTF8String]);
        [window orderOut:nil];[opaqueWindow orderOut:nil];
        checkPresentation(CGLGetCurrentContext()==caller,"teardown preserves caller CGL context");
        puts("PASS: ordinary CPU-raster/GPU-presentation windows, reference pixels, update, resize, remap, alpha, flush pacing and context restoration");
        [timer invalidate];stopApp();
    }
}
@end
int main(int argc,char **argv) {
    @autoreleasepool {
        setbuf(stdout,NULL);puts("ENTER ordinary AppKit EGL presentation");
        setenv("DARLING_APPKIT_RENDERER","egl",1);setenv("DARLING_APPKIT_EGL_VERIFY","1",1);
        if(argc>1&&strcmp(argv[1],"--negative-control")==0)setenv("DARLING_APPKIT_EGL_TEST_CORRUPT","1",1);
        [NSApplication sharedApplication];
        PresentationDriver *driver=[PresentationDriver new];
        CGLPixelFormatAttribute a[]={kCGLPFAAccelerated,0};CGLPixelFormatObj f=NULL;GLint n=0;
        checkPresentation(CGLChoosePixelFormat(a,&f,&n)==kCGLNoError&&f&&n,"caller context pixel format");
        checkPresentation(CGLCreateContext(f,NULL,&driver->caller)==kCGLNoError,"independent caller context");CGLReleasePixelFormat(f);
        checkPresentation(CGLSetCurrentContext(driver->caller)==kCGLNoError,"bind independent caller context");
        driver->window=[[NSWindow alloc] initWithContentRect:NSMakeRect(120,140,96,64) styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
        [driver->window setReleasedWhenClosed:NO];[driver->window setOpaque:NO];
        driver->view=[[AsymmetricView alloc] initWithFrame:NSMakeRect(0,0,96,64)];
        [driver->view setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
        [driver->window setContentView:driver->view];[driver->window orderFront:nil];[driver->window display];
        NSTimer *timer=[NSTimer scheduledTimerWithTimeInterval:0.05 target:driver selector:@selector(tick:) userInfo:nil repeats:YES];
        [NSApp run];[timer invalidate];
        [driver->window release];[driver->opaqueWindow release];[driver->view release];
        CGLSetCurrentContext(NULL);CGLReleaseContext(driver->caller);[driver release];
    }
    return 0;
}
