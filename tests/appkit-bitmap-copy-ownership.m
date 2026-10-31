// Original raw-plane, immutable-CG-backing and property ownership workflows.
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#define CHECK(c,m) do{if(!(c)){fprintf(stderr,"FAIL %s (%d)\n",m,__LINE__);return 1;}}while(0)
static unsigned markerLive,markerReleased;
@interface QVBitmapOwnershipMarker:NSObject @end
@implementation QVBitmapOwnershipMarker
- init{if((self=[super init]))markerLive++;return self;}
- (void)dealloc{markerLive--;markerReleased++;[super dealloc];}
@end
static unsigned stringLive;
@interface QVOwnedColorSpaceString:NSString {NSString *_text;BOOL _nilNextCopy;}
- initWithText:(NSString *)text;
- (void)armNilCopy;
@end
@implementation QVOwnedColorSpaceString
- initWithText:(NSString *)text{if((self=[super init])){_text=[text copy];stringLive++;}return self;}
- (void)dealloc{stringLive--;[_text release];[super dealloc];}
- (NSUInteger)length{return [_text length];}
- (unichar)characterAtIndex:(NSUInteger)index{return [_text characterAtIndex:index];}
- (void)armNilCopy{_nilNextCopy=YES;}
- copyWithZone:(NSZone *)zone{if(_nilNextCopy){_nilNextCopy=NO;return nil;}return [[[self class]allocWithZone:zone]initWithText:_text];}
@end
@interface QVThrowingCopyValue:NSObject {BOOL _throwNextRetain;}
- (void)arm;
@end
@implementation QVThrowingCopyValue
- (void)arm{_throwNextRetain=YES;}
- retain{if(_throwNextRetain){_throwNextRetain=NO;[NSException raise:@"QvolutionInjectedRetainFailure" format:@"Original metadata ownership failure"]; }return [super retain];}
@end
static NSBitmapImageRep *owned(void){NSBitmapImageRep *rep=[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:NULL pixelsWide:7 pixelsHigh:3 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bitmapFormat:NSAlphaNonpremultipliedBitmapFormat bytesPerRow:33 bitsPerPixel:32];if(rep){for(unsigned i=0;i<99;i++)[rep bitmapData][i]=(unsigned char)(i*13+7);[rep setSize:NSMakeSize(3.5,1.5)];}return rep;}
static int planeCopy(NSBitmapImageRep *source,unsigned char **borrowed,unsigned count,BOOL sourceFirst){
 CHECK(source,"actual original bitmap source");unsigned char *before[5]={0},*after[5]={0};[source getBitmapDataPlanes:before];NSUInteger length=(NSUInteger)[source bytesPerRow]*[source pixelsHigh];NSMutableArray *bytes=[NSMutableArray array];for(unsigned i=0;i<count;i++){CHECK(before[i],"real source plane");[bytes addObject:[NSData dataWithBytes:before[i] length:length]];}
 NSBitmapImageRep *copy=[source copy];CHECK(copy&&copy!=source&&[copy class]==[source class],"distinct concrete bitmap copy");[copy getBitmapDataPlanes:after];
 CHECK([copy pixelsWide]==[source pixelsWide]&&[copy pixelsHigh]==[source pixelsHigh]&&[copy bitsPerSample]==[source bitsPerSample]&&[copy bitsPerPixel]==[source bitsPerPixel]&&[copy samplesPerPixel]==[source samplesPerPixel]&&[copy bitmapFormat]==[source bitmapFormat]&&[copy isPlanar]==[source isPlanar]&&[copy hasAlpha]==[source hasAlpha]&&[copy bytesPerRow]==[source bytesPerRow]&&NSEqualSizes([copy size],[source size])&&[[copy colorSpaceName]isEqual:[source colorSpaceName]],"copy preserves generic scalar/layout state");
 // Fail before releasing either object on the old aliasing implementation.
 for(unsigned i=0;i<count;i++)CHECK(after[i]&&after[i]!=before[i]&&!memcmp(after[i],[[bytes objectAtIndex:i]bytes],length),"copy owns an independent complete raw plane");
 for(unsigned i=0;i<count;i++){before[i][0]^=0x5A;CHECK(!memcmp(after[i],[[bytes objectAtIndex:i]bytes],length),"source mutation does not change copy bytes");}
 if(sourceFirst){[source release];if(borrowed)for(unsigned i=0;i<count;i++){free(borrowed[i]);borrowed[i]=NULL;}for(unsigned i=0;i<count;i++)CHECK(!memcmp(after[i],[[bytes objectAtIndex:i]bytes],length),"copy survives source and borrowed buffer lifetime");[copy release];}
 else{[copy release];for(unsigned i=0;i<count;i++)CHECK(before[i][0]==(((const unsigned char *)[[bytes objectAtIndex:i]bytes])[0]^0x5A),"source survives copied plane release");[source release];if(borrowed)for(unsigned i=0;i<count;i++){free(borrowed[i]);borrowed[i]=NULL;}}
 return 0;
}
static int borrowedPlanes(BOOL sourceFirst){
 typedef struct{const char *name;int bpc,samples,bpp;BOOL planar,alpha;NSString *space;NSBitmapFormat format;}Case;
 Case cases[]={
  {"gray1",1,1,1,NO,NO,NSDeviceWhiteColorSpace,0},{"gray16",16,1,16,NO,NO,NSDeviceWhiteColorSpace,0},
  {"rgb16-planar",16,3,16,YES,NO,NSDeviceRGBColorSpace,0},{"cmyk8",8,4,32,NO,NO,NSDeviceCMYKColorSpace,0},
  {"rgba32float",32,4,128,NO,YES,NSDeviceRGBColorSpace,NSFloatingPointSamplesBitmapFormat},
  {"gray1-alpha-planar",1,2,1,YES,YES,NSDeviceWhiteColorSpace,0},{"cmyka8",8,5,40,NO,YES,NSDeviceCMYKColorSpace,0}};
 for(unsigned c=0;c<sizeof(cases)/sizeof(cases[0]);c++){
  Case spec=cases[c];int width=7,height=3,stride=(width*spec.bpp+7)/8+5;unsigned count=spec.planar?spec.samples:1;unsigned char *planes[5]={0};
  for(unsigned i=0;i<count;i++){planes[i]=malloc(stride*height);CHECK(planes[i],"allocate original borrowed plane");for(int j=0;j<stride*height;j++)planes[i][j]=(unsigned char)(c*31+i*47+j*13+7);if(spec.format&NSFloatingPointSamplesBitmapFormat)for(int y=0;y<height;y++)for(int x=0;x<width*4;x++){float value=(x%4==3)?1.0f:(float)(x%11)/11;memcpy(planes[i]+y*stride+x*4,&value,4);}}
  NSBitmapImageRep *rep=[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:planes pixelsWide:width pixelsHigh:height bitsPerSample:spec.bpc samplesPerPixel:spec.samples hasAlpha:spec.alpha isPlanar:spec.planar colorSpaceName:spec.space bitmapFormat:spec.format bytesPerRow:stride bitsPerPixel:spec.bpp];
  if(planeCopy(rep,planes,count,sourceFirst))return 1;fprintf(stderr,"PASS borrowed generic %s\n",spec.name);
 }
 puts("PASS generic borrowed planar/subbyte/16/float/CMYK copy ownership");return 0;
}
static void releaseProvider(void *info,const void *data,size_t size){(*(unsigned *)info)++;free((void *)data);}
static int cgCopy(BOOL sourceFirst,BOOL dual,BOOL gray){
 unsigned released=0;size_t width=7,height=3,stride=gray?12:33,length=stride*height+13;unsigned char *raw=malloc(length);CHECK(raw,"original provider bytes");for(size_t i=0;i<length;i++)raw[i]=(unsigned char)(i*11+3);if(!gray)for(size_t y=0;y<height;y++)for(size_t x=0;x<width;x++)raw[y*stride+x*4+3]=255;
 NSData *expected=[NSData dataWithBytes:raw length:length];CGDataProviderRef provider=CGDataProviderCreateWithData(&released,raw,length,releaseProvider);CGColorSpaceRef space=gray?CGColorSpaceCreateDeviceGray():CGColorSpaceCreateDeviceRGB();CGImageRef image=CGImageCreate(width,height,8,gray?8:32,stride,space,gray?kCGImageAlphaNone:kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big,provider,NULL,NO,kCGRenderingIntentDefault);CGColorSpaceRelease(space);CGDataProviderRelease(provider);CHECK(image,"actual CG source control");
 NSBitmapImageRep *source=[[NSBitmapImageRep alloc]initWithCGImage:image];CGImageRelease(image);CHECK(source&&released==0,"source owns actual CG provider");NSData *plane=nil;if(dual){[source bitmapData][0]=217;plane=[NSData dataWithBytes:[source bitmapData] length:stride*height];}
 NSBitmapImageRep *copy=[source copy];CHECK(copy&&copy!=source,"real CG-backed bitmap copy");if(dual)CHECK([copy bitmapData]!=[source bitmapData]&&!memcmp([copy bitmapData],[plane bytes],[plane length]),"dual copy independently owns materialized plane");
 NSBitmapImageRep *survivor=sourceFirst?copy:source;[(sourceFirst?source:copy)release];
 // Own release callback catches the old missing retain before reading a dangling image.
 CHECK(released==0,"CG provider remains alive after first bitmap release");CGImageRef actual=[survivor CGImage];CFDataRef bytes=CGDataProviderCopyData(CGImageGetDataProvider(actual));CHECK([(NSData *)bytes isEqual:expected],"surviving immutable CG backing retains complete original provider bytes");CFRelease(bytes);if(dual)CHECK(!memcmp([survivor bitmapData],[plane bytes],[plane length]),"dual surviving component plane remains independent");[survivor release];CHECK(released==1,"CG provider released exactly once after final bitmap owner");return 0;
}
static int properties(BOOL copying,BOOL sourceFirst){
 CHECK(markerLive==0,"marker baseline");unsigned released=markerReleased;NSBitmapImageRep *source=owned();CHECK(source,"original bitmap");QVBitmapOwnershipMarker *marker=[QVBitmapOwnershipMarker new];[source setProperty:@"QvolutionOwnershipMarker" withValue:marker];[marker release];CHECK(markerLive==1&&[source valueForProperty:@"QvolutionOwnershipMarker"]!=nil,"public property setter retains value");
 if(!copying){[source setProperty:@"QvolutionOwnershipMarker" withValue:nil];CHECK([source valueForProperty:@"QvolutionOwnershipMarker"]==nil&&markerLive==0&&markerReleased==released+1,"nil clears property and releases its value");[source setProperty:@"QvolutionOwnershipMarker" withValue:nil];[source release];return 0;}
 NSBitmapImageRep *copy=[source copy];CHECK([copy bitmapData]!=[source bitmapData],"property bitmap copy owns its plane");CHECK([copy valueForProperty:@"QvolutionOwnershipMarker"]==[source valueForProperty:@"QvolutionOwnershipMarker"],"copy dictionary retains existing value with normal shallow semantics");
 [copy setProperty:@"QvolutionCopyOnly" withValue:@"copy"];CHECK([source valueForProperty:@"QvolutionCopyOnly"]==nil,"copy dictionary insertion is independent");[source setProperty:@"QvolutionOwnershipMarker" withValue:@"replacement"];CHECK([[source valueForProperty:@"QvolutionOwnershipMarker"]isEqual:@"replacement"]&&[[copy valueForProperty:@"QvolutionOwnershipMarker"]isKindOfClass:[QVBitmapOwnershipMarker class]],"source replacement does not mutate copied property dictionary");
 if(sourceFirst){[source release];CHECK(markerLive==1,"copied metadata owns value after source release");[copy release];}else{[copy release];CHECK(markerLive==0,"copied metadata releases value without source dictionary alias");[source release];}
 CHECK(markerLive==0&&markerReleased==released+1,"property value released exactly once");return 0;
}
static int colorSpaceOwnership(BOOL failure){
 CHECK(stringLive==0,"owned color-space baseline");NSBitmapImageRep *source=nil;unsigned released=0;
 if(failure){unsigned char *bytes=malloc(4);CHECK(bytes,"original provider bytes");memcpy(bytes,(unsigned char[]){20,30,40,255},4);CGDataProviderRef provider=CGDataProviderCreateWithData(&released,bytes,4,releaseProvider);CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();CGImageRef cg=CGImageCreate(1,1,8,32,4,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big,provider,NULL,NO,kCGRenderingIntentDefault);CGColorSpaceRelease(space);CGDataProviderRelease(provider);CHECK(cg,"real staged-cleanup CG control");source=[[NSBitmapImageRep alloc]initWithCGImage:cg];CGImageRelease(cg);CHECK(source&&[source bitmapData][0]==20,"real staged-cleanup materialized plane control");}
 else source=[NSBitmapImageRep new];
 QVOwnedColorSpaceString *name=[[QVOwnedColorSpaceString alloc]initWithText:NSDeviceRGBColorSpace];CHECK(name&&stringLive==1,"original NSString ownership sentinel");[source setColorSpaceName:name];[name release];CHECK(stringLive==1&&[[source colorSpaceName]isEqual:NSDeviceRGBColorSpace],"source owns copied color-space string");
 if(failure){QVThrowingCopyValue *value=[QVThrowingCopyValue new];[source setProperty:@"QvolutionThrowingMetadata" withValue:value];CHECK([source valueForProperty:@"QvolutionThrowingMetadata"]==value,"real public metadata prerequisite");NSDictionary *control=[NSDictionary dictionaryWithObject:value forKey:@"control"];[value arm];BOOL controlThrew=NO;@try{NSMutableDictionary *copy=[control mutableCopy];[copy release];}@catch(NSException *error){controlThrew=[[error name]isEqual:@"QvolutionInjectedRetainFailure"];}CHECK(controlThrew,"actual dictionary copy invokes original throwing retain control");[value arm];BOOL threw=NO;@try{NSBitmapImageRep *copy=[source copy];(void)copy;}@catch(NSException *error){threw=[[error name]isEqual:@"QvolutionInjectedRetainFailure"];}CHECK(threw,"bitmap copy propagates metadata failure after color/CG ownership stages");CHECK(stringLive==1&&released==0&&[source bitmapData][0]==20,"failed copy releases its new string/CG ownership and preserves source plane");[value release];[source release];CHECK(stringLive==0&&released==1,"source final release proves no copied string or CG ownership leaked");}
 else{NSBitmapImageRep *copy=[source copy];CHECK(copy&&stringLive==2,"bitmap copy owns its copied color-space string");[source release];CHECK(stringLive==1,"copied color-space survives source release");[copy release];CHECK(stringLive==0,"owned color-space strings both released");}
 puts("PASS owned NSString lifetime or staged exceptional bitmap copy cleanup");return 0;
}
static int nilColorCopy(void){
 CHECK(stringLive==0,"owned string baseline before nil-copy fault");NSBitmapImageRep *source=[NSBitmapImageRep new];QVOwnedColorSpaceString *name=[[QVOwnedColorSpaceString alloc]initWithText:NSDeviceRGBColorSpace];[source setColorSpaceName:name];[name release];CHECK(stringLive==1&&[[source colorSpaceName]isEqual:NSDeviceRGBColorSpace],"real public owned color-space control");[(QVOwnedColorSpaceString *)[source colorSpaceName]armNilCopy];BOOL rejected=NO;@try{NSBitmapImageRep *copy=[source copy];[copy release];}@catch(NSException *error){rejected=[[error name]isEqual:NSMallocException];}CHECK(rejected&&stringLive==1,"nil color-space copy raises allocation error and preserves source ownership");[source release];CHECK(stringLive==0,"source string released after nil-copy fault");return 0;
}
int main(int argc,char **argv){@autoreleasepool{@try{
 CHECK(argc==2,"explicit owned-source-first|owned-copy-first|borrowed-source-first|borrowed-copy-first|cg-source-first|cg-copy-first|dual-source-first|dual-copy-first|properties|property-copy-source-first|property-copy-copy-first|empty|invalid mode");NSString *mode=[NSString stringWithUTF8String:argv[1]];BOOL sourceFirst=[mode hasSuffix:@"source-first"];
 if([mode isEqual:@"copy-nil"])return nilColorCopy();if([mode isEqual:@"color-space"])return colorSpaceOwnership(NO);if([mode isEqual:@"copy-failure"])return colorSpaceOwnership(YES);
 if([mode hasPrefix:@"owned-"])return planeCopy(owned(),NULL,1,sourceFirst);if([mode hasPrefix:@"borrowed-"])return borrowedPlanes(sourceFirst);
 if([mode hasPrefix:@"cg-"]){if(cgCopy(sourceFirst,NO,NO))return 1;return cgCopy(sourceFirst,NO,YES);}if([mode hasPrefix:@"dual-"])return cgCopy(sourceFirst,YES,NO);
 if([mode hasPrefix:@"property-copy-"])return properties(YES,sourceFirst);if([mode isEqual:@"properties"])return properties(NO,NO);
 if([mode isEqual:@"empty"]){NSBitmapImageRep *source=[NSBitmapImageRep new],*copy=[source copy];CHECK(copy&&copy!=source&&[copy pixelsWide]==0&&[copy pixelsHigh]==0,"blank bitmap copy remains blank");[source release];[copy release];return 0;}
 if([mode isEqual:@"invalid"]){NSBitmapImageRep *source=owned();[source setPixelsHigh:-1];BOOL rejected=NO;@try{NSBitmapImageRep *copy=[source copy];(void)copy;}@catch(NSException *error){rejected=[[error name]isEqual:NSInvalidArgumentException];}CHECK(rejected,"invalid declared raw extent rejects before copying");[source setPixelsHigh:3];[source release];return 0;}
 CHECK(NO,"known mode");
 }@catch(NSException *error){fprintf(stderr,"FAIL exception %s\n",[[error name]UTF8String]);return 1;}}}
