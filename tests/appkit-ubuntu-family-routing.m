/* Original regression: actual manager/inspector APIs and own FT/O2 rendering. */
#import <AppKit/AppKit.h>
#import <CoreText/CoreText.h>
#import <Onyx2D/O2Font_freetype.h>
#import <Onyx2D/O2Surface.h>
#import <Onyx2D/O2Context_builtin_FT.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
static unsigned failures;
#define INPUT(c,m) do { if (!(c)) { fprintf(stderr,"INPUT FAIL %s\n",m); return 2; } } while (0)
static void expectUbuntu(BOOL good,const char *what) { printf("%s %s\n",good?"PASS":"FAIL",what); failures+=!good; }
static NSString *ps(NSFont *font) { return [(id)CTFontCopyPostScriptName((CTFontRef)font) autorelease]; }
static unsigned inkWidth(NSFont *font,CGGlyph glyph) {
    O2ColorSpaceRef space=O2ColorSpaceCreateDeviceRGB();
    O2Surface *surface=[[O2Surface alloc] initWithBytes:NULL width:64 height:64 bitsPerComponent:8
        bytesPerRow:256 colorSpace:space bitmapInfo:kO2ImageAlphaPremultipliedLast|kO2BitmapByteOrder32Big];
    O2ColorSpaceRelease(space); memset([surface pixelBytes],0,64*256);
    O2Context_builtin_FT *context=[[O2Context_builtin_FT alloc] initWithSurface:surface flipped:NO];
    CGFontRef graphics=CTFontCopyGraphicsFont((CTFontRef)font,NULL);
    CGContextSetFont((CGContextRef)context,graphics); CGContextSetFontSize((CGContextRef)context,20);
    CGContextSetRGBFillColor((CGContextRef)context,0,0,0,1); CGContextSetTextPosition((CGContextRef)context,8,24);
    CGContextShowGlyphs((CGContextRef)context,&glyph,1);
    unsigned min=64,max=0; unsigned char *pixels=[surface pixelBytes];
    for(unsigned y=0;y<64;y++)for(unsigned x=0;x<64;x++)if(pixels[y*256+x*4+3]) { min=MIN(min,x); max=MAX(max,x); }
    CGFontRelease(graphics); [context release]; [surface release]; return min<64?max-min+1:0;
}
static BOOL compare(NSFont *got,NSFont *reference,const char *file,long index) {
    if(!got || !reference) { expectUbuntu(NO,"font exists"); return NO; }
    CGFontRef graphics=CTFontCopyGraphicsFont((CTFontRef)got,NULL);
    FT_Face actual=[(O2Font_freetype *)graphics face];
    BOOL good=[ps(got) isEqualToString:ps(reference)] && actual && actual->face_index==index;
    printf("FACE ps=%s family=%s catalog-file=%s actual-index=%ld expected-index=%ld\n",
        [ps(got) UTF8String],[[got familyName] UTF8String],file,actual?actual->face_index:-1,index);
    // Map actual PS/index back to a catalog file; never infer it from the requested family.
    FcPattern *q=FcPatternCreate(); FcPatternAddString(q,FC_POSTSCRIPT_NAME,(const FcChar8 *)[ps(got) UTF8String]);
    FcObjectSet *props=FcObjectSetBuild(FC_FILE,FC_INDEX,FC_POSTSCRIPT_NAME,NULL);
    FcFontSet *set=FcFontList(O2FontSharedFontConfig(),q,props); BOOL found=NO;
    for(int i=0;set && i<set->nfont;i++) { FcChar8 *path; int n;
        if(FcPatternGetString(set->fonts[i],FC_FILE,0,&path)==FcResultMatch &&
            FcPatternGetInteger(set->fonts[i],FC_INDEX,0,&n)==FcResultMatch && n==index && !strcmp((char *)path,file)) found=YES;
    }
    good &= found; if(set)FcFontSetDestroy(set); FcObjectSetDestroy(props); FcPatternDestroy(q);
    expectUbuntu(good,"resolved PostScript/file/instance agrees with independent raw FT reference");
    UniChar chars[]={'W','i','A','m'}; CGGlyph a[4]={0},b[4]={0}; CGSize wa[4]={{0}},wb[4]={{0}};
    BOOL glyphs=CTFontGetGlyphsForCharacters((CTFontRef)got,chars,a,4) && CTFontGetGlyphsForCharacters((CTFontRef)reference,chars,b,4);
    CTFontGetAdvancesForGlyphs((CTFontRef)got,kCTFontOrientationHorizontal,a,wa,4);
    CTFontGetAdvancesForGlyphs((CTFontRef)reference,kCTFontOrientationHorizontal,b,wb,4);
    for(unsigned i=0;i<4;i++) {
        unsigned actualWidth=inkWidth(got,a[i]),expectedWidth=inkWidth(reference,b[i]);
        printf("GLYPH cp=%c advance=%.6f reference=%.6f ink=%u reference=%u\n",(char)chars[i],wa[i].width,wb[i].width,actualWidth,expectedWidth);
        expectUbuntu(glyphs && a[i] && a[i]==b[i] && isfinite(wa[i].width) && fabs(wa[i].width-wb[i].width)<.00001 &&
            actualWidth>0 && actualWidth==expectedWidth,"actual O2 rendered glyph width and CT advance match reference");
    }
    CGFontRelease(graphics); return good;
}
static id identified(NSView *parent,NSString *name) {
    for(NSView *child in [parent subviews]) { if([[child identifier] isEqual:name])return child; id nested=identified(child,name); if(nested)return nested; } return nil;
}
int main(void) {
    FT_Library library; if(FT_Init_FreeType(&library))return 2;
    @autoreleasepool {
    setbuf(stdout,NULL); [NSApplication sharedApplication]; NSFontManager *manager=[NSFontManager sharedFontManager];
    const char *files[]={"/usr/share/fonts/truetype/ubuntu/Ubuntu[wdth,wght].ttf","/usr/share/fonts/truetype/ubuntu/Ubuntu-Italic[wdth,wght].ttf"};
    const long indices[]={0,327680,0,327680,262144,131072};
    const unsigned traits[]={0,NSBoldFontMask,NSItalicFontMask,NSBoldFontMask|NSItalicFontMask};
    NSFont *references[6]={nil};
    for(unsigned i=0;i<6;i++) {
        FT_Face raw; int error=FT_New_Face(library,files[i==2||i==3],indices[i],&raw);
        if(i>=4 && error) { printf("SKIP optional instance %u not installed\n",i); continue; }
        INPUT(!error,"installed open Ubuntu fixture file/index");
        O2Font_freetype *graphics=[[O2Font_freetype alloc] initWithFace:raw];
        references[i]=(NSFont *)CTFontCreateWithGraphicsFont((CGFontRef)graphics,20,NULL,NULL); [graphics release];
        INPUT(references[i],"reference wraps independently selected raw FT face");
        NSFont *got=i<4?[manager fontWithFamily:@"Ubuntu" traits:traits[i] weight:5 size:20]:
            [manager convertFont:references[0] toFace:ps(references[i])];
        compare(got,references[i],files[i==2||i==3],indices[i]);
    }
    compare([manager convertFont:[NSFont userFontOfSize:20] toFamily:@"Ubuntu"],references[0],files[0],0);
    NSFont *bold=[manager convertFont:references[0] toHaveTrait:NSBoldFontMask]; compare(bold,references[1],files[0],indices[1]);
    NSFont *both=[manager convertFont:bold toHaveTrait:NSItalicFontMask]; compare(both,references[3],files[1],indices[3]);
    compare([manager convertFont:both toNotHaveTrait:NSBoldFontMask],references[2],files[1],0);
    compare([manager convertFont:bold toNotHaveTrait:NSBoldFontMask],references[0],files[0],0);
    NSScrollView *scroll=[[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,600,400)] autorelease];
    NSTextView *view=[[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,600,400)] autorelease];
    [scroll setDocumentView:view]; [view setRichText:YES]; [view setString:@"Ubuntu sample"]; [view setFont:[NSFont userFontOfSize:20]];
    [view setUsesInspectorBar:YES]; [view setSelectedRange:NSMakeRange(0,6)];
    NSView *bar=identified(scroll,@"NSTextViewInspectorBar"); NSPopUpButton *family=identified(bar,@"Font family");
    INPUT(family,"actual inspector family control"); [family selectItemWithTitle:@"Ubuntu"];
    [NSApp sendAction:[family action] to:[family target] from:family];
    compare([[view textStorage] attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL],references[0],files[0],0);
    NSButton *button=identified(bar,@"Bold"); INPUT(button,"actual inspector bold control"); [button setState:NSControlStateValueOn];
    [NSApp sendAction:[button action] to:[button target] from:button];
    compare([[view textStorage] attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL],references[1],files[0],indices[1]);
    for(unsigned i=0;i<6;i++)[references[i] release];
    printf("RESULT %u failures\n",failures);
    }
    FT_Done_FreeType(library); return failures?1:0;
}
