/* Own raw sampler precision; no public RGB-mask acceptance or profile claim. */
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Onyx2D/O2Image.h>
#import <Onyx2D/O2Paint_image.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#define REQUIRE(c,m) do {if(!(c)){printf("FAIL %s\n",m);return 1;}} while(0)
static CGImageRef makeFloat(CGColorSpaceRef space,float *samples) {
 CGDataProviderRef p=CGDataProviderCreateWithData(NULL,samples,32,NULL);
 CGImageRef image=CGImageCreate(2,1,32,128,32,space,kCGBitmapFloatComponents|kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedLast,p,NULL,false,kCGRenderingIntentDefault);CGDataProviderRelease(p);return image;
}
int main(int argc,char **argv) {@autoreleasepool {
 setbuf(stdout,NULL);REQUIRE(argc==2,"alpha|nearest|bilinear");CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
 float sourceBytes[]={.125,.25,.375,.5,.125,.25,.375,.5};float maskBytes[]={.375,.125,.25,.625,.375,.125,.25,.625};
 CGImageRef source=makeFloat(space,sourceBytes),mask=makeFloat(space,maskBytes);REQUIRE(source&&mask,"real float images");
 if(!strcmp(argv[1],"alpha")) {O2Float values[2]={-1,-1};O2ImageReadSpan_Af_MASK((O2Image *)mask,0,0,values,2);REQUIRE(fabs(values[0]-.625)<1e-7&&fabs(values[1]-.625)<1e-7,"float alpha extraction preserves precision");}
 else {BOOL nearest=!strcmp(argv[1],"nearest");REQUIRE(nearest||!strcmp(argv[1],"bilinear"),"known mode");O2Paint_image *paint=[[O2Paint_image alloc] initWithImage:(O2Image *)source mask:(O2Image *)mask mode:VG_DRAW_IMAGE_NORMAL paint:nil interpolationQuality:nearest?kO2InterpolationNone:kO2InterpolationLow surfaceToImage:O2AffineTransformIdentity surfaceToMask:O2AffineTransformIdentity];REQUIRE(paint,"real image paint");O2argb32f samples[2];REQUIRE(O2PaintReadSpan_largb32f_PRE(paint,0,0,samples,2)==2,"real float sampler");for(int i=0;i<2;i++){REQUIRE(fabs(samples[i].r-.046875)<1e-7&&fabs(samples[i].g-.09375)<1e-7&&fabs(samples[i].b-.140625)<1e-7&&fabs(samples[i].a-.1875)<1e-7,"mask red coverage multiplies every premultiplied channel in float");}REQUIRE(paint->_paint_largb8u_PRE==NULL,"float mask never advertises missing byte reader");[paint release];}
 CGImageRelease(mask);CGImageRelease(source);CGColorSpaceRelease(space);puts("FLOAT_MASK_RAW_SAMPLER_PASS_NO_PROFILE_CLAIM");return 0;
}}
