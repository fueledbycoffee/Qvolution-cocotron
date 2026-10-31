#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>

static unsigned failures,draws;
static double started;
static const char *phase;
static NSUInteger workload,iteration;
static double nowMS(void) { struct timeval t; gettimeofday(&t,NULL); return t.tv_sec*1000.0+t.tv_usec/1000.0; }
static void begin(const char *name) { phase=name; printf("BEGIN chars=%lu iteration=%lu phase=%s\n",(unsigned long)workload,(unsigned long)iteration,phase); started=nowMS(); }
static void end(void) { printf("TIME chars=%lu iteration=%lu phase=%s ms=%.3f draws=%u\n",(unsigned long)workload,(unsigned long)iteration,phase,nowMS()-started,draws); }
static void expectLatency(BOOL value,const char *message) { if (!value) { failures++; fprintf(stderr,"FAIL: %s\n",message); } }
static id identified(NSView *parent,NSString *name) { for (NSView *view in [parent subviews]) if ([[view identifier]isEqual:name])return view;return nil; }
@interface TimedTextView:NSTextView @end
@implementation TimedTextView
- (void)drawRect:(NSRect)rect { draws++;[super drawRect:rect]; }
@end
@interface LatencyPump:NSObject
- (void)stop:(NSTimer *)timer;
@end
@implementation LatencyPump
- (void)stop:(NSTimer *)timer { [NSApp stop:nil];[NSApp postEvent:[NSEvent otherEventWithType:NSApplicationDefined location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0]atStart:NO]; }
@end
static void pumpConfigure(void) {
    LatencyPump *pump=[LatencyPump new];
    NSTimer *timer=[NSTimer scheduledTimerWithTimeInterval:.25 target:pump selector:@selector(stop:)userInfo:nil repeats:NO];
    [NSApp run];[timer invalidate];[pump release];
}
static NSString *fixedText(NSUInteger length) {
    NSString *line=@"The quick brown fox edits a real rich text document. 0123456789\n";
    NSMutableString *text=[NSMutableString string];
    while ([text length]<length) [text appendString:line];
    return [text substringToIndex:length];
}
static void runWorkload(NSUInteger length,BOOL mapped) {
    workload=length;iteration=0;
    begin("construct_window_text_system");
    NSWindow *window=[[NSWindow alloc]initWithContentRect:NSMakeRect(120,120,640,480)styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    [window setReleasedWhenClosed:NO];[window setTitle:@"Source-owned text latency fixture"];
    NSScrollView *scroll=[[NSScrollView alloc]initWithFrame:NSMakeRect(0,0,640,480)];
    [scroll setHasVerticalScroller:YES];
    TimedTextView *view=[[TimedTextView alloc]initWithFrame:NSMakeRect(0,0,620,460)];
    [view setVerticallyResizable:YES];[view setHorizontallyResizable:NO];
    [scroll setDocumentView:view];[window setContentView:scroll];end();
    begin("rich_inspector_and_ruler_setup");
    [view setRichText:YES];[view setUsesInspectorBar:YES];[view setUsesRuler:YES];
    [scroll setHasHorizontalRuler:YES];[scroll setRulersVisible:YES];[scroll tile];end();
    NSView *bar=identified(scroll,@"NSTextViewInspectorBar");
    NSPopUpButton *size=identified(bar,@"Font size"),*family=identified(bar,@"Font family");
    expectLatency(bar && size && family,"actual rich-text inspector exists");
    begin("font_lookup_cold");NSFont *font=[NSFont fontWithName:@"DejaVu Sans" size:14];end();
    expectLatency(font!=nil,"fixed DejaVu Sans font resolves");
    if (!font) { [window release];[view release];[scroll release];return; }
    NSString *text=fixedText(length);
    begin("set_fixed_text_and_font");[view setString:text];[view setFont:font];end();
    NSLayoutManager *layout=[view layoutManager];NSTextContainer *container=[view textContainer];
    begin("initial_layout");NSRect used=[layout usedRectForTextContainer:container];end();
    expectLatency(NSHeight(used)>0,"fixed text lays out to nonempty rect");
    if (mapped) {
        begin("order_window");[window makeKeyAndOrderFront:nil];[window makeFirstResponder:view];end();
        pumpConfigure();
        begin("first_display_after_event_pump");[window display];end();
    }
    NSBitmapImageRep *rep=[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:NULL pixelsWide:640 pixelsHigh:480 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    expectLatency(rep!=nil,"fixed CPU drawing bitmap allocated");
    NSGraphicsContext *bitmap=[NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    for (iteration=1;iteration<=7;iteration++) {
        begin("font_lookup_warm");NSFont *same=[NSFont fontWithName:@"DejaVu Sans" size:14];end();expectLatency(same!=nil,"repeat font resolves");
        NSUInteger target=31;
        begin("selection");[view setSelectedRange:NSMakeRange(target,12)];end();expectLatency([view selectedRange].location==target,"selection moved");
        begin("layout_valid");used=[layout usedRectForTextContainer:container];end();
        begin("font_size_action");[size selectItemWithTitle:iteration%2?@"18":@"14"];[NSApp sendAction:[size action]to:[size target]from:size];end();
        expectLatency([[[view textStorage]attribute:NSFontAttributeName atIndex:target effectiveRange:NULL]pointSize]==(iteration%2?18:14),"actual inspector changes selected font");
        begin("layout_after_font");used=[layout usedRectForTextContainer:container];end();
        begin("font_menu_update");[[family menu]update];end();
        begin("set_end_caret");[view setSelectedRange:NSMakeRange([[view string]length],0)];end();
        NSUInteger before=[[view string]length];
        begin("insert_one_character");[view insertText:@"x"];end();expectLatency([[view string]length]==before+1,"actual insertion appends one character");
        begin("layout_after_insert");used=[layout usedRectForTextContainer:container];end();
        NSGraphicsContext *previous=[[NSGraphicsContext currentContext]retain];
        [NSGraphicsContext setCurrentContext:bitmap];
        begin("cpu_draw_viewport");[view drawRect:NSMakeRect(0,0,620,420)];end();
        [NSGraphicsContext setCurrentContext:previous];[previous release];
        if (mapped) {
            unsigned beforeDraws=draws;begin("display_after_edit");[window display];end();expectLatency(draws>beforeDraws,"display executes real text drawing");
        }
    }
    expectLatency([[view string]length]==length+7,"all seven insertions preserved");
    [rep release];[window orderOut:nil];[view release];[scroll release];[window release];
}
int main(int argc,char **argv) { @autoreleasepool {
    setbuf(stdout,NULL);setbuf(stderr,NULL);
    if(argc!=2 || (strcmp(argv[1],"model") && strcmp(argv[1],"window")))return 2;
    BOOL mapped=!strcmp(argv[1],"window");
    printf("ENTER source-owned public AppKit timing mode=%s capture=%s\n",argv[1],getenv("DARLING_APPKIT_CAPTURE_DIR")?"enabled":"disabled");
    begin("application_setup");[NSApplication sharedApplication];end();
    runWorkload(256,mapped);runWorkload(4096,mapped);
    printf("RESULT failures=%u draws=%u\n",failures,draws);return failures?1:0;
} }
