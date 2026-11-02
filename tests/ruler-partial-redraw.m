// Source-owned AppKit/Wayland regression. Reads only our window's backing store.
#import <AppKit/AppKit.h>
#import <Onyx2D/O2Context_builtin.h>
#import <Onyx2D/O2Surface.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "ruler-capture-geometry.h"
#include "window-frame-settle.h"

@interface NSObject (RulerFixtureBackend)
- (id)platformWindow;
- (BOOL)isPopup;
- (NSPoint)contentOffset;
- (NSSize)logicalSurfaceSize;
@end
static unsigned failures,checks;
static void expect(BOOL ok,const char *name) {
    printf("%s %s\n",ok?"PASS":"FAIL",name);failures+=!ok;
}
static BOOL configured(NSWindow *window) {
    id backend=[window platformWindow];
    Ivar ivar=class_getInstanceVariable([backend class],"_configured");
    if(!ivar){fprintf(stderr,"own Wayland backend required\n");exit(2);}
    BOOL value;memcpy(&value,(char *)backend+ivar_getOffset(ivar),sizeof value);return value;
}
@interface ProbeRuler : NSRulerView { @public unsigned draws;NSRect lastDirty; }
@end
@implementation ProbeRuler
- (void)drawRect:(NSRect)r {draws++;lastDirty=r;[super drawRect:r];}
@end
@interface PopupContent : NSView @end
@implementation PopupContent
- (void)drawRect:(NSRect)r {
    [[NSColor whiteColor]set];NSRectFill(r);
    [@"Font family\nDejaVu Sans\nDejaVu Serif\nMonospace" drawInRect:NSInsetRect([self bounds],8,8)
        withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:13]}];
}
@end
@interface RulerDriver : NSObject { @public
    NSWindow *window,*popup;NSScrollView *scroll;NSTextView *text;ProbeRuler *ruler;
    NSArray *markers;NSRect region;unsigned phase,ticks;BOOL popupPending;
}
- (void)tick:(NSTimer *)timer;
@end
static NSImage *markerImage(void) {
    NSBitmapImageRep *rep=[[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:NULL
        pixelsWide:9 pixelsHigh:10 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
        isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:36 bitsPerPixel:32]autorelease];
    unsigned char *p=[rep bitmapData];memset(p,0,360);
    for(int y=1;y<9;y++)for(int x=1;x<8;x++)if(x<3||y>6) {
        unsigned char rgba[]={20,60,180,255};memcpy(p+y*36+x*4,rgba,4);
    }
    NSImage *image=[[[NSImage alloc]initWithSize:NSMakeSize(9,10)]autorelease];
    [image addRepresentation:rep];return image;
}
static NSData *snapshot(RulerDriver *d,const char *name) {
    O2Context_builtin *context=(id)[[d->window graphicsContext]graphicsPort];
    if(![context isKindOfClass:[O2Context_builtin class]]){fprintf(stderr,"own bitmap context required\n");exit(2);}
    O2Surface *surface=[context surface];
    if(!O2SurfaceCanReadWriteARGB8u(surface)){fprintf(stderr,"32-bit backing surface required\n");exit(2);}
    // Use the scroll frame, not its bounds or the ruler's current CTM. The
    // region includes the exposed row even after the ruler shrinks.
    NSRect frame=[[d->scroll superview]convertRect:[d->scroll frame]toView:nil];
    id backend=[d->window platformWindow];
    NSSize logical=[backend logicalSurfaceSize];NSPoint offset=[backend contentOffset];
    CGFloat scale=[d->window backingScaleFactor];
    RulerCaptureRect capture;
    if(![d->scroll isFlipped]||!NSEqualPoints([d->scroll bounds].origin,NSZeroPoint)||
       !rulerCaptureRect(frame.origin.x,NSMaxY(frame),
           d->region.origin.x,d->region.origin.y,d->region.size.width,d->region.size.height,
           logical.width,logical.height,offset.x,scale,
           O2SurfaceGetWidth(surface),O2SurfaceGetHeight(surface),&capture)) {
        fprintf(stderr,"capture unsupported: invalid view/backing geometry\n");exit(2);
    }
    int x=capture.x,y=capture.y,w=capture.width,h=capture.height;
    NSMutableData *data=[NSMutableData dataWithLength:(size_t)w*h*4];
    const unsigned char *p=O2SurfaceGetPixelBytes(surface);size_t stride=O2SurfaceGetBytesPerRow(surface);
    for(int row=0;row<h;row++)memcpy((char *)[data mutableBytes]+row*w*4,p+(y+row)*stride+x*4,w*4);
    NSString *directory=[[[NSProcessInfo processInfo]environment]objectForKey:@"RULER_EVIDENCE_DIR"];
    if(directory){
        [data writeToFile:[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%02u-%s.rgba",checks,name]]atomically:YES];
        NSString *meta=[NSString stringWithFormat:@"RGBA raw backing bytes; width=%d height=%d device_origin=%d,%d stride=%d backing_scale=%.8g\n",w,h,x,y,w*4,(double)scale];
        [meta writeToFile:[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%02u-%s.txt",checks,name]]atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
    return data;
}
static void compareFull(RulerDriver *d,const char *name) {
    checks++;NSData *before=[[snapshot(d,"incremental")copy]autorelease];
    // Redraw the whole window, including pixels outside the ruler's NEW frame.
    [d->window display];NSData *after=snapshot(d,"full");
    BOOL equal=[before isEqualToData:after];size_t changed=0;
    const unsigned char *a=[before bytes],*b=[after bytes];
    if([before length]==[after length])for(size_t i=0;i<[before length];i+=4)changed+=memcmp(a+i,b+i,4)!=0;
    printf("CHECK %u %s markers=%lu ruler_height=%.2f draws=%u changed_pixels=%zu\n",checks,name,(unsigned long)[[d->ruler markers]count],NSHeight([d->ruler frame]),d->ruler->draws,changed);
    expect(equal,name);
}
static void partial(RulerDriver *d,NSRect rect,const char *name) {
    unsigned before=d->ruler->draws;[d->ruler setNeedsDisplayInRect:rect];[d->window displayIfNeeded];
    expect(d->ruler->draws>before,"partial invalidation reached ruler drawRect");
    printf("DIRTY %.2f,%.2f %.2fx%.2f\n",d->ruler->lastDirty.origin.x,d->ruler->lastDirty.origin.y,d->ruler->lastDirty.size.width,d->ruler->lastDirty.size.height);
    compareFull(d,name);
}
@implementation RulerDriver
- (void)tick:(NSTimer *)timer {
    if(!configured(window)||(popupPending&&!configured(popup))) {
        if(++ticks<100)return;expect(NO,"window configured within 100 timer ticks");goto finish;
    }
    ticks=0;
    switch(phase++) {
    case 0:
        [window display];compareFull(self,"normal ruler stable under forced full redraw");
        partial(self,NSMakeRect(37,17,203,11),"normal nonzero partial rect equals full redraw");
        [popup orderFront:nil];popupPending=YES;return;
    case 1:
        expect([[popup platformWindow]isPopup],"popup uses the Wayland popup role");
        [popup display];compareFull(self,"popup overlap preserves ruler backing pixels");
        partial(self,NSMakeRect(53,0,190,15),"overlapped marker row partial redraw equals full");
        partial(self,NSMakeRect(53,15,190,16),"overlapped number row partial redraw equals full");
        // Deterministic equivalent of text resigning first responder to a
        // control outside its formatting context: setClientView clears markers.
        [ruler setClientView:nil];[window displayIfNeeded];
        expect([[ruler markers]count]==0&&NSHeight([ruler frame])==16,"marker removal shrinks ruler by one row");
        compareFull(self,"marker removal erases old number row below new ruler");
        [popup orderOut:nil];popupPending=NO;return;
    case 2:
        [window displayIfNeeded];compareFull(self,"popup dismissal equals full redraw");
        [ruler setClientView:text];[ruler setMarkers:markers];[window displayIfNeeded];
        compareFull(self,"marker restoration repaints shifted document and ruler");
        [ruler setBoundsOrigin:NSMakePoint(11,7)];[window display];
        partial(self,NSMakeRect(59,14,197,9),"nonzero ruler bounds origin partial equals full");
        [ruler setBoundsOrigin:NSZeroPoint];[window display];
        [scroll setFrameOrigin:NSMakePoint(47,43)];[window display];
        partial(self,NSMakeRect(59,14,197,9),"translated scroll view partial equals full");
        goto finish;
    }
finish:
    [popup orderOut:nil];[window orderOut:nil];[timer invalidate];[NSApp stop:nil];
    [NSApp postEvent:[NSEvent otherEventWithType:NSApplicationDefined location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0]atStart:NO];
}
@end
int main(void){@autoreleasepool {
    setbuf(stdout,NULL);[NSApplication sharedApplication];RulerDriver *d=[RulerDriver new];
    d->window=[[NSWindow alloc]initWithContentRect:NSMakeRect(100,100,720,340)styleMask:NSTitledWindowMask|NSClosableWindowMask backing:NSBackingStoreBuffered defer:NO];
    [d->window setReleasedWhenClosed:NO];[d->window setTitle:@"Ruler partial redraw regression"];
    d->scroll=[[NSScrollView alloc]initWithFrame:NSMakeRect(31,29,620,270)];
    [d->scroll setBorderType:NSNoBorder];[d->scroll setHasHorizontalScroller:NO];[d->scroll setHasVerticalScroller:NO];
    d->text=[[NSTextView alloc]initWithFrame:NSMakeRect(0,0,620,400)];
    [d->text setString:@"Source-owned TextEdit-like document\nTabs and ruler redraw regression\nOne\tTwo\tThree"];
    [d->text setEditable:NO];[d->text setSelectable:NO];[d->text setUsesRuler:NO];
    [d->scroll setDocumentView:d->text];[[d->window contentView]addSubview:d->scroll];
    d->ruler=[[ProbeRuler alloc]initWithScrollView:d->scroll orientation:NSHorizontalRuler];
    [d->scroll setHorizontalRulerView:d->ruler];[d->scroll setRulersVisible:YES];[d->ruler setClientView:d->text];
    NSMutableArray *markers=[NSMutableArray array];NSImage *image=markerImage();
    for(int x=72;x<=576;x+=72)[markers addObject:[[[NSRulerMarker alloc]initWithRulerView:d->ruler markerLocation:x image:image imageOrigin:NSZeroPoint]autorelease]];
    d->markers=[markers copy];[d->ruler setMarkers:d->markers];
    d->region=NSMakeRect(0,0,620,60);
    // Use our existing popup window class so Wayland creates a positioned
    // xdg_popup, rather than an independently placed toplevel panel.
    Class popupClass=NSClassFromString(@"NSPopUpWindow");
    if(!popupClass){fprintf(stderr,"own popup class required\n");return 2;}
    d->popup=[[popupClass alloc]initWithContentRect:NSMakeRect(170,320,220,120)styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
    [d->popup setReleasedWhenClosed:NO];[d->popup setLevel:NSPopUpMenuWindowLevel];
    [d->popup setContentView:[[[PopupContent alloc]initWithFrame:NSMakeRect(0,0,220,120)]autorelease]];
    // Use window-to-screen conversion so overlap follows actual content geometry.
    NSPoint screen=[d->window convertBaseToScreen:[d->scroll convertPoint:NSMakePoint(53,0)toView:nil]];
    [d->popup setFrameOrigin:NSMakePoint(screen.x,screen.y-80)];
    [d->window makeKeyAndOrderFront:nil];
    if (!fixtureWaitForWindowFrame(d->window,"ruler-partial-redraw")) return 2;
    NSTimer *timer=[NSTimer scheduledTimerWithTimeInterval:.05 target:d selector:@selector(tick:)userInfo:nil repeats:YES];
    [NSApp run];[timer invalidate];
    expect(checks==10,"all ten pixel checkpoints executed");
    printf("RESULT ruler-partial-redraw failures=%u checks=%u\n",failures,checks);return failures?1:0;
}}
