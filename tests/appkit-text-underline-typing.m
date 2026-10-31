#import <AppKit/AppKit.h>
#include <stdio.h>
#define CHECK(c, message) do { if (!(c)) { fprintf(stderr,"FAIL: %s\n",message); return 1; } } while (0)
@interface DenyFormatting : NSObject @end
@implementation DenyFormatting
- (BOOL)textView:(NSTextView *)view shouldChangeTextInRange:(NSRange)range replacementString:(NSString *)replacement { return NO; }
@end
int main(void) {
    NSAutoreleasePool *pool=[NSAutoreleasePool new];
    [NSApplication sharedApplication];
    NSTextView *view=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,400,200)];
    [view setRichText:YES];
    @try { [view underline:nil]; }
    @catch (NSException *e) { fprintf(stderr,"FAIL: empty caret raised %s\n",[[e name] UTF8String]); return 1; }
    CHECK([[[view typingAttributes] objectForKey:NSUnderlineStyleAttributeName] integerValue]==NSUnderlineStyleSingle,"empty caret enables underline");
    [view insertText:@"x"];
    [view underline:nil];
    CHECK([[[view typingAttributes] objectForKey:NSUnderlineStyleAttributeName] integerValue]==0,"end caret disables underline");
    [view insertText:@"y"];
    CHECK([[[view textStorage] attribute:NSUnderlineStyleAttributeName atIndex:0 effectiveRange:NULL] integerValue]!=0,"first typed character underlined");
    CHECK([[[view textStorage] attribute:NSUnderlineStyleAttributeName atIndex:1 effectiveRange:NULL] integerValue]==0,"second typed character not underlined");
    [view setSelectedRange:NSMakeRange(0,2)];
    [view underline:nil];
    CHECK([[[view textStorage] attribute:NSUnderlineStyleAttributeName atIndex:0 effectiveRange:NULL] integerValue]==0,"selection removes underline");
    [view underline:nil];
    CHECK([[[view textStorage] attribute:NSUnderlineStyleAttributeName atIndex:1 effectiveRange:NULL] integerValue]!=0,"selection reapplies underline");
    DenyFormatting *delegate=[DenyFormatting new];
    [view setDelegate:delegate];
    [view underline:nil];
    CHECK([[[view textStorage] attribute:NSUnderlineStyleAttributeName atIndex:1 effectiveRange:NULL] integerValue]!=0,"delegate veto preserves formatting");
    [view setDelegate:nil]; [delegate release]; [view release]; [pool drain];
    puts("PASS: underline toggles empty/end typing, selections and delegate veto");
    return 0;
}
