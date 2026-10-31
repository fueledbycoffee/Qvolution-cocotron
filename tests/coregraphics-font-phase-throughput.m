#import "font-phase-probe.h"
int main(int argc,char **argv){
    REQUIRE(argc==2,"provide exact open DejaVuSans.ttf path");NSAutoreleasePool *pool=[NSAutoreleasePool new];
    CGGlyph glyph;CGFontRef font=phaseLoadFont(argv[1],&glyph);REQUIRE(font,"explicit DejaVu font validated");
    const char *names[]={"default-integer","enabled-integer","enabled-4phase","enabled-64phase"};
    for(int test=0;test<4;test++){
        uint8_t *pixels=calloc(PHASE_W*PHASE_H,4);CGContextRef c=phaseContext(pixels,font,1,test==0?PhaseDefault:PhaseEnabled);REQUIRE(c,"benchmark context creates");
        CGSize step=CGSizeMake(0,0);double start=0;const int count=10000;
        for(int i=-128;i<count;i++){
            if(i==0)start=phaseNow();unsigned phase=(unsigned)(i+128);double x=10;
            if(test==2)x+=(phase%4)/4.;if(test==3)x+=(phase%64)/64.;
            CGContextSetTextPosition(c,x,40);CGContextShowGlyphsWithAdvances(c,&glyph,&step,1);
        }
        printf("%s glyphs=%d seconds=%.6f\n",names[test],count,phaseNow()-start);CGContextRelease(c);free(pixels);
    }
    CGFontRelease(font);[pool drain];return 0;
}
