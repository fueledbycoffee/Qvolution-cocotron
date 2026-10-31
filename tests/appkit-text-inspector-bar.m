#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>
#define CHECK(c, message) do { if (!(c)) { fprintf(stderr,"FAIL: %s\n",message); return 1; } } while (0)
static id identified(NSView *parent, NSString *name) {
    for (NSView *view in [parent subviews])
        if ([[view identifier] isEqual:name]) return view;
    return nil;
}
static void activate(NSControl *control) {
    [NSApp sendAction:[control action] to:[control target] from:control];
}
int main(void) {
    NSAutoreleasePool *pool=[NSAutoreleasePool new];
    [NSApplication sharedApplication];
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,600,400)];
    NSTextView *view=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,600,400)];
    [scroll setDocumentView:view];
    [scroll setHasHorizontalRuler:YES]; [scroll setRulersVisible:YES]; [scroll tile];
    NSRect original=[[scroll contentView] frame];
    [view setRichText:YES]; [view setUsesInspectorBar:YES];
    NSView *bar=identified(scroll,@"NSTextViewInspectorBar");
    CHECK(bar != nil,"rich text must create inspector controls");
    [view setUsesInspectorBar:YES];
    CHECK(identified(scroll,@"NSTextViewInspectorBar")==bar,"repeated enable reuses inspector");
    NSUInteger inspectorCount=0;
    for (NSView *child in [scroll subviews])
        if ([[child identifier] isEqual:@"NSTextViewInspectorBar"]) inspectorCount++;
    CHECK(inspectorCount==1,"repeated enable creates no duplicate accessory");
    CHECK(NSMinY([[scroll contentView] frame]) >= NSMinY(original)+NSHeight([bar frame]),"inspector reserves document space");
    CHECK(NSMinY([[scroll horizontalRulerView] frame]) >= NSMaxY([bar frame]),"ruler starts below inspector");
    NSPopUpButton *family=identified(bar,@"Font family"), *size=identified(bar,@"Font size");
    NSButton *bold=identified(bar,@"Bold"), *italic=identified(bar,@"Italic"), *underline=identified(bar,@"Underline");
    NSButton *center=identified(bar,@"Align center");
    CHECK(family && size && bold && italic && underline && center,"functional inspector controls exist");
    [view setString:@"abc\nxyz"];
    [view setFont:[NSFont systemFontOfSize:12]];
    [view setSelectedRange:NSMakeRange(0,3)];
    [size selectItemWithTitle:@"18"]; activate(size);
    CHECK([[[view textStorage] attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] pointSize]==18,"size action changes selected text");
    CHECK([[[view textStorage] attribute:NSFontAttributeName atIndex:4 effectiveRange:NULL] pointSize]==12,"size action preserves unselected text");
    [bold setState:NSControlStateValueOn]; activate(bold);
    NSFont *font=[[view textStorage] attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
    CHECK([[NSFontManager sharedFontManager] traitsOfFont:font] & NSBoldFontMask,"bold action changes selected font");
    [italic setState:NSControlStateValueOn]; activate(italic);
    font=[[view textStorage] attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
    CHECK([[NSFontManager sharedFontManager] traitsOfFont:font] & NSItalicFontMask,"italic action changes selected font");
    activate(underline);
    CHECK([[[view textStorage] attribute:NSUnderlineStyleAttributeName atIndex:0 effectiveRange:NULL] integerValue]!=0,"underline action changes selected text");
    activate(center);
    CHECK([[[view textStorage] attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL] alignment]==NSCenterTextAlignment,"alignment action changes selected paragraph");
    [view setSelectedRange:NSMakeRange(4,3)];
    CHECK([bold state]==NSControlStateValueOff && [italic state]==NSControlStateValueOff,"selection refreshes trait controls");
    CHECK([[[size selectedItem] title] isEqual:@"12"],"selection refreshes size control");
    NSString *current=[[[view typingAttributes] objectForKey:NSFontAttributeName] familyName];
    for (NSString *name in [family itemTitles]) {
        if (![name isEqual:current]) { [family selectItemWithTitle:name]; activate(family); break; }
    }
    CHECK([[[[view textStorage] attribute:NSFontAttributeName atIndex:4 effectiveRange:NULL] familyName] isEqual:[family titleOfSelectedItem]],"family action changes selected font");
    [view setSelectedRange:NSMakeRange([[view string] length],0)];
    [size selectItemWithTitle:@"24"]; activate(size);
    CHECK([[[view typingAttributes] objectForKey:NSFontAttributeName] pointSize]==24,"caret action changes typing font");
    [view setEditable:NO];
    CHECK(![size isEnabled] && ![bold isEnabled],"read-only text disables controls");
    [view setEditable:YES];
    [scroll setFrameSize:NSMakeSize(320,400)]; [scroll tile];
    CHECK(NSHeight([bar frame])==60,"narrow inspector wraps controls");
    for (NSView *control in [bar subviews]) CHECK(NSContainsRect([bar bounds],[control frame]),"wrapped controls fit inspector");
    [scroll setFrameSize:NSMakeSize(600,400)]; [scroll tile];
    CHECK(NSHeight([bar frame])==30,"wide inspector returns to one row");
    CHECK(NSMinY([[scroll horizontalRulerView] frame]) >= NSMaxY([bar frame]),"wide resize preserves ruler spacing");
    for (NSView *control in [bar subviews]) CHECK(NSContainsRect([bar bounds],[control frame]),"wide controls fit inspector");
    [view setRichText:NO];
    CHECK(identified(scroll,@"NSTextViewInspectorBar")==nil,"plain text hides inspector");
    [view setRichText:YES];
    CHECK(identified(scroll,@"NSTextViewInspectorBar")!=nil,"returning to rich text restores inspector");
    [view setUsesInspectorBar:NO];
    CHECK(identified(scroll,@"NSTextViewInspectorBar")==nil,"explicit disable removes inspector");
    NSView *pages=[[NSView alloc] initWithFrame:NSMakeRect(0,0,600,800)];
    [view retain]; [view removeFromSuperview]; [pages addSubview:view]; [scroll setDocumentView:pages];
    CHECK([view superview]==pages,"replacing clip document preserves reparented old document");
    [view setUsesInspectorBar:YES];
    CHECK(identified(scroll,@"NSTextViewInspectorBar")!=nil,"nested page text view installs inspector in enclosing scroll view");
    [view removeFromSuperview];
    CHECK(identified(scroll,@"NSTextViewInspectorBar")==nil,"removing text view detaches its inspector");
    [view release]; [pages release]; [view release]; [scroll release]; [pool drain];
    puts("PASS: rich inspector layout, formatting, selection, caret, modes and nested pages");
    return 0;
}
