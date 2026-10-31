#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#define CHECK(c, message) do { if (!(c)) { fprintf(stderr,"FAIL: %s\n",message); return 1; } } while (0)
static NSView *ownedVictim;
static unsigned killerChanges,victimChanges,victimDeaths;
@interface EqualAppearanceView : NSView @end
@implementation EqualAppearanceView
- (NSUInteger)hash { return 7; }
- (BOOL)isEqual:(id)object { return [object isKindOfClass:[EqualAppearanceView class]]; }
@end
@interface AppearanceVictim : EqualAppearanceView @end
@implementation AppearanceVictim
- (void)viewDidChangeEffectiveAppearance {
    if(victimDeaths){fprintf(stderr,"FAIL: appearance callback dispatched after recipient deallocation\n");exit(1);}
    victimChanges++;
}
- (void)dealloc { victimDeaths++;[super dealloc]; }
@end
@interface AppearanceKiller : EqualAppearanceView @end
@implementation AppearanceKiller
- (void)viewDidChangeEffectiveAppearance {
    killerChanges++;
    NSView *victim=ownedVictim;ownedVictim=nil;
    [victim release]; // Last owner; deliberately not removeFromSuperview's autorelease path.
}
@end
int main(void){
    NSAutoreleasePool *pool=[NSAutoreleasePool new];[NSApplication sharedApplication];
    NSAppearance *light=[NSAppearance appearanceNamed:NSAppearanceNameAqua],*dark=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    [NSApp setAppearance:light];
    AppearanceKiller *killer=[[AppearanceKiller alloc] initWithFrame:NSZeroRect];
    ownedVictim=[[AppearanceVictim alloc] initWithFrame:NSZeroRect];
    NSAutoreleasePool *dispatch=[NSAutoreleasePool new];
    [NSApp setAppearance:dark];
    CHECK(killerChanges==1&&ownedVictim==nil,"appearance callback releases detached recipient's last owner");
    CHECK(victimChanges==1,"snapshot recipient still receives its effective change safely");
    [dispatch drain];
    CHECK(victimDeaths==1,"weak registry does not keep released recipient alive after dispatch temporaries");
    [killer release];[NSApp setAppearance:nil];[pool drain];
    puts("PASS: complete appearance broadcast snapshot protects directly released recipient");return 0;
}
