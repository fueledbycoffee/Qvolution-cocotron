/* Rung 3: Quartz 2D Programming Guide, Setting the Alpha Value. */
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
enum { W=32,H=32,ROW=32*16+16 };
static unsigned failures;
static void pattern(void *info,CGContextRef c){CGContextSetRGBFillColor(c,.8,.4,.2,.7);CGContextFillRect(c,CGRectMake(0,0,4,4));}
static void shade(void *info,const CGFloat *in,CGFloat *out){out[0]=.2+.6*in[0];out[1]=.4;out[2]=.2;out[3]=.7;}
static void draw(CGContextRef c,int path){
 CGContextSetRGBFillColor(c,.8,.4,.2,.7);CGContextSetRGBStrokeColor(c,.8,.4,.2,.7);
 if(path==0){CGContextFillRect(c,CGRectMake(2,2,26,26));}
 else if(path==1){CGContextSetGrayFillColor(c,.6,.7);CGContextFillEllipseInRect(c,CGRectMake(2,2,26,26));}
 else if(path==2){CGContextSetLineWidth(c,3);CGContextStrokeRect(c,CGRectMake(4,4,22,22));}
 else if(path==3){CGContextAddRect(c,CGRectMake(2,2,26,26));CGContextAddRect(c,CGRectMake(8,8,10,10));CGContextEOFillPath(c);}
 else if(path==4){CGFontRef f=CGFontCreateWithFontName(CFSTR("DejaVuSans"));CGGlyph g=CGFontGetGlyphWithGlyphName(f,CFSTR("A"));if(!f||!g){failures++;return;}CGContextSetFont(c,f);CGContextSetFontSize(c,20);CGContextSetTextPosition(c,4,22);CGContextShowGlyphs(c,&g,1);CGFontRelease(f);}
 else if(path==5){CGPatternCallbacks cb={0,pattern,NULL};CGPatternRef p=CGPatternCreate(NULL,CGRectMake(0,0,4,4),CGAffineTransformIdentity,4,4,kCGPatternTilingNoDistortion,true,&cb);CGColorSpaceRef cs=CGColorSpaceCreatePattern(NULL);CGFloat a=1;CGContextSetFillColorSpace(c,cs);CGContextSetFillPattern(c,p,&a);CGContextFillRect(c,CGRectMake(2,2,26,26));CGColorSpaceRelease(cs);CGPatternRelease(p);}
 else if(path==6||path==7){CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();CGFloat domain[]={0,1},range[]={0,1,0,1,0,1,0,1};CGFunctionCallbacks cb={0,shade,NULL};CGFunctionRef f=CGFunctionCreate(NULL,1,domain,4,range,&cb);CGShadingRef s=path==6?CGShadingCreateAxial(cs,CGPointMake(3,0),CGPointMake(27,0),f,false,false):CGShadingCreateRadial(cs,CGPointMake(12,12),1,CGPointMake(16,16),14,f,false,false);CGContextDrawShading(c,s);CGShadingRelease(s);CGFunctionRelease(f);CGColorSpaceRelease(cs);}
 else if(path==8||path==9){CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();unsigned char data[]={143,71,36,179,143,71,36,179,143,71,36,179,143,71,36,179};CGDataProviderRef dp=CGDataProviderCreateWithData(NULL,data,sizeof(data),NULL);CGImageRef im=CGImageCreate(2,2,8,32,8,cs,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big,dp,NULL,false,kCGRenderingIntentDefault);CGContextSetInterpolationQuality(c,path==8?kCGInterpolationNone:kCGInterpolationLow);CGContextDrawImage(c,CGRectMake(2,2,26,26),im);CGImageRelease(im);CGDataProviderRelease(dp);CGColorSpaceRelease(cs);}
 else if(path==10){CGLayerRef l=CGLayerCreateWithContext(c,CGSizeMake(W,H),NULL);CGContextRef lc=CGLayerGetContext(l);CGContextSetRGBFillColor(lc,.8,.4,.2,.7);CGContextFillRect(lc,CGRectMake(2,2,26,26));CGContextDrawLayerInRect(c,CGRectMake(0,0,W,H),l);CGLayerRelease(l);}
 else if(path==11){CGContextBeginTransparencyLayer(c,NULL);CGContextFillRect(c,CGRectMake(2,2,26,26));CGContextEndTransparencyLayer(c);}
}
static CGContextRef context(unsigned char *bytes,bool floating){
 memset(bytes,0xa7,ROW*H);for(int y=0;y<H;y++)memset(bytes+y*ROW,0,W*(floating?16:4));
 CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();CGContextRef c=CGBitmapContextCreate(bytes,W,H,floating?32:8,ROW,cs,(floating?kCGBitmapFloatComponents:0)|kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedLast);CGColorSpaceRelease(cs);return c;
}
/* 0 none; 1 integral rectangle; 2 antialiased ellipse path, which cannot be reduced to a pixel rectangle. */
static void clipTo(CGContextRef c,int clip){
 if(clip==1)CGContextClipToRect(c,CGRectMake(6,5,19,20));
 else if(clip==2){CGContextAddEllipseInRect(c,CGRectMake(1.3,1.6,29.4,28.7));CGContextClip(c);}
}
int main(int argc,char **argv){@autoreleasepool{
 bool alphaOne=argc==2&&!strcmp(argv[1],"alpha-one");
 const char *clips[]={"none","integral","antialiased"};
 const char *names[]={"rgb-fill","gray-ellipse","stroke","even-odd-fill","glyph","pattern","axial","radial","image-nearest","image-bilinear","layer","transparency-layer"};
 /* Out of range is GUESS-grade (rung 6): clamp to [0,1], NaN draws nothing. */
 double alphas[]={0,.35,.9995,1,2,-1,NAN},expected[]={0,.35,.9995,1,1,0,0};unsigned checks=0;
 for(int floating=0;floating<2;floating++)for(int clip=0;clip<3;clip++)for(int path=0;path<12;path++){
  unsigned char base[ROW*H],actual[ROW*H];CGContextRef c=context(base,floating);if(!c){puts("FAIL bitmap context creation");return 1;}
  clipTo(c,clip);draw(c,path);CGContextRelease(c);unsigned prior=failures;bool ink=false;
  for(unsigned ai=alphaOne?3:0;ai<(alphaOne?4:sizeof(alphas)/sizeof(*alphas));ai++){
   c=context(actual,floating);clipTo(c,clip);CGContextSetAlpha(c,alphas[ai]);draw(c,path);CGContextRelease(c);
   for(int y=0;y<H;y++){
    for(int x=0;x<W;x++)for(int ch=0;ch<4;ch++){
     double b,v;if(floating){float bf,vf;memcpy(&bf,base+y*ROW+x*16+ch*4,4);memcpy(&vf,actual+y*ROW+x*16+ch*4,4);b=bf;v=vf;}else{b=base[y*ROW+x*4+ch];v=actual[y*ROW+x*4+ch];}
     ink|=b>0;checks++;if(!isfinite(v)||fabs(v-b*expected[ai])>(floating?2e-6:2.0))failures++;
    }
    for(int k=W*(floating?16:4);k<ROW;k++)if(actual[y*ROW+k]!=0xa7)failures++;
   }
   if(expected[ai]==1&&memcmp(base,actual,sizeof(base)))failures++;
  }
  unsigned long long hash=14695981039346656037ull;for(unsigned i=0;i<sizeof(base);i++){hash^=base[i];hash*=1099511628211ull;}
  printf("PIXELS alpha-one path=%s float=%d clip=%s hash=%016llx\n",names[path],floating,clips[clip],hash);
  if(!ink)failures++;printf("%s path=%s float=%d clip=%s failures=%u\n",failures==prior?"PASS":"FAIL",names[path],floating,clips[clip],failures-prior);
 }
 printf("RESULT global-alpha checks=%u failures=%u\n",checks,failures);return failures!=0;
}}
