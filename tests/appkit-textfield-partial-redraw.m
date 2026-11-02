// Source-owned pixel regression: child invalidation must repaint behind translucent edges.
#import <AppKit/AppKit.h>
#import <Onyx2D/O2Context_builtin.h>
#import <Onyx2D/O2Surface.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "window-frame-settle.h"
static unsigned failures, checks;
static void expect(BOOL ok, const char *label) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", label); failures += !ok;
}
@interface FieldBackground : NSView { @public unsigned draws; }
@end
@implementation FieldBackground
- (BOOL)isOpaque { return YES; }
- (void)drawRect:(NSRect)rect {
    draws++;
    [[NSColor colorWithDeviceRed:.72 green:.81 blue:.91 alpha:1] set]; NSRectFill(rect);
}
@end
@interface ProbeField : NSTextField @end
@implementation ProbeField
- (BOOL)isOpaque { return getenv("FIXTURE_FORCE_OPAQUE") ? YES : [super isOpaque]; }
@end
static NSData *snapshot(NSWindow *window) {
    O2Context_builtin *context=(id)[[window graphicsContext] graphicsPort];
    if (![context isKindOfClass:[O2Context_builtin class]]) { fprintf(stderr,"own CPU context required\n"); exit(2); }
    O2Surface *surface=[context surface];
    if (!O2SurfaceCanReadWriteARGB8u(surface)) { fprintf(stderr,"32-bit surface required\n"); exit(2); }
    size_t w=O2SurfaceGetWidth(surface), h=O2SurfaceGetHeight(surface), stride=O2SurfaceGetBytesPerRow(surface);
    NSMutableData *data=[NSMutableData dataWithLength:w*h*4];
    for (size_t y=0;y<h;y++) memcpy((char *)[data mutableBytes]+y*w*4, O2SurfaceGetPixelBytes(surface)+y*stride,w*4);
    return data;
}
static void compare(NSWindow *window, const char *style, unsigned pass) {
    NSData *partial=[[snapshot(window) copy] autorelease];
    [window display]; NSData *full=snapshot(window);
    size_t changed=0;
    if ([partial length]==[full length]) {
        for (size_t i=0;i<[partial length];i+=4)
            changed+=memcmp((const char *)[partial bytes]+i,(const char *)[full bytes]+i,4)!=0;
    } else changed=(size_t)-1;
    printf("PIXELS style=%s pass=%u changed=%zu\n",style,pass,changed); checks++;
    expect(changed==0,"partial field invalidation equals full parent redraw");
    const char *directory=getenv("TEXTFIELD_EVIDENCE_DIR");
    if (directory) {
        NSString *prefix=[NSString stringWithFormat:@"%s/%s-%u",directory,style,pass];
        expect([partial writeToFile:[prefix stringByAppendingString:@"-partial.rgba"] atomically:YES],"write partial evidence");
        expect([full writeToFile:[prefix stringByAppendingString:@"-full.rgba"] atomically:YES],"write full evidence");
    }
}
int main(void) { @autoreleasepool {
    setbuf(stdout,NULL); [NSApplication sharedApplication];
    NSMenu *menu=[[[NSMenu alloc] initWithTitle:@"Fixture"] autorelease];
    [menu addItemWithTitle:@"Fixture" action:NULL keyEquivalent:@""]; [NSApp setMainMenu:menu];
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(120,120,300,160)
        styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
    [window setReleasedWhenClosed:NO]; [window setTitle:@"Text field redraw regression"];
    FieldBackground *background=[[[FieldBackground alloc] initWithFrame:NSMakeRect(0,0,300,160)] autorelease];
    [window setContentView:background];
    ProbeField *field=[[[ProbeField alloc] initWithFrame:NSMakeRect(37,61,220,26)] autorelease];
    [field setStringValue:@""]; [field setEditable:NO]; [field setSelectable:NO];
    [background addSubview:field]; [window makeKeyAndOrderFront:nil];
    if (!fixtureWaitForWindowFrame(window,"textfield-theme")) return 2;
    const char *styles[]={"square","rounded","line","plain","alpha-background","no-background"};
    for (unsigned style=0;style<6;style++) {
        [field setBezeled:style<2]; [field setBordered:style==2];
        [field setBezelStyle:style==1 ? NSTextFieldRoundedBezel : NSTextFieldSquareBezel];
        [field setDrawsBackground:style!=5];
        [field setBackgroundColor:[NSColor colorWithDeviceRed:.95 green:.9 blue:.83 alpha:style==4 ? .5 : 1]];
        [window display];
        for (unsigned pass=0;pass<3;pass++) {
            unsigned before=background->draws;
            [field setNeedsDisplayInRect:pass==0 ? [field bounds] : NSMakeRect(17,0,83,8)];
            [window displayIfNeeded];
            printf("DRAW style=%s pass=%u parent=%u opaque=%d\n",styles[style],pass,background->draws-before,[field isOpaque]);
            compare(window,styles[style],pass);
        }
    }
    [window orderOut:nil]; [window release];
    expect(checks==18,"all eighteen field pixel checkpoints executed");
    printf("RESULT textfield-partial-redraw failures=%u checks=%u\n",failures,checks); return failures ? 1 : 0;
} }
