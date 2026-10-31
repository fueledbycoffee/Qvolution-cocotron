#import <AppKit/AppKit.h>
#include <stdio.h>
#define CHECK(c, message) do { if (!(c)) { fprintf(stderr,"FAIL: %s\n",message); return 1; } } while (0)
@interface DenyAlignment : NSObject @end
@implementation DenyAlignment
- (BOOL)textView:(NSTextView *)view shouldChangeTextInRange:(NSRange)range replacementString:(NSString *)replacement { return NO; }
@end
static NSParagraphStyle *typingStyle(NSTextView *view) { return [[view typingAttributes] objectForKey:NSParagraphStyleAttributeName]; }
int main(void) {
    NSAutoreleasePool *pool=[NSAutoreleasePool new];
    [NSApplication sharedApplication];
    NSTextView *view=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,400,200)];
    [view setRichText:YES]; [view setString:@"abc\n"];
    [view setSelectedRange:NSMakeRange(4,0)];
    NSMutableParagraphStyle *style=[[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
    [style setFirstLineHeadIndent:17];
    NSMutableDictionary *attrs=[[[view typingAttributes] mutableCopy] autorelease];
    [attrs setObject:style forKey:NSParagraphStyleAttributeName]; [view setTypingAttributes:attrs];
    @try { [view alignCenter:nil]; }
    @catch (NSException *e) { fprintf(stderr,"FAIL: trailing newline caret raised %s\n",[[e name] UTF8String]); return 1; }
    CHECK([typingStyle(view) alignment]==NSCenterTextAlignment,"trailing empty paragraph centers typing");
    CHECK([typingStyle(view) firstLineHeadIndent]==17,"typing paragraph properties preserved");
    CHECK(NSEqualRanges([view selectedRange],NSMakeRange(4,0)),"trailing caret preserved");
    CHECK([[[view textStorage] attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL] alignment]!=NSCenterTextAlignment,"previous paragraph unchanged");
    [view alignRight:nil]; CHECK([typingStyle(view) alignment]==NSRightTextAlignment,"trailing caret right alignment");
    [view alignLeft:nil]; CHECK([typingStyle(view) alignment]==NSLeftTextAlignment,"trailing caret left alignment");
    [view setString:@""]; [view setSelectedRange:NSMakeRange(0,0)];
    @try { [view alignCenter:nil]; }
    @catch (NSException *e) { fprintf(stderr,"FAIL: empty document raised %s\n",[[e name] UTF8String]); return 1; }
    CHECK([typingStyle(view) alignment]==NSCenterTextAlignment,"empty document centers typing");
    [view setEditable:NO]; [view alignRight:nil];
    CHECK([typingStyle(view) alignment]==NSCenterTextAlignment,"read-only alignment unchanged");
    [view setEditable:YES]; DenyAlignment *delegate=[DenyAlignment new]; [view setDelegate:delegate]; [view alignRight:nil];
    CHECK([typingStyle(view) alignment]==NSCenterTextAlignment,"delegate veto preserves typing alignment");
    [view setDelegate:nil]; [delegate release];
    [view setString:@"abc\nxyz"]; [view setSelectedRange:NSMakeRange(1,1)]; [view alignRight:nil];
    CHECK([[[view textStorage] attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL] alignment]==NSRightTextAlignment,"selected paragraph alignment applied");
    CHECK([[[view textStorage] attribute:NSParagraphStyleAttributeName atIndex:4 effectiveRange:NULL] alignment]!=NSRightTextAlignment,"unselected paragraph unchanged");
    CHECK(NSEqualRanges([view selectedRange],NSMakeRange(1,1)),"character selection preserved");
    [view release]; [pool drain]; puts("PASS: alignment empty/trailing caret, selection and editing guards"); return 0;
}
