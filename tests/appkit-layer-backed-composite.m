// Source-owned NSViews: draw counts, CPU backing pixels, and the real layer GL
// framebuffer prove that moving/fading a view only composites cached contents.
#define GL_GLEXT_PROTOTYPES 1
#import <AppKit/AppKit.h>
#import <OpenGL/glext.h>
#import <OpenGL/OpenGL.h>
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
@interface CountView : NSView { @public unsigned draws, rectChecks; BOOL blue; }
@end
@implementation CountView
- (BOOL)isOpaque { return YES; }
- (void)drawRect:(NSRect)rect {
    if ([[self layer] delegate]==(id)self) {
        const NSRect *rects=NULL; NSInteger count=0;
        [self getRectsBeingDrawn:&rects count:&count];
        expect(count>0 && rects && NSContainsRect(rects[0],rect),"raster installs rects-being-drawn");
        expect([self needsToDrawRect:rect],"raster needsToDrawRect includes drawn region");
        rectChecks++;
    }
    draws++; [(blue ? [NSColor blueColor] : [NSColor redColor]) set]; NSRectFill(rect);
}
@end
@interface ScaleView : CountView
@end
@implementation ScaleView
- (CALayer *)makeBackingLayer { CALayer *layer=[CALayer layer]; [layer setContentsScale:2]; return layer; }
@end
@interface PatternView : CountView
@end
@implementation PatternView
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)rect {
    [super drawRect:rect];
    NSGradient *gradient=[[NSGradient alloc] initWithStartingColor:[NSColor redColor] endingColor:[NSColor blueColor]];
    [gradient drawInRect:rect angle:90]; [gradient release];
    [[NSColor greenColor] set]; NSRectFill(NSMakeRect(0,0,12,8));
    [@"Top" drawAtPoint:NSMakePoint(16,8) withAttributes:@{NSForegroundColorAttributeName:[NSColor whiteColor]}];
}
@end
static void capture(const char *name, CGFloat scale) {
    NSString *dir=[[[NSProcessInfo processInfo] environment] objectForKey:@"QV_LAYER_EVIDENCE"];
    if (!dir) return;
    size_t width=lround(400*scale), height=lround(260*scale);
    NSMutableData *data=[NSMutableData dataWithLength:width*height*4];
    glReadPixels(0,0,width,height,GL_BGRA,GL_UNSIGNED_BYTE,[data mutableBytes]);
    expect([data writeToFile:[dir stringByAppendingPathComponent:[NSString stringWithUTF8String:name]] atomically:NO],"capture layer framebuffer");
}
static void pixel(CGFloat x, CGFloat y, CGFloat scale, int r, int g, int b, int a, const char *label) {
    unsigned char p[4]={0}; glReadPixels(lround(x*scale), lround(y*scale), 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, p);
    BOOL ok=abs(p[0]-r)<=2 && abs(p[1]-g)<=2 && abs(p[2]-b)<=2 && abs(p[3]-a)<=2;
    if (!ok) printf("PIXEL %s got=%d,%d,%d,%d want=%d,%d,%d,%d\n", label,p[0],p[1],p[2],p[3],r,g,b,a);
    expect(ok,label);
}
// An RGBA + depth16 FBO has no stencil even on a stencil-capable EGL config.
// This exercises the real renderer, with nested clipping and a later sibling.
static void stencilFree(void) {
    GLuint fbo, color, depth;
    glPushAttrib(GL_ALL_ATTRIB_BITS);
    glGenFramebuffers(1,&fbo); glBindFramebuffer(GL_FRAMEBUFFER,fbo);
    glGenRenderbuffers(1,&color); glBindRenderbuffer(GL_RENDERBUFFER,color);
    glRenderbufferStorage(GL_RENDERBUFFER,GL_RGBA8,100,100);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_RENDERBUFFER,color);
    glGenRenderbuffers(1,&depth); glBindRenderbuffer(GL_RENDERBUFFER,depth);
    glRenderbufferStorage(GL_RENDERBUFFER,GL_DEPTH_COMPONENT16,100,100);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER,GL_DEPTH_ATTACHMENT,GL_RENDERBUFFER,depth);
    expect(glCheckFramebufferStatus(GL_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE,"stencil-free depth16 drawable complete");
    GLint bits=-1; glGetIntegerv(GL_STENCIL_BITS,&bits); expect(bits==0,"drawable really has no stencil");
    glViewport(0,0,100,100); glMatrixMode(GL_PROJECTION); glPushMatrix(); glLoadIdentity(); glOrtho(0,100,0,100,-1,1);
    glMatrixMode(GL_MODELVIEW); glPushMatrix();
    CALayer *root=[CALayer layer], *outer=[CALayer layer], *inner=[CALayer layer], *fill=[CALayer layer], *sibling=[CALayer layer];
    [root setFrame:CGRectMake(0,0,100,100)]; [outer setFrame:CGRectMake(10,10,40,40)]; [outer setMasksToBounds:YES];
    [inner setFrame:CGRectMake(20,0,40,30)]; [inner setMasksToBounds:YES]; [fill setFrame:CGRectMake(-50,-50,150,150)];
    CGColorRef green=CGColorCreateGenericRGB(0,1,0,1), blue=CGColorCreateGenericRGB(0,0,1,1);
    [fill setBackgroundColor:green]; [sibling setBackgroundColor:blue]; [sibling setFrame:CGRectMake(80,80,10,10)];
    CGColorRelease(green); CGColorRelease(blue);
    [inner addSublayer:fill]; [outer addSublayer:inner]; [root addSublayer:outer]; [root addSublayer:sibling];
    CARenderer *renderer=[CARenderer rendererWithCGLContext:CGLGetCurrentContext() options:nil]; [renderer setLayer:root];
    [renderer render];
    pixel(35,20,1,0,255,0,255,"stencil-free nested mask interior");
    pixel(15,20,1,0,0,0,0,"stencil-free inner mask clips");
    pixel(55,20,1,0,0,0,0,"stencil-free outer mask clips");
    pixel(85,85,1,0,0,255,255,"stencil-free clip restored for sibling");
    expect(glGetError()==GL_NO_ERROR,"stencil-free renderer has no GL error");
    glPopMatrix(); glMatrixMode(GL_PROJECTION); glPopMatrix(); glMatrixMode(GL_MODELVIEW);
    glBindFramebuffer(GL_FRAMEBUFFER,0); glDeleteFramebuffers(1,&fbo); glDeleteRenderbuffers(1,&depth); glDeleteRenderbuffers(1,&color);
    glPopAttrib();
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
        CountView *custom=[[ScaleView alloc] initWithFrame:NSMakeRect(220,20,30,20)];
        [custom setWantsLayer:YES]; CALayer *customLayer=[custom layer]; [host addSubview:custom];
        CountView *hosting=[[CountView alloc] initWithFrame:NSMakeRect(150,70,30,20)];
        CALayer *hosted=[CALayer layer]; [hosting setLayer:hosted]; [hosting setWantsLayer:YES]; [host addSubview:hosting];
        expect([hosted delegate]==nil,"setLayer before wantsLayer preserves app delegate ownership");
        CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
        CGContextRef bitmap=CGBitmapContextCreate(NULL,2,2,8,8,space,kCGImageAlphaPremultipliedLast); CGColorSpaceRelease(space);
        CGContextSetRGBFillColor(bitmap,1,1,0,1); CGContextFillRect(bitmap,CGRectMake(0,0,2,2));
        CGImageRef appImage=CGBitmapContextCreateImage(bitmap); CGContextRelease(bitmap); [hosted setContents:(id)appImage];
        NSClipView *clip=[[NSClipView alloc] initWithFrame:NSMakeRect(300,10,80,80)];
        CountView *document=[[CountView alloc] initWithFrame:NSMakeRect(0,0,80,40000)];
        [clip setDocumentView:document]; [host addSubview:clip];
        PatternView *pattern=[[PatternView alloc] initWithFrame:NSMakeRect(20,100,100,60)]; [host addSubview:pattern];
        NSView *clipping=[[NSView alloc] initWithFrame:NSMakeRect(20,190,40,40)];
        CountView *overflow=[[CountView alloc] initWithFrame:NSMakeRect(30,0,30,40)];
        [clipping addSubview:overflow]; [host addSubview:clipping];
        expect([clipping wantsDefaultClipping],"NSView defaults to clipping");
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
        expect(view->draws==1 && custom->draws==1,"view-owned backing layers each draw once");
        expect(CGImageGetWidth((CGImageRef)[customLayer contents])==60 &&
               CGImageGetHeight((CGImageRef)[customLayer contents])==40,"2x view contents raster dimensions");
        CGFloat scale=[w backingScaleFactor];
        pixel(235,140,scale,0,255,0,255,"inside nested masks");
        pixel(225,140,scale,0,0,0,0,"outside inner mask");
        pixel(270,140,scale,0,0,0,0,"outside outer mask");
        expect([hosted contents]==(id)appImage && hosting->draws==0,"app contents survive first display");
        [hosting setFrameSize:NSMakeSize(35,25)]; [hosting setNeedsDisplay:YES];
        [hosting setNeedsDisplayInRect:[hosting bounds]]; [hosting display]; [context render];
        expect([hosted contents]==(id)appImage && hosting->draws==0,"host contents survive resize and invalidation");
        pixel(155,75,scale,255,255,0,255,"host layer retains later-set contents");
        pixel(55,200,scale,255,0,0,255,"overflow child inside parent");
        pixel(65,200,scale,0,0,0,0,"default clipping hides child beyond parent");
        pixel(25,157,scale,0,255,0,255,"flipped asymmetric top marker stays at top");
        expect(CGImageGetHeight((CGImageRef)[[document layer] contents])<=ceil(80*scale),"40000-point document allocates visible height only");
        capture("initial.bgra",scale);
        unsigned documentBefore=document->draws;
        [clip setBoundsOrigin:NSMakePoint(0,30000)]; [context render];
        expect(document->draws==documentBefore+1,"scroll exposes and rasterizes a new document region");
        expect(CGImageGetHeight((CGImageRef)[[document layer] contents])<=ceil(80*scale),"scrolled document remains viewport sized");
        pixel(310,20,scale,255,0,0,255,"scrolled raster positioned at visible document origin");
        capture("scrolled.bgra",scale);
        stencilFree(); [context render];
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
        CGImageRelease(appImage); [w orderOut:nil]; return failures!=0;
    }
}
