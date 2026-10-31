// Original own-source compact popup/inspector contract; no native input claim.
#import <AppKit/AppKit.h>
#import <AppKit/NSPopUpWindow.h>
#import <AppKit/NSPopUpView.h>
#import <CoreGraphics/CGWindowPrivate.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
static unsigned failures;
#define INPUT(c,m) do{if(!(c)){fprintf(stderr,"INPUT FAIL: %s\n",m);return 2;}}while(0)
static void expect(BOOL c,const char *m){printf("%s: %s\n",c?"PASS":"FAIL",m);failures+=!c;}
@interface NSPopUpButtonCell (CompactProbe)
- (NSUInteger)_maximumVisibleRows;
- (void)_setMaximumVisibleRows:(NSUInteger)rows;
@end
@interface NSPopUpWindow (CompactProbe)
- (void)setMaximumVisibleRows:(NSUInteger)rows;
- (NSPopUpView *)qvView;
@end
@implementation NSPopUpWindow (CompactProbe)
- (NSPopUpView *)qvView { return _view; }
@end
@interface NSPopUpView (CompactProbe)
- (NSRect)rectForItemAtIndex:(NSInteger)index;
- (NSInteger)itemIndexForPoint:(NSPoint)point;
@end
static CGSize nativeLimit;
static NSRect visibleFrame;
static NSInteger returnedSelection=-1;
static CGFloat capturedHeight;
@interface ProbeBounds : CGWindow @end
@implementation ProbeBounds
- (CGSize)maximumPopupSize { return nativeLimit; }
@end
@interface CompactWindow : NSPopUpWindow @end
@implementation CompactWindow
- (CGWindow *)platformWindow { return [[[ProbeBounds alloc]init]autorelease]; }
- (NSScreen *)screen { return [[[NSScreen alloc]initWithFrame:visibleFrame visibleFrame:visibleFrame]autorelease]; }
- (void)orderFront:(id)sender {}
- (void)orderOut:(id)sender {}
@end
@interface ImmediateView : NSPopUpView @end
@implementation ImmediateView
- (NSInteger)runTrackingWithEvent:(NSEvent *)event { return returnedSelection<0?_selectedIndex:returnedSelection; }
@end
@interface ProbeWheel : NSEvent @end
@implementation ProbeWheel
- (CGFloat)deltaY { return -1; }
@end
static CGFloat rowExtent(NSPopUpView *view,NSUInteger rows,NSUInteger count){
 if(count<=rows)return [view sizeForContents].height;
 NSRect last=[view rectForItemAtIndex:rows-1];
 // Real cached border extent, not a guessed per-row pixel constant.
 NSRect end=[view rectForItemAtIndex:count-1];
 CGFloat bottom=[view sizeForContents].height-NSMaxY(end);
 return NSMaxY(last)+bottom;
}
static void selectedVisible(NSPopUpView *view){expect(NSContainsRect([view bounds],[view rectForSelectedItem]),"selected row remains fully visible");}
static NSMenu *menu(NSUInteger count){NSMenu *m=[[[NSMenu alloc]initWithTitle:@"Original families"]autorelease];[m setAutoenablesItems:NO];for(NSUInteger i=0;i<count;i++)[m addItemWithTitle:[NSString stringWithFormat:@"Family %03lu",(unsigned long)i]action:NULL keyEquivalent:@""];if(count)[[m itemAtIndex:count-1]setTitle:@"Zulu"];return m;}
static void preference(NSPopUpWindow *window,NSUInteger rows){if([window respondsToSelector:@selector(setMaximumVisibleRows:)])[window setMaximumVisibleRows:rows];}
static void prepare(NSPopUpWindow *window,NSMenu *m,NSInteger selected){[window setMenu:m];[window selectItemAtIndex:selected];object_setClass([window qvView],[ImmediateView class]);}
static int geometry(void){
 NSMenu *m=menu(400);NSInteger selections[]={0,200,399};
 for(unsigned native=0;native<2;native++)for(unsigned i=0;i<3;i++){
  nativeLimit=native?CGSizeMake(1000,900):CGSizeZero;visibleFrame=NSMakeRect(-1280,140,1280,840);
  CompactWindow *window=[[CompactWindow alloc]initWithFrame:NSMakeRect(-50,950,150,24)];prepare(window,m,selections[i]);preference(window,16);
  NSPopUpView *view=[window qvView];CGFloat wanted=rowExtent(view,16,400);[window runTrackingWithEvent:nil];
  printf("MEASURE native=%u selected=%ld actualHeight=%.3f wanted16=%.3f\n",native,(long)selections[i],NSHeight([window frame]),wanted);
  expect(NSHeight([window frame])<=wanted+.001,"400-item popup requests at most16 actual row extents");
  expect([[view menu]numberOfItems]==400,"all400 families retained");if(!native)expect(NSContainsRect(visibleFrame,[window frame]),"compact popup fits negative/nonzero-origin visible frame");selectedVisible(view);
  [view scrollBy:1e6];CGFloat last=NSMinY([view bounds]);expect(last>0,"last rows remain scroll reachable");[view scrollBy:1e6];expect(NSMinY([view bounds])==last,"scroll clamps at last row");[view scrollBy:-1e6];expect(NSMinY([view bounds])==0,"scroll clamps at first row");
  ProbeWheel *wheel=[ProbeWheel new];[view scrollWheel:wheel];[wheel release];expect(NSMinY([view bounds])>0,"existing wheel path scrolls compact viewport");
  [view selectItemAtIndex:398];[view moveDown:nil];expect(NSEqualRects([view rectForSelectedItem],[view rectForItemAtIndex:399]),"keyboard reaches last family");selectedVisible(view);
  [view selectItemAtIndex:0];[view insertText:@"Z"];expect(NSEqualRects([view rectForSelectedItem],[view rectForItemAtIndex:399]),"type-ahead reaches last family");selectedVisible(view);[window release];
 }
 // Native constraints remain stronger than the preference.
 nativeLimit=CGSizeMake(180,120);CompactWindow *small=[[CompactWindow alloc]initWithFrame:NSMakeRect(100,100,150,24)];prepare(small,m,399);preference(small,16);[small runTrackingWithEvent:nil];expect(NSHeight([small frame])<=120&&NSWidth([small frame])<=180,"native output cap still wins over16row preference");selectedVisible([small qvView]);[small release];
 // No-cap generic and short menus retain existing behavior.
 nativeLimit=CGSizeZero;visibleFrame=NSMakeRect(2000,3000,1400,1000);CompactWindow *generic=[[CompactWindow alloc]initWithFrame:NSMakeRect(2200,3500,150,24)];prepare(generic,m,200);[generic runTrackingWithEvent:nil];expect(NSHeight([generic frame])>rowExtent([generic qvView],16,400),"default generic popup retains no extra row cap");[generic release];
 CompactWindow *shortWindow=[[CompactWindow alloc]initWithFrame:NSMakeRect(2200,3500,150,24)];prepare(shortWindow,menu(3),1);preference(shortWindow,16);NSPopUpView *shortView=[shortWindow qvView];CGFloat full=[shortView sizeForContents].height;[shortWindow runTrackingWithEvent:nil];expect(NSHeight([shortWindow frame])==full,"short menu retains exact full height");selectedVisible(shortView);[shortWindow release];return 0;
}
static int configured(void){
 nativeLimit=CGSizeZero;visibleFrame=NSMakeRect(-1200,200,1200,1000);
 CompactWindow *window=[[CompactWindow alloc]initWithFrame:NSMakeRect(-800,700,150,24)];prepare(window,menu(400),399);preference(window,16);[window runTrackingWithEvent:nil];
 NSPopUpView *view=[window qvView];CGFloat preferred=rowExtent(view,16,400);CGFloat heights[]={120,700,80,preferred};
 for(unsigned i=0;i<sizeof(heights)/sizeof(*heights);i++){
  NSRect frame=[window frame];frame.size.height=heights[i];[window platformWindow:[window platformWindow]frameChanged:frame didSize:YES];
  NSRect content=[[window contentView]bounds];CGFloat wanted=MIN(NSHeight(content),preferred);
  expect(NSHeight([window frame])==heights[i],"configured outer frame honored without resize feedback");
  expect(fabs(NSHeight([view frame])-wanted)<.001,"configured shrink and enlargement keep compact content extent");
  CGFloat actualTop=[[window contentView]isFlipped]?NSMinY([view frame]):NSMaxY([view frame]);CGFloat wantedTop=[[window contentView]isFlipped]?NSMinY(content):NSMaxY(content);
  expect(fabs(actualTop-wantedTop)<.001,"compact viewport anchors at actual content top");selectedVisible(view);
 }
 [window release];return 0;
}
static NSView *identified(NSView *parent,NSString *identifier){for(NSView *v in [parent subviews])if([[v identifier]isEqual:identifier])return v;return nil;}
static int inspector(void){
 NSScrollView *scroll=[[[NSScrollView alloc]initWithFrame:NSMakeRect(0,0,650,400)]autorelease];NSTextView *text=[[[NSTextView alloc]initWithFrame:NSMakeRect(0,0,650,400)]autorelease];[scroll setDocumentView:text];[text setRichText:YES];[text setString:@"Selected text"];[text setFont:[NSFont fontWithName:@"DejaVu Sans"size:16]];[text setUsesInspectorBar:YES];
 NSView *bar=identified(scroll,@"NSTextViewInspectorBar");INPUT(bar,"actual inspector exists");NSPopUpButton *family=(id)identified(bar,@"Font family"),*size=(id)identified(bar,@"Font size");INPUT(family&&size,"actual family and size controls exist");
 BOOL api=[[family cell]respondsToSelector:@selector(_maximumVisibleRows)];NSUInteger requested=api?[[family cell]_maximumVisibleRows]:0;expect(requested==16,"real inspector family cell requests16rows");expect(![[size cell]respondsToSelector:@selector(_maximumVisibleRows)]||[[size cell]_maximumVisibleRows]==0,"font size keeps default viewport policy");
 NSUInteger count=[family numberOfItems];NSArray *available=[[NSFontManager sharedFontManager]availableFontFamilies];expect(count>0&&count>=[available count],"real installed family catalog retained");
 INPUT([[family itemTitles]containsObject:@"DejaVu Serif"],"explicit open family available");[text setSelectedRange:NSMakeRange(0,8)];[family selectItemWithTitle:@"DejaVu Serif"];expect([NSApp sendAction:[family action]to:[family target]from:family],"real inspector family action dispatches");NSFont *changed=[[text textStorage]attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];expect([[changed familyName]isEqual:@"DejaVu Serif"],"real inspector action changes selected family");return 0;
}
static IMP originalWindowTracking;
static NSInteger interceptedTracking(NSPopUpWindow *window,SEL selector,NSEvent *event){object_setClass(window,[CompactWindow class]);object_setClass([window qvView],[ImmediateView class]);NSInteger result=((NSInteger(*)(id,SEL,id))originalWindowTracking)(window,selector,event);capturedHeight=NSHeight([window frame]);expect(capturedHeight<=rowExtent([window qvView],16,400)+.001,"actual cell transfers compact preference to actual popup sizing");return result;}
static int cell(void){
 nativeLimit=CGSizeZero;visibleFrame=NSMakeRect(-1280,140,1280,840);returnedSelection=399;Method method=class_getInstanceMethod([NSPopUpWindow class],@selector(runTrackingWithEvent:));originalWindowTracking=method_setImplementation(method,(IMP)interceptedTracking);
 NSPopUpButton *button=[[[NSPopUpButton alloc]initWithFrame:NSMakeRect(0,0,150,24)pullsDown:NO]autorelease];[button setMenu:menu(400)];[button selectItemAtIndex:200];if([[button cell]respondsToSelector:@selector(_setMaximumVisibleRows:)])[[button cell]_setMaximumVisibleRows:16];
 NSWindow *parent=[[[NSWindow alloc]initWithContentRect:NSMakeRect(-600,400,300,150)styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO]autorelease];[[parent contentView]addSubview:button];
 BOOL accepted=[[button cell]trackMouse:nil inRect:[button bounds]ofView:button untilMouseUp:NO];expect(accepted&&[button indexOfSelectedItem]==399,"actual cell accepts last-family selection through tracking result");expect([button numberOfItems]==400,"actual cell retains complete menu");method_setImplementation(method,originalWindowTracking);return 0;
}
int main(int argc,char **argv){@autoreleasepool{setbuf(stdout,NULL);INPUT(argc==2,"mode geometry|configured|inspector|cell");[NSApplication sharedApplication];int result=!strcmp(argv[1],"geometry")?geometry():!strcmp(argv[1],"configured")?configured():!strcmp(argv[1],"inspector")?inspector():!strcmp(argv[1],"cell")?cell():2;if(result)return result;printf("RESULT %u failures\n",failures);return failures?1:0;}}
