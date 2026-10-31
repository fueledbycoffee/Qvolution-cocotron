#import "font-phase-probe.h"
int main(int argc,char **argv){
    REQUIRE(argc==2,"provide exact open DejaVuSans.ttf path");NSAutoreleasePool *pool=[NSAutoreleasePool new];
    CGGlyph glyph;CGFontRef font=phaseLoadFont(argv[1],&glyph);REQUIRE(font,"explicit DejaVu font validated without fallback");
    PhaseMask base,shifted,again,legacy;const double shifts[]={.25,.5,1};
    for(int scale=1;scale<=2;scale++){
        REQUIRE(phaseRender(font,glyph,scale,10,40,0,PhaseEnabled,&base),"base renders");
        REQUIRE(phaseRender(font,glyph,scale,10,40,0,PhaseDefault,&legacy),"default renders");
        REQUIRE(phaseEqual(&base,&legacy),"integer enabled output equals default");
        for(int i=0;i<3;i++){
            REQUIRE(phaseRender(font,glyph,scale,10+shifts[i],40,0,PhaseEnabled,&shifted),"x shift renders");
            REQUIRE(fabs(shifted.x-base.x-shifts[i]*scale)<.15,"enabled x origin preserves phase");
            REQUIRE(phaseRender(font,glyph,scale,10,40+shifts[i],0,PhaseEnabled,&shifted),"y shift renders");
            REQUIRE(fabs(shifted.y-base.y+shifts[i]*scale)<.15,"enabled y origin preserves phase");
        }
        REQUIRE(phaseRender(font,glyph,scale,-11,40,30,PhaseEnabled,&base),"negative user origin renders");
        REQUIRE(phaseRender(font,glyph,scale,-10.5,40,30,PhaseEnabled,&shifted),"negative user phase renders");
        REQUIRE(fabs(shifted.x-base.x-.5*scale)<.15,"negative user origin preserves translation");
    }
    REQUIRE(phaseRender(font,glyph,1,10.5,40.25,0,PhaseDefault,&legacy),"fractional default renders");
    const PhaseMode disabled[]={PhaseOff,PhaseAllowOff,PhaseQuantized,PhaseRestoreAllow};
    for(size_t i=0;i<sizeof(disabled)/sizeof(disabled[0]);i++){
        REQUIRE(phaseRender(font,glyph,1,10.5,40.25,0,disabled[i],&shifted),"disabled/legacy branch renders");
        REQUIRE(phaseEqual(&legacy,&shifted),"default/disallowed/quantized branch preserves legacy mask");
    }
    REQUIRE(phaseRender(font,glyph,1,10.5,40.25,0,PhaseEnabled,&base),"explicit phase renders");
    REQUIRE(!phaseEqual(&base,&legacy),"enabled phase differs from legacy integral mask");
    const PhaseMode enabled[]={PhaseRestoreShould,PhaseRestoreQuant,PhaseQuantAllowOff};
    for(size_t i=0;i<sizeof(enabled)/sizeof(enabled[0]);i++){
        REQUIRE(phaseRender(font,glyph,1,10.5,40.25,0,enabled[i],&shifted),"state/allow branch renders");
        REQUIRE(phaseEqual(&base,&shifted),"should flags restore but quantization permission stays context-wide");
    }
    REQUIRE(phaseRender(font,glyph,1,10.25,40.5,0,PhaseEnabled,&base),"first phase caches");
    REQUIRE(phaseRender(font,glyph,1,10.5,40.25,0,PhaseEnabled,&shifted),"another phase caches");
    REQUIRE(!phaseEqual(&base,&shifted),"phase cache masks remain distinct");
    REQUIRE(phaseRender(font,glyph,1,10.25,40.5,0,PhaseEnabled,&again),"first phase revisited");
    REQUIRE(phaseEqual(&base,&again),"phase cache revisits correct mask");
    CGFontRelease(font);[pool drain];puts("PASS: x/y/negative origins, default/integer equality, flags/state and phase cache");return 0;
}
