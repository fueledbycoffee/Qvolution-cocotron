// Own Darling backend regression: no Apple implementation or guest introspection.
#import <AppKit/AppKit.h>
#import <Onyx2D/O2Surface.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

@interface NSObject (DecorationFixture)
- (id)platformWindow;
- (id)cgContext;
- (O2Surface *)surface;
- (void)drawDecorations;
- (void)applyConfigure;
- (void)hideWindow;
- (void)showWindowWithoutActivation;
@end
static unsigned failures, renders;
static IMP originalDraw;
static Ivar field(id object, const char *name) {
    Ivar result=class_getInstanceVariable([object class],name);
    if (!result) { fprintf(stderr,"missing own backend field %s\n",name); exit(2); }
    return result;
}
static void *slot(id object,const char *name) { return (char *)object+ivar_getOffset(field(object,name)); }
static BOOL flag(id object,const char *name) { BOOL result;memcpy(&result,slot(object,name),sizeof(result));return result; }
static void setFlag(id object,const char *name,BOOL value) { memcpy(slot(object,name),&value,sizeof(value)); }
static void trackDraw(id object,SEL selector) {
    BOOL dirty=flag(object,"_decorationsDirty");
    ((void(*)(id,SEL))originalDraw)(object,selector);
    if(dirty&&!flag(object,"_decorationsDirty"))renders++;
}
static void expectCache(BOOL success,const char *name) { printf("%s %s\n",success?"PASS":"FAIL",name);failures+=!success; }
static NSData *pixels(id backend) {
    O2Surface *surface=[[backend cgContext]surface];
    return [NSData dataWithBytes:[surface pixelBytes]
                         length:O2ImageGetHeight(surface)*O2ImageGetBytesPerRow(surface)];
}
static void compareForcedDraw(id backend) {
    NSData *before=[[pixels(backend)copy]autorelease];
    setFlag(backend,"_decorationsDirty",YES);[backend drawDecorations];
    NSData *after=pixels(backend);
    BOOL equal=[before isEqualToData:after];
    expectCache(equal,"cached backing pixels equal forced decoration rendering");
    if(!equal) {
        O2Surface *surface=[[backend cgContext]surface];
        size_t width=O2ImageGetWidth(surface),height=O2ImageGetHeight(surface),stride=O2ImageGetBytesPerRow(surface);
        size_t count=0,minX=width,minY=height,maxX=0,maxY=0;
        const unsigned char *a=[before bytes],*b=[after bytes];
        for(size_t y=0;y<height;y++)for(size_t x=0;x<width;x++)
            if(memcmp(a+y*stride+x*4,b+y*stride+x*4,4)) {
                count++;minX=MIN(minX,x);maxX=MAX(maxX,x);minY=MIN(minY,y);maxY=MAX(maxY,y);
            }
        printf("DIFF pixels=%zu bounds=%zu,%zu..%zu,%zu surface=%zu,%zu\n",count,minX,minY,maxX,maxY,width,height);
    }
}
static void compareContentAfterDecoration(id backend) {
    O2ContextRef context=[backend cgContext];
    O2Surface *surface=[(id)context surface];
    NSRect frame;memcpy(&frame,slot(backend,"_frame"),sizeof(frame));
    O2Rect content=O2ContextConvertRectToDeviceSpace(context,O2RectMake(0,0,frame.size.width,frame.size.height));
    NSData *before=[[pixels(backend)copy]autorelease];
    setFlag(backend,"_decorationsDirty",YES);[backend drawDecorations];
    NSData *after=pixels(backend);
    const unsigned char *a=[before bytes],*b=[after bytes];
    size_t stride=O2ImageGetBytesPerRow(surface);BOOL equal=YES;
    for(size_t y=ceil(content.origin.y);y<floor(content.origin.y+content.size.height);y++)
        for(size_t x=ceil(content.origin.x);x<floor(content.origin.x+content.size.width);x++)
            equal&=memcmp(a+y*stride+x*4,b+y*stride+x*4,4)==0;
    expectCache(equal,"forced decoration rendering preserves content pixels");
}
@interface CacheView : NSView @end
@implementation CacheView
- (void)drawRect:(NSRect)dirty { [[NSColor whiteColor]set];NSRectFill(dirty); }
@end
@interface CacheDriver : NSObject { @public NSWindow *window;unsigned ticks;BOOL remapping; }
- (void)tick:(NSTimer *)timer;
@end
@implementation CacheDriver
- (void)tick:(NSTimer *)timer {
    id backend=[window platformWindow];
    if(!flag(backend,"_configured")) {
        if(++ticks<100)return;
        expectCache(NO,"own window configured before cache checks");
    } else if (remapping) {
        setFlag(backend,"_pendingActivated",NO);[backend applyConfigure];
        [window display];compareForcedDraw(backend);
        expectCache(!flag(backend,"_activated"),"remapped window uses inactive decorations");
    } else {
        [window display];renders=0;
        [window display];[window display];
        expectCache(renders==0,"unchanged full displays retain decoration rendering");
        compareForcedDraw(backend);renders=0;
        [backend setTitle:@"Changed own title"];
        expectCache(renders==1,"changed title renders exactly once");
        renders=0;[backend setTitle:@"Changed own title"];
        expectCache(renders==0,"identical title reuses decoration rendering");
        [window display];compareForcedDraw(backend);compareContentAfterDecoration(backend);
        renders=0;[window disableFlushWindow];
        [backend setTitle:@"Deferred title"];[window display];
        expectCache(renders==0&&flag(backend,"_decorationsDirty"),"disabled flush defers dirty decoration work");
        [window enableFlushWindow];[window flushWindow];
        expectCache(renders==1&&!flag(backend,"_decorationsDirty"),"enabled final flush renders pending decorations once");
        renders=0;BOOL active=flag(backend,"_activated");
        setFlag(backend,"_pendingActivated",!active);[backend applyConfigure];
        expectCache(flag(backend,"_decorationsDirty"),"activation configure invalidates decorations");
        [window flushWindow];expectCache(renders==1,"changed activation renders once");
        [window display];compareForcedDraw(backend);
        NSUInteger style=[backend styleMask];
        NSUInteger buttons[]={NSWindowStyleMaskClosable,NSWindowStyleMaskMiniaturizable,NSWindowStyleMaskResizable};
        for(unsigned i=0;i<3;i++) {
            renders=0;[backend setStyleMask:style^buttons[i]];
            expectCache(flag(backend,"_decorationsDirty"),"button style change invalidates decorations");
            [window flushWindow];expectCache(renders==1,"button style change renders once");
            compareForcedDraw(backend);renders=0;
            [backend setStyleMask:style^buttons[i]];[window flushWindow];
            expectCache(renders==0,"identical button style reuses decorations");
            [backend setStyleMask:style];[window flushWindow];compareForcedDraw(backend);
        }
        for(uint32_t scale=120;scale<=240;scale+=120) {
            memcpy(slot(backend,"_renderScale120"),&scale,sizeof(scale));
            NSRect frame=[window frame];frame.size.width+=1;renders=0;
            [window setFrame:frame display:YES];[window display];
            expectCache(renders==1,"new size and scaled backing context render once");
            compareForcedDraw(backend);renders=0;[window display];
            expectCache(renders==0,"scaled backing context retains decorations");
        }
        for(NSString *title in @[@"gyp\ngyp\ngyp\ngyp",@"Changed own title",@"A long title with descenders gyp gyp gyp gyp gyp gyp",@"Own cache input"]) {
            [backend setTitle:title];[window display];
            compareForcedDraw(backend);compareContentAfterDecoration(backend);
        }
        NSAppearance *dark=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        [window display];renders=0;[window setAppearance:dark];
        expectCache(flag(backend,"_decorationsDirty"),"window appearance change invalidates decorations");
        [window flushWindow];expectCache(renders==1,"window appearance change renders once");
        [window setAppearance:nil];[window flushWindow];renders=0;[NSApp setAppearance:dark];
        expectCache(flag(backend,"_decorationsDirty"),"application appearance change invalidates decorations");
        [window flushWindow];expectCache(renders==1,"application appearance change renders once");
        [NSApp setAppearance:nil];[window flushWindow];compareForcedDraw(backend);
        setFlag(backend,"_pendingActivated",YES);[backend applyConfigure];[window flushWindow];
        id context=[backend cgContext];
        [backend hideWindow];
        expectCache(!flag(backend,"_activated")&&flag(backend,"_decorationsDirty"),"unmap invalidates retained active decorations");
        expectCache(context==[backend cgContext],"hide retains the backing context");
        renders=0;[backend drawDecorations];
        expectCache(renders==1,"unmap repaints retained active pixels with inactive colors");
        compareForcedDraw(backend);[backend showWindowWithoutActivation];
        remapping=YES;ticks=0;return;
    }
    [window orderOut:nil];[timer invalidate];[NSApp stop:nil];
    [NSApp postEvent:[NSEvent otherEventWithType:NSApplicationDefined location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0]atStart:NO];
}
@end
int main(void) { @autoreleasepool {
    setbuf(stdout,NULL);setenv("DARLING_WAYLAND_DECORATIONS","client",1);
    [NSApplication sharedApplication];
    CacheDriver *driver=[CacheDriver new];
    driver->window=[[NSWindow alloc]initWithContentRect:NSMakeRect(50,50,192,96)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    Class cls=[[driver->window platformWindow]class];
    if(![NSStringFromClass(cls)isEqualToString:@"WaylandWindow"]){fprintf(stderr,"Wayland backend required\n");return 2;}
    Method method=class_getInstanceMethod(cls,@selector(drawDecorations));
    originalDraw=method_setImplementation(method,(IMP)trackDraw);
    [driver->window setReleasedWhenClosed:NO];
    [driver->window setContentView:[[[CacheView alloc]initWithFrame:NSMakeRect(0,0,192,96)]autorelease]];
    [driver->window setTitle:@"Own cache input"];[driver->window orderFront:nil];
    NSTimer *timer=[NSTimer scheduledTimerWithTimeInterval:.05 target:driver selector:@selector(tick:)userInfo:nil repeats:YES];
    [NSApp run];[timer invalidate];method_setImplementation(method,originalDraw);
    [driver->window release];[driver release];
    printf("RESULT decoration-cache failures=%u\n",failures);return failures?1:0;
}}
