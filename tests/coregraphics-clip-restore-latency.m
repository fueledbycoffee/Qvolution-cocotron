#import <AppKit/AppKit.h>
#include <stdio.h>
#include <sys/time.h>
static double nowMS(void){struct timeval t;gettimeofday(&t,NULL);return t.tv_sec*1000.0+t.tv_usec/1000.0;}
static double begin(const char *phase,unsigned clips,unsigned round){printf("BEGIN phase=%s clips=%u round=%u\n",phase,clips,round);return nowMS();}
static void end(const char *phase,unsigned clips,unsigned round,double start){printf("TIME phase=%s clips=%u round=%u ms=%.3f\n",phase,clips,round,nowMS()-start);}
int main(void){@autoreleasepool{
 setbuf(stdout,NULL);puts("ENTER source-owned public CGContext clip/restore timing, fixed 640x480 RGBA");
 CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();unsigned failures=0;
 for(unsigned clips=0;clips<=3;clips++){
  CGContextRef c=CGBitmapContextCreate(NULL,640,480,8,640*4,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
  if(!c)return 2;
  for(unsigned i=0;i<clips;i++){double t=begin("add_rect_clip",clips,i);CGContextClipToRect(c,CGRectMake(10+i*5,10+i*5,600-i*10,440-i*10));end("add_rect_clip",clips,i,t);}
  for(unsigned i=0;i<7;i++){
   double t=begin("save_restore_unchanged_clip",clips,i);CGContextSaveGState(c);CGContextRestoreGState(c);end("save_restore_unchanged_clip",clips,i,t);
   t=begin("fill_with_clip",clips,i);CGContextSetRGBFillColor(c,1,0,0,1);CGContextFillRect(c,CGRectMake(0,0,640,480));end("fill_with_clip",clips,i,t);
  }
  CGContextSaveGState(c);CGContextClipToRect(c,CGRectMake(100,100,80,80));CGContextSetRGBFillColor(c,0,1,0,1);CGContextFillRect(c,CGRectMake(0,0,640,480));CGContextRestoreGState(c);
  CGContextSetRGBFillColor(c,0,0,1,1);CGContextFillRect(c,CGRectMake(30,30,4,4));
  unsigned char *p=CGBitmapContextGetData(c);size_t row=CGBitmapContextGetBytesPerRow(c);
  BOOL blue=p[31*row+31*4]==0 && p[31*row+31*4+1]==0 && p[31*row+31*4+2]==255 && p[31*row+31*4+3]==255;
  if(!blue){failures++;fprintf(stderr,"FAIL: restore must remove temporary smaller clip clips=%u\n",clips);}
  CGContextRelease(c);
 }
 CGColorSpaceRelease(space);printf("RESULT failures=%u\n",failures);return failures?1:0;
}}
