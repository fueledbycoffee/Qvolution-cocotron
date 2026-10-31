// Original project image archive workflows; no vendor assets or native keys.
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#define CHECK(c,m) do{if(!(c)){fprintf(stderr,"FAIL %s (%d)\n",m,__LINE__);return 1;}}while(0)

@interface QVImageRecordCoder:NSCoder {
    BOOL _keyed;id _record;NSUInteger _writes;
}
- initKeyed:(BOOL)keyed record:(id)record;
- (id)record;
- (NSUInteger)writes;
@end
@implementation QVImageRecordCoder
- initKeyed:(BOOL)keyed record:(id)record{if((self=[super init])){_keyed=keyed;_record=[record retain];}return self;}
- (void)dealloc{[_record release];[super dealloc];}
- (BOOL)allowsKeyedCoding{return _keyed;}
- (BOOL)containsValueForKey:(NSString *)key{return [key isEqual:@"QvolutionNSImageArchive"]||[key isEqual:@"QvolutionNSBitmapImageRepArchive"];}
- (void)encodeObject:(id)object{_writes++;[_record release];_record=[object retain];}
- (void)encodeObject:(id)object forKey:(NSString *)key{if(![key isEqual:@"QvolutionNSImageArchive"]&&![key isEqual:@"QvolutionNSBitmapImageRepArchive"])[NSException raise:NSInvalidArgumentException format:@"Unknown own fixture key"];[self encodeObject:object];}
- (id)decodeObject{return _record;}
- (id)decodeObjectForKey:(NSString *)key{return _record;}
- (NSInteger)versionForClassName:(NSString *)name{return 0;}
- (id)record{return _record;}
- (NSUInteger)writes{return _writes;}
@end
@interface QVVersionImageRecordCoder:QVImageRecordCoder @end
@implementation QVVersionImageRecordCoder
- (NSInteger)versionForClassName:(NSString *)name{return [NSClassFromString(name) version];}
@end
@interface QVLegacyBitmapCoder:QVImageRecordCoder @end
@implementation QVLegacyBitmapCoder
- (NSInteger)versionForClassName:(NSString *)name{return 17;}
- (NSData *)decodeDataObject{return [self record];}
- (id)decodeObject{[NSException raise:NSInvalidArgumentException format:@"Legacy bitmap path must read its existing data object"];return nil;}
@end
@interface QVNilCopyString:NSString {NSString *_value;}
- initWithValue:(NSString *)value;
@end
@implementation QVNilCopyString
- initWithValue:(NSString *)value{if((self=[super init]))_value=[value copy];return self;}
- (void)dealloc{[_value release];[super dealloc];}
- (NSUInteger)length{return [_value length];}
- (unichar)characterAtIndex:(NSUInteger)index{return [_value characterAtIndex:index];}
- copyWithZone:(NSZone *)zone{return nil;}
@end
@interface QVNilCopyData:NSData {NSData *_value;}
- initWithValue:(NSData *)value;
@end
@implementation QVNilCopyData
- initWithValue:(NSData *)value{if((self=[super init]))_value=[value copy];return self;}
- (void)dealloc{[_value release];[super dealloc];}
- (NSUInteger)length{return [_value length];}
- (const void *)bytes{return [_value bytes];}
- copyWithZone:(NSZone *)zone{return nil;}
@end
@interface QVNilCopyDictionary:NSDictionary {NSDictionary *_value;}
- initWithValue:(NSDictionary *)value;
@end
@implementation QVNilCopyDictionary
- initWithValue:(NSDictionary *)value{if((self=[super init]))_value=[value copy];return self;}
- (void)dealloc{[_value release];[super dealloc];}
- (NSUInteger)count{return [_value count];}
- (id)objectForKey:(id)key{return [_value objectForKey:key];}
- (NSEnumerator *)keyEnumerator{return [_value keyEnumerator];}
- mutableCopyWithZone:(NSZone *)zone{return nil;}
@end
@interface QVUnknownImage:NSImage @end
@implementation QVUnknownImage @end
@interface QVUnknownBitmap:NSBitmapImageRep @end
@implementation QVUnknownBitmap @end

static NSData *archive(id value,BOOL keyed){return keyed?[NSKeyedArchiver archivedDataWithRootObject:value]:[NSArchiver archivedDataWithRootObject:value];}
static id unarchive(NSData *data,BOOL keyed){return keyed?[NSKeyedUnarchiver unarchiveObjectWithData:data]:[NSUnarchiver unarchiveObjectWithData:data];}
static NSBitmapImageRep *makeBitmap(Class cls,unsigned seed,unsigned samples,NSBitmapFormat format){
 int width=5+seed,height=2+seed,stride=width*samples+5;
 NSBitmapImageRep *rep=[[cls alloc]initWithBitmapDataPlanes:NULL pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:samples hasAlpha:samples==4 isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bitmapFormat:format bytesPerRow:stride bitsPerPixel:samples*8];
 if(!rep)return nil;unsigned char *pixels=[rep bitmapData];memset(pixels,0xD3,stride*height);
 for(int y=0;y<height;y++)for(int x=0;x<width;x++){
  unsigned a=(unsigned[]){0,1,64,128,254,255}[x%6],rgb[]={31+x*17,193-y*23,17+y*41+x*7};
  BOOL first=(format&NSAlphaFirstBitmapFormat)!=0,pm=samples==4&&!(format&NSAlphaNonpremultipliedBitmapFormat);
  for(unsigned c=0;c<3;c++)pixels[y*stride+x*samples+c+(samples==4&&first)]=pm?(rgb[c]*a+127)/255:rgb[c];
  if(samples==4)pixels[y*stride+x*4+(first?0:3)]=a;
 }
 [rep setSize:NSMakeSize(3.25+seed,1.75+seed)];[rep setOpaque:samples==3];return rep;
}
static NSImage *makeImage(BOOL derive){
 NSImage *image=[[NSImage alloc]initWithSize:derive?NSZeroSize:NSMakeSize(17.5,11.25)];
 NSBitmapFormat formats[]={NSAlphaNonpremultipliedBitmapFormat,NSAlphaFirstBitmapFormat|NSAlphaNonpremultipliedBitmapFormat,0,NSAlphaFirstBitmapFormat,0};
 for(unsigned i=0;i<5;i++){NSBitmapImageRep *rep=makeBitmap([NSBitmapImageRep class],i,i==4?3:4,formats[i]);if(!rep){[image release];return nil;}[image addRepresentation:rep];[rep release];}
 [image setTemplate:YES];[image setFlipped:YES];[image setScalesWhenResized:YES];[image setMatchesOnMultipleResolution:YES];[image setUsesEPSOnResolutionMismatch:YES];[image setPrefersColorMatch:YES];[image setCachedSeparately:YES];[image setCacheDepthMatchesImageDepth:YES];[image setDataRetained:YES];[image setCacheMode:NSImageCacheNever];
 [image setAlignmentRect:NSMakeRect(-1.25,2.5,8.75,6.5)];[image setCapInsets:NSEdgeInsetsMake(1.25,2.5,3.75,4.5)];[image setResizingMode:NSImageResizingModeStretch];[image setAccessibilityDescription:@"Original Qvolution bitmap archive fixture"];
 return image;
}
static NSArray *snapshots(NSImage *image){NSMutableArray *out=[NSMutableArray array];for(NSBitmapImageRep *rep in [image representations])[out addObject:[NSData dataWithBytes:[rep bitmapData] length:[rep bytesPerRow]*[rep pixelsHigh]]];return out;}
static BOOL exactReps(NSImage *image,NSArray *bytes){
 NSArray *reps=[image representations];if([reps count]!=[bytes count]||[reps count]!=5)return NO;
 NSBitmapFormat formats[]={NSAlphaNonpremultipliedBitmapFormat,NSAlphaFirstBitmapFormat|NSAlphaNonpremultipliedBitmapFormat,0,NSAlphaFirstBitmapFormat,0};
 for(unsigned i=0;i<5;i++){id rep=[reps objectAtIndex:i];NSData *data=[bytes objectAtIndex:i];unsigned samples=i==4?3:4;
  if([rep class]!=[NSBitmapImageRep class]||[rep pixelsWide]!=5+i||[rep pixelsHigh]!=2+i||[rep bitsPerSample]!=8||[rep samplesPerPixel]!=samples||[rep bitsPerPixel]!=samples*8||[rep bitmapFormat]!=formats[i]||[rep bytesPerRow]!=(5+i)*samples+5||[rep hasAlpha]!=(samples==4)||[rep isOpaque]!=(samples==3)||!NSEqualSizes([rep size],NSMakeSize(3.25+i,1.75+i))||memcmp([rep bitmapData],[data bytes],[data length]))return NO;
 }
 return YES;
}
static BOOL scalarState(NSImage *image){NSEdgeInsets insets=[image capInsets];return [image isTemplate]&&[image isFlipped]&&[image scalesWhenResized]&&[image matchesOnMultipleResolution]&&[image usesEPSOnResolutionMismatch]&&[image prefersColorMatch]&&[image isCachedSeparately]&&[image cacheDepthMatchesImageDepth]&&[image isDataRetained]&&[image cacheMode]==NSImageCacheNever&&[image resizingMode]==NSImageResizingModeStretch&&NSEqualRects([image alignmentRect],NSMakeRect(-1.25,2.5,8.75,6.5))&&insets.top==1.25&&insets.left==2.5&&insets.bottom==3.75&&insets.right==4.5&&[[image accessibilityDescription]isEqual:@"Original Qvolution bitmap archive fixture"];}
static int roundtrip(BOOL keyed,BOOL derive){
 NSImage *decoded=nil;NSArray *bytes=nil;
 @autoreleasepool{
  NSImage *source=makeImage(derive);CHECK(source,"five original packed bitmap representations");bytes=[snapshots(source)copy];
  NSDictionary *control=@{@"data":[bytes objectAtIndex:0],@"strings":@[@"Own archive control",@42]};CHECK([unarchive(archive(control,keyed),keyed)isEqual:control],"actual generic data/container archive control");
  NSData *data=[archive(source,keyed)retain];decoded=[unarchive(data,keyed)retain];CHECK(decoded&&decoded!=source,"real decoded image exists independently");
  memset([[[source representations]objectAtIndex:0]bitmapData],0,[[bytes objectAtIndex:0]length]);
  [source release];[data release];
 }
 CHECK(exactReps(decoded,bytes),"all five layouts, alpha0RGB, row padding and logical rep sizes survive source/archive lifetime");CHECK(scalarState(decoded),"all implemented image scalar fields survive");
 CHECK(NSEqualSizes([decoded size],derive?NSMakeSize(7.25,5.75):NSMakeSize(17.5,11.25)),"image logical size survives");
 [[[decoded representations]lastObject]setSize:NSMakeSize(100,90)];CHECK(NSEqualSizes([decoded size],derive?NSMakeSize(100,90):NSMakeSize(17.5,11.25)),"raw zero vs explicit image size semantics survive");
 NSImage *copy=[decoded copy];[decoded release];CHECK(scalarState(copy)&&[[copy representations]count]==5,"decoded image copy owns its representations");[copy release];[bytes release];puts("PASS genuine packed bitmap multirep/scalar/alpha/ownership archive workflow");return 0;
}
static NSImage *cgImage(BOOL dual){
 unsigned char raw[71];memset(raw,0xA7,sizeof(raw));for(unsigned i=58;i<71;i++)raw[i]=(unsigned char)(i*3+7);for(unsigned y=0;y<2;y++)for(unsigned x=0;x<6;x++){unsigned char *p=raw+y*29+x*4;p[0]=x*13;p[1]=y*41;p[2]=x*7+y*19;p[3]=255;}
 CFDataRef data=CFDataCreate(NULL,raw,sizeof(raw));CGDataProviderRef provider=CGDataProviderCreateWithCFData(data);CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();CGImageRef cg=CGImageCreate(6,2,8,32,29,cs,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big,provider,NULL,YES,kCGRenderingIntentRelativeColorimetric);CGColorSpaceRelease(cs);CGDataProviderRelease(provider);CFRelease(data);if(!cg)return nil;
 NSBitmapImageRep *rep=[[NSBitmapImageRep alloc]initWithCGImage:cg];CGImageRelease(cg);[rep setSize:NSMakeSize(2.5,1.25)];
 if(dual)[rep bitmapData][0]=231; // This differs from the retained CG backing on purpose.
 NSImage *image=[[NSImage alloc]initWithSize:NSMakeSize(5.5,2.75)];[image addRepresentation:rep];[rep release];return image;
}
static int cgRoundtrip(BOOL keyed,BOOL dual){
 NSImage *decoded=nil;NSData *cgBytes=nil,*planeBytes=nil;
 @autoreleasepool{NSImage *source=cgImage(dual);CHECK(source,"real source CG-backed bitmap control");NSBitmapImageRep *rep=[[source representations]objectAtIndex:0];CGImageRef cg=[rep CGImage];cgBytes=(NSData *)CGDataProviderCopyData(CGImageGetDataProvider(cg));if(dual)planeBytes=[[NSData alloc]initWithBytes:[rep bitmapData] length:58];decoded=[unarchive(archive(source,keyed),keyed)retain];[source release];}
 CHECK(decoded&&[[decoded representations]count]==1,"decoded CG-backed image exists");NSBitmapImageRep *rep=[[decoded representations]objectAtIndex:0];CGImageRef cg=[rep CGImage];CHECK(cg&&CGImageGetWidth(cg)==6&&CGImageGetHeight(cg)==2&&CGImageGetBytesPerRow(cg)==29&&CGImageGetBitmapInfo(cg)==(kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big)&&CGImageGetShouldInterpolate(cg)&&CGImageGetRenderingIntent(cg)==kCGRenderingIntentRelativeColorimetric,"CG backing layout/interpolation/intent survives");
 CFDataRef actual=CGDataProviderCopyData(CGImageGetDataProvider(cg));CHECK([(NSData *)actual isEqual:cgBytes],"actual CG provider samples and padding survive");CFRelease(actual);
 if(dual)CHECK(!memcmp([rep bitmapData],[planeBytes bytes],58),"distinct materialized plane bytes survive alongside original CG backing");
 CHECK(NSEqualSizes([rep size],NSMakeSize(2.5,1.25))&&NSEqualSizes([decoded size],NSMakeSize(5.5,2.75)),"CG rep and image point sizes survive");
 [decoded release];[cgBytes release];[planeBytes release];puts("PASS genuine CG provider or dual-storage archive workflow");return 0;
}
static BOOL rejects(NSImage *image,BOOL keyed){QVImageRecordCoder *coder=[[QVImageRecordCoder alloc]initKeyed:keyed record:nil];BOOL rejected=NO;@try{[image encodeWithCoder:coder];}@catch(NSException *error){rejected=[[error name]isEqual:NSInvalidArchiveOperationException];}BOOL result=rejected&&[coder writes]==0;[coder release];return result;}
static BOOL badRecord(id record,BOOL keyed){QVImageRecordCoder *coder=[[QVImageRecordCoder alloc]initKeyed:keyed record:record];BOOL rejected=NO;@try{NSImage *image=[[NSImage alloc]initWithCoder:coder];[image release];}@catch(NSException *error){rejected=[[error name]isEqual:NSInvalidUnarchiveOperationException];}[coder release];return rejected;}
static int unsupported(BOOL keyed){
 NSImage *image=makeImage(NO);CHECK(image,"real bitmap source control");[image setDelegate:@"Original delegate marker"];CHECK(rejects(image,keyed),"delegate rejected before graph writes");[image setDelegate:nil];[image setBackgroundColor:[NSColor redColor]];CHECK(rejects(image,keyed),"unimplemented color state rejected before graph writes");[image setBackgroundColor:nil];
 NSImage *custom=[NSImage imageWithSize:NSMakeSize(8,4) flipped:NO drawingHandler:^BOOL(NSRect rect){return YES;}];[image addRepresentation:[[custom representations]objectAtIndex:0]];CHECK(rejects(image,keyed),"later unsupported representation does not write/drop/flatten earlier content");[image release];
 image=[[QVUnknownImage alloc]initWithSize:NSMakeSize(3,2)];CHECK(rejects(image,keyed),"unknown image subclass rejected");[image release];
 NSBitmapImageRep *rep=makeBitmap([QVUnknownBitmap class],0,4,0);image=[[NSImage alloc]initWithSize:NSMakeSize(3,2)];[image addRepresentation:rep];[rep release];CHECK(rejects(image,keyed),"unknown bitmap subclass rejected");[image release];
 puts("PASS explicit unsupported image state before graph writes");return 0;
}
static NSMutableDictionary *changedBitmap(NSDictionary *base,NSString *key,id value){NSMutableDictionary *record=[[base mutableCopy]autorelease];[record setObject:value forKey:key];return record;}
static BOOL badBitmapRecord(id record,BOOL keyed,NSString *exception){QVImageRecordCoder *coder=[[QVImageRecordCoder alloc]initKeyed:keyed record:record];BOOL rejected=NO;@try{NSBitmapImageRep *rep=[[NSBitmapImageRep alloc]initWithCoder:coder];[rep release];}@catch(NSException *error){rejected=[[error name]isEqual:exception];}[coder release];return rejected;}
static int malformed(BOOL keyed){
 NSImage *source=makeImage(NO);QVImageRecordCoder *writer=[[QVImageRecordCoder alloc]initKeyed:keyed record:nil];[source encodeWithCoder:writer];CHECK([writer writes]==1&&[[writer record]isKindOfClass:[NSDictionary class]],"real image writer creates one project envelope");NSDictionary *base=[writer record];
 CHECK(badRecord(@{},keyed),"missing project version rejects");NSMutableDictionary *changed=[[base mutableCopy]autorelease];
 [changed setObject:@2 forKey:@"version"];CHECK(badRecord(changed,keyed),"unknown image schema rejects");
 [changed setObject:@1 forKey:@"version"];[changed setObject:@[@(NAN),@1]forKey:@"size"];CHECK(badRecord(changed,keyed),"nonfinite geometry rejects");
 changed=[[base mutableCopy]autorelease];[changed setObject:@[@"not a bitmap"]forKey:@"representations"];CHECK(badRecord(changed,keyed),"wrong representation object class rejects");
 QVImageRecordCoder *bitmapWriter=[[QVImageRecordCoder alloc]initKeyed:keyed record:nil];[[[source representations]objectAtIndex:0]encodeWithCoder:bitmapWriter];CHECK([bitmapWriter writes]==1&&[[bitmapWriter record]isKindOfClass:[NSDictionary class]],"real standalone bitmap writer prerequisite");NSDictionary *bitmap=[bitmapWriter record];NSString *exception=NSInvalidUnarchiveOperationException;
 CHECK(badBitmapRecord(@{},keyed,exception),"missing bitmap schema rejects");
 CHECK(badBitmapRecord(changedBitmap(bitmap,@"width",@(-1)),keyed,exception),"negative bitmap width rejects");CHECK(badBitmapRecord(changedBitmap(bitmap,@"width",@(INT_MAX)),keyed,exception),"row multiplication overflow rejects");CHECK(badBitmapRecord(changedBitmap(bitmap,@"stride",@1),keyed,exception),"short stride rejects");CHECK(badBitmapRecord(changedBitmap(bitmap,@"height",@(INT_MAX)),keyed,exception),"plane multiplication overflow rejects");CHECK(badBitmapRecord(changedBitmap(bitmap,@"planeData",[NSData dataWithBytes:"x" length:1]),keyed,exception),"truncated plane rejects");CHECK(badBitmapRecord(changedBitmap(bitmap,@"format",@4),keyed,exception),"unsupported float samples reject");CHECK(badBitmapRecord(changedBitmap(bitmap,@"samples",@3.5),keyed,exception),"fractional integer rejects");CHECK(badBitmapRecord(changedBitmap(bitmap,@"version",@2),keyed,exception),"unknown bitmap schema rejects");
 NSMutableDictionary *cycle=[NSMutableDictionary dictionary];[cycle setObject:cycle forKey:@"self"];CHECK(badBitmapRecord(changedBitmap(bitmap,@"properties",cycle),keyed,exception),"cyclic metadata rejects without recursive traversal");[cycle removeAllObjects];
 [bitmapWriter release];[writer release];[source release];puts("PASS malformed image/standalone bitmap project archives reject explicitly");return 0;
}
static int namesAndEmpty(BOOL keyed,BOOL empty){
 NSImage *source=empty?[[NSImage alloc]initWithSize:NSMakeSize(13.5,8.25)]:makeImage(NO);
 NSString *name=@"Qvolution-own-image-archive-cache-control";
 if(!empty)CHECK([source setName:name]&&[NSImage imageNamed:name]==source,"own registered image-name control");
 NSImage *copy=unarchive(archive(source,keyed),keyed);CHECK(copy&&copy!=source,"distinct decoded image");
 if(empty)CHECK([[copy representations]count]==0&&NSEqualSizes([copy size],NSMakeSize(13.5,8.25)),"intentional empty image preserves point size");
 else CHECK([[copy name]isEqual:name]&&[NSImage imageNamed:name]==source,"name metadata survives without replacing shared named image");
 [source release];puts("PASS intentional empty image or image-name cache isolation");return 0;
}
static int properties(BOOL keyed){
 NSImage *source=makeImage(NO);NSBitmapImageRep *rep=[[source representations]objectAtIndex:0];
 NSMutableArray *children=[NSMutableArray arrayWithObjects:@1,@"metadata",[NSData dataWithBytes:"Own" length:3],nil];
 NSMutableDictionary *metadata=[NSMutableDictionary dictionaryWithObject:children forKey:@"Original"];
 [rep setProperty:NSImageEXIFData withValue:metadata];CHECK([[rep valueForProperty:NSImageEXIFData]isEqual:metadata],"public metadata setter/getter control before archive");
 NSImage *copy=unarchive(archive(source,keyed),keyed);CHECK(copy,"decoded metadata image exists");
 id before=[[[copy representations]objectAtIndex:0]valueForProperty:NSImageEXIFData];CHECK([before isEqual:metadata],"nested property-list metadata survives");
 [children addObject:@"mutated source"];CHECK(![before isEqual:metadata]&&[[before objectForKey:@"Original"]count]==3,"decoded metadata has independent children");
 [source release];puts("PASS actual bitmap property metadata archive workflow");return 0;
}
static int decodedBitmapCopies(BOOL keyed){
 CHECK([unarchive(archive(@[@"Original decoded-copy scalar control",@42],keyed),keyed)isEqual:(@[@"Original decoded-copy scalar control",@42])],"actual generic archive control");
 for(unsigned kind=0;kind<3;kind++)for(unsigned order=0;order<2;order++){
  NSBitmapImageRep *decoded=nil;NSData *plane=nil,*cgBytes=nil;
  @autoreleasepool{
   NSImage *source=kind?cgImage(kind==2):makeImage(NO);CHECK(source,"real image source before decoded bitmap copy");NSBitmapImageRep *rep=[[source representations]objectAtIndex:0];
   if(kind)cgBytes=(NSData *)CGDataProviderCopyData(CGImageGetDataProvider([rep CGImage]));
   if(kind==1)plane=[[NSData alloc]initWithBytes:[cgBytes bytes] length:58];else plane=[[NSData alloc]initWithBytes:[rep bitmapData] length:[rep bytesPerRow]*[rep pixelsHigh]];
   NSImage *image=unarchive(archive(source,keyed),keyed);CHECK(image&&[[image representations]count],"actual populated image decoded before bitmap copy");decoded=[[[image representations]objectAtIndex:0]retain];[source release];
  }
  [decoded setProperty:@"QvolutionDecodedCopy" withValue:@"original"];CHECK([[decoded valueForProperty:@"QvolutionDecodedCopy"]isEqual:@"original"],"real decoded bitmap property prerequisite");
  NSBitmapImageRep *copy=[decoded copy];CHECK(copy&&copy!=decoded&&[copy bitmapData]!=[decoded bitmapData]&&!memcmp([copy bitmapData],[plane bytes],[plane length])&&NSEqualSizes([copy size],[decoded size]),"actual decoded bitmap copy has independent bytes and logical state");
  [decoded bitmapData][0]^=1;[decoded setProperty:@"QvolutionDecodedCopy" withValue:@"changed"];CHECK(!memcmp([copy bitmapData],[plane bytes],[plane length])&&[[copy valueForProperty:@"QvolutionDecodedCopy"]isEqual:@"original"],"decoded bitmap copy isolates source plane and property mutations");
  NSBitmapImageRep *survivor=order?decoded:copy;[(order?copy:decoded)release];
  if(kind){CFDataRef actual=CGDataProviderCopyData(CGImageGetDataProvider([survivor CGImage]));CHECK([(NSData *)actual isEqual:cgBytes],"decoded copied CG backing survives first bitmap release");CFRelease(actual);}
  if(!order)CHECK(!memcmp([survivor bitmapData],[plane bytes],[plane length]),"copied decoded plane survives original owner release");
  [survivor release];[plane release];[cgBytes release];
 }
 puts("PASS actual decoded NSBitmapImageRep plane/CG/dual copies in both release orders");return 0;
}
static BOOL allocationRecord(id record,BOOL keyed){QVImageRecordCoder *coder=[[QVImageRecordCoder alloc]initKeyed:keyed record:record];BOOL rejected=NO;@try{NSImage *image=[[NSImage alloc]initWithCoder:coder];[image release];}@catch(NSException *error){rejected=[[error name]isEqual:NSMallocException];}[coder release];return rejected;}
static int allocationFailures(BOOL keyed){
 NSImage *source=makeImage(NO);QVImageRecordCoder *writer=[[QVImageRecordCoder alloc]initKeyed:keyed record:nil];[source encodeWithCoder:writer];CHECK([writer writes]==1&&[[writer record]isKindOfClass:[NSDictionary class]],"real writer prerequisite before allocation-field faults");NSDictionary *base=[writer record];
 QVNilCopyString *text=[[[QVNilCopyString alloc]initWithValue:@"Original nil-copy allocation fixture"]autorelease];CHECK([text isKindOfClass:[NSString class]]&&[text length]>0&&[text copy]==nil,"original NSString nil-copy control");
 for(NSString *key in @[@"name",@"accessibility"]){NSMutableDictionary *record=[[base mutableCopy]autorelease];[record setObject:text forKey:key];CHECK(allocationRecord(record,keyed),"nil scalar-string copy must reject, never silently drop metadata");}
 QVImageRecordCoder *bitmapWriter=[[QVImageRecordCoder alloc]initKeyed:keyed record:nil];[[[source representations]objectAtIndex:0]encodeWithCoder:bitmapWriter];CHECK([bitmapWriter writes]==1,"standalone bitmap writer prerequisite");NSDictionary *bitmap=[bitmapWriter record];
 QVNilCopyString *space=[[[QVNilCopyString alloc]initWithValue:NSDeviceRGBColorSpace]autorelease];CHECK([space isEqual:NSDeviceRGBColorSpace]&&[space copy]==nil,"original color-space nil-copy control");CHECK(badBitmapRecord(changedBitmap(bitmap,@"colorSpace",space),keyed,NSMallocException),"nil copied bitmap color space must reject populated output");
 QVNilCopyDictionary *metadata=[[[QVNilCopyDictionary alloc]initWithValue:@{@"Original":@[@1,@"metadata"]}]autorelease];CHECK([metadata isKindOfClass:[NSDictionary class]]&&[metadata count]==1&&[metadata mutableCopy]==nil,"original metadata dictionary nil-copy control");CHECK(badBitmapRecord(changedBitmap(bitmap,@"properties",metadata),keyed,NSMallocException),"nil owned metadata dictionary must reject explicitly");
 NSImage *cg=cgImage(NO);QVImageRecordCoder *cgWriter=[[QVImageRecordCoder alloc]initKeyed:keyed record:nil];[[[cg representations]objectAtIndex:0]encodeWithCoder:cgWriter];CHECK([cgWriter writes]==1,"real standalone CG bitmap writer prerequisite");NSDictionary *cgRecord=[cgWriter record];NSData *bytes=[cgRecord objectForKey:@"cgData"];QVNilCopyData *data=[[[QVNilCopyData alloc]initWithValue:bytes]autorelease];CHECK([data isKindOfClass:[NSData class]]&&[data length]==[bytes length]&&[data copy]==nil,"original CG provider nil-copy control");CHECK(badBitmapRecord(changedBitmap(cgRecord,@"cgData",data),keyed,NSMallocException),"nil owned CG provider snapshot must reject instead of creating empty backing");
 [cgWriter release];[cg release];[bitmapWriter release];[writer release];[source release];puts("PASS explicit image/bitmap archive allocation-field failure policy");return 0;
}
static int sharedGraph(BOOL keyed){
 NSBitmapImageRep *source=makeBitmap([NSBitmapImageRep class],0,4,NSAlphaNonpremultipliedBitmapFormat);CHECK(source,"actual shared bitmap source");NSMutableArray *values=[NSMutableArray arrayWithObjects:@"Original mutable metadata",@42,nil];NSMutableDictionary *metadata=[NSMutableDictionary dictionaryWithObjectsAndKeys:values,@"first",values,@"second",nil];[source setProperty:NSImageEXIFData withValue:metadata];CHECK([source valueForProperty:NSImageEXIFData]==metadata,"public bitmap metadata prerequisite");
 NSImage *first=[[NSImage alloc]initWithSize:NSMakeSize(9,5)],*second=[[NSImage alloc]initWithSize:NSMakeSize(8,4)];[first addRepresentation:source];[first addRepresentation:source];[second addRepresentation:source];NSArray *input=@[first,second,source,values];
 NSArray *decoded=unarchive(archive(input,keyed),keyed);CHECK([decoded isKindOfClass:[NSArray class]]&&[decoded count]==4,"real image/bitmap graph decodes");NSImage *a=[decoded objectAtIndex:0],*b=[decoded objectAtIndex:1];NSBitmapImageRep *rep=[decoded objectAtIndex:2];CHECK(rep!=source&&[rep class]==[NSBitmapImageRep class],"standalone decoded bitmap exists independently");CHECK([[a representations]count]==2&&[[b representations]count]==1&&[[a representations]objectAtIndex:0]==rep&&[[a representations]objectAtIndex:1]==rep&&[[b representations]objectAtIndex:0]==rep,"duplicate, cross-image and standalone references preserve one bitmap identity");
 unsigned char old=[source bitmapData][0];[rep bitmapData][0]^=0x3F;CHECK([[[a representations]objectAtIndex:1]bitmapData][0]==[rep bitmapData][0]&&[source bitmapData][0]==old,"shared decoded bitmap mutation propagates only within decoded graph");
 id restored=[rep valueForProperty:NSImageEXIFData],child=[restored objectForKey:@"first"];CHECK([restored isKindOfClass:[NSMutableDictionary class]]&&[child isKindOfClass:[NSMutableArray class]]&&child==[restored objectForKey:@"second"]&&child==[decoded objectAtIndex:3]&&child!=values,"metadata mutable classes and shared child references survive archive");[child addObject:@"decoded mutation"];CHECK([[restored objectForKey:@"second"]count]==3&&[values count]==2,"mutable decoded metadata remains usable and independent of source graph");
 [first release];[second release];[source release];puts("PASS real Foundation shared image/bitmap and mutable metadata object graph");return 0;
}
static int standaloneBitmap(BOOL keyed){NSBitmapImageRep *source=makeBitmap([NSBitmapImageRep class],1,4,NSAlphaFirstBitmapFormat|NSAlphaNonpremultipliedBitmapFormat);CHECK(source&&[source conformsToProtocol:@protocol(NSCoding)],"original standalone bitmap advertises NSCoding");NSData *bytes=[NSData dataWithBytes:[source bitmapData]length:[source bytesPerRow]*[source pixelsHigh]];NSBitmapImageRep *copy=unarchive(archive(source,keyed),keyed);CHECK(copy&&copy!=source&&[copy class]==[NSBitmapImageRep class]&&[copy bitmapFormat]==[source bitmapFormat]&&[copy bytesPerRow]==[source bytesPerRow]&&NSEqualSizes([copy size],[source size])&&!memcmp([copy bitmapData],[bytes bytes],[bytes length]),"actual standalone bitmap layout/content roundtrip");[source release];puts("PASS standalone raw bitmap NSCoding workflow");return 0;}
static int liveStateBoundary(BOOL keyed){
 NSImage *source=makeImage(NO);QVImageRecordCoder *writer=[[QVImageRecordCoder alloc]initKeyed:keyed record:nil];[source encodeWithCoder:writer];CHECK([writer writes]==1,"real project image writer prerequisite");NSDictionary *base=[writer record];
 NSBitmapImageRep *gray=[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:NULL pixelsWide:3 pixelsHigh:2 bitsPerSample:8 samplesPerPixel:1 hasAlpha:NO isPlanar:NO colorSpaceName:NSDeviceWhiteColorSpace bitmapFormat:0 bytesPerRow:3 bitsPerPixel:8];
 NSBitmapImageRep *planar=[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:NULL pixelsWide:3 pixelsHigh:2 bitsPerSample:8 samplesPerPixel:3 hasAlpha:NO isPlanar:YES colorSpaceName:NSDeviceRGBColorSpace bitmapFormat:0 bytesPerRow:3 bitsPerPixel:8],*empty=[NSBitmapImageRep new];CHECK(gray&&planar&&empty,"actual exact-class gray/planar/empty bitmap controls");
 for(NSBitmapImageRep *rep in @[gray,planar,empty]){CHECK([rep class]==[NSBitmapImageRep class],"exact bitmap class control");NSMutableDictionary *record=[[base mutableCopy]autorelease];[record setObject:@[rep]forKey:@"representations"];CHECK(badRecord(record,keyed),"unsupported live bitmap state rejected without object reconstruction");}
 NSBitmapImageRep *invalid=makeBitmap([NSBitmapImageRep class],0,4,0);[invalid setSize:NSMakeSize(NAN,2)];NSMutableDictionary *record=[[base mutableCopy]autorelease];[record setObject:@[invalid]forKey:@"representations"];CHECK(badRecord(record,keyed),"nonfinite live bitmap metadata rejects");[invalid release];
 QVImageRecordCoder *reader=[[QVImageRecordCoder alloc]initKeyed:keyed record:base];BOOL imageRejected=NO;@try{NSImage *image=[[QVUnknownImage alloc]initWithCoder:reader];[image release];}@catch(NSException *error){imageRejected=[[error name]isEqual:NSInvalidUnarchiveOperationException];}CHECK(imageRejected,"unknown image receiver rejects project dictionary");[reader release];
 QVImageRecordCoder *bitmapWriter=[[QVImageRecordCoder alloc]initKeyed:keyed record:nil];[[[source representations]objectAtIndex:0]encodeWithCoder:bitmapWriter];CHECK([bitmapWriter writes]==1,"actual bitmap writer prerequisite");reader=[[QVImageRecordCoder alloc]initKeyed:keyed record:[bitmapWriter record]];BOOL bitmapRejected=NO;@try{NSBitmapImageRep *rep=[[QVUnknownBitmap alloc]initWithCoder:reader];[rep release];}@catch(NSException *error){bitmapRejected=[[error name]isEqual:NSInvalidUnarchiveOperationException];}CHECK(bitmapRejected,"unknown bitmap receiver rejects project dictionary");[reader release];[bitmapWriter release];
 [gray release];[planar release];[empty release];[writer release];[source release];puts("PASS live decoded bitmap state and exact receiver boundaries");return 0;
}
static int versionGuard(void){
 NSInteger saved=[NSImageRep version];NSImage *image=nil;NSBitmapImageRep *bitmap=nil;
 @try{
  [NSImageRep setVersion:17];image=makeImage(NO);bitmap=makeBitmap([NSBitmapImageRep class],0,4,0);
  for(id value in @[bitmap,image]){
   QVVersionImageRecordCoder *coder=[[QVVersionImageRecordCoder alloc]initKeyed:NO record:nil];BOOL rejected=NO;
   @try{[value encodeWithCoder:coder];}@catch(NSException *error){rejected=[[error name]isEqual:NSInvalidArchiveOperationException];}
   BOOL untouched=[coder writes]==0;[coder release];CHECK(rejected&&untouched,"caller-version17 unkeyed writer refuses before graph writes");
   rejected=NO;@try{archive(value,NO);}@catch(NSException *error){rejected=[[error name]isEqual:NSInvalidArchiveOperationException];}
   CHECK(rejected,"real NSArchiver refuses unsupported caller-version17 project record");
   NSData *data=archive(value,YES);id restored=unarchive(data,YES);CHECK(data&&restored,"keyed project coding remains independent of caller-version17");
  }
 }@finally{[image release];[bitmap release];[NSImageRep setVersion:saved];}
 CHECK([NSImageRep version]==saved,"caller class version restored");puts("PASS explicit unkeyed version17 writer guard and independent keyed control");return 0;
}
static int legacyBitmap(void){
 NSBitmapImageRep *source=makeBitmap([NSBitmapImageRep class],0,4,0);CHECK(source,"original legacy-path PNG source");NSData *png=[source representationUsingType:NSPNGFileType properties:@{}];CHECK([png length]>20,"real PNG producer control for existing legacy data branch");QVLegacyBitmapCoder *coder=[[QVLegacyBitmapCoder alloc]initKeyed:NO record:png];NSBitmapImageRep *rep=[[NSBitmapImageRep alloc]initWithCoder:coder];CHECK(rep&&[rep pixelsWide]==[source pixelsWide]&&[rep pixelsHigh]==[source pixelsHigh],"existing version17+ DataObject branch remains intact");[rep release];[coder release];[source release];puts("PASS existing own legacy bitmap DataObject branch; no native schema claim");return 0;
}
int main(int argc,char **argv){@autoreleasepool{@try{
 CHECK(argc==2,"explicit keyed|unkeyed|derive-keyed|derive-unkeyed|cg-keyed|cg-unkeyed|dual-keyed|dual-unkeyed|unsupported-keyed|unsupported-unkeyed|malformed-keyed|malformed-unkeyed|properties-control mode");NSString *mode=[NSString stringWithUTF8String:argv[1]];BOOL keyed=![mode hasSuffix:@"unkeyed"];
 if([mode isEqual:@"properties-control"]){NSBitmapImageRep *rep=makeBitmap([NSBitmapImageRep class],0,4,0);[rep setProperty:NSImageEXIFData withValue:@{@"Original":@[@1,@"metadata"]}];CHECK(([[rep valueForProperty:NSImageEXIFData]isEqual:@{@"Original":@[@1,@"metadata"]}]),"public bitmap metadata setter/getter control");[rep release];puts("PASS public bitmap metadata control");return 0;}
 if([mode isEqual:@"version-guard"])return versionGuard();if([mode hasPrefix:@"live-state-"])return liveStateBoundary(keyed);if([mode isEqual:@"legacy-bitmap"])return legacyBitmap();if([mode hasPrefix:@"shared-"])return sharedGraph(keyed);if([mode hasPrefix:@"standalone-"])return standaloneBitmap(keyed);if([mode hasPrefix:@"allocation-failures-"])return allocationFailures(keyed);if([mode hasPrefix:@"decoded-copy-"])return decodedBitmapCopies(keyed);if([mode hasPrefix:@"names-"])return namesAndEmpty(keyed,NO);if([mode hasPrefix:@"empty-"])return namesAndEmpty(keyed,YES);if([mode hasPrefix:@"properties-"])return properties(keyed);if([mode hasPrefix:@"unsupported-"])return unsupported(keyed);if([mode hasPrefix:@"malformed-"])return malformed(keyed);if([mode hasPrefix:@"dual-"])return cgRoundtrip(keyed,YES);if([mode hasPrefix:@"cg-"])return cgRoundtrip(keyed,NO);if([mode isEqual:@"keyed"]||[mode isEqual:@"unkeyed"]||[mode hasPrefix:@"derive-"])return roundtrip(keyed,[mode hasPrefix:@"derive-"]);
 CHECK(NO,"known mode");
 }@catch(NSException *error){fprintf(stderr,"FAIL exception %s\n",[[error name]UTF8String]);return 1;}}}
