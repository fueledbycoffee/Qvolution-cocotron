// Put representative P4/P5 controls in an actual native framebuffer. The EGL
// backend verifies the GL frame against this same CPU backing; the runner also
// compares the captured backing byte-for-byte with the shm run.
#import <AppKit/AppKit.h>
#import <Onyx2D/O2Context.h>
#import <Onyx2D/O2Surface.h>
#include <stdio.h>
#include <stdlib.h>
@interface NSObject (ThemeGPUProbe)
- (O2Context *)cgContext;
- (NSDictionary *)eglPresentationStatistics;
@end
int main(void) { @autoreleasepool {
    setbuf(stdout,NULL); [NSApplication sharedApplication];
    NSWindow *w=[[NSWindow alloc] initWithContentRect:NSMakeRect(100,100,420,240)
        styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
    [w setReleasedWhenClosed:NO];
    NSView *root=[w contentView];
    for (int i=0;i<3;i++) {
        NSButton *b=[[NSButton alloc] initWithFrame:NSMakeRect(20+i*125,180,110,28)];
        [b setTitle:i==0 ? @"Action" : i==1 ? @"Checked" : @"Disabled"];
        [b setButtonType:i==1 ? NSSwitchButton : NSMomentaryPushInButton];
        [b setBezelStyle:NSRoundedBezelStyle]; [b setState:i==1 ? NSOnState : NSOffState];
        if (i==2) [b setEnabled:NO]; [root addSubview:b]; [b release];
    }
    NSTextField *field=[[NSTextField alloc] initWithFrame:NSMakeRect(20,125,260,26)];
    [field setStringValue:@"Theme presentation pixels"]; [field setEditable:NO]; [root addSubview:field];
    NSScroller *s=[[NSScroller alloc] initWithFrame:NSMakeRect(370,20,16,130)];
    [s setKnobProportion:0.35]; [s setDoubleValue:0.4]; [root addSubview:s];
    NSPopUpButton *popup=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(20,65,200,28) pullsDown:NO];
    [popup addItemsWithTitles:@[@"First item",@"Second item"]]; [root addSubview:popup];
    [w orderFront:nil]; [w makeFirstResponder:nil]; [w display];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
    [w display];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    NSDictionary *stats=[[w platformWindow] eglPresentationStatistics];
    BOOL egl=[[[[NSProcessInfo processInfo] environment] objectForKey:@"DARLING_APPKIT_RENDERER"] isEqualToString:@"egl"];
    unsigned failures=0;
    if (![[stats objectForKey:@"renderer"] isEqualToString:egl ? @"egl" : @"shm"] ||
        [[stats objectForKey:@"failures"] unsignedIntValue] ||
        (egl && ![[stats objectForKey:@"checks"] unsignedIntValue])) failures++;
    O2Surface *surface=[(O2Context *)[[w platformWindow] cgContext] surface];
    size_t width=O2SurfaceGetWidth(surface),height=O2SurfaceGetHeight(surface),stride=O2SurfaceGetBytesPerRow(surface);
    NSMutableData *data=[NSMutableData dataWithLength:width*height*4];
    for (size_t y=0;y<height;y++) memcpy((char *)[data mutableBytes]+y*width*4,
        (const char *)O2SurfaceGetPixelBytes(surface)+y*stride,width*4);
    NSString *dir=[[[NSProcessInfo processInfo] environment] objectForKey:@"QV_THEME_EVIDENCE"];
    if (!dir || ![data writeToFile:[dir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"theme-%zux%zu.bgra",width,height]] atomically:NO]) failures++;
    printf("RESULT appkit-theme-gpu-frame failures=%u framebuffer_checks=%llu\n",failures,
        [[stats objectForKey:@"checks"] unsignedLongLongValue]);
    [w orderOut:nil]; return failures!=0;
} }
