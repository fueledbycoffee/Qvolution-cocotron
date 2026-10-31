/* Additional frozen geometric intersection controls; no clip internals. */
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <math.h>
#include <string.h>
#define REQUIRE(c,m) do {if(!(c)){printf("FAIL %s\n",m);return 1;}} while(0)
enum {W=16,H=16,ROW=W*16+16};
static int cut(CGPoint *out,const CGPoint *p,int n,double nx,double ny,double d){int count=0;for(int i=0;i<n;i++){CGPoint a=p[i],b=p[(i+1)%n];double da=nx*a.x+ny*a.y-d,db=nx*b.x+ny*b.y-d;if(da<=0)out[count++]=a;if((da<0&&db>0)||(da>0&&db<0)){double t=da/(da-db);out[count++]=CGPointMake(a.x+t*(b.x-a.x),a.y+t*(b.y-a.y));}}return count;}
static double area(int x,int y,BOOL overlap){CGPoint a[16]={{x,y},{x+1,y},{x+1,y+1},{x,y+1}},b[16];int n=4;double planes[][3]={{-1,0,-2},{0,-1,-2},{1,1,16},{1,0,14},{-1,1,-.5}};for(int k=0;k<(overlap?5:3);k++){n=cut(b,a,n,planes[k][0],planes[k][1],planes[k][2]);memcpy(a,b,n*sizeof(*a));}double result=0;for(int i=0;i<n;i++)result+=a[i].x*a[(i+1)%n].y-a[(i+1)%n].x*a[i].y;return fabs(result)*.5;}
static void triangle(CGContextRef c){CGContextBeginPath(c);CGContextMoveToPoint(c,2,2);CGContextAddLineToPoint(c,14,2);CGContextAddLineToPoint(c,2,14);CGContextClosePath(c);}
static void second(CGContextRef c){CGContextBeginPath(c);CGContextMoveToPoint(c,2.5,2);CGContextAddLineToPoint(c,14,2);CGContextAddLineToPoint(c,14,13.5);CGContextClosePath(c);}
static void draw(CGContextRef c){CGContextSetRGBFillColor(c,.125,.25,.5,.5);CGContextFillRect(c,CGRectMake(0,0,W,H));}
int main(int argc,char **argv){@autoreleasepool{
 setbuf(stdout,NULL);REQUIRE(argc==2,"layer-same|nested-layer-same|layer-overlap|layer-opposite");const char *mode=argv[1];BOOL repeated=NO,overlap=!strcmp(mode,"layer-overlap"),same=NO,opposite=!strcmp(mode,"layer-opposite"),layer=YES,aa=NO,nested=!strcmp(mode,"nested-layer-same");REQUIRE(!strcmp(mode,"layer-same")||nested||overlap||opposite,"known layer mode");unsigned char raw[H*ROW],baseline[H*ROW];CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
 for(int copy=0;copy<2;copy++)for(int restore=0;restore<(aa?2:1);restore++){
 memset(raw,0xa7,sizeof(raw));for(int y=0;y<H;y++)for(int x=0;x<W;x++){float d[]={.2,.3,.4,.8};memcpy(raw+y*ROW+x*16,d,16);}CGContextRef c=CGBitmapContextCreate(raw,W,H,32,ROW,space,kCGBitmapFloatComponents|kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedLast);REQUIRE(c,"public float context");CGContextTranslateCTM(c,0,H);CGContextScaleCTM(c,1,-1);CGContextSetShouldAntialias(c,!aa);CGContextSetBlendMode(c,copy?kCGBlendModeCopy:kCGBlendModeNormal);triangle(c);CGContextClip(c);
 if(repeated){triangle(c);CGContextClip(c);}if(overlap){second(c);CGContextEOClip(c);}if(aa){CGContextSetShouldAntialias(c,true);if(restore){CGContextSaveGState(c);CGContextRestoreGState(c);}}
 if(layer){CGContextBeginTransparencyLayer(c,NULL);if(nested)CGContextBeginTransparencyLayer(c,NULL);if(overlap)second(c);else if(opposite){CGContextBeginPath(c);CGContextMoveToPoint(c,14,2);CGContextAddLineToPoint(c,14,14);CGContextAddLineToPoint(c,2,14);CGContextClosePath(c);}else triangle(c);CGContextClip(c);draw(c);if(nested)CGContextEndTransparencyLayer(c);CGContextEndTransparencyLayer(c);}else if(same||opposite){CGContextSetRGBFillColor(c,.125,.25,.5,.5);if(same)triangle(c);else{CGContextBeginPath(c);CGContextMoveToPoint(c,14,2);CGContextAddLineToPoint(c,14,14);CGContextAddLineToPoint(c,2,14);CGContextClosePath(c);}CGContextFillPath(c);}else draw(c);
 double largest=0;for(int y=0;y<H;y++)for(int x=0;x<W;x++){double cov=area(x,y,overlap),s[]={.0625,.125,.25,.5},d[]={.2,.3,.4,.8};if(opposite)cov=0;if(aa)continue;for(int k=0;k<4;k++)d[k]=copy?d[k]*(1-area(x,y,NO))+s[k]*cov:d[k]+(s[k]-d[k]*s[3])*cov;float got[4];memcpy(got,raw+y*ROW+x*16,16);for(int k=0;k<4;k++)largest=fmax(largest,fabs(got[k]-d[k]));}
 if(aa){if(!restore)memcpy(baseline,raw,sizeof(raw));else REQUIRE(!memcmp(baseline,raw,sizeof(raw)),"existing clip unchanged by later AA plus no-op save/restore");}else{printf("mode=%s copy=%d largest_error=%.9f\n",mode,copy,largest);REQUIRE(largest<.008,"independent polygon intersection area and blend equation");}for(int y=0;y<H;y++)for(int i=W*16;i<ROW;i++)REQUIRE(raw[y*ROW+i]==0xa7,"padding preserved");CGContextRelease(c);
 }CGColorSpaceRelease(space);puts("PUBLIC_CLIPPING_GEOMETRY_PIXEL_ORACLE_PASS");return 0;
}}
