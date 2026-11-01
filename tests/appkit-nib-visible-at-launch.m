// Own nibs, loaded through the same NSBundle entry point as NSApplicationMain.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
@interface NSObject (OwnWaylandVisibility)
- (id)platformWindow;
- (BOOL)isMapped;
@end
static void expect(BOOL condition,const char *phase,NSWindow *window,BOOL expected) {
    if(!condition) { fprintf(stderr,"FAIL %s %s expected=%d visible=%d mapped=%d\n",phase,[[window title]UTF8String],expected,[window isVisible],[[window platformWindow]isMapped]);exit(1); }
}
static void checkVisibility(NSArray *objects,BOOL mixed,const char *phase) {
    unsigned windows=0;
    for(id object in objects)if([object isKindOfClass:[NSWindow class]]) {
        NSWindow *window=object;BOOL visible=mixed&&[[window title]isEqualToString:@"Visible"];
        expect([window isVisible]==visible,phase,window,visible);
        expect([[window platformWindow]isMapped]==visible,phase,window,visible);windows++;
    }
    if(windows!=3) { fprintf(stderr,"FAIL top-level window count %u\n",windows);exit(1); }
}
int main(int argc,char **argv) {
    @autoreleasepool {
        if(argc!=3)return 2;
        [NSApplication sharedApplication];
        NSMutableArray *objects=[NSMutableArray array];
        NSDictionary *names=@{NSNibOwner:NSApp,NSNibTopLevelObjects:objects};
        BOOL loaded=[NSBundle loadNibFile:[NSString stringWithUTF8String:argv[1]] externalNameTable:names withZone:NSDefaultMallocZone()];
        if(!loaded) { fprintf(stderr,"FAIL nib load\n");return 1; }
        BOOL mixed=atoi(argv[2]);checkVisibility(objects,mixed,"load");
        [NSApp finishLaunching];checkVisibility(objects,mixed,"finishLaunching");
        [NSApp activateIgnoringOtherApps:YES];checkVisibility(objects,mixed,"activate");
        for(NSWindow *window in objects)if([window isKindOfClass:[NSWindow class]]) {
            [window makeKeyAndOrderFront:nil];
            expect([window isVisible]&&[[window platformWindow]isMapped],"explicit show",window,YES);
            [window orderOut:nil];
            [NSApp activateIgnoringOtherApps:YES];
            expect(![window isVisible]&&![[window platformWindow]isMapped],"ordered out then activate",window,NO);
        }
        puts("PASS authored nib: load, finishLaunching, activation, explicit ordering and Wayland mapping");
    }
    return 0;
}
