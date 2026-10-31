#import <AppKit/AppKit.h>
#import <QuartzCore/CALayer.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define CHECK(c, message) do { if (!(c)) { fprintf(stderr,"FAIL: %s\n",message); return 1; } } while (0)
@interface NSGraphicsContext (AppearanceProbeFocus)
- (NSMutableArray *)focusStack;
@end
@interface AppearancePaintView : NSView {
@public
    NSGraphicsContext *bitmap;
    uint8_t *pixels;
    NSAppearance *providerSeen,*drawSeen,*afterNested;
    AppearancePaintView *nested;
    BOOL throwDraw,throwSetup,useLayer;
    NSUInteger drawings,updates;
}
- (void)paint;
@end
@implementation AppearancePaintView
- (id)init {
    if(!(self=[super initWithFrame:NSMakeRect(0,0,16,16)]))return nil;
    pixels=calloc(16*16,4);CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef c=CGBitmapContextCreate(pixels,16,16,8,64,space,kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);bitmap=[[NSGraphicsContext graphicsContextWithGraphicsPort:c flipped:NO] retain];CGContextRelease(c);return self;
}
- (void)dealloc { [bitmap release];free(pixels);[providerSeen release];[drawSeen release];[afterNested release];[super dealloc]; }
- (BOOL)canDraw { return YES; }
- (BOOL)isOpaque { return YES; }
- (void)lockFocus { [super lockFocusIfCanDrawInContext:bitmap]; }
- (void)setUpGState { if(throwSetup)[NSException raise:@"QVSetupFailure" format:@"own source setup failure"];[super setUpGState]; }
- (BOOL)wantsUpdateLayer { return useLayer; }
- (void)paint {
    [drawSeen release];drawSeen=[[NSAppearance currentDrawingAppearance] retain];
    NSColor *dynamic=[NSColor colorWithName:@"QVAppearancePixel" dynamicProvider:^NSColor *(NSAppearance *appearance){
        [providerSeen release];providerSeen=[appearance retain];
        return [[appearance name] isEqual:NSAppearanceNameDarkAqua]?[NSColor blueColor]:[NSColor redColor];
    }];
    [dynamic setFill];NSRectFill([self bounds]);
    if(nested){
        [nested displayRectIgnoringOpacity:[nested bounds]];
        [afterNested release];afterNested=[[NSAppearance currentDrawingAppearance] retain];
        [dynamic setFill];NSRectFill(NSMakeRect(0,0,1,1));
    }
}
- (void)drawRect:(NSRect)rect { drawings++;if(throwDraw)[NSException raise:@"QVDrawFailure" format:@"own source draw failure"];[self paint]; }
- (void)updateLayer { updates++;if(throwDraw)[NSException raise:@"QVDrawFailure" format:@"own source layer failure"];[self paint]; }
- (void)enableLayerProbe { useLayer=YES;_layer=[[CALayer alloc] init]; }
@end
static BOOL blue(AppearancePaintView *view){uint8_t *p=view->pixels+(8*16+8)*4;return p[0]>250&&p[2]<5&&p[3]>250;}
static BOOL red(AppearancePaintView *view){uint8_t *p=view->pixels+(8*16+8)*4;return p[2]>250&&p[0]<5&&p[3]>250;}
int main(int argc,char **argv){
    CHECK(argc==2,"choose --draw, --layer, --throw or --setup-throw");
    NSAutoreleasePool *pool=[NSAutoreleasePool new];[NSApplication sharedApplication];
    NSAppearance *outside=[NSAppearance appearanceNamed:NSAppearanceNameVibrantLight];
    NSAppearance *dark=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua],*light=[NSAppearance appearanceNamed:NSAppearanceNameAqua];
    [NSAppearance setCurrentAppearance:outside];[NSApp setAppearance:light];
    AppearancePaintView *view=[AppearancePaintView new],*child=nil;
    [view setAppearance:dark];NSGraphicsContext *prior=[NSGraphicsContext currentContext];
    BOOL layer=!strcmp(argv[1],"--layer"),throwing=!strcmp(argv[1],"--throw"),setup=!strcmp(argv[1],"--setup-throw");
    CHECK(layer||throwing||setup||!strcmp(argv[1],"--draw"),"known probe mode");
    if(layer)[view enableLayerProbe];view->throwDraw=throwing;view->throwSetup=setup;
    if(!layer&&!throwing&&!setup){child=[AppearancePaintView new];[child setAppearance:light];[view addSubview:child];view->nested=child;}
    BOOL sawException=NO,caught=NO;
    @try{[view displayRectIgnoringOpacity:[view bounds]];}
    @catch(NSException *exception){sawException=YES;caught=[[exception name] isEqual:setup?@"QVSetupFailure":@"QVDrawFailure"];}
    CHECK(sawException==(throwing||setup)&&(!sawException||caught),"expected own-source drawing exception only");
    CHECK([NSGraphicsContext currentContext]==prior,"drawing restores prior graphics context after success/exception");
    CHECK([[view->bitmap focusStack] count]==0,"drawing restores focus stack after success/exception");
    CHECK([NSAppearance currentDrawingAppearance]==outside,"drawing restores outer thread appearance");
    if(!throwing&&!setup){
        CHECK(view->drawSeen==dark&&view->providerSeen==dark&&blue(view),"actual automatic view drawing resolves dynamic provider to dark pixels");
        if(child){CHECK(child->drawSeen==light&&child->providerSeen==light&&red(child),"nested view draws its own light provider pixels");CHECK(view->afterNested==dark,"nested draw restores parent drawing appearance");}
        if(layer)CHECK(view->updates==1&&view->drawings==0,"actual updateLayer path uses automatic appearance");
    }
    [child release];[view release];[NSApp setAppearance:nil];[NSAppearance setCurrentAppearance:nil];[pool drain];
    puts("PASS: automatic appearance scope, actual provider pixels and focus/exception restoration");return 0;
}
