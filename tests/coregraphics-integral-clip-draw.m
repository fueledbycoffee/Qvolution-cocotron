#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
enum {W=32,H=26,MAXROW=W*16+16};
static unsigned failures;
static uint64_t digest(const unsigned char *p,size_t n){uint64_t h=UINT64_C(1469598103934665603);while(n--){h^=*p++;h*=UINT64_C(1099511628211);}return h;}
static void render(unsigned char *raw,BOOL bytes,BOOL clipped,BOOL copy,int drawing){
 int bpp=bytes?4:16,row=W*bpp+16;memset(raw,0xa7,H*row);
 for(int y=0;y<H;y++)for(int x=0;x<W;x++){if(bytes){unsigned char d[]={51,77,102,204};memcpy(raw+y*row+x*bpp,d,bpp);}else{float d[]={.2,.3,.4,.8};memcpy(raw+y*row+x*bpp,d,bpp);}}
 CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();CGContextRef c=CGBitmapContextCreate(raw,W,H,bytes?8:32,row,space,(bytes?kCGBitmapByteOrder32Big:kCGBitmapByteOrder32Little)|(bytes?0:kCGBitmapFloatComponents)|kCGImageAlphaPremultipliedLast);CGColorSpaceRelease(space);
 if(!c){failures++;return;}CGContextTranslateCTM(c,0,H);CGContextScaleCTM(c,1,-1);CGContextSetShouldAntialias(c,true);CGContextSetBlendMode(c,copy?kCGBlendModeCopy:kCGBlendModeNormal);
 if(clipped)CGContextClipToRect(c,CGRectMake(2,2,28,22));
 CGContextSetRGBFillColor(c,.125,.25,.5,.5);CGContextSetRGBStrokeColor(c,.125,.25,.5,.5);
 if(drawing==0){CGContextBeginPath(c);CGContextMoveToPoint(c,6.25,5.125);CGContextAddLineToPoint(c,26.75,9.375);CGContextAddLineToPoint(c,11.625,22.25);CGContextClosePath(c);CGContextFillPath(c);}
 else if(drawing==1){CGContextSetLineWidth(c,1.375);CGContextBeginPath(c);CGContextMoveToPoint(c,4.25,5.625);CGContextAddLineToPoint(c,26.75,20.125);CGContextStrokePath(c);}
 else{CGFontRef font=CGFontCreateWithFontName(CFSTR("DejaVuSans"));CGGlyph g=CGFontGetGlyphWithGlyphName(font,CFSTR("A"));if(!font||!g)failures++;CGContextSetFont(c,font);CGContextSetFontSize(c,17);CGContextSetTextPosition(c,6,21);CGContextShowGlyphs(c,&g,1);CGFontRelease(font);}
 CGContextRelease(c);
}
int main(void){@autoreleasepool{
 setbuf(stdout,NULL);unsigned char a[H*MAXROW],b[H*MAXROW];
 for(int bytes=0;bytes<2;bytes++)for(int copy=0;copy<2;copy++)for(int drawing=0;drawing<3;drawing++){
  int bpp=bytes?4:16,row=W*bpp+16;render(a,bytes,NO,copy,drawing);render(b,bytes,YES,copy,drawing);BOOL ink=NO;double largest=0;
  for(int y=0;y<H;y++){for(int x=0;x<W;x++){unsigned char background[16];if(bytes){unsigned char d[]={51,77,102,204};memcpy(background,d,4);}else{float d[]={.2,.3,.4,.8};memcpy(background,d,16);}unsigned char *p=b+y*row+x*bpp;ink|=memcmp(p,background,bpp)!=0;
   if((x<2||x>=30||y<2||y>=24)&&memcmp(p,background,bpp)){failures++;fprintf(stderr,"FAIL outside integral clip\n");}
   if(x>=2&&x<30&&y>=2&&y<24){for(int k=0;k<4;k++){double v0,v1;if(bytes){v0=a[y*row+x*bpp+k]/255.;v1=p[k]/255.;}else{float f0,f1;memcpy(&f0,a+y*row+x*bpp+k*4,4);memcpy(&f1,p+k*4,4);v0=f0;v1=f1;}largest=fmax(largest,fabs(v0-v1));}}
  }for(int k=W*bpp;k<row;k++)if(a[y*row+k]!=0xa7||b[y*row+k]!=0xa7){failures++;fprintf(stderr,"FAIL padding\n");}}
  if(!ink){failures++;fprintf(stderr,"FAIL no actual ink\n");}
  printf("PIXELS bytes=%d copy=%d drawing=%d unclipped=%016llx clipped=%016llx interior_maxdiff=%.9g\n",bytes,copy,drawing,(unsigned long long)digest(a,H*row),(unsigned long long)digest(b,H*row),largest);
 }
 printf("RESULT failures=%u\n",failures);return failures?1:0;
}}
