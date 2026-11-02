/* Original Qvolution typography acceptance. Only own backend/public AppKit calls. */
#import <AppKit/AppKit.h>
#include "window-frame-settle.h"
#import <CoreText/CoreText.h>
#import <Onyx2D/O2Surface.h>
#import <Onyx2D/O2Context_builtin_FT.h>
#import "../AppKit/NSTextView.subproj/NSTextInspectorBar.h"
#import <objc/runtime.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static unsigned failures, labels;
static void expectUIFont(BOOL ok, const char *name) { printf("%s %s\n",ok?"PASS":"FAIL",name);failures+=!ok; }
static void png(O2Surface *surface, NSString *path) {
    O2ImageRef image=O2SurfaceCreateImage(surface);
    NSBitmapImageRep *rep=[[[NSBitmapImageRep alloc] initWithCGImage:(CGImageRef)image] autorelease];
    NSData *data=[rep representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]];
    expectUIFont(data && [data writeToFile:path atomically:YES],"fixture PNG written");
    O2ImageRelease(image);
}
static O2Context_builtin_FT *context(unsigned w,unsigned h,O2Surface **surface) {
    O2ColorSpaceRef space=O2ColorSpaceCreateDeviceRGB();
    *surface=[[O2Surface alloc] initWithBytes:NULL width:w height:h bitsPerComponent:8 bytesPerRow:w*4
        colorSpace:space bitmapInfo:kO2ImageAlphaPremultipliedLast|kO2BitmapByteOrder32Big];
    O2ColorSpaceRelease(space);
    memset([*surface pixelBytes],0,w*h*4);
    return [[O2Context_builtin_FT alloc] initWithSurface:*surface flipped:NO];
}
static void capHeight(NSString *directory) {
    NSFont *font=[NSFont systemFontOfSize:0];
    UniChar h='H';CGGlyph glyph=0;
    expectUIFont(CTFontGetGlyphsForCharacters((CTFontRef)font,&h,&glyph,1)&&glyph,"system face has H");
    for(int scale=1;scale<=2;++scale) {
        unsigned width=40*scale,height=40*scale;O2Surface *surface;
        O2Context_builtin_FT *cpu=context(width,height,&surface);CGContextRef cg=(CGContextRef)cpu;
        CGContextScaleCTM(cg,scale,scale);CGFontRef graphics=CTFontCopyGraphicsFont((CTFontRef)font,NULL);
        CGContextSetFont(cg,graphics);CGContextSetFontSize(cg,13);
        CGContextSetRGBFillColor(cg,0,0,0,1);CGContextSetTextPosition(cg,8,12);CGContextShowGlyphs(cg,&glyph,1);
        unsigned char *bytes=[surface pixelBytes];int top=height,bottom=-1;BOOL solid=NO,black=YES;
        for(unsigned y=0;y<height;++y)for(unsigned x=0;x<width;++x) {
            unsigned char *p=bytes+y*width*4+x*4;
            if(p[3]>2) { top=MIN(top,(int)y);bottom=MAX(bottom,(int)y); }
            if(p[3]>=253) { solid=YES;black&=p[0]<=2&&p[1]<=2&&p[2]<=2; }
        }
        double logical=bottom>=top?(bottom-top+1)/(double)scale:0;
        printf("MEASURE H scale=%d logical-height=%.2f\n",scale,logical);
        expectUIFont(logical>=8 && logical<=10,"O2Surface H cap height 9 +/- 1 logical px");
        expectUIFont(solid && black,"H solid pixel black within 2/255");
        expectUIFont(solid && bytes[3]<=2,"H has opaque ink and transparent corner within 2/255");
        png(surface,[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"H-%dx.png",scale]]);
        CGFontRelease(graphics);[cpu release];[surface release];
    }
}
static void inspect(NSView *view) {
    if([view isHidden])return;
    if([view isKindOfClass:[NSControl class]] &&
       ![view isKindOfClass:[NSMatrix class]] && ![view isKindOfClass:[NSTextView class]]) {
        NSControl *control=(id)view;NSCell *cell=[control cell];
        BOOL editable=[cell isEditable];
        if(!editable && [cell type]==NSTextCellType) {
            NSString *title=[cell stringValue];
            if([control isKindOfClass:[NSButton class]]) {
                NSButtonCell *button=(id)cell;
                if([button imagePosition]==NSImageOnly) title=nil;
            }
            if([title length] && [cell font]) {
                NSRect available=[cell titleRectForBounds:[view bounds]];
                NSDictionary *attributes=[NSDictionary dictionaryWithObject:[cell font] forKey:NSFontAttributeName];
                NSSize needed=[title sizeWithAttributes:attributes];
                if([cell wraps]) needed=[title boundingRectWithSize:NSMakeSize(NSWidth(available),100000)
                    options:NSStringDrawingUsesLineFragmentOrigin attributes:attributes].size;
                ++labels;
                BOOL fits=needed.width<=NSWidth(available)+.5 && needed.height<=NSHeight(available)+1;
                if(!fits)printf("TRUNCATED %s title=%s needed=%.2fx%.2f available=%.2fx%.2f\n",
                    object_getClassName(view),[title UTF8String],needed.width,needed.height,NSWidth(available),NSHeight(available));
                expectUIFont(fits,"standard control label fits actual title rect");
            }
        }
    }
    for(NSView *child in [view subviews])inspect(child);
}
static void panel(NSView *view,NSString *name,NSString *directory) {
    if ([[view window] isVisible] && !fixtureWaitForWindowFrame([view window],"ui-font-theme")) { failures++; return; }
    unsigned before=labels;expectUIFont(view && NSWidth([view bounds])>0 && NSHeight([view bounds])>0,"panel has real laid-out content");
    inspect(view);expectUIFont(labels>before,"panel checks at least one actual static label");
    for(int scale=1;scale<=2;++scale) {
        unsigned w=ceil(NSWidth([view bounds])*scale),h=ceil(NSHeight([view bounds])*scale);
        if(!w||!h)continue;
        O2Surface *surface;O2Context_builtin_FT *cpu=context(w,h,&surface);
        CGContextScaleCTM((CGContextRef)cpu,scale,scale);
        NSGraphicsContext *graphics=[NSGraphicsContext graphicsContextWithCGContext:(CGContextRef)cpu flipped:[view isFlipped]];
        [view displayRectIgnoringOpacity:[view bounds] inContext:graphics];
        png(surface,[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%dx.png",name,scale]]);
        [cpu release];[surface release];
    }
}
int main(int argc,char **argv) {@autoreleasepool {
    setbuf(stdout,NULL);[NSApplication sharedApplication];
    NSString *directory=argc>1?[NSString stringWithUTF8String:argv[1]]:@"/tmp/theme-p2";
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    NSFont *system=[NSFont systemFontOfSize:0];expectUIFont(system && [system pointSize]==13,"system zero size is 13");
    expectUIFont([NSFont systemFontSize]==13 && [NSFont smallSystemFontSize]==11 && [NSFont labelFontSize]==10,"AppKit role sizes 13/11/10");
    expectUIFont([[NSFont toolTipsFontOfSize:0] pointSize]==11 && [[NSFont labelFontOfSize:0] pointSize]==10,"tooltip/label default sizes");
    // UI fonts go through the font cache: one object per face and size.
    expectUIFont([NSFont systemFontOfSize:0]==system && [NSFont systemFontOfSize:13]==system &&
        [NSFont fontWithName:[system fontName] size:13]==system,"system font is the cached font object");
    NSFont *bold=[NSFont boldSystemFontOfSize:13];
    expectUIFont(bold && [NSFont boldSystemFontOfSize:13]==bold && bold!=system,"bold system font is cached separately");
    printf("MEASURE system-family=%s name=%s size=%.2f\n",[[system familyName] UTF8String],[[system fontName] UTF8String],[system pointSize]);
    if(argc>2)expectUIFont([[system familyName] isEqualToString:[NSString stringWithUTF8String:argv[2]]],"expected portal/fallback family");
    for(NSString *alias in [NSArray arrayWithObjects:@".AppleSystemUIFont",@"Helvetica",@"Helvetica Neue",@"Lucida Grande",nil]) {
        NSFont *named=[NSFont fontWithName:alias size:13];
        expectUIFont([[named familyName] isEqualToString:[system familyName]],"named UI alias uses same chosen family");
    }
    expectUIFont([[NSFont userFontOfSize:0] pointSize]==13,"document default uses chosen UI face at 13");
    expectUIFont([[NSFont systemFontOfSize:17.25] pointSize]==17.25,"explicit font size preserved");
    capHeight(directory);
    NSSavePanel *save=[NSSavePanel savePanel];panel([save contentView],@"save-panel",directory);
    NSFontPanel *fonts=[NSFontPanel sharedFontPanel];panel([fonts contentView],@"font-panel",directory);
    NSAlert *alert=[[[NSAlert alloc] init] autorelease];[alert setMessageText:@"Save changes before closing?"];
    [alert setInformativeText:@"Your changes will be saved in this document."];
    [alert addButtonWithTitle:@"Save"];[alert addButtonWithTitle:@"Cancel"];[alert addButtonWithTitle:@"Don't Save"];
    [alert layout];panel([[alert window] contentView],@"alert",directory);
    NSTextView *text=[[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,640,200)] autorelease];
    [text setRichText:YES];[text setFont:system];
    _NSTextInspectorBar *bar=[[[_NSTextInspectorBar alloc] initWithTextView:text] autorelease];
    for(int width=450;width<=640;width+=190) {
        [bar setFrameSize:NSMakeSize(width,30)];[bar resizeSubviewsWithOldSize:NSZeroSize];
        panel(bar,[NSString stringWithFormat:@"format-bar-%d",width],directory);
    }
    printf("RESULT labels=%u failures=%u\n",labels,failures);return failures?1:0;
}}
