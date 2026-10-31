#import <AppKit/AppKit.h>
#include <stdio.h>
#define CHECK(c, message) do { if (!(c)) { fprintf(stderr,"FAIL: %s\n",message); return 1; } } while (0)
static id identified(NSView *parent, NSString *name) {
    for (NSView *view in [parent subviews]) if ([[view identifier] isEqual:name]) return view;
    return nil;
}
static void activate(NSControl *control) { [NSApp sendAction:[control action] to:[control target] from:control]; }
int main(void) {
    NSAutoreleasePool *pool=[NSAutoreleasePool new];
    [NSApplication sharedApplication];
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,600,450) styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,50,600,400)];
    NSTextView *view=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,600,400)];
    NSTextView *other=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,600,40)];
    [[window contentView] addSubview:scroll]; [[window contentView] addSubview:other];
    [scroll setDocumentView:view]; [view setRichText:YES]; [view setUsesInspectorBar:YES];
    [view setString:@"abc"]; [view setFont:[NSFont systemFontOfSize:12]]; [view setSelectedRange:NSMakeRange(0,3)];
    NSView *bar=identified(scroll,@"NSTextViewInspectorBar");
    NSPopUpButton *size=identified(bar,@"Font size"), *family=identified(bar,@"Font family");
    CHECK(bar && size && family,"windowed inspector controls exist");
    CHECK([window makeFirstResponder:other],"another text view receives focus");
    [size selectItemWithTitle:@"24"]; activate(size);
    CHECK([[[view textStorage] attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] pointSize]==24,"windowed size action preserves requested value across focus sync");
    CHECK([window firstResponder]==view,"font action restores document focus");
    CHECK(identified(scroll,@"NSTextViewInspectorBar")==bar && [bar window]==window,"inspector persists after size action and focus change");
    NSFont *font=[[view typingAttributes] objectForKey:NSFontAttributeName];
    NSString *wanted=nil;
    for (NSString *name in [family itemTitles]) {
        NSFont *converted=[[NSFontManager sharedFontManager] convertFont:font toFamily:name];
        if (![name isEqual:[font familyName]] && [[converted familyName] isEqual:name]) { wanted=[name copy]; break; }
    }
    CHECK(wanted!=nil,"another convertible font family is available");
    CHECK([window makeFirstResponder:other],"another text view receives focus before family action");
    [family selectItemWithTitle:wanted]; activate(family);
    CHECK([[[[view textStorage] attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] familyName] isEqual:wanted],"windowed family action preserves requested value across focus sync");
    CHECK(identified(scroll,@"NSTextViewInspectorBar")==bar,"inspector persists after family action");
    [view setSelectedRange:NSMakeRange(3,0)];
    CHECK([window makeFirstResponder:other],"another text view receives focus before caret action");
    [size selectItemWithTitle:@"36"]; activate(size);
    CHECK([[[view typingAttributes] objectForKey:NSFontAttributeName] pointSize]==36,"windowed caret size action changes typing font");
    CHECK([[[view textStorage] attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] pointSize]==24,"caret size preserves stored font");
    CHECK(identified(scroll,@"NSTextViewInspectorBar")==bar,"inspector persists after caret action");
    [wanted release]; [window setContentView:nil]; [view release]; [other release]; [scroll release]; [window release]; [pool drain];
    puts("PASS: windowed inspector font actions survive focus synchronization"); return 0;
}
