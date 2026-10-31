// Original public API contract: no display-name contents are printed.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
@interface NSScreen (LocalizedNameContract)
- (NSString *)localizedName;
@end
#define CHECK(x) do{if(!(x)){fprintf(stderr,"FAIL line%d: %s\n",__LINE__,#x);exit(1);}}while(0)
int main(void) {
    NSString *retainedName=nil;
    @autoreleasepool {
        [NSApplication sharedApplication];NSArray *screens=[NSScreen screens];CHECK([screens count]>0);
        for(NSScreen *screen in screens) {
            CHECK([screen respondsToSelector:@selector(localizedName)]);
            NSString *name=[screen localizedName];CHECK([name isKindOfClass:[NSString class]]&&[name length]>0);
            CHECK([[screen localizedName] isEqualToString:name]);
            [retainedName release];retainedName=[name retain];
        }
        NSScreen *fallback=[[[NSScreen alloc] initWithFrame:NSMakeRect(0,0,20,10) visibleFrame:NSMakeRect(0,0,20,10)] autorelease];
        [fallback setCgDirectDisplayID:42];CHECK([[fallback localizedName] isEqualToString:@"Display 42"]);
    }
    CHECK([retainedName length]>0);[retainedName release];
    puts("PASS: screen localized-name API, nonempty project fallback and retained name lifetime");return 0;
}
