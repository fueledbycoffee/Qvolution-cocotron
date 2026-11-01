// Original public UI-role font contract, independent of vendor startup.
#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <math.h>
#define CHECK(c,m) do{if(!(c)){fprintf(stderr,"FAIL %s\n",m);return 1;}}while(0)
struct role {CTFontUIFontType type;CGFloat defaultSize;};
static int exercise(struct role role,CGFloat requested,CFStringRef language){
 CTFontRef font=CTFontCreateUIFontForLanguage(role.type,requested,language);
 CHECK(font,"supported UI role creates real font");
 CHECK(CTFontGetSize(font)==(requested>0?requested:role.defaultSize),"explicit/project-policy default size");
 CFStringRef family=CTFontCopyFamilyName(font);CHECK(family&&CFGetTypeID(family)==CFStringGetTypeID()&&CFStringGetLength(family)>0,"actual family metadata");CFRelease(family);
 CGFontRef graphics=CTFontCopyGraphicsFont(font,NULL);CHECK(graphics,"real underlying graphics font");
 CFStringRef ps=CGFontCopyPostScriptName(graphics),full=CGFontCopyFullName(graphics);CHECK(ps&&full&&CFStringGetLength(ps)>0&&CFStringGetLength(full)>0,"actual provider PS/full names after separate prerequisite");CHECK(!CFEqual(ps,CFSTR("sans-serif"))&&!CFEqual(ps,CFSTR("monospace")),"requested generic alias is not font identity");CFRelease(ps);CFRelease(full);
 UniChar text[3]={'A','i','W'};CGGlyph glyphs[3]={0};CHECK(CTFontGetGlyphsForCharacters(font,text,glyphs,3)&&glyphs[0]&&glyphs[1]&&glyphs[2],"actual Unicode glyphs");CGSize advances[3];double total=CTFontGetAdvancesForGlyphs(font,kCTFontOrientationHorizontal,glyphs,advances,3);CHECK(isfinite(total)&&total>0&&isfinite(CTFontGetAscent(font))&&CTFontGetAscent(font)>0,"finite real glyph metrics");for(int i=0;i<3;i++)CHECK(isfinite(advances[i].width)&&advances[i].width>0,"actual positive advances");
 if(role.type==kCTFontUIFontUserFixedPitch)CHECK(fabs(advances[1].width-advances[2].width)<0.0001,"fixed role actual i/W advances");
 CFRelease(font);CHECK(CGFontGetNumberOfGlyphs(graphics)>0,"retained graphics font survives UI font release");CGFontRelease(graphics);return 0;
}
int main(void){@autoreleasepool{
 CTFontRef control=CTFontCreateWithName(CFSTR("Helvetica"),14,NULL);CHECK(control&&CTFontGetSize(control)==14,"existing named-font control");CFRelease(control);
 struct role roles[]={{kCTFontUIFontSystem,13},{kCTFontUIFontMenuItem,13},{kCTFontUIFontEmphasizedSystem,13},{kCTFontUIFontToolTip,11},{kCTFontUIFontWindowTitle,13},{kCTFontUIFontSmallSystem,11},{kCTFontUIFontPushButton,13},{kCTFontUIFontSmallToolbar,11},{kCTFontUIFontViews,13},{kCTFontUIFontMiniSystem,9},{kCTFontUIFontUserFixedPitch,13},{kCTFontUIFontMenuTitle,13}};
 for(unsigned i=0;i<sizeof roles/sizeof roles[0];i++){fprintf(stderr,"PHASE role %u\n",(unsigned)roles[i].type);fflush(stderr);CHECK(exercise(roles[i],0,NULL)==0,"default role font sequence");CHECK(exercise(roles[i],17.25,CFSTR("en"))==0,"explicit-size/language role sequence");}
 CHECK(exercise(roles[0],13,CFSTR("fr"))==0&&exercise(roles[0],13,CFSTR("ja"))==0,"language hints yield real fonts without claiming localization identity");
 CHECK(!CTFontCreateUIFontForLanguage(kCTFontUIFontNone,0,NULL)&&!CTFontCreateUIFontForLanguage((CTFontUIFontType)0x7fffffff,0,NULL),"unsupported role returns NULL");
 CHECK(!CTFontCreateUIFontForLanguage(kCTFontUIFontSystem,-1,NULL)&&!CTFontCreateUIFontForLanguage(kCTFontUIFontSystem,NAN,NULL)&&!CTFontCreateUIFontForLanguage(kCTFontUIFontSystem,INFINITY,NULL),"invalid size returns NULL");
 CHECK(!CTFontCreateUIFontForLanguage(kCTFontUIFontSystem,13,CFSTR("")),"empty language rejected explicitly");
 UniChar embedded[]={ 'e','n',0,'f','r' },invalid[]={0xd800};
 CFStringRef withNull=CFStringCreateWithCharacters(NULL,embedded,5),bad=CFStringCreateWithCharacters(NULL,invalid,1);
 CHECK(withNull&&!CTFontCreateUIFontForLanguage(kCTFontUIFontSystem,13,withNull),"embedded language NUL rejected");CFRelease(withNull);
 if(bad){CHECK(!CTFontCreateUIFontForLanguage(kCTFontUIFontSystem,13,bad),"invalid UTF8 conversion rejected");CFRelease(bad);}
 CHECK(!CTFontCreateUIFontForLanguage(kCTFontUIFontSmallEmphasizedSystem,0,NULL),"unimplemented valid role remains unsupported");
 puts("PASS original real UI-role fonts/size/language/glyph metrics/ownership; no native face policy or app qualification");return 0;
}}
