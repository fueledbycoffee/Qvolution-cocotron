#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>
/* Own-source private drawing entry points: no interposition or fake title renderer. */
@interface NSWindow (TitleProbe)
- (NSView *)_backgroundView;
@end
@interface NSView (TitleProbe)
- (void)_drawTitleBar:(NSRect)rect;
@end
@interface NSToolbarItem (TitleProbe)
- (void)_setToolbar:(NSToolbar *)toolbar;
- (void)drawInRect:(NSRect)rect highlighted:(BOOL)highlighted;
@end
#define W 400
#define H 48
static unsigned failures;
static void expectResult(BOOL ok,const char *what) { printf("%s: %s\n",ok?"PASS":"FAIL",what);if(!ok)failures++; }
static void raster(NSView *frame,NSToolbarItem *item,unsigned char *out) {
    memset(out,0,W*H*4);
    CGColorSpaceRef rgb=CGColorSpaceCreateDeviceRGB();
    CGContextRef c=CGBitmapContextCreate(out,W,H,8,W*4,rgb,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    if(!c){fputs("FAIL: raster allocation\n",stderr);exit(2);}
    [NSGraphicsContext saveGraphicsState];
    @try {
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithGraphicsPort:c flipped:NO]];
        if(frame)[frame _drawTitleBar:NSMakeRect(0,0,W,H)];
        if(item)[item drawInRect:NSMakeRect(0,0,W,H) highlighted:NO];
    } @finally {[NSGraphicsContext restoreGraphicsState];CGContextRelease(c);CGColorSpaceRelease(rgb);}
}
static unsigned difference(const unsigned char *a,const unsigned char *b) {
    unsigned n=0;for(unsigned i=0;i<W*H;i++)if(memcmp(a+i*4,b+i*4,4))n++;return n;
}
int main(void){
    setbuf(stdout,NULL);puts("ENTER: original title visibility raster");
    NSAutoreleasePool *pool=[NSAutoreleasePool new];[NSApplication sharedApplication];
    NSWindow *window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,W,160) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    [window setReleasedWhenClosed:NO];
    NSView *frame=[window _backgroundView];
    NSToolbar *toolbar=[[NSToolbar alloc]initWithIdentifier:@"OwnTitleToolbar"];
    [toolbar setDisplayMode:NSToolbarDisplayModeLabelOnly];
    NSToolbarItem *item=[[NSToolbarItem alloc]initWithItemIdentifier:@"OwnGeneral"];
    [item setLabel:@"General"];[item setEnabled:YES];[item _setToolbar:toolbar];
    unsigned char *empty=calloc(W*H,4),*visible=calloc(W*H,4),*hidden=calloc(W*H,4),*again=calloc(W*H,4),*label=calloc(W*H,4),*labelAfter=calloc(W*H,4);
    if(!empty||!visible||!hidden||!again||!label||!labelAfter)return 2;
    [window setTitle:@""];[window setTitleVisibility:NSWindowTitleVisible];raster(frame,nil,empty);
    [window setTitle:@"General"];raster(frame,nil,visible);raster(nil,item,label);
    unsigned labelInk=0;for(unsigned i=0;i<W*H;i++)if(label[i*4+3])labelInk++;
    expectResult(difference(empty,visible)>20,"visible title has actual text pixels against empty-title control");
    expectResult(labelInk>20,"actual toolbar item label has text pixels");
    [frame setNeedsDisplay:NO];[window setTitleVisibility:NSWindowTitleHidden];
    expectResult([frame needsDisplay],"visibility setter invalidates actual theme frame");
    raster(frame,nil,hidden);raster(nil,item,labelAfter);
    printf("MEASURE: visibleInk=%u hiddenInk=%u toolbarInk=%u\n",difference(empty,visible),difference(empty,hidden),labelInk);
    expectResult(difference(empty,hidden)==0,"hidden title removes title text pixels");
    expectResult(difference(label,labelAfter)==0,"hiding title preserves actual toolbar label pixels");
    expectResult([[window title]isEqualToString:@"General"] && [[item label]isEqualToString:@"General"],"title and toolbar label metadata preserved");
    [frame setNeedsDisplay:NO];[window setTitleVisibility:NSWindowTitleVisible];expectResult([frame needsDisplay],"showing title invalidates frame");raster(frame,nil,again);
    expectResult(difference(visible,again)==0,"visible-hidden-visible restores same title pixels");
    [frame setNeedsDisplay:NO];[window setTitle:@"Different title"];expectResult([frame needsDisplay],"changing visible title invalidates theme frame");
    raster(frame,nil,again);expectResult(difference(visible,again)>20,"updated title changes actual text pixels");
    [item _setToolbar:nil];[item release];[toolbar release];[window release];
    free(empty);free(visible);free(hidden);free(again);free(label);free(labelAfter);[pool drain];
    printf("RESULT: %u failures\n",failures);return failures?1:0;
}
