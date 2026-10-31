// Original public boundary regression; no physical display names are recorded.
#import <AppKit/AppKit.h>
#import <CoreGraphics/CGDirectDisplay.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#define CHECK(x) do{if(!(x)){fprintf(stderr,"FAIL line%d: %s\n",__LINE__,#x);exit(1);}}while(0)
typedef boolean_t (*OnlineQuery)(CGDirectDisplayID);
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];uint32_t capacity=0;
    CHECK(CGGetOnlineDisplayList(0,NULL,&capacity)==kCGErrorSuccess&&capacity>0&&capacity<4096);
    CGDirectDisplayID *ids=calloc(capacity,sizeof(*ids));CHECK(ids!=NULL);uint32_t count=0;
    CHECK(CGGetOnlineDisplayList(capacity,ids,&count)==kCGErrorSuccess&&count>0&&count<=capacity);
    OnlineQuery online=(OnlineQuery)dlsym(RTLD_DEFAULT,"CGDisplayIsOnline");CHECK(online!=NULL);
    CGDirectDisplayID invalid=UINT32_MAX;
    for(uint32_t i=0;i<count;i++) {CHECK(ids[i]!=kCGNullDirectDisplay);CHECK(online(ids[i]));}
    for(;;) {BOOL found=NO;for(uint32_t i=0;i<count;i++)if(ids[i]==invalid)found=YES;if(!found)break;--invalid;}
    CHECK(!online(kCGNullDirectDisplay));CHECK(!online(invalid));free(ids);
    puts("PASS: reported online IDs agree with predicate; null and absent IDs are false");
}return 0;}
