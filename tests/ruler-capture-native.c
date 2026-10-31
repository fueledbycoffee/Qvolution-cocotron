// Source-owned capture geometry; no AppKit or graphics-state conversion stubs.
#include "ruler-capture-geometry.h"
#include <stdio.h>
static unsigned failures,checks;
static void check(int ok,const char *name) {checks++;if(!ok){failures++;printf("FAIL %s\n",name);}}
static int equal(RulerCaptureRect a,int x,int y,int w,int h) {
    return a.x==x&&a.y==y&&a.width==w&&a.height==h;
}
int main(void) {
    RulerCaptureRect r;
    check(rulerCaptureRect(31,299,0,0,620,60,720,340,0,1,720,340,&r)&&equal(r,31,41,620,60),"flipped scroll top row");
    check(rulerCaptureRect(47,313,0,0,620,60,720,340,0,1,720,340,&r)&&equal(r,47,27,620,60),"translated scroll frame");
    check(rulerCaptureRect(31,299,0,0,620,60,732,380,6,1,732,380,&r)&&equal(r,37,75,620,60),"client decorated backing");
    check(rulerCaptureRect(31,299,0,0,620,60,732,380,6,2,1464,760,&r)&&equal(r,74,150,1240,120),"double backing scale");
    check(rulerCaptureRect(31,299,0,0,620,60,732,380,6,1.25,915,475,&r)&&equal(r,46,93,776,76),"fractional backing scale");
    check(rulerCaptureRect(31,299,0,0,620,60,733,381,6,1.25,916,476,&r)&&equal(r,46,94,776,76),"fractional rounded extents");
    check(rulerCaptureRect(31,299,53,15,190,16,720,340,0,1,720,340,&r)&&equal(r,84,56,190,16),"nonzero region origin");
    check(!rulerCaptureRect(31,299,0,0,0,60,720,340,0,1,720,340,&r),"reject zero capture");
    check(!rulerCaptureRect(-50,299,0,0,620,60,720,340,0,1,720,340,&r),"reject outside backing");
    check(!rulerCaptureRect(31,299,0,0,620,60,720,340,0,2,720,340,&r),"reject inconsistent backing scale");
    check(!rulerCaptureRect(NAN,299,0,0,620,60,720,340,0,1,720,340,&r),"reject nonfinite geometry");
    check(!rulerCaptureRect(31,299,0,0,620,60,720,340,0,0,720,340,&r),"reject zero backing scale");
    printf("RESULT ruler-capture failures=%u checks=%u\n",failures,checks);return failures?1:0;
}
