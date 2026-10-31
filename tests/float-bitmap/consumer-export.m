/* Own raw component -> byte consumer compatibility. No profile/HDR claim. */
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Onyx2D/O2Image.h>
#import <Onyx2D/O2ImageDestination.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <dlfcn.h>
static O2ImageRef (*copyForExport)(O2ImageRef image);
#define REQUIRE(c,m) do {if(!(c)){printf("FAIL %s\n",m);return 1;}} while(0)
static CGImageRef make(CGColorSpaceRef space,void *data,size_t width,size_t height,size_t stride,size_t length,BOOL floating,BOOL big) {
 CGDataProviderRef provider=CGDataProviderCreateWithData(NULL,data,length,NULL);
 CGImageRef image=CGImageCreate(width,height,floating?32:8,floating?128:32,stride,space,(floating?kCGBitmapFloatComponents:0)|(big?kCGBitmapByteOrder32Big:kCGBitmapByteOrder32Little)|kCGImageAlphaPremultipliedLast,provider,NULL,false,kCGRenderingIntentDefault);
 CGDataProviderRelease(provider);return image;
}
static NSData *encoded(CGImageRef image,NSString *uti) {
 NSMutableData *data=[NSMutableData data];O2ImageDestinationRef dest=O2ImageDestinationCreateWithData((CFMutableDataRef)data,(CFStringRef)uti,1,NULL);
 if(!dest)return nil;O2ImageDestinationAddImage(dest,(O2Image *)image,NULL);BOOL result=O2ImageDestinationFinalize(dest);[dest release];return result?data:nil;
}
static NSData *pdf(CGImageRef image) {
 NSMutableData *data=[NSMutableData data];CGDataConsumerRef consumer=CGDataConsumerCreateWithCFData((CFMutableDataRef)data);CGRect box=CGRectMake(0,0,10,10);CGContextRef context=CGPDFContextCreate(consumer,&box,NULL);CGPDFContextBeginPage(context,NULL);if(image)CGContextDrawImage(context,box,image);CGPDFContextEndPage(context);CGPDFContextClose(context);CGContextRelease(context);CGDataConsumerRelease(consumer);return data;
}
typedef struct {int calls,releases;} WriterState;
static size_t rejectWrite(void *info,const void *bytes,size_t count) {(void)bytes;((WriterState *)info)->calls++;return count?count-1:0;}
static void releaseWriter(void *info) {((WriterState *)info)->releases++;}
static unsigned expected(float v) {return !(v>0)?0:v>=1?255:(unsigned)floor((double)v*255+.5);}
int main(int argc,char **argv) {@autoreleasepool {
 setbuf(stdout,NULL);copyForExport=dlsym(RTLD_DEFAULT,"O2ImageCreateCopyForByteExport");REQUIRE(argc==2,"copy|jpeg|tiff|png|pdf|nested|bitmask|stencil|shortwrite|reject");CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();REQUIRE(space,"device RGB");
 if(!strcmp(argv[1],"copy")) {
  REQUIRE(copyForExport!=NULL,"byte export copy implementation present");
  enum{w=300,h=2,stride=w*16+16};unsigned char raw[h*stride];memset(raw,0xa7,sizeof(raw));
  for(int big=0;big<2;big++){
   for(int y=0;y<h;y++)for(int x=0;x<w;x++)for(int c=0;c<4;c++) {float value=(float)((x+c+y)%13)/16; if(x==1&&c==0)value=NAN;if(x==2&&c==1)value=INFINITY;if(x==3&&c==2)value=-INFINITY;uint32_t word;memcpy(&word,&value,4);for(int b=0;b<4;b++)raw[y*stride+x*16+c*4+b]=(word>>(8*(big?3-b:b)))&255;}
   CGImageRef image=make(space,raw,w,h,stride,sizeof(raw),YES,big);REQUIRE(image,"backed float image");O2ImageRef copy=copyForExport((O2Image *)image);REQUIRE(copy&&copy!=(O2Image *)image,"actual converted owned image");REQUIRE(O2ImageGetBitsPerComponent(copy)==8&&O2ImageGetBitsPerPixel(copy)==32&&O2ImageGetAlphaInfo(copy)==kO2ImageAlphaPremultipliedLast,"converted packing preserves premultiplication");
   NSData *bytes=[copy directData];REQUIRE([bytes length]==w*h*4,"tight byte output");const unsigned char *p=[bytes bytes];for(int y=0;y<h;y++)for(int x=0;x<w;x++)for(int c=0;c<4;c++){float value=(float)((x+c+y)%13)/16;if(x==1&&c==0)value=NAN;if(x==2&&c==1)value=INFINITY;if(x==3&&c==2)value=-INFINITY;REQUIRE(p[(y*w+x)*4+c]==expected(value),"independent saturated rounded component oracle");}
   for(int y=0;y<h;y++)for(int i=w*16;i<stride;i++)REQUIRE(raw[y*stride+i]==0xa7,"source padding unchanged");O2ImageRelease(copy);CGImageRelease(image);
  }
 } else if(!strcmp(argv[1],"reject")) {
  REQUIRE(copyForExport!=NULL,"byte export preflight implementation present");
  unsigned char raw[64]={0};size_t badLengths[]={0,15,63};for(unsigned i=0;i<3;i++){CGImageRef bad=make(space,raw,2,2,32,badLengths[i],YES,NO);REQUIRE(bad==NULL,"short float provider rejected before usable image");}
  CGImageRef nilImage=CGImageCreate(1,1,32,128,16,space,kCGBitmapFloatComponents|kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedLast,NULL,NULL,false,kCGRenderingIntentDefault);REQUIRE(nilImage==NULL,"nil float provider rejected");
  CGImageRef malformed=make(space,raw,10,1,4,4,NO,YES);REQUIRE(malformed,"preexisting byte constructor accepts malformed row control");REQUIRE(copyForExport((O2Image *)malformed)==nil,"graph preflight rejects undersized byte row");
  NSMutableData *data=[NSMutableData data];O2ImageDestinationRef dest=O2ImageDestinationCreateWithData((CFMutableDataRef)data,CFSTR("public.tiff"),1,NULL);NSUInteger before=[data length];O2ImageDestinationAddImage(dest,(O2Image *)malformed,NULL);REQUIRE(dest->_imageCount==1&&[data length]==before,"invalid byte input preserves count and consumer bytes");REQUIRE(!O2ImageDestinationFinalize(dest),"invalid input reports failure");[dest release];
  REQUIRE([pdf(malformed) isEqual:pdf(NULL)],"invalid PDF input changes no content/resources");
  CGImageRelease(malformed);CGImageRef cycle=make(space,raw,1,1,4,4,NO,YES);REQUIRE(cycle,"valid cycle control");[(O2Image *)cycle setMask:(O2Image *)cycle];REQUIRE(copyForExport((O2Image *)cycle)==nil,"valid-backed cyclic graph rejected");[(O2Image *)cycle setMask:nil];CGImageRelease(cycle);
 } else {
  float values[]={0,0,0,0,.125,.25,.375,.5,.25,.5,.75,1};unsigned char bytes[]={0,0,0,0,32,64,96,128,64,128,191,255};
  CGImageRef source=make(space,values,3,1,48,sizeof(values),YES,NO),reference=make(space,bytes,3,1,12,sizeof(bytes),NO,YES);REQUIRE(source&&reference,"float and independent byte reference");
  if(!strcmp(argv[1],"nested")) {
   REQUIRE(copyForExport!=NULL,"graph byte export implementation present");
   float maskValues[]={.125,.25,.375,.5,.75,.25,.125,1};unsigned char maskBytes[]={32,64,96,128,191,64,32,255};CGImageRef mask=make(space,maskValues,2,1,32,sizeof(maskValues),YES,NO),byteMask=make(space,maskBytes,2,1,8,sizeof(maskBytes),NO,YES);REQUIRE(mask&&byteMask,"unequal2:3 nonuniform mask");[(O2Image *)reference setMask:(O2Image *)mask];O2ImageRef copy=copyForExport((O2Image *)reference);REQUIRE(copy&&copy!=(O2Image *)reference&&O2ImageGetMask(copy)!=(O2Image *)mask,"byte parent cloned before nested mask replacement");REQUIRE(O2ImageGetMask((O2Image *)reference)==(O2Image *)mask,"source mask ownership unchanged");[(O2Image *)source setMask:(O2Image *)byteMask];NSData *nested=pdf(reference);REQUIRE([nested isEqual:pdf(source)],"nested float mask PDF equals independent byte mask reference");unsigned char expectedMask[]={0,96,191};REQUIRE([nested rangeOfData:[NSData dataWithBytes:expectedMask length:3] options:0 range:NSMakeRange(0,[nested length])].location!=NSNotFound,"independent center-aligned2:3 alpha oracle");O2ImageRelease(copy);CGImageRelease(mask);CGImageRelease(byteMask);
  } else if(!strcmp(argv[1],"shortwrite")) {
   for(int i=0;i<3;i++){WriterState state={0};CGDataConsumerCallbacks callbacks={rejectWrite,releaseWriter};CGDataConsumerRef consumer=CGDataConsumerCreate(&state,&callbacks);O2ImageDestinationRef dest=O2ImageDestinationCreateWithDataConsumer((O2DataConsumerRef)consumer,i==0?CFSTR("public.jpeg"):i==1?CFSTR("public.tiff"):CFSTR("public.png"),1,NULL);REQUIRE(dest,"failing consumer destination");CGDataConsumerRelease(consumer);O2ImageDestinationAddImage(dest,(O2Image *)source,NULL);REQUIRE(!O2ImageDestinationFinalize(dest),"short consumer writes propagate failure");REQUIRE(state.calls>0,"real encoder attempted consumer output");REQUIRE(state.releases==1,"Finalize releases the final consumer ownership");[dest release];REQUIRE(state.releases==1,"destination release never repeats consumer finalization");}
   for(int i=0;i<3;i++){WriterState state={0};CGDataConsumerCallbacks callbacks={rejectWrite,releaseWriter};CGDataConsumerRef consumer=CGDataConsumerCreate(&state,&callbacks);O2ImageDestinationRef dest=O2ImageDestinationCreateWithDataConsumer((O2DataConsumerRef)consumer,i==0?CFSTR("public.jpeg"):i==1?CFSTR("public.tiff"):CFSTR("public.png"),1,NULL);CGDataConsumerRelease(consumer);[dest release];REQUIRE(state.releases==1,"unfinalized destination cleans up encoder and consumer ownership");}
  } else if(!strcmp(argv[1],"bitmask")||!strcmp(argv[1],"stencil")) {
   unsigned char packed=0xa0;CGDataProviderRef provider=CGDataProviderCreateWithData(NULL,&packed,1,NULL);CGImageRef mask=CGImageMaskCreate(3,1,1,1,1,provider,NULL,false);CGDataProviderRelease(provider);REQUIRE(mask,"real1bit mask");if(!strcmp(argv[1],"stencil")){NSData *output=pdf(mask);const unsigned char stream[]={'s','t','r','e','a','m','\n',0xa0,'\n','e','n','d','s','t','r','e','a','m'};REQUIRE([output rangeOfData:[NSData dataWithBytes:stream length:sizeof(stream)] options:0 range:NSMakeRange(0,[output length])].location!=NSNotFound,"standalone stencil retains actual packed sample stream");REQUIRE([output rangeOfData:[@"/ImageMask true" dataUsingEncoding:NSASCIIStringEncoding] options:0 range:NSMakeRange(0,[output length])].location!=NSNotFound,"standalone stencil declares ImageMask");}else{[(O2Image *)source setMask:(O2Image *)mask];NSData *output=pdf(source);unsigned char expectedMask[]={0,0,255};REQUIRE([output rangeOfData:[NSData dataWithBytes:expectedMask length:3] options:0 range:NSMakeRange(0,[output length])].location!=NSNotFound,"actual1bit mask alpha stream oracle");}CGImageRelease(mask);
  } else if(!strcmp(argv[1],"pdf")) {NSData *actual=pdf(source),*want=pdf(reference);REQUIRE([actual length]>0&&[actual isEqual:want],"float PDF equals premultiplied byte reference including alpha");unsigned char expectedRGB[]={0,0,0,64,128,191,64,128,191},expectedAlpha[]={0,128,255};REQUIRE([actual rangeOfData:[NSData dataWithBytes:expectedRGB length:9] options:0 range:NSMakeRange(0,[actual length])].location!=NSNotFound,"independent unassociated RGB stream oracle");REQUIRE([actual rangeOfData:[NSData dataWithBytes:expectedAlpha length:3] options:0 range:NSMakeRange(0,[actual length])].location!=NSNotFound,"independent alpha stream oracle");REQUIRE([actual rangeOfData:[@"/SMask" dataUsingEncoding:NSASCIIStringEncoding] options:0 range:NSMakeRange(0,[actual length])].location!=NSNotFound,"fractional alpha encoded as actual soft mask");}
  else {NSString *type=!strcmp(argv[1],"jpeg")?@"public.jpeg":!strcmp(argv[1],"tiff")?@"public.tiff":!strcmp(argv[1],"png")?@"public.png":nil;REQUIRE(type,"known encoder");NSData *actual=encoded(source,type),*want=encoded(reference,type);REQUIRE(actual&&[actual length]>0&&[actual isEqual:want],"float export equals explicit premultiplied byte reference");}
  CGImageRelease(source);CGImageRelease(reference);
 }
 CGColorSpaceRelease(space);puts("FLOAT_BYTE_EXPORT_COMPATIBILITY_PASS_NO_MANAGED_PROFILE_CLAIM");return 0;
}}
