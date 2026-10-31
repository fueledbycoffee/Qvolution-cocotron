#import <AppKit/AppKit.h>
#include <stdio.h>
#define CHECK(c, message) do { if (!(c)) { fprintf(stderr,"FAIL: %s\n",message); return 1; } } while (0)
@interface AppearanceReentryView : NSView { @public NSMutableArray *seen;NSAppearance *next;int mode; }
@end
@implementation AppearanceReentryView
- (id)init { if((self=[super initWithFrame:NSMakeRect(0,0,16,16)]))seen=[NSMutableArray new];return self; }
- (void)dealloc { [seen release];[super dealloc]; }
- (void)viewDidChangeEffectiveAppearance {
    [seen addObject:[self effectiveAppearance]];
    int action=mode;mode=0;
    if(action==1)[self setAppearance:next];
    if(action==2)[NSApp setAppearance:next];
}
@end
static BOOL noConsecutiveDuplicate(NSArray *values){for(NSUInteger i=1;i<[values count];i++)if([values objectAtIndex:i]==[values objectAtIndex:i-1])return NO;return YES;}
int main(void){
    NSAutoreleasePool *pool=[NSAutoreleasePool new];[NSApplication sharedApplication];
    NSAppearance *light=[NSAppearance appearanceNamed:NSAppearanceNameAqua],*dark=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua],*next=[NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
    [NSApp setAppearance:light];
    AppearanceReentryView *root=[AppearanceReentryView new],*child=[AppearanceReentryView new];[root addSubview:child];
    [root->seen removeAllObjects];[child->seen removeAllObjects];root->mode=1;root->next=next;
    [root setAppearance:dark];
    CHECK([root->seen count]==2&&[root effectiveAppearance]==next,"view setter reentry reaches latest appearance");
    CHECK([child->seen count]==1&&[child->seen lastObject]==next,"superseded view propagation does not duplicate latest child callback");
    AppearanceReentryView *trigger=[AppearanceReentryView new],*watch=[AppearanceReentryView new];trigger->mode=2;trigger->next=next;
    [NSApp setAppearance:dark];
    CHECK([NSApp effectiveAppearance]==next&&[watch->seen count]>0,"app setter reentry reaches latest appearance");
    CHECK(noConsecutiveDuplicate(watch->seen),"superseded app broadcast does not repeat latest callback");
    [child release];[root release];[trigger release];[watch release];[NSApp setAppearance:nil];[pool drain];
    puts("PASS: reentrant appearance changes supersede stale propagation");return 0;
}
