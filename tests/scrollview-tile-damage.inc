#include <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
typedef double CGFloat;
typedef struct { double x,y; } NSPoint;
typedef struct { double width,height; } NSSize;
typedef struct { NSPoint origin; NSSize size; } NSRect;
#define NSMakeRect(x,y,w,h) ((NSRect){{x,y},{w,h}})
#define MIN(a,b) ((a)<(b)?(a):(b))
static BOOL NSEqualRects(NSRect a,NSRect b){return !memcmp(&a,&b,sizeof a);}
static double NSWidth(NSRect r){return r.size.width;}
static double NSHeight(NSRect r){return r.size.height;}
static NSRect NSUnionRect(NSRect a,NSRect b){double x=fmin(a.origin.x,b.origin.x),y=fmin(a.origin.y,b.origin.y);return NSMakeRect(x,y,fmax(a.origin.x+a.size.width,b.origin.x+b.size.width)-x,fmax(a.origin.y+a.size.height,b.origin.y+b.size.height)-y);}
@interface NSObject { Class isa; }
+ (id)new;
@end
@implementation NSObject
+ (id)new {return class_createInstance(self,0);}
@end
@interface NSView : NSObject { @public NSRect f,b;BOOL dirty; }
- (NSRect)frame; - (NSRect)bounds; - (void)setFrame:(NSRect)frame;
- (void)setBoundsOrigin:(NSPoint)p; - (void)setNeedsDisplay:(BOOL)d;
- (void)discardCursorRects; - (void)addCursorRect:(NSRect)r cursor:(id)c;
@end
@implementation NSView
- (NSRect)frame{return f;}
- (NSRect)bounds{return b;}
- (void)setFrame:(NSRect)r{f=r;b.size=r.size;}
- (void)setBoundsOrigin:(NSPoint)p{b.origin=p;}
- (void)setNeedsDisplay:(BOOL)d{dirty=d;}
- (void)discardCursorRects{}
- (void)addCursorRect:(NSRect)r cursor:(id)c{}
@end
@interface _NSTextInspectorBar : NSView
- (CGFloat)preferredHeightForWidth:(CGFloat)w;
@end
@implementation _NSTextInspectorBar
- (CGFloat)preferredHeightForWidth:(CGFloat)w{return 30;}
@end
@interface NSScrollView : NSView { @public
 NSView *_textInspectorBar,*_headerClipView,*_cornerView,*_verticalScroller,*_horizontalScroller,*_clipView,*_horizontalRuler,*_verticalRuler;
 id _documentCursor;double thickness;unsigned damageCalls;unsigned char damage[160];
}
- (void)tile; - (NSRect)insetBounds; - (void)createHeaderAndCornerViewsIfNeeded; - (void)createRulerViewsIfNeeded;
- (NSRect)headerClipViewFrame; - (NSRect)cornerViewFrame; - (NSRect)verticalScrollerFrame; - (NSRect)horizontalScrollerFrame;
- (NSRect)clipViewFrame; - (NSRect)horizontalRulerFrame; - (NSRect)verticalRulerFrame;
- (BOOL)hasVerticalScroller; - (BOOL)hasHorizontalScroller; - (void)reflectScrolledClipView:(NSView *)v;
- (void)setNeedsDisplayInRect:(NSRect)r;
@end
@implementation NSScrollView
- (NSRect)insetBounds{return b;}
- (void)createHeaderAndCornerViewsIfNeeded{}
- (void)createRulerViewsIfNeeded{}
- (NSRect)headerClipViewFrame{return (NSRect){0};}
- (NSRect)cornerViewFrame{return (NSRect){0};}
- (NSRect)verticalScrollerFrame{return (NSRect){0};}
- (NSRect)horizontalScrollerFrame{return (NSRect){0};}
- (NSRect)verticalRulerFrame{return (NSRect){0};}
- (NSRect)horizontalRulerFrame{return NSMakeRect(b.origin.x,b.origin.y,96,thickness);}
- (NSRect)clipViewFrame{return NSMakeRect(b.origin.x,b.origin.y+thickness,96,100-thickness);}
- (BOOL)hasVerticalScroller{return YES;}
- (BOOL)hasHorizontalScroller{return YES;}
- (void)reflectScrolledClipView:(NSView *)v{[_horizontalRuler setNeedsDisplay:YES];}
- (void)setNeedsDisplayInRect:(NSRect)r{damageCalls++;for(int y=0;y<160;y++)if(y>=r.origin.y&&y<r.origin.y+r.size.height)damage[y]=1;}
/* PRODUCTION */
@end
static unsigned failures;
static void expect(BOOL ok,const char *name){printf("%s %s\n",ok?"PASS":"FAIL",name);failures+=!ok;}
static void reset(NSScrollView *s){memset(s->damage,0,sizeof s->damage);s->damageCalls=0;s->_clipView->dirty=NO;s->_horizontalRuler->dirty=NO;}
static void paint(NSScrollView *s,unsigned char *rows,BOOL full){
 int origin=s->b.origin.y,ruleEnd=origin+s->thickness;
 for(int y=origin;y<origin+100;y++) {
  BOOL ruler=y<ruleEnd;BOOL invalid=full||s->damage[y]||(ruler?s->_horizontalRuler->dirty:s->_clipView->dirty);
  if(invalid)rows[y]=ruler?1:3;
 }
 // Label positions follow NSRulerView's bounds origin + marker reservation + 3.
 int label=origin+(s->thickness==31?15:0)+3;
 if(full||s->damage[label]||s->_horizontalRuler->dirty)rows[label]=9;
}
int main(void){
 for(int origin=0;origin<=23;origin+=23){
  NSScrollView *s=[NSScrollView new];s->b=NSMakeRect(17,origin,96,100);
  s->_clipView=[NSView new];s->_horizontalRuler=[NSView new];s->thickness=31;[s tile];
  unsigned char rows[160]={0},forced[160]={0};paint(s,rows,YES);reset(s);
  s->thickness=16;[s tile];paint(s,rows,NO);paint(s,forced,YES);
  expect(!memcmp(rows+origin,forced+origin,100),"marker removal incremental rows equal full repaint");
  expect(rows[origin+18]!=9,"old number row is erased when marker row becomes numbers");
  expect(s->_clipView->dirty,"moved document content is invalidated");
  expect(s->damage[origin+18],"old ruler area invalidated in scroll-view coordinates");
  reset(s);s->thickness=31;[s tile];paint(s,rows,NO);paint(s,forced,YES);
  expect(!memcmp(rows+origin,forced+origin,100),"marker restoration incremental rows equal full repaint");
  reset(s);[s tile];expect(s->damageCalls==0&&!s->_clipView->dirty,"unchanged tiling adds no geometry damage");
 }
 printf("RESULT tile-damage failures=%u (native boundary doubles; guest pixels separate)\n",failures);
 return failures?1:0;
}
