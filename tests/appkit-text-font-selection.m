#import <AppKit/AppKit.h>
#include <stdio.h>

@interface FontSizeSender : NSObject { @public CGFloat size; }
- (NSFont *)convertFont:(NSFont *)font;
@end
@implementation FontSizeSender
- (NSFont *)convertFont:(NSFont *)font {
    return [[NSFontManager sharedFontManager] convertFont:font toSize:size];
}
@end
#define CHECK(c, message) do { if (!(c)) { fprintf(stderr,"FAIL: %s\n",message); return 1; } } while (0)
int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0,0,400,200)];
    [view setRichText:YES];
    [view setString:@"abc"];
    [view setFont:[NSFont systemFontOfSize:12]];
    FontSizeSender *sender = [FontSizeSender new];
    sender->size=16;
    [view setSelectedRange:NSMakeRange(0,3)];
    @try { [view changeFont:sender]; }
    @catch (NSException *e) { fprintf(stderr,"FAIL: full selection raised %s\n",[[e name] UTF8String]); return 1; }
    for (NSUInteger i=0;i<3;i++)
        CHECK([[[view textStorage] attribute:NSFontAttributeName atIndex:i effectiveRange:NULL] pointSize]==16,"full selection font size");
    [view setSelectedRange:NSMakeRange(3,0)];
    sender->size=20;
    @try { [view changeFont:sender]; }
    @catch (NSException *e) { fprintf(stderr,"FAIL: end caret raised %s\n",[[e name] UTF8String]); return 1; }
    CHECK([[[view typingAttributes] objectForKey:NSFontAttributeName] pointSize]==20,"caret typing font size");
    CHECK([[[view textStorage] attribute:NSFontAttributeName atIndex:2 effectiveRange:NULL] pointSize]==16,"caret must not change existing text");
    [view setString:@""];
    [view setSelectedRange:NSMakeRange(0,0)];
    @try { [view changeFont:sender]; }
    @catch (NSException *e) { fprintf(stderr,"FAIL: empty text raised %s\n",[[e name] UTF8String]); return 1; }
    [sender release]; [view release]; [pool drain];
    puts("PASS: font conversion handles full selection, end caret and empty text");
    return 0;
}
