// Original released-button and formatting/ruler focus workflow; own CPU rasters.
#import <AppKit/AppKit.h>
#import <CoreText/CoreText.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
static unsigned failures;
#define INPUT(c,m) do{if(!(c)){fprintf(stderr,"INPUT FAIL: %s\n",m);return 2;}}while(0)
static void expect(BOOL c,const char *m){printf("%s: %s\n",c?"PASS":"FAIL",m);failures+=!c;}
@interface NSView (InspectorContextProbe)
- (void)setTextView:(NSTextView *)view;
@end
@interface NSButtonCell (VisualStateProbe)
- (BOOL)isVisuallyHighlighted;
@end
static id identified(NSView *parent,NSString *name){for(NSView *v in [parent subviews])if([[v identifier]isEqual:name])return v;return nil;}
static NSData *raster(NSView *view,NSString *path){
 NSSize size=[view bounds].size;int width=ceil(size.width),height=ceil(size.height);if(width<=0||height<=0)return nil;
 NSBitmapImageRep *rep=[[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:NULL pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bitmapFormat:NSAlphaNonpremultipliedBitmapFormat bytesPerRow:width*4 bitsPerPixel:32]autorelease];if(!rep)return nil;
 NSGraphicsContext *old=[[NSGraphicsContext currentContext]retain];[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
 @try{[[NSColor whiteColor]setFill];NSRectFill(NSMakeRect(0,0,width,height));[view drawRect:[view bounds]];}@finally{[NSGraphicsContext setCurrentContext:old];[old release];}
 NSData *bytes=[NSData dataWithBytes:[rep bitmapData]length:width*height*4];if(path){NSData *png=[rep representationUsingType:NSPNGFileType properties:@{}];if(![png writeToFile:path atomically:YES])return nil;}return bytes;
}
@interface GlyphCanvas:NSView { NSImage *_image;BOOL _selected; }
- initWithImage:(NSImage *)image selected:(BOOL)selected;
@end
@implementation GlyphCanvas
- initWithImage:(NSImage *)image selected:(BOOL)selected { if((self=[super initWithFrame:NSMakeRect(0,0,16,16)])){_image=[image retain];_selected=selected;}return self; }
- (BOOL)isFlipped{return YES;}
- (void)dealloc{[_image release];[super dealloc];}
- (void)drawRect:(NSRect)rect{[(_selected?[NSColor blackColor]:[NSColor whiteColor])setFill];NSRectFill([self bounds]);[_image drawInRect:[self bounds]fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1];}
@end
static NSWindow *window;static NSScrollView *scroll;static NSTextView *text;static NSView *bar;static NSString *output;
static NSString *captureName(NSString *name){return [output stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]];}
static BOOL boldAt(NSUInteger index){NSFont *font=[[text textStorage]attribute:NSFontAttributeName atIndex:index effectiveRange:NULL];return ([[NSFontManager sharedFontManager]traitsOfFont:font]&NSBoldFontMask)!=0;}
static int setup(void){
 window=[[NSWindow alloc]initWithContentRect:NSMakeRect(100,100,650,450)styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];scroll=[[NSScrollView alloc]initWithFrame:NSMakeRect(0,50,650,400)];text=[[NSTextView alloc]initWithFrame:NSMakeRect(0,0,650,400)];[[window contentView]addSubview:scroll];[scroll setDocumentView:text];[text setRichText:YES];[text setString:@"Styled plain"];NSFont *font=[NSFont fontWithName:@"DejaVu Sans"size:16];INPUT(font&&[[font familyName]isEqual:@"DejaVu Sans"],"explicit installed open font");[text setFont:font];
 NSMutableParagraphStyle *style=[[[NSParagraphStyle defaultParagraphStyle]mutableCopy]autorelease];[style setTabStops:@[[[[NSTextTab alloc]initWithType:NSLeftTabStopType location:36]autorelease],[[[NSTextTab alloc]initWithType:NSLeftTabStopType location:72]autorelease],[[[NSTextTab alloc]initWithType:NSRightTabStopType location:108]autorelease]]];[[text textStorage]addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0,12)];[text setDefaultParagraphStyle:style];[text setSelectedRange:NSMakeRange(0,6)];[text setUsesInspectorBar:YES];[text setUsesRuler:YES];[text setRulerVisible:YES];INPUT([window makeFirstResponder:text],"document receives actual window focus");bar=identified(scroll,@"NSTextViewInspectorBar");INPUT(bar,"actual inspector exists");return 0;
}
static int state(void){
 NSString *names[]={@"Bold",@"Italic",@"Underline"};
 for(unsigned i=0;i<3;i++){
  NSButton *button=identified(bar,names[i]);INPUT(button,"actual formatting button");[button performClick:nil];
  expect([button state]==NSControlStateValueOn&&![[button cell]isHighlighted],"real action leaves persistent On state after release");expect([[button cell]isVisuallyHighlighted],"released On control retains active visual state");
  NSData *on=raster(button,captureName([names[i]stringByAppendingString:@"-on"]));INPUT(on,"own released On CPU raster");[button performClick:nil];
  expect([button state]==NSControlStateValueOff&&![[button cell]isHighlighted],"second real action clears persistent state");NSData *off=raster(button,captureName([names[i]stringByAppendingString:@"-off"]));INPUT(off,"own released Off CPU raster");expect(![on isEqual:off],"released On and Off button rasters differ");
 }
 NSButton *bold=identified(bar,@"Bold");[bold performClick:nil];INPUT(boldAt(0)&&!boldAt(7),"real bold changes only selected text");[text setSelectedRange:NSMakeRange(7,5)];expect([bold state]==NSControlStateValueOff,"selection of plain text clears Bold indicator");[text setSelectedRange:NSMakeRange(0,6)];expect([bold state]==NSControlStateValueOn&&[[bold cell]isVisuallyHighlighted],"selection of bold text restores persistent indicator");
 NSButton *center=identified(bar,@"Align center"),*left=identified(bar,@"Align left"),*right=identified(bar,@"Align right");[center performClick:nil];expect([center state]==NSControlStateValueOn&&[left state]==NSControlStateValueOff&&[right state]==NSControlStateValueOff&&[[center cell]isVisuallyHighlighted],"actual alignment action leaves one visible active choice");[right performClick:nil];expect([right state]==NSControlStateValueOn&&[center state]==NSControlStateValueOff&&[[right cell]isVisuallyHighlighted],"alignment action updates persistent choice");return 0;
}
static int icons(void){
 NSMutableSet *distinct=[NSMutableSet set];
 for(NSString *name in @[@"Bold",@"Italic",@"Underline",@"Align left",@"Align center",@"Align right"]){
  NSButton *button=identified(bar,name);INPUT(button,"actual inspector glyph control");
  expect([button image]!=nil&&[button imagePosition]==NSImageOnly,"formatting control exposes a real image glyph");
  expect([[button identifier]isEqual:name]&&[[button toolTip]isEqual:name],"formatting control retains readable identity and tooltip");
  INPUT(raster(button,captureName([name stringByAppendingString:@"-glyph"])),"own glyph control CPU raster");
  if([button image])for(unsigned selected=0;selected<2;selected++){
   NSImage *image=selected?[button alternateImage]:[button image];expect(image!=nil,"normal and selected glyph images exist");if(!image)continue;
   GlyphCanvas *canvas=[[[GlyphCanvas alloc]initWithImage:image selected:selected]autorelease];NSData *bytes=raster(canvas,captureName([name stringByAppendingString:selected?@"-selected-art":@"-normal-art"]));INPUT([bytes length]==16*16*4,"original16pointglyph raster extent");
   const unsigned char *pixels=[bytes bytes];NSUInteger ink=0;for(NSUInteger i=0;i<16*16;i++){unsigned sum=pixels[i*4]+pixels[i*4+1]+pixels[i*4+2];if(selected?sum>600:sum<300)ink++;}
   expect(ink>=4&&ink<220,"glyph has visible contrasting ink independent of bezel");if(!selected)[distinct addObject:bytes];
  }
 }
 expect([distinct count]==6,"all six actual formatting glyphs have distinct drawings");return 0;
}
static void rulerSnapshot(NSRulerView *ruler,NSString *phase){printf("MEASURE %s markers=%lu thickness=%.3f ruler=%s clip=%s bar=%s clientIsText=%d\n",[phase UTF8String],(unsigned long)[[ruler markers]count],[ruler requiredThickness],[NSStringFromRect([ruler frame])UTF8String],[NSStringFromRect([[scroll contentView]frame])UTF8String],[NSStringFromRect([bar frame])UTF8String],[ruler clientView]==text);raster(ruler,captureName(phase));}
static int ruler(void){
 NSRulerView *ruler=[scroll horizontalRulerView];INPUT(ruler&&[[ruler markers]count]==3&&[ruler clientView]==text,"real ruler with three explicit tab markers");NSRect frame=[ruler frame],clip=[[scroll contentView]frame],barFrame=[bar frame];CGFloat thickness=[ruler requiredThickness];rulerSnapshot(ruler,@"ruler-document");NSButton *bold=identified(bar,@"Bold");INPUT([window makeFirstResponder:bold],"actual formatter receives keyboard/programmatic window focus");rulerSnapshot(ruler,@"ruler-format-focus");
 expect([ruler clientView]==text&&[[ruler markers]count]==3,"formatting control focus preserves document ruler markers");expect([ruler requiredThickness]==thickness&&NSEqualRects([ruler frame],frame)&&NSEqualRects([[scroll contentView]frame],clip)&&NSEqualRects([bar frame],barFrame),"formatting focus keeps ruler marker row and document geometry stable");
 [bold performClick:nil];rulerSnapshot(ruler,@"ruler-after-format");expect([window firstResponder]==text&&[ruler clientView]==text&&[[ruler markers]count]==3,"actual format action restores document focus and ruler context");expect([ruler requiredThickness]==thickness&&NSEqualRects([ruler frame],frame)&&NSEqualRects([[scroll contentView]frame],clip),"completed format preserves ruler and clip geometry");
 NSButton *italic=identified(bar,@"Italic");INPUT([window makeFirstResponder:italic],"second formatting control remains keyboard-focusable");expect([ruler clientView]==text&&[[ruler markers]count]==3,"formatting-to-formatting focus retains document context");
 [bar setTextView:nil];expect([ruler clientView]==nil&&[[ruler markers]count]==0,"editor detachment clears formatting ruler context");[bar setTextView:text];expect([ruler clientView]==text&&[[ruler markers]count]==3,"focused formatting control can bind its original editor again");
 NSButton *unrelated=[[[NSButton alloc]initWithFrame:NSMakeRect(0,0,60,30)]autorelease];[[window contentView]addSubview:unrelated];INPUT([window makeFirstResponder:unrelated],"unrelated control receives focus");expect([ruler clientView]==nil&&[[ruler markers]count]==0,"ordinary unrelated focus loss still clears document ruler context");INPUT([window makeFirstResponder:text],"restore document");return 0;
}
@interface NSWindow (ScopedTransitionProbe)
- (NSResponder *)_qvolutionProposedFirstResponder;
@end
static CGFloat transitionRulerThickness;
static NSRect transitionRulerFrame,transitionClipFrame;
@interface TransitionObserver:NSObject {
@public NSUInteger samples;NSUInteger mode;NSButton *takeover;BOOL fired;
}
- (void)ended:(NSNotification *)note;
@end
@implementation TransitionObserver
- (void)ended:(NSNotification *)note {
    samples++;
    if (mode==1) {
        if (!fired) { fired=YES;[window makeFirstResponder:takeover]; }
        return;
    }
    if (mode==2) {
        if (!fired) { fired=YES;[text setUsesInspectorBar:NO]; }
        return;
    }
    NSRulerView *ruler=[scroll horizontalRulerView];
    expect([ruler clientView]==text&&[[ruler markers]count]==3,
            "synchronous end-editing observer never sees missing formatting markers");
    expect([ruler requiredThickness]==transitionRulerThickness&&NSEqualRects([ruler frame],transitionRulerFrame)&&NSEqualRects([[scroll contentView]frame],transitionClipFrame),
            "synchronous end-editing observer never sees collapsed marker row");
    NSString *phase=[NSString stringWithFormat:@"ruler-sync-notification-%lu",(unsigned long)samples];
    expect(raster(ruler,captureName(phase))!=nil,"synchronous observer draws actual ruler CPU snapshot");
}
@end
@interface RefuseEndEditing:NSObject @end
@implementation RefuseEndEditing
- (BOOL)textShouldEndEditing:(NSText *)editor { return NO; }
@end
static BOOL rejectBecome(id self,SEL selector) { return NO; }
static void noPendingContext(void) {
    expect(![window respondsToSelector:@selector(_qvolutionProposedFirstResponder)] ||
            [window _qvolutionProposedFirstResponder]==nil,
            "scoped proposed responder is cleared after transition");
}
static int transition(void) {
    NSButton *bold=identified(bar,@"Bold");
    transitionRulerThickness=[[scroll horizontalRulerView]requiredThickness];transitionRulerFrame=[[scroll horizontalRulerView]frame];transitionClipFrame=[[scroll contentView]frame];
    TransitionObserver *observer=[TransitionObserver new];
    NSNotificationCenter *center=[NSNotificationCenter defaultCenter];
    [center addObserver:observer selector:@selector(ended:) name:NSTextDidEndEditingNotification object:text];
    INPUT([window makeFirstResponder:bold],"actual formatting focus transition");
    expect(observer->samples>0,"real end-editing notification reaches observer");
    expect([window firstResponder]==bold,"formatting button keeps actual keyboard focus");
    noPendingContext();[center removeObserver:observer];[window makeFirstResponder:text];
    // Reject after the old editor resigns, so preserved context must reconcile.
    Class original=object_getClass(bold),rejected=objc_allocateClassPair(original,"QvolutionRejectInspectorFocus",0);
    INPUT(rejected,"original own rejecting responder class");
    const char *encoding=method_getTypeEncoding(class_getInstanceMethod(original,@selector(becomeFirstResponder)));
    INPUT(class_addMethod(rejected,@selector(becomeFirstResponder),(IMP)rejectBecome,encoding),"own rejection override");objc_registerClassPair(rejected);object_setClass(bold,rejected);
    expect(![window makeFirstResponder:bold]&&[window firstResponder]!=bold,"rejected become does not leave requested button focused");
    NSRulerView *ruler=[scroll horizontalRulerView];expect([ruler clientView]==nil&&[[ruler markers]count]==0,"rejected become rolls back preserved ruler context");noPendingContext();object_setClass(bold,original);[window makeFirstResponder:text];
    RefuseEndEditing *delegate=[RefuseEndEditing new];[text setDelegate:delegate];
    expect(![window makeFirstResponder:bold]&&[window firstResponder]==text,"refused resignation retains actual editor focus");
    expect([ruler clientView]==text&&[[ruler markers]count]==3,"refused resignation preserves original ruler context");noPendingContext();[text setDelegate:nil];[delegate release];
    // A synchronous observer's newer focus decision must win over its caller.
    NSButton *other=[[[NSButton alloc]initWithFrame:NSMakeRect(0,0,60,30)]autorelease];[[window contentView]addSubview:other];observer->mode=1;observer->takeover=other;observer->fired=NO;
    [center addObserver:observer selector:@selector(ended:) name:NSTextDidEndEditingNotification object:text];
    expect(![window makeFirstResponder:bold]&&[window firstResponder]==other,"nested observer focus takeover is not overwritten");
    expect([ruler clientView]==nil&&[[ruler markers]count]==0,"nested unrelated takeover clears formatting context");noPendingContext();[center removeObserver:observer];[window makeFirstResponder:text];
    observer->mode=2;observer->fired=NO;[center addObserver:observer selector:@selector(ended:) name:NSTextDidEndEditingNotification object:text];
    expect(![window makeFirstResponder:bold]&&[window firstResponder]!=bold,"observer-detached formatting control cannot become first responder");
    expect([ruler clientView]==nil&&[[ruler markers]count]==0,"observer-driven inspector teardown clears formatting context");noPendingContext();[center removeObserver:observer];[observer release];[text setUsesInspectorBar:YES];[window makeFirstResponder:text];return 0;
}
int main(int argc,char **argv){@autoreleasepool{setbuf(stdout,NULL);INPUT(argc==3,"mode state|icons|ruler|transition and explicit owned output directory");output=[NSString stringWithUTF8String:argv[2]];BOOL directory=NO;INPUT([output isAbsolutePath]&&[[NSFileManager defaultManager]fileExistsAtPath:output isDirectory:&directory]&&directory,"existing explicit output directory");[NSApplication sharedApplication];int result=setup();if(result)return result;result=!strcmp(argv[1],"state")?state():!strcmp(argv[1],"icons")?icons():!strcmp(argv[1],"ruler")?ruler():!strcmp(argv[1],"transition")?transition():2;[window setContentView:nil];[text release];[scroll release];[window release];if(result)return result;printf("RESULT %u failures\n",failures);return failures?1:0;}}
