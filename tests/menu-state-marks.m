// Pixel regression for the shared menu state-mark renderer.
#import <AppKit/AppKit.h>
#import <AppKit/NSGraphicsStyle.h>
#import <Onyx2D/O2Context_builtin.h>
#import <Onyx2D/O2Surface.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

@interface MarkView : NSView { NSMenu *menu; }
@end
@implementation MarkView
- (id)initWithFrame:(NSRect)r {
    if ((self=[super initWithFrame:r])) {
        menu=[[NSMenu alloc] initWithTitle:@"marks"];
        NSInteger states[]={NSOffState,NSOnState,NSMixedState};
        for(int i=0;i<3;i++) { NSMenuItem *item=[[[NSMenuItem alloc] initWithTitle:@"Item" action:NULL keyEquivalent:@""] autorelease]; [item setState:states[i]]; [menu addItem:item]; }
    } return self;
}
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirty {
    NSGraphicsStyle *style=[[[NSGraphicsStyle alloc] initWithView:self] autorelease];
    for(int selected=0;selected<2;selected++) for(int row=0;row<3;row++) {
        NSRect cell=NSMakeRect(10+selected*60,10+row*30,40,25);
        [(selected?[NSColor selectedMenuItemColor]:[NSColor whiteColor]) set]; NSRectFill(cell);
        NSRect mark=NSMakeRect(cell.origin.x+10,cell.origin.y+4,20,17);
        NSInteger state=[[menu itemAtIndex:row] state];
        if(state==NSOnState) [style drawMenuCheckmarkInRect:mark enabled:YES selected:selected];
        if(state==NSMixedState) [style drawMenuMixedMarkInRect:mark enabled:YES selected:selected];
    }
}
@end
static double seg(double x,double y,double ax,double ay,double bx,double by) {
    double dx=bx-ax,dy=by-ay,t=((x-ax)*dx+(y-ay)*dy)/(dx*dx+dy*dy);
    t=fmax(0,fmin(1,t)); return hypot(x-(ax+t*dx),y-(ay+t*dy));
}
int main(void) {
    NSAutoreleasePool *pool=[NSAutoreleasePool new]; [NSApplication sharedApplication];
    NSWindow *window=[[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,140,110) styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO] autorelease];
    MarkView *view=[[[MarkView alloc] initWithFrame:NSMakeRect(0,0,140,110)] autorelease]; [window setContentView:view]; [window orderFront:nil]; [window display];
    O2Context_builtin *ctx=(id)[[window graphicsContext] graphicsPort];
    if(![ctx isKindOfClass:[O2Context_builtin class]]) return 2;
    O2Surface *surface=[ctx surface]; if(!O2SurfaceCanReadWriteARGB8u(surface)) return 2;
    const unsigned char *bytes=O2SurfaceGetPixelBytes(surface); size_t stride=O2SurfaceGetBytesPerRow(surface);
    double size=ceil([[NSFont menuFontOfSize:0] pointSize]); int failures=0;
    for(int selected=0;selected<2;selected++) for(int row=1;row<3;row++) {
        int inside=0,outside=0; double ox=20+selected*60+(20-size)/2, oy=14+row*30+(17-size)/2;
        for(int iy=0;iy<(int)ceil(size);iy++) for(int ix=0;ix<(int)ceil(size);ix++) {
            double x=ox+ix+0.5,y=oy+iy+0.5;
            NSRect a=[view convertRect:NSMakeRect(x,y,1,1) toView:nil];
            NSRect b=[view convertRect:NSMakeRect(x,y-row*30,1,1) toView:nil];
            O2Rect da=O2ContextConvertRectToDeviceSpace(ctx,a),db=O2ContextConvertRectToDeviceSpace(ctx,b);
            if(!isfinite(da.origin.x)||!isfinite(da.origin.y)||!isfinite(db.origin.x)||!isfinite(db.origin.y)||
               da.size.width<=0||da.size.height<=0||db.size.width<=0||db.size.height<=0) {
                fprintf(stderr,"FAIL invalid device-space sample rectangles\n"); return 2;
            }
            int ax=floor(da.origin.x),ay=floor(da.origin.y),bx=floor(db.origin.x),by=floor(db.origin.y);
            if(ax==bx&&ay==by) { fprintf(stderr,"FAIL mark and off-state samples alias\n"); return 2; }
            if(ax<0||ay<0||bx<0||by<0||ax>=O2SurfaceGetWidth(surface)||bx>=O2SurfaceGetWidth(surface)||ay>=O2SurfaceGetHeight(surface)||by>=O2SurfaceGetHeight(surface)) return 2;
            const unsigned char *pa=bytes+ay*stride+ax*4,*pb=bytes+by*stride+bx*4;
            int diff=abs(pa[0]-pb[0])+abs(pa[1]-pb[1])+abs(pa[2]-pb[2]);
            double nx=(x-ox)/size,ny=(y-oy)/size;
            double d=row==1?fmin(seg(nx,ny,.16,.51,.39,.73),seg(nx,ny,.39,.73,.84,.27)):seg(nx,ny,.23,.5,.77,.5);
            if(diff>30) { if(d<.18) inside++; else outside++; }
        }
        int ok=inside>=3 && outside<=2; failures+=!ok;
        printf("%s %s %s inside=%d outside=%d\n",ok?"PASS":"FAIL",row==1?"on":"mixed",selected?"highlighted":"normal",inside,outside);
    }
    printf("RESULT menu-state-marks failures=%d checks=4\n",failures); [pool drain]; return failures?1:0;
}
