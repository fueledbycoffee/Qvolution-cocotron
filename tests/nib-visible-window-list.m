// Test-only observer of our AppKit/Wayland boundary. No application output/hooks.
#import <AppKit/AppKit.h>
@interface NSObject (OwnWindowList)
- (id)platformWindow;
- (BOOL)isMapped;
@end
@interface NibVisibleWindowList : NSObject
+ (void)poll:(NSTimer *)timer;
@end
@implementation NibVisibleWindowList
+ (void)load {
    @autoreleasepool {
        if([[[NSProcessInfo processInfo]environment]objectForKey:@"NIB_WINDOW_LIST_REQUEST"])
            [NSTimer scheduledTimerWithTimeInterval:0.05 target:self selector:@selector(poll:) userInfo:nil repeats:YES];
    }
}
+ (void)poll:(NSTimer *)timer {
    NSDictionary *env=[[NSProcessInfo processInfo]environment];
    NSString *request=env[@"NIB_WINDOW_LIST_REQUEST"],*output=env[@"NIB_WINDOW_LIST_OUTPUT"];
    if(!NSApp||![[NSFileManager defaultManager]fileExistsAtPath:request])return;
    NSMutableArray *rows=[NSMutableArray array];
    for(NSWindow *window in [NSApp windows]) {
        id backend=[window platformWindow];
        if(![backend respondsToSelector:@selector(isMapped)])continue;
        [rows addObject:@{@"title":[window title]?:@"",@"visible":@([window isVisible]),@"mapped":@([backend isMapped])}];
    }
    NSData *data=[NSJSONSerialization dataWithJSONObject:rows options:0 error:NULL];
    if(!data||![data writeToFile:output atomically:YES])exit(3);
    [timer invalidate];
}
@end
