/* Public clip construction only; independent area/sample and blend pixel oracles. */
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Onyx2D/O2Font_freetype.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#define REQUIRE(c,m) do {if(!(c)){printf("FAIL %s\n",m);return 1;}} while(0)
enum {W=16,H=16,MW=12};
static double triangle(int x,int y) {if(x<2||y<2||x>=14||y>=14)return 0;return x+y<15?1:x+y==15?.5:0;}
static unsigned sample(int x,int y) {int dx=x-5,dy=y-5;if(dx*dx+dy*dy>29)return 255;return (unsigned[]){0,64,128,255}[(x+2*y)%4];}
static double maskAt(int x,int y,BOOL inverse,BOOL decoded,int dx) {x-=2+dx;y-=2;if(x<0||y<0||x>=MW||y>=MW)return 0;double s=sample(x,MW-1-y)/255.;if(decoded)s=1-s;return inverse?1-s:s;}
static void blend(double d[4],double coverage,BOOL copy) {const double s[]={.0625,.125,.25,.5};for(int c=0;c<4;c++)d[c]+=(s[c]-(copy?d[c]:d[c]*.5))*coverage;}
static void clipTriangle(CGContextRef c) {CGContextBeginPath(c);CGContextMoveToPoint(c,2,2);CGContextAddLineToPoint(c,14,2);CGContextAddLineToPoint(c,2,14);CGContextClosePath(c);CGContextClip(c);}
int main(int argc,char **argv) {@autoreleasepool {
 setbuf(stdout,NULL);REQUIRE(argc==2||argc==3,"mode [byte]");const char *mode=argv[1];BOOL bytes=argc==3;int stride=W*(bytes?4:16)+16;unsigned char raw[H*stride];CGColorSpaceRef rgb=CGColorSpaceCreateDeviceRGB(),gray=CGColorSpaceCreateDeviceGray();REQUIRE(rgb&&gray,"color spaces");
 for(int copy=0;copy<2;copy++) {
 memset(raw,0xa7,sizeof(raw));for(int y=0;y<H;y++)for(int x=0;x<W;x++){if(bytes){unsigned char d[]={51,77,102,204};memcpy(raw+y*stride+x*4,d,4);}else{float d[]={.2,.3,.4,.8};memcpy(raw+y*stride+x*16,d,16);}}
 CGContextRef c=CGBitmapContextCreate(raw,W,H,bytes?8:32,stride,rgb,(bytes?0:kCGBitmapFloatComponents)|(bytes?kCGBitmapByteOrder32Big:kCGBitmapByteOrder32Little)|kCGImageAlphaPremultipliedLast);REQUIRE(c,"actual public bitmap context");CGContextTranslateCTM(c,0,H);CGContextScaleCTM(c,1,-1);CGContextSetShouldAntialias(c,true);CGContextSetInterpolationQuality(c,kCGInterpolationNone);CGContextSetBlendMode(c,copy?kCGBlendModeCopy:kCGBlendModeNormal);CGContextSetRGBFillColor(c,.125,.25,.5,.5);
 unsigned char samples[MW*MW];for(int y=0;y<MW;y++)for(int x=0;x<MW;x++)samples[y*MW+x]=sample(x,y);CGDataProviderRef p=CGDataProviderCreateWithData(NULL,samples,sizeof(samples),NULL);BOOL inverse=!strcmp(mode,"image-mask")||!strcmp(mode,"decode");CGFloat decode[]={1,0};CGImageRef mask=inverse?CGImageMaskCreate(MW,MW,8,8,MW,p,!strcmp(mode,"decode")?decode:NULL,false):CGImageCreate(MW,MW,8,8,MW,gray,kCGImageAlphaNone,p,NULL,false,kCGRenderingIntentDefault);REQUIRE(mask,"actual public gray image/mask");
 BOOL ring=!strcmp(mode,"nonzero")||!strcmp(mode,"evenodd"),masked=!strcmp(mode,"mask")||inverse||!strcmp(mode,"transform")||!strcmp(mode,"accumulate")||!strcmp(mode,"restore")||!strcmp(mode,"reset")||!strcmp(mode,"image")||!strcmp(mode,"layer")||!strcmp(mode,"nested-layer")||!strcmp(mode,"text");BOOL tri=!strcmp(mode,"triangle")||!strcmp(mode,"accumulate");REQUIRE(ring||masked||tri,"known mode");
 if(ring){CGContextBeginPath(c);CGContextAddRect(c,CGRectMake(2,2,12,12));CGContextAddRect(c,CGRectMake(5,5,6,6));if(!strcmp(mode,"evenodd"))CGContextEOClip(c);else CGContextClip(c);}
 if(tri)clipTriangle(c);
 if(masked){if(!strcmp(mode,"transform"))CGContextTranslateCTM(c,1,0);CGContextClipToMask(c,CGRectMake(2,2,MW,MW),mask);if(!strcmp(mode,"transform"))CGContextTranslateCTM(c,-1,0);}
 if(!strcmp(mode,"restore")){CGContextSaveGState(c);clipTriangle(c);CGContextFillRect(c,CGRectMake(0,0,W,H));CGContextRestoreGState(c);}
 if(!strcmp(mode,"reset"))CGContextResetClip(c);
 CGFontRef font=NULL;O2FreeTypeCachedGlyph *glyphBitmap=NULL;
 if(!strcmp(mode,"text")){font=CGFontCreateWithFontName(CFSTR("DejaVuSans"));CGGlyph glyph=CGFontGetGlyphWithGlyphName(font,CFSTR("A"));REQUIRE(font&&glyph,"actual open font");CGContextSetFont(c,font);CGContextSetFontSize(c,10);CGContextSetTextPosition(c,3,12);CGContextShowGlyphs(c,&glyph,1);glyphBitmap=[(O2Font_freetype *)font rasterizeGlyph:glyph pointSize:10 phaseX:0 phaseY:0];REQUIRE(glyphBitmap,"independent actual glyph coverage");}
 else if(!strcmp(mode,"image")){float color[]={.0625,.125,.25,.5};CGDataProviderRef ip=CGDataProviderCreateWithData(NULL,color,sizeof(color),NULL);CGImageRef image=CGImageCreate(1,1,32,128,16,rgb,kCGBitmapFloatComponents|kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedLast,ip,NULL,false,kCGRenderingIntentDefault);REQUIRE(image,"actual float raster image");CGContextDrawImage(c,CGRectMake(0,0,W,H),image);CGImageRelease(image);CGDataProviderRelease(ip);}
 else if(!strcmp(mode,"layer")||!strcmp(mode,"nested-layer")){CGContextBeginTransparencyLayer(c,NULL);if(!strcmp(mode,"nested-layer"))CGContextBeginTransparencyLayer(c,NULL);CGContextFillRect(c,CGRectMake(0,0,W,H));if(!strcmp(mode,"nested-layer"))CGContextEndTransparencyLayer(c);CGContextEndTransparencyLayer(c);}
 else CGContextFillRect(c,CGRectMake(0,0,W,H));
 BOOL zero=NO,fraction=NO,full=NO,ink=NO;double largest=0;
 for(int y=0;y<H;y++)for(int x=0;x<W;x++) {double cov=ring?(x>=2&&x<14&&y>=2&&y<14&&(!strcmp(mode,"nonzero")||!(x>=5&&x<11&&y>=5&&y<11))):tri?triangle(x,y):1;if(masked)cov*=maskAt(x,y,inverse,!strcmp(mode,"decode"),!strcmp(mode,"transform"));if(!strcmp(mode,"reset"))cov=1;
 if(glyphBitmap){int gx=x-(3+glyphBitmap->left),gy=y-(12-glyphBitmap->top);unsigned g=0;if(gx>=0&&gy>=0&&gx<glyphBitmap->bitmap.width&&gy<glyphBitmap->bitmap.rows){int pitch=glyphBitmap->bitmap.pitch;g=glyphBitmap->bitmap.buffer[(pitch>=0?gy: glyphBitmap->bitmap.rows-1-gy)*abs(pitch)+gx];}cov*=g/255.;}
 double d[]={bytes?51/255.:.2,bytes?77/255.:.3,bytes?102/255.:.4,bytes?204/255.:.8};if(!strcmp(mode,"restore"))blend(d,maskAt(x,y,NO,NO,0)*triangle(x,y),copy);blend(d,cov,copy);float f[4];if(!bytes)memcpy(f,raw+y*stride+x*16,16);for(int k=0;k<4;k++){double got=bytes?raw[y*stride+x*4+k]/255.:f[k];largest=fmax(largest,fabs(got-d[k]));}zero|=cov==0;fraction|=cov>0&&cov<1;full|=cov==1;ink|=cov>0;}
 printf("mode=%s byte=%d copy=%d largest_error=%.9f\n",mode,bytes,copy,largest);REQUIRE(largest<(bytes?.018:.008),"every pixel matches independent coverage and premultiplied blend equation");REQUIRE(ink,"visible covered output");if(strcmp(mode,"reset"))REQUIRE(zero,"outside clip remains unchanged");if(!ring&&strcmp(mode,"reset"))REQUIRE(fraction,"fractional coverage actually exercised");if(!glyphBitmap&&!ring&&strcmp(mode,"reset")&&strcmp(mode,"accumulate"))REQUIRE(full,"full coverage actually exercised");for(int y=0;y<H;y++)for(int i=W*(bytes?4:16);i<stride;i++)REQUIRE(raw[y*stride+i]==0xa7,"row padding unchanged");if(font)CGFontRelease(font);CGImageRelease(mask);CGDataProviderRelease(p);CGContextRelease(c);
 }
 CGColorSpaceRelease(rgb);CGColorSpaceRelease(gray);puts("PUBLIC_CLIPPING_PIXEL_ORACLE_PASS");return 0;
}}
