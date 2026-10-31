#import <AppKit/AppKit.h>
#import <AppKit/NSWindow-Private.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static id ownedReceiver;
static unsigned receiverDeaths, callbacks;
static BOOL armed, throwAfterDrop;
static void dropLastOwner(void) {
    if(!armed) return;
    armed=NO; callbacks++;
    NSAutoreleasePool *nested=[NSAutoreleasePool new];
    id receiver=ownedReceiver; ownedReceiver=nil; [receiver release];
    [nested drain];
    if(receiverDeaths) {fprintf(stderr,"FAIL: direct appearance receiver deallocated during callback\n");exit(1);}
    if(throwAfterDrop) [NSException raise:@"QVDirectAppearanceFailure" format:@"original deliberate callback failure"];
}
@interface DirectReleaseView : NSView @end
@implementation DirectReleaseView
- (void)viewDidChangeEffectiveAppearance {dropLastOwner();}
- (void)dealloc {receiverDeaths++;[super dealloc];}
@end
@interface WindowReleaseContent : NSView @end
@implementation WindowReleaseContent
- (void)viewDidChangeEffectiveAppearance {dropLastOwner();}
@end
@interface DirectReleaseWindow : NSWindow @end
@implementation DirectReleaseWindow
- (void)dealloc {receiverDeaths++;[super dealloc];}
@end
int main(int argc,char **argv) {
    NSAutoreleasePool *pool=[NSAutoreleasePool new];[NSApplication sharedApplication];
    [NSApp setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
    NSAutoreleasePool *transaction=[NSAutoreleasePool new];
    if(argc==2 && !strcmp(argv[1],"--window")) {
        ownedReceiver=[[DirectReleaseWindow alloc] initWithContentRect:NSMakeRect(0,0,32,32)
            styleMask:NSBorderlessWindowMask|NSAppKitPrivateWindow backing:NSBackingStoreBuffered defer:YES];
        NSView *content=[[WindowReleaseContent alloc] initWithFrame:NSMakeRect(0,0,32,32)];
        [ownedReceiver setContentView:content];[content release];
    } else {
        ownedReceiver=[[DirectReleaseView alloc] initWithFrame:NSMakeRect(0,0,32,32)];
        NSView *child=[[NSView alloc] initWithFrame:NSMakeRect(0,0,16,16)];
        [ownedReceiver addSubview:child];[child release];
    }
    armed=YES; throwAfterDrop=argc==2 && !strcmp(argv[1],"--throw");
    BOOL caught=NO;
    @try { [ownedReceiver setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]]; }
    @catch(NSException *exception) {
        if(![[exception name] isEqual:@"QVDirectAppearanceFailure"]) @throw;
        caught=YES;
    }
    if(caught!=throwAfterDrop) {fprintf(stderr,"FAIL: callback exception contract\n");return 1;}
    [transaction drain];
    if(callbacks!=1 || ownedReceiver!=nil || receiverDeaths!=1) {
        fprintf(stderr,"FAIL: direct transaction cleanup callbacks=%u deaths=%u\n",callbacks,receiverDeaths);return 1;
    }
    [pool drain];puts("PASS: direct appearance propagation retains receiver through callback/pool drain");return 0;
}
