/* Raw SDR component compositing controls, independent of HLG/profile/display policy. */
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Onyx2D/O2BitmapContext.h>
#import <Onyx2D/O2Font_freetype.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#define REQUIRE(c,m) do { if(!(c)){printf("FAIL %s\n",m);return 1;} } while(0)
static BOOL closePixel(const unsigned char *data,size_t row,unsigned x,unsigned y,const double expected[4]) { float actual[4];memcpy(actual,data+y*row+x*16,16);for(unsigned c=0;c<4;c++)if(fabs(actual[c]-expected[c])>1e-6)return NO;return YES; }
static BOOL padding(const unsigned char *data,size_t row,unsigned width,unsigned height) { for(unsigned y=0;y<height;y++)for(size_t i=width*16;i<row;i++)if(data[y*row+i]!=0xa7)return NO;return YES; }
int main(int argc,char **argv) { @autoreleasepool {
 setbuf(stdout,NULL);REQUIRE(argc==2,"mode solid|blend|image|text");
 enum {width=32,height=32,row=width*16+16};unsigned char data[row*height];memset(data,0xa7,sizeof(data));for(unsigned y=0;y<height;y++)memset(data+y*row,0,width*16);
 CGColorSpaceRef space=CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearSRGB);REQUIRE(space,"existing SDR space");
 CGContextRef context=CGBitmapContextCreate(data,width,height,32,row,space,kCGBitmapFloatComponents|kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedLast);
 REQUIRE(context&&[(O2BitmapContext *)context surface],"real float backing prerequisite");
 REQUIRE(CGBitmapContextGetBitsPerPixel(context)==128,"actual float packing");CGContextSetShouldAntialias(context,false);
 if(!strcmp(argv[1],"solid")) {
  CGContextSetRGBFillColor(context,.125,.25,.5,1);CGContextFillRect(context,CGRectMake(0,0,width,height));const double expected[]={.125,.25,.5,1};REQUIRE(closePixel(data,row,8,8,expected),"solid fill retains float components beyond 8bit quantization");
 } else if(!strcmp(argv[1],"blend")) {
  CGContextSetRGBFillColor(context,.25,.5,.75,1);CGContextFillRect(context,CGRectMake(0,0,width,height));CGContextSetRGBFillColor(context,.75,.25,.5,.5);CGContextFillRect(context,CGRectMake(0,0,width,height));const double expected[]={.5,.375,.625,1};REQUIRE(closePixel(data,row,8,8,expected),"source over uses float premultiplied components");
 } else if(!strcmp(argv[1],"image")) {
  float samples[16]={.1875,.0625,.125,.25,.1875,.0625,.125,.25,.1875,.0625,.125,.25,.1875,.0625,.125,.25};
  CGDataProviderRef provider=CGDataProviderCreateWithData(NULL,samples,sizeof(samples),NULL);CGImageRef image=CGImageCreate(2,2,32,128,32,space,kCGBitmapFloatComponents|kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedLast,provider,NULL,false,kCGRenderingIntentDefault);REQUIRE(image,"float image prerequisite");
  CGContextSetBlendMode(context,kCGBlendModeCopy);CGContextSetInterpolationQuality(context,kCGInterpolationNone);CGContextDrawImage(context,CGRectMake(0,0,width,height),image);const double expected[]={.1875,.0625,.125,.25};REQUIRE(closePixel(data,row,8,8,expected),"float image copy avoids 8bit staging");CGImageRelease(image);CGDataProviderRelease(provider);
 } else if(!strcmp(argv[1],"text")) {
  CGFontRef font=CGFontCreateWithFontName(CFSTR("DejaVuSans"));REQUIRE(font,"explicit open font");CGGlyph glyph=CGFontGetGlyphWithGlyphName(font,CFSTR("A"));REQUIRE(glyph,"known glyph");CGContextSetFont(context,font);CGContextSetFontSize(context,14);CGContextSetTextPosition(context,2,14);CGContextSetRGBFillColor(context,.125,.25,.5,.5);CGContextShowGlyphs(context,&glyph,1);
  O2FreeTypeCachedGlyph *bitmap=[(O2Font_freetype *)font rasterizeGlyph:glyph pointSize:14 phaseX:0 phaseY:0];REQUIRE(bitmap&&bitmap->bitmap.num_grays==256,"actual open-font gray coverage reference");BOOL sawFraction=NO,sawInk=NO;
  for(unsigned y=0;y<bitmap->bitmap.rows;y++)for(unsigned x=0;x<bitmap->bitmap.width;x++) { int px=2+bitmap->left+x,py=height-14-bitmap->top+y;if(px<0||py<0||px>=width||py>=height)continue;int pitch=bitmap->bitmap.pitch;unsigned offset=pitch>=0?y*pitch:(bitmap->bitmap.rows-1-y)*(-pitch);unsigned coverage=bitmap->bitmap.buffer[offset+x];double factor=coverage/255.0;double expected[]={.0625*factor,.125*factor,.25*factor,.5*factor};REQUIRE(closePixel(data,row,px,py,expected),"glyph float coverage matches independent mask-to-source-over equation");sawInk|=coverage>0;sawFraction|=coverage>0&&coverage<255; }
  REQUIRE(sawInk&&sawFraction,"real glyph exercises visible fractional coverage");CGFontRelease(font);
 } else return 2;
 REQUIRE(padding(data,row,width,height),"all drawing preserves padded rows");CGContextRelease(context);CGColorSpaceRelease(space);puts("FLOAT_RAW_DRAW_PASS_NO_PROFILE_HDR_DISPLAY_CLAIM");return 0;
} }
