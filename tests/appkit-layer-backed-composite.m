// Source-owned NSViews: draw counts, CPU backing pixels, and the real layer GL
// framebuffer prove that moving/fading a view only composites cached contents.
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <QuartzCore/CALayerContext.h>
#import <Onyx2D/O2Context.h>
#import <Onyx2D/O2Surface.h>
#import <OpenGL/gl.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

static unsigned failures, checks;
static void expect(BOOL ok, const char *message) {
    checks++; if (!ok) { failures++; printf("FAIL %s\n", message); }
}
@interface NSObject (BackingProbe)
- (O2Context *)cgContext;
@end
@interface CountView : NSView { @public unsigned draws; BOOL blue; }
@end
@implementation CountView
- (BOOL)isOpaque { return YES; }
- (void)drawRect:(NSRect)rect {
    draws++; [(blue ? [NSColor blueColor] : [NSColor redColor]) set]; NSRectFill(rect);
}
@end
static void pixel(CGFloat x, CGFloat y, CGFloat scale, int r, int g, int b, int a, const char *label) {
    unsigned char p[4]={0}; glReadPixels(lround(x*scale), lround(y*scale), 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, p);
    BOOL ok=abs(p[0]-r)<=2 && abs(p[1]-g)<=2 && abs(p[2]-b)<=2 && abs(p[3]-a)<=2;
    if (!ok) printf("PIXEL %s got=%d,%d,%d,%d want=%d,%d,%d,%d\n", label,p[0],p[1],p[2],p[3],r,g,b,a);
    expect(ok,label);
}
int main(int argc,char **argv) {
    @autoreleasepool {
        setbuf(stdout,NULL); [NSApplication sharedApplication];
        unsigned frames=argc>1 ? atoi(argv[1]) : 120;
        expect(frames>=20 && frames<=1000,"bounded fixture frame count");
        NSWindow *w=[[NSWindow alloc] initWithContentRect:NSMakeRect(80,80,400,260)
            styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
        [w setReleasedWhenClosed:NO];
        CountView *cpu=[[CountView alloc] initWithFrame:NSMakeRect(0,0,400,260)]; cpu->blue=YES;
        [w setContentView:cpu];
        NSView *host=[[NSView alloc] initWithFrame:NSMakeRect(0,0,400,260)];
        [host setWantsLayer:YES]; [cpu addSubview:host];
        CountView *view=[[CountView alloc] initWithFrame:NSMakeRect(20,20,40,30)];
        [host addSubview:view]; // Implicitly layer-backed by the parent.
        CountView *custom=[[CountView alloc] initWithFrame:NSMakeRect(220,20,30,20)];
        CALayer *customLayer=[CALayer layer]; [customLayer setContentsScale:2];
        [custom setLayer:customLayer]; [host addSubview:custom];
        // Nested masks: a green oversized child must be clipped to the inner
        // mask and its outer ancestor; removing masks later exposes it.
        CALayer *outer=[CALayer layer], *inner=[CALayer layer], *green=[CALayer layer];
        [outer setFrame:CGRectMake(200,120,60,50)]; [outer setMasksToBounds:YES];
        [inner setFrame:CGRectMake(30,10,60,30)]; [inner setMasksToBounds:YES];
        [green setFrame:CGRectMake(-20,-20,120,90)];
        CGColorRef color=CGColorCreateGenericRGB(0,1,0,1); [green setBackgroundColor:color]; CGColorRelease(color);
        [inner addSublayer:green]; [outer addSublayer:inner]; [[host layer] addSublayer:outer];
        [w orderFront:nil]; [w display];
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        CALayerContext *context=[host valueForKey:@"layerContext"];
        expect(context!=nil,"real native layer context");
        [context render];
        expect(view->draws==1 && custom->draws==1,"wantsLayer and setLayer each draw once");
        expect(CGImageGetWidth((CGImageRef)[customLayer contents])==60 &&
               CGImageGetHeight((CGImageRef)[customLayer contents])==40,"2x view contents raster dimensions");
        CGFloat scale=[w backingScaleFactor];
        pixel(235,140,scale,0,255,0,255,"inside nested masks");
        pixel(225,140,scale,0,0,0,0,"outside inner mask");
        pixel(270,140,scale,0,0,0,0,"outside outer mask");
        [context flush];
        unsigned cpuBefore=cpu->draws;
        for (unsigned i=0;i<frames;i++) {
            [view setFrameOrigin:NSMakePoint(20+i%100,20)];
            [view setAlphaValue:0.5];
            [custom setFrameOrigin:NSMakePoint(220+i%30,20)];
            [w display]; // CPU ancestors redraw; clean layer views must not.
            [context render];
            if (i%10==0) {
                pixel(25+i%100,25,scale,128,0,0,128,"moved/faded NSView cached raster");
                pixel(225+i%30,25,scale,255,0,0,255,"setLayer view cached raster");
            }
            [context flush];
        }
        expect(view->draws==1 && custom->draws==1,"move/fade never re-runs drawRect");
        [host setBoundsOrigin:NSMakePoint(10,0)]; [context render];
        pixel(15+(frames-1)%100,25,scale,128,0,0,128,"view bounds scrolling composites cached subviews");
        expect(view->draws==1 && custom->draws==1,"scroll never re-runs drawRect");
        [host setBoundsOrigin:NSZeroPoint]; [context render];
        expect(cpu->draws>cpuBefore,"non-layer-backed CPU view still draws");
        O2Surface *surface=[(O2Context *)[[w platformWindow] cgContext] surface];
        const unsigned char *bytes=O2SurfaceGetPixelBytes(surface);
        const unsigned char *p=bytes+O2SurfaceGetBytesPerRow(surface)*(O2SurfaceGetHeight(surface)/2)+4*(O2SurfaceGetWidth(surface)/2);
        expect(p[0]>250 && p[1]<3 && p[2]<3,"layer content never painted into blue CPU backing");
        [view setNeedsDisplayInRect:NSMakeRect(0,0,2,2)]; [view displayIfNeeded]; [context render];
        expect(view->draws==2,"view invalidation redraws its layer once");
        [view displayRectIgnoringOpacity:[view bounds]];
        expect(view->draws==3,"explicit displayRect forces a raster refresh");
        [outer setMasksToBounds:NO]; [inner setMasksToBounds:NO]; [context render];
        pixel(270,140,scale,0,255,0,255,"unmasked child visible on next composite");
        expect(glGetError()==GL_NO_ERROR,"no GL errors");
        printf("RESULT appkit-layer-backed-composite failures=%u checks=%u frames=%u view_draws=%u custom_draws=%u\n",
            failures,checks,frames,view->draws,custom->draws);
        [w orderOut:nil]; return failures!=0;
    }
}
