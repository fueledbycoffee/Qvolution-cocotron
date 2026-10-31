#import <AppKit/AppKit.h>
#import <AppKit/NSPopUpView.h>
#include <assert.h>
#include <stdio.h>
#ifdef NDEBUG
#error Assertions required
#endif
static NSUInteger menuReads, rectReads;
@interface CountingMenu : NSMenu
@end
@implementation CountingMenu
- (NSArray *)itemArray { ++menuReads; return [super itemArray]; }
@end
@interface NSPopUpView (HitTest)
- (NSRect)rectForItemAtIndex:(NSInteger)index;
- (NSInteger)itemIndexForPoint:(NSPoint)point;
@end
@interface CountingView : NSPopUpView
@end
@implementation CountingView
- (NSRect)rectForItemAtIndex:(NSInteger)index {
    ++rectReads;
    return [super rectForItemAtIndex:index];
}
@end
int main(void) {
    @autoreleasepool {
        setbuf(stdout,NULL);
        puts("ENTER popup throughput probe");
        [NSApplication sharedApplication];
        CountingMenu *menu = [[CountingMenu alloc] initWithTitle:@"Many"];
        [menu setAutoenablesItems:NO];
        for (NSUInteger i=0; i<400; ++i)
            [menu addItemWithTitle:[NSString stringWithFormat:@"Item %lu", (unsigned long)i]
                            action:NULL keyEquivalent:@""];
        CountingView *view = [[CountingView alloc] initWithFrame:NSMakeRect(0,0,300,500)];
        [view setMenu:menu];
        [view sizeForContents];
        NSRect last = [view rectForItemAtIndex:399];
        NSPoint point = NSMakePoint(NSMidX(last), NSMidY(last));
        menuReads = rectReads = 0;
        for (NSUInteger i=0; i<1000; ++i)
            assert([view itemIndexForPoint:point] == 399);
        printf("1000 last-row hits: menu array reads=%lu rectangle reads=%lu\n",
                (unsigned long)menuReads, (unsigned long)rectReads);
        fflush(stdout);

        assert(rectReads <= 10000);
        [[menu itemAtIndex:399] setEnabled:NO];
        assert([view itemIndexForPoint:point] == -1);
        [[menu itemAtIndex:399] setEnabled:YES];
        assert([view itemIndexForPoint:point] == 399);
        [[menu itemAtIndex:399] setHidden:YES];
        assert([view itemIndexForPoint:point] == NSNotFound);
        [[menu itemAtIndex:399] setHidden:NO];
        [menu removeItemAtIndex:399];
        assert([view itemIndexForPoint:point] == NSNotFound);
        [view release]; [menu release];
        puts("PASS: bounded lookup work with live enabled, hidden and removed state");
    }
    return 0;
}
