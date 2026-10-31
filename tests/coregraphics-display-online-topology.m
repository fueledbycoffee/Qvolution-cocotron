// Original mutable backend boundary; actual CoreGraphics functions are not mocked.
#import <AppKit/AppKit.h>
#import <AppKit/NSDisplay.h>
#import <CoreGraphics/CGDirectDisplay.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#define CHECK(x) do{if(!(x)){fprintf(stderr,"FAIL line%d: %s\n",__LINE__,#x);exit(1);}}while(0)
typedef boolean_t (*OnlineQuery)(CGDirectDisplayID);
static NSArray *currentScreens,*laterScreens;
static unsigned reads;
static BOOL mutateAfterFirst;
static NSArray *fixtureScreens(id self,SEL selector) {
    ++reads;return mutateAfterFirst&&reads>1?laterScreens:currentScreens;
}
static NSScreen *screen(CGDirectDisplayID ident,BOOL active) {
    NSRect frame=active?NSMakeRect(0,0,100,50):NSZeroRect;
    NSScreen *s=[[[NSScreen alloc] initWithFrame:frame visibleFrame:frame] autorelease];
    [s setCgDirectDisplayID:ident];return s;
}
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];id backend=[NSDisplay currentDisplay];
    CHECK([NSStringFromClass([backend class]) isEqualToString:@"WaylandDisplay"]);
    OnlineQuery online=(OnlineQuery)dlsym(RTLD_DEFAULT,"CGDisplayIsOnline");CHECK(online!=NULL);
    NSArray *first=[@[screen(9,NO),screen(7,YES),screen(0x80000001u,YES)] retain];
    NSArray *second=[@[screen(11,YES)] retain];currentScreens=first;laterScreens=second;
    Method method=class_getInstanceMethod([backend class],@selector(screens));CHECK(method!=NULL);
    IMP previous=method_setImplementation(method,(IMP)fixtureScreens);
    @try {
        // An online but non-drawable reported screen must not alias active.
        CHECK(online(9));CHECK(!CGDisplayIsActive(9));CHECK(online(7));CHECK(online(0x80000001u));
        CHECK(!online(0));CHECK(!online(42));
        // A single query must own its first topology, not re-query midway to
        // discover a different main/list or perform count-then-fill allocation.
        reads=0;mutateAfterFirst=YES;CHECK(online(9));CHECK(reads==1);
        reads=0;CGDirectDisplayID ids[8]={0};uint32_t count=0;
        CHECK(CGGetOnlineDisplayList(8,ids,&count)==kCGErrorSuccess);
        CHECK(reads==1&&count==3&&ids[0]==7&&ids[1]==9&&ids[2]==0x80000001u);
        mutateAfterFirst=NO;currentScreens=second;
        CHECK(!online(9)&&!online(7)&&online(11));
        currentScreens=@[];CHECK(online(1)&&!online(11)&&!online(0));
        CHECK(CGGetOnlineDisplayList(8,ids,&count)==kCGErrorSuccess&&count==1&&ids[0]==1);
    } @finally {
        method_setImplementation(method,previous);[first release];[second release];
        currentScreens=laterScreens=nil;
    }
    puts("PASS: real online predicate distinguishes active, handles changed/noncontiguous/high IDs, owns one backend snapshot and preserves explicit virtual fallback");
}return 0;}
