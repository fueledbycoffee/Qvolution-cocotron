/* Own internal clip-surface injection; does not claim public clip construction. */
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Onyx2D/O2Context_builtin_FT.h>
#import <Onyx2D/O2Font_freetype.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#define REQUIRE(c,m) do {if(!(c)){printf("FAIL %s\n",m);return 1;}} while(0)
@interface FloatClipFixtureContext : O2Context_builtin_FT
- (void) fixtureClipSurface:(O2Surface *)surface;
@end
@implementation FloatClipFixtureContext
- (void) fixtureClipSurface:(O2Surface *)surface {[_clipContext release];_clipContext=[[O2Context_builtin alloc] initWithSurface:surface flipped:NO];}
@end
int main(void) {@autoreleasepool {
 setbuf(stdout,NULL);enum{w=32,h=32,stride=w*16+16};unsigned char raw[h*stride],maskBytes[h*stride];memset(raw,0xa7,sizeof(raw));memset(maskBytes,0xa7,sizeof(maskBytes));
 for(int y=0;y<h;y++)for(int x=0;x<w;x++){float d[4]={.2,.3,.4,.8};float alpha=((x-12)*(x-12)+(y-15)*(y-15)<49)?(float[]){0,.1255,.5,1}[(x+y)%4]:0;float mask[4]={.9,.1,.2,alpha};memcpy(raw+y*stride+x*16,d,16);memcpy(maskBytes+y*stride+x*16,mask,16);}
 CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();O2Surface *surface=[[O2Surface alloc] initWithBytes:raw width:w height:h bitsPerComponent:32 bytesPerRow:stride colorSpace:(O2ColorSpaceRef)space bitmapInfo:kO2BitmapFloatComponents|kO2BitmapByteOrder32Little|kO2ImageAlphaPremultipliedLast];O2Surface *mask=[[O2Surface alloc] initWithBytes:maskBytes width:w height:h bitsPerComponent:32 bytesPerRow:stride colorSpace:(O2ColorSpaceRef)space bitmapInfo:kO2BitmapFloatComponents|kO2BitmapByteOrder32Little|kO2ImageAlphaPremultipliedLast];FloatClipFixtureContext *context=[[FloatClipFixtureContext alloc] initWithSurface:surface flipped:NO];REQUIRE(context&&mask,"real float context and clip surface");[context fixtureClipSurface:mask];
 CGFontRef font=CGFontCreateWithFontName(CFSTR("DejaVuSans"));CGGlyph glyph=CGFontGetGlyphWithGlyphName(font,CFSTR("A"));REQUIRE(font&&glyph,"known actual open font glyph");CGContextSetFont((CGContextRef)context,font);CGContextSetFontSize((CGContextRef)context,14);CGContextSetTextPosition((CGContextRef)context,2,14);CGContextSetRGBFillColor((CGContextRef)context,.125,.25,.5,.5);CGContextShowGlyphs((CGContextRef)context,&glyph,1);
 O2FreeTypeCachedGlyph *cached=[(O2Font_freetype *)font rasterizeGlyph:glyph pointSize:14 phaseX:0 phaseY:0];REQUIRE(cached,"actual cached gray coverage");BOOL fractional=NO,ink=NO;
 for(int y=0;y<h;y++)for(int x=0;x<w;x++){int bx=x-(2+cached->left),by=y-(h-14-cached->top);unsigned coverage=0;if(bx>=0&&by>=0&&bx<cached->bitmap.width&&by<cached->bitmap.rows){int pitch=cached->bitmap.pitch;coverage=cached->bitmap.buffer[(pitch>=0?by:cached->bitmap.rows-1-by)*abs(pitch)+bx];}float m[4],actual[4];memcpy(m,maskBytes+y*stride+x*16,16);memcpy(actual,raw+y*stride+x*16,16);float f=coverage/255.0f*m[3];float want[]={.2f+(.0625f-.2f*.5f)*f,.3f+(.125f-.3f*.5f)*f,.4f+(.25f-.4f*.5f)*f,.8f+(.5f-.8f*.5f)*f};for(int c=0;c<4;c++)REQUIRE(fabsf(actual[c]-want[c])<1e-6,"actual text equals independent glyph*clip*sourceover equation");fractional|=f>0&&f<1;ink|=f>0;}
 for(int y=0;y<h;y++)for(int i=w*16;i<stride;i++)REQUIRE(raw[y*stride+i]==0xa7&&maskBytes[y*stride+i]==0xa7,"row padding intact");REQUIRE(ink&&fractional,"nonzero fractional masked glyph pixels");CGFontRelease(font);[context release];[mask release];[surface release];CGColorSpaceRelease(space);puts("FLOAT_TEXT_INTERNAL_CLIP_PASS_NO_PUBLIC_CLIP_CLAIM");return 0;
}}
