#import <AppKit/AppKit.h>
#import <AppKit/NSWindow-Private.h>
#include <stdio.h>
#define CHECK(c, message) do { if (!(c)) { fprintf(stderr,"FAIL: %s\n",message); return 1; } } while (0)
@interface AppearanceCountView : NSView { @public NSUInteger changes; }
@end
@implementation AppearanceCountView
- (void)viewDidChangeEffectiveAppearance { changes++; }
@end
static void reset(AppearanceCountView *v){v->changes=0;[v setNeedsDisplay:NO];}
int main(void){
    NSAutoreleasePool *pool=[NSAutoreleasePool new];[NSApplication sharedApplication];
    NSAppearance *light=[NSAppearance appearanceNamed:NSAppearanceNameAqua];
    NSAppearance *dark=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    [NSApp setAppearance:dark];
    AppearanceCountView *root=[[AppearanceCountView alloc] initWithFrame:NSMakeRect(0,0,16,16)];
    CHECK([root effectiveAppearance]==dark,"detached root inherits explicit app appearance");
    AppearanceCountView *child=[[AppearanceCountView alloc] initWithFrame:[root bounds]];
    AppearanceCountView *fixed=[[AppearanceCountView alloc] initWithFrame:[root bounds]];
    AppearanceCountView *leaf=[[AppearanceCountView alloc] initWithFrame:[root bounds]];
    [fixed setAppearance:light];[root addSubview:child];[root addSubview:fixed];[fixed addSubview:leaf];
    CHECK([child effectiveAppearance]==dark&&[leaf effectiveAppearance]==light,"nearest explicit ancestor wins");
    reset(root);reset(child);reset(fixed);reset(leaf);[NSApp setAppearance:light];
    CHECK(root->changes==1&&child->changes==1,"app change notifies detached inheriting tree");
    CHECK([root needsDisplay]&&[child needsDisplay],"changed views invalidate drawing");
    CHECK(fixed->changes==0&&leaf->changes==0&&![fixed needsDisplay]&&![leaf needsDisplay],"explicit branch remains unchanged");
    reset(root);reset(child);[root setAppearance:light];
    CHECK(root->changes==0&&child->changes==0,"equal effective object does not notify");
    [root setAppearance:dark];CHECK(root->changes==1&&child->changes==1,"view change propagates inheriting descendants");
    reset(root);reset(child);[root setAppearance:dark];CHECK(root->changes==0&&child->changes==0,"repeated setter does not notify");
    [root setAppearance:nil];CHECK([root effectiveAppearance]==light&&root->changes==1&&child->changes==1,"clearing explicit appearance restores inheritance");
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,32,32) styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:YES];
    [window setContentView:root];[window setAppearance:dark];
    CHECK([root effectiveAppearance]==dark&&[child effectiveAppearance]==dark,"window appearance inherited through frame view");
    reset(root);reset(child);reset(fixed);reset(leaf);[window setAppearance:light];
    CHECK(root->changes==1&&child->changes==1&&fixed->changes==0&&leaf->changes==0,"window change respects explicit view boundary");
    reset(root);reset(child);[NSApp setAppearance:dark];CHECK(root->changes==0&&child->changes==0,"explicit window ignores app change");
    [window setAppearance:nil];CHECK([root effectiveAppearance]==dark&&root->changes==1,"clearing window appearance restores app");
    [root removeFromSuperview];CHECK([root effectiveAppearance]==dark,"detached view keeps app preference");
    [root setAppearance:nil];reset(root);reset(child);[NSApp setAppearance:light];
    CHECK([root effectiveAppearance]==light&&root->changes==1&&child->changes==1,"detached views continue receiving app changes");
    NSWindow *privateWindow=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,16,16) styleMask:NSAppKitPrivateWindow backing:NSBackingStoreBuffered defer:YES];
    AppearanceCountView *privateView=[[AppearanceCountView alloc] initWithFrame:NSMakeRect(0,0,16,16)];[privateWindow setContentView:privateView];reset(privateView);
    [NSApp setAppearance:dark];CHECK([privateView effectiveAppearance]==dark&&privateView->changes==1,"private window receives inherited app change");
    [privateWindow setContentView:nil];[window setContentView:nil];[privateView release];[privateWindow release];[window release];
    [leaf release];[fixed release];[child release];[root release];[NSApp setAppearance:nil];[pool drain];
    puts("PASS: view/window/app inheritance and effective-change notifications");return 0;
}
