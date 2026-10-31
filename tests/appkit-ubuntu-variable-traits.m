// Original public client over explicitly identified installed open Ubuntu named instances.
#import <AppKit/AppKit.h>
#import <CoreText/CoreText.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
static unsigned failures;
#define INPUT(c,m) do{if(!(c)){fprintf(stderr,"INPUT FAIL: %s\n",m);return 2;}}while(0)
static void expect(BOOL c,const char *m){printf("%s: %s\n",c?"PASS":"FAIL",m);failures+=!c;}
static NSString *ps(NSFont *font){CFStringRef name=CTFontCopyPostScriptName((CTFontRef)font);return [(id)name autorelease];}
static double width(NSFont *font){UniChar c='W';CGGlyph glyph=0;CGSize advance=CGSizeZero;if(!CTFontGetGlyphsForCharacters((CTFontRef)font,&c,&glyph,1)||!glyph)return NAN;return CTFontGetAdvancesForGlyphs((CTFontRef)font,kCTFontOrientationHorizontal,&glyph,&advance,1);}
static id identified(NSView *parent,NSString *name){for(NSView *v in [parent subviews])if([[v identifier]isEqual:name])return v;return nil;}
int main(int argc,char **argv){@autoreleasepool{
 setbuf(stdout,NULL);INPUT(argc==2,"mode traits|manager|catalog|convert|inspector");[NSApplication sharedApplication];
 NSString *names[]={@"Ubuntu-Regular",@"Ubuntu-Bold",@"UbuntuItalic-BoldItalic"};
 CTFontSymbolicTraits expected[]={0,kCTFontTraitBold,kCTFontTraitBold|kCTFontTraitItalic};
 NSFont *fonts[3];for(unsigned i=0;i<3;i++){
  fonts[i]=[NSFont fontWithName:names[i]size:1000];INPUT(fonts[i]&&[ps(fonts[i])isEqual:names[i]],"actual named PostScript instance must load without substitution");
  printf("INPUT instance=%s CTtraits=%u W=%.6f\n",[names[i]UTF8String],CTFontGetSymbolicTraits((CTFontRef)fonts[i]),width(fonts[i]));
  INPUT(isfinite(width(fonts[i]))&&width(fonts[i])>0,"actual named instance has positive real glyph metrics");
 }
 // Independent FT inspection of these installed open-font files: units1000, W924/942/931.
 // These input guards reject accidentally loading default face0 for a named bold instance.
 INPUT(fabs(width(fonts[0])-924)<.001&&fabs(width(fonts[1])-942)<.001&&fabs(width(fonts[2])-931)<.001,"real named instance metrics agree with independent native FreeType file/index observation");
 NSFontManager *m=[NSFontManager sharedFontManager];
 if(!strcmp(argv[1],"traits")){
  for(unsigned i=0;i<3;i++)expect((CTFontGetSymbolicTraits((CTFontRef)fonts[i])&(kCTFontTraitBold|kCTFontTraitItalic))==expected[i],"CoreText reflects actual named-instance bold/italic metadata");
 }else if(!strcmp(argv[1],"manager")){
  for(unsigned i=0;i<3;i++){unsigned wanted=(expected[i]&kCTFontTraitBold?NSBoldFontMask:0)|(expected[i]&kCTFontTraitItalic?NSItalicFontMask:0);expect(([m traitsOfFont:fonts[i]]&(NSBoldFontMask|NSItalicFontMask))==wanted,"manager traits agree with actual named-instance style");}
 }else if(!strcmp(argv[1],"catalog")){
  NSArray *rows=[m availableMembersOfFontFamily:@"Ubuntu"];INPUT([rows count]>0,"installed Ubuntu catalog exists");BOOL seen[3]={0};
  for(id row in rows){INPUT([row count]==4,"public catalog tuple shape");for(unsigned i=0;i<3;i++)if([row[0]isEqual:names[i]]){seen[i]=YES;unsigned wanted=(expected[i]&kCTFontTraitBold?NSBoldFontMask:0)|(expected[i]&kCTFontTraitItalic?NSItalicFontMask:0);expect(([row[3]unsignedIntValue]&(NSBoldFontMask|NSItalicFontMask))==wanted,"canonical catalog named instance has actual basic traits");}}
  for(unsigned i=0;i<3;i++)expect(seen[i],"canonical catalog enumerates real named PostScript instance");
 }else if(!strcmp(argv[1],"convert")){
  NSFont *b=[m convertFont:fonts[0]toHaveTrait:NSBoldFontMask];expect([ps(b)isEqual:names[1]]&&fabs(width(b)-942)<.001,"adding bold selects genuine namedBold with real metrics");
  NSFont *bi=[m convertFont:b toHaveTrait:NSItalicFontMask];expect([ps(bi)isEqual:names[2]]&&fabs(width(bi)-931)<.001,"adding italic preserves actual variable bold");
  NSFont *r=[m convertFont:b toNotHaveTrait:NSBoldFontMask];expect([ps(r)isEqual:names[0]]&&fabs(width(r)-924)<.001,"removing bold returns actual regular instance");
 }else if(!strcmp(argv[1],"inspector")){
  NSScrollView *scroll=[[[NSScrollView alloc]initWithFrame:NSMakeRect(0,0,600,400)]autorelease];NSTextView *view=[[[NSTextView alloc]initWithFrame:NSMakeRect(0,0,600,400)]autorelease];[scroll setDocumentView:view];[view setRichText:YES];[view setString:@"Ubuntu bold action"];[view setFont:[NSFont fontWithName:names[0]size:20]];[view setUsesInspectorBar:YES];[view setSelectedRange:NSMakeRange(0,6)];
  NSView *bar=identified(scroll,@"NSTextViewInspectorBar");NSButton *bold=identified(bar,@"Bold");INPUT(bold,"real inspector bold control exists");[bold setState:NSControlStateValueOn];[NSApp sendAction:[bold action]to:[bold target]from:bold];
  NSFont *got=[[view textStorage]attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];expect([ps(got)isEqual:names[1]],"real inspector bold action changes selected Ubuntu text to actual namedBold");
  NSFont *untouched=[[view textStorage]attribute:NSFontAttributeName atIndex:7 effectiveRange:NULL];expect([ps(untouched)isEqual:names[0]],"real inspector preserves unselected Ubuntu text");
 }else INPUT(NO,"known mode");
 printf("RESULT %u failures\n",failures);return failures?1:0;
}}
