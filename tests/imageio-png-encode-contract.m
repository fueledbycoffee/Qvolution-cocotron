// Original public PNG destination boundary inputs; no decoder used as pixel oracle.
#import <AppKit/AppKit.h>
#import <ImageIO/ImageIO.h>
#include <stdio.h>
#include <string.h>
#define CHECK(c,m) do{if(!(c)){fprintf(stderr,"FAIL %s\n",m);return 1;}}while(0)
typedef struct {const char *name;CGImageAlphaInfo alpha;CGBitmapInfo order;int channels;} Case;
static Case cases[]={
 {"rgba-straight",kCGImageAlphaLast,kCGBitmapByteOrder32Big,4},{"rgba-premul",kCGImageAlphaPremultipliedLast,kCGBitmapByteOrder32Big,4},
 {"argb-straight",kCGImageAlphaFirst,kCGBitmapByteOrder32Big,4},{"argb-premul",kCGImageAlphaPremultipliedFirst,kCGBitmapByteOrder32Big,4},
 {"bgra-straight",kCGImageAlphaFirst,kCGBitmapByteOrder32Little,4},{"bgra-premul",kCGImageAlphaPremultipliedFirst,kCGBitmapByteOrder32Little,4},
 {"abgr-straight",kCGImageAlphaLast,kCGBitmapByteOrder32Little,4},{"abgr-premul",kCGImageAlphaPremultipliedLast,kCGBitmapByteOrder32Little,4},
 {"rgb",kCGImageAlphaNone,kCGBitmapByteOrderDefault,3},{"rgbx",kCGImageAlphaNoneSkipLast,kCGBitmapByteOrder32Big,4},
 {"xrgb",kCGImageAlphaNoneSkipFirst,kCGBitmapByteOrder32Big,4},{"bgrx",kCGImageAlphaNoneSkipFirst,kCGBitmapByteOrder32Little,4},{"xbgr",kCGImageAlphaNoneSkipLast,kCGBitmapByteOrder32Little,4}};
static CGImageRef imageFor(Case c){
 unsigned char bytes[58];memset(bytes,0xD3,sizeof(bytes));size_t stride=6*c.channels+5;const unsigned char alphas[]={0,1,64,128,254,255};
 for(int y=0;y<2;y++)for(int x=0;x<6;x++){
  unsigned a=alphas[x],r=31+x*29,g=193-y*67-x*11,b=17+y*109+x*7;BOOL pm=c.alpha==kCGImageAlphaPremultipliedFirst||c.alpha==kCGImageAlphaPremultipliedLast;
  BOOL ha=c.alpha==kCGImageAlphaFirst||c.alpha==kCGImageAlphaLast||pm;if(pm){r=(r*a+127)/255;g=(g*a+127)/255;b=(b*a+127)/255;}
  unsigned char q[4];if(c.channels==3){q[0]=r;q[1]=g;q[2]=b;}else{BOOL first=c.alpha==kCGImageAlphaFirst||c.alpha==kCGImageAlphaPremultipliedFirst||c.alpha==kCGImageAlphaNoneSkipFirst;
   q[first?1:0]=r;q[first?2:1]=g;q[first?3:2]=b;q[first?0:3]=ha?a:0xAB;
   if(c.order==kCGBitmapByteOrder32Little)for(int i=0;i<2;i++){unsigned char t=q[i];q[i]=q[3-i];q[3-i]=t;}}
  memcpy(bytes+y*stride+x*c.channels,q,c.channels);
 }
 CFDataRef data=CFDataCreate(NULL,bytes,2*stride);CGDataProviderRef p=CGDataProviderCreateWithCFData(data);CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
 CGImageRef result=CGImageCreate(6,2,8,c.channels*8,stride,cs,c.alpha|c.order,p,NULL,NO,kCGRenderingIntentDefault);CGColorSpaceRelease(cs);CGDataProviderRelease(p);CFRelease(data);return result;
}
static size_t shortWrite(void *info,const void *bytes,size_t count){return count?count-1:0;}
int main(int argc,char **argv){@autoreleasepool{@try{
 CHECK(argc==3,"mode vectors|depth16|short-write and explicit output directory");NSString *dir=[NSString stringWithUTF8String:argv[2]];BOOL isdir=NO;CHECK([dir isAbsolutePath]&&[[NSFileManager defaultManager]fileExistsAtPath:dir isDirectory:&isdir]&&isdir,"existing explicit output directory");
 if(!strcmp(argv[1],"vectors")||!strncmp(argv[1],"vector:",7)){
  unsigned attempted=0,constructed=0,emitted=0,failures=0;
  for(unsigned i=0;i<sizeof(cases)/sizeof(cases[0]);i++){
   if(strncmp(argv[1],"vector:",7)==0&&strcmp(argv[1]+7,cases[i].name))continue;
   attempted++;
   @try {
    CGImageRef image=imageFor(cases[i]);
    if(!image){fprintf(stderr,"FAIL CONSTRUCT %s\n",cases[i].name);failures++;continue;}
    constructed++;fprintf(stderr,"CONSTRUCTED %s\n",cases[i].name);
    NSMutableData *data=[NSMutableData data];
    CGImageDestinationRef d=CGImageDestinationCreateWithData((CFMutableDataRef)data,CFSTR("public.png"),1,NULL);
    if(!d){CGImageRelease(image);fprintf(stderr,"FAIL DESTINATION %s\n",cases[i].name);failures++;continue;}
    CGImageDestinationAddImage(d,image,NULL);BOOL ok=CGImageDestinationFinalize(d);CFRelease(d);CGImageRelease(image);
    if(!ok){fprintf(stderr,"FAIL FINALIZE %s\n",cases[i].name);failures++;continue;}
    NSString *path=[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%s.png",cases[i].name]];
    if(![data writeToFile:path atomically:NO]){fprintf(stderr,"FAIL FILE %s\n",cases[i].name);failures++;continue;}
    emitted++;fprintf(stderr,"EMITTED %s\n",cases[i].name);
   }@catch(NSException *e){fprintf(stderr,"FAIL EXCEPTION %s %s\n",cases[i].name,[[e name]UTF8String]);failures++;}
  }
  fprintf(stderr,"SUMMARY attempted=%u constructed=%u emitted=%u failures=%u; independent host pixel oracle REQUIRED\n",attempted,constructed,emitted,failures);
  CHECK(attempted>0,"known vector case");return failures?1:0;}
 if(!strcmp(argv[1],"draw")){
  unsigned failures=0,constructed=0,drawn=0;
  CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
  for(unsigned i=0;i<sizeof(cases)/sizeof(cases[0]);i++){
   @try {
    CGImageRef image=imageFor(cases[i]);if(!image){fprintf(stderr,"FAIL DRAW CONSTRUCT %s\n",cases[i].name);failures++;continue;}constructed++;
    unsigned char pixels[58];memset(pixels,0xD3,sizeof(pixels));for(unsigned y=0;y<2;y++)memset(pixels+y*29,0,24);
    CGContextRef context=CGBitmapContextCreate(pixels,6,2,8,29,cs,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    if(!context){CGImageRelease(image);fprintf(stderr,"FAIL DRAW CONTEXT %s\n",cases[i].name);failures++;continue;}
    CGContextSetInterpolationQuality(context,kCGInterpolationNone);CGContextDrawImage(context,CGRectMake(0,0,6,2),image);
    unsigned bad=0;const unsigned alphas[]={0,1,64,128,254,255};
    for(unsigned y=0;y<2;y++)for(unsigned x=0;x<6;x++){
     unsigned alpha=i<8?alphas[x]:255,expected[]={31+x*29,193-y*67-x*11,17+y*109+x*7,alpha};
     if(i<8)for(unsigned c=0;c<3;c++)expected[c]=(expected[c]*alpha+127)/255;
     for(unsigned c=0;c<4;c++){int delta=(int)pixels[y*29+x*4+c]-expected[c];if(delta < -1 || delta > 1)bad++;}
    }
    for(unsigned y=0;y<2;y++)for(unsigned k=24;k<29;k++)if(pixels[y*29+k]!=0xD3)bad++;
    CGContextRelease(context);CGImageRelease(image);
    if(bad){fprintf(stderr,"FAIL DRAW PIXELS %s mismatches=%u\n",cases[i].name,bad);failures++;}
    else{fprintf(stderr,"PASS DRAW %s\n",cases[i].name);drawn++;}
   }@catch(NSException *e){fprintf(stderr,"FAIL DRAW EXCEPTION %s %s\n",cases[i].name,[[e name]UTF8String]);failures++;}
  }
  CGColorSpaceRelease(cs);fprintf(stderr,"SUMMARY draw requested=13 constructed=%u passed=%u failures=%u\n",constructed,drawn,failures);return failures?1:0;
 }
 if(!strcmp(argv[1],"no-image")||!strcmp(argv[1],"repeated-image")||!strcmp(argv[1],"null-image")){
  NSMutableData *data=[NSMutableData data];CGImageDestinationRef d=CGImageDestinationCreateWithData((CFMutableDataRef)data,CFSTR("public.png"),1,NULL);CHECK(d,"PNG completion destination");
  if(!strcmp(argv[1],"repeated-image")){
   CGImageRef image=imageFor(cases[0]);CHECK(image,"repeated image source control");CGImageDestinationAddImage(d,image,NULL);CGImageDestinationAddImage(d,image,NULL);CGImageRelease(image);
  }else if(!strcmp(argv[1],"null-image"))CGImageDestinationAddImage(d,NULL,NULL);
  BOOL ok=CGImageDestinationFinalize(d);CFRelease(d);CHECK(!ok,"PNG requires exactly one successful image");
  if(strcmp(argv[1],"repeated-image"))CHECK([data length]==0,"absent image emits no PNG bytes");
  fprintf(stderr,"PASS public %s completion failure\n",argv[1]);return 0;
 }
 if(!strcmp(argv[1],"short-write")){CGImageRef image=imageFor(cases[0]);CHECK(image,"source control");CGDataConsumerCallbacks cb={shortWrite,NULL};CGDataConsumerRef c=CGDataConsumerCreate(NULL,&cb);CGImageDestinationRef d=CGImageDestinationCreateWithDataConsumer(c,CFSTR("public.png"),1,NULL);CHECK(d,"consumer destination");CGImageDestinationAddImage(d,image,NULL);BOOL ok=CGImageDestinationFinalize(d);CFRelease(d);CGDataConsumerRelease(c);CGImageRelease(image);CHECK(!ok,"short consumer must fail finalization");puts("PASS public short-write failure");return 0;}
 if(!strcmp(argv[1],"depth16")){unsigned char bytes[24]={0};CFDataRef data=CFDataCreate(NULL,bytes,sizeof(bytes));CGDataProviderRef p=CGDataProviderCreateWithCFData(data);CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();CGImageRef image=CGImageCreate(2,2,16,48,12,cs,kCGImageAlphaNone|kCGBitmapByteOrder16Big,p,NULL,NO,kCGRenderingIntentDefault);CHECK(image,"valid depth16 control");NSMutableData *out=[NSMutableData data];CGImageDestinationRef d=CGImageDestinationCreateWithData((CFMutableDataRef)out,CFSTR("public.png"),1,NULL);CGImageDestinationAddImage(d,image,NULL);BOOL ok=CGImageDestinationFinalize(d);CFRelease(d);CGImageRelease(image);CGColorSpaceRelease(cs);CGDataProviderRelease(p);CFRelease(data);CHECK(!ok&&[out length]==0,"unsupported16bit rejects before PNG bytes");puts("PASS bounded unsupported depth policy");return 0;}
 CHECK(NO,"known mode");
 }@catch(NSException *e){fprintf(stderr,"FAIL exception %s\n",[[e name]UTF8String]);return 1;}}}
