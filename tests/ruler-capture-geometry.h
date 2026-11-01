#pragma once
#include <math.h>
#include <limits.h>
#include "../AppKit/Wayland.backend/WaylandScale.h"

typedef struct { int x,y,width,height; } RulerCaptureRect;

// WaylandDrawingContext uses the rounded surface extents divided by logical
// size, with equal left/bottom borders. No graphics-state conversion is used.
static int rulerCaptureRect(double frameX,double frameTop,
    double regionX,double regionY,double regionWidth,double regionHeight,
    double logicalWidth,double logicalHeight,double border,double scale,
    double surfaceWidth,double surfaceHeight,RulerCaptureRect *out) {
    double inputs[]={frameX,frameTop,regionX,regionY,regionWidth,regionHeight,
        logicalWidth,logicalHeight,border,scale,surfaceWidth,surfaceHeight};
    for(unsigned i=0;i<sizeof(inputs)/sizeof(inputs[0]);i++)if(!isfinite(inputs[i]))return 0;
    if(logicalWidth>INT_MAX||logicalHeight>INT_MAX||scale>UINT32_MAX/120.0)return 0;
    if(regionWidth<=0||regionHeight<=0||logicalWidth<=0||logicalHeight<=0||scale<=0||border<0||
       surfaceWidth<=0||surfaceHeight<=0||surfaceWidth>INT_MAX||surfaceHeight>INT_MAX||
       floor(logicalWidth)!=logicalWidth||floor(logicalHeight)!=logicalHeight)return 0;
    uint32_t scale120=(uint32_t)llround(scale*120);
    int32_t expectedWidth,expectedHeight;
    if(fabs(scale120/120.0-scale)>1e-10||
       !WaylandScaleExtent((int32_t)logicalWidth,scale120,INT_MAX,&expectedWidth)||
       !WaylandScaleExtent((int32_t)logicalHeight,scale120,INT_MAX,&expectedHeight)||
       expectedWidth!=surfaceWidth||expectedHeight!=surfaceHeight)return 0;
    double sx=surfaceWidth/logicalWidth,sy=surfaceHeight/logicalHeight;
    double x0=floor((border+frameX+regionX)*sx);
    double x1=ceil((border+frameX+regionX+regionWidth)*sx);
    double y0=floor(surfaceHeight-(border+frameTop-regionY)*sy);
    double y1=ceil(surfaceHeight-(border+frameTop-regionY-regionHeight)*sy);
    if(!isfinite(x0)||!isfinite(x1)||!isfinite(y0)||!isfinite(y1)||
       x0<0||y0<0||x1>surfaceWidth||y1>surfaceHeight||x1<=x0||y1<=y0)return 0;
    *out=(RulerCaptureRect){(int)x0,(int)y0,(int)(x1-x0),(int)(y1-y0)};return 1;
}
