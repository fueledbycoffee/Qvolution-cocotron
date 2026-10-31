"""Actual production copy/dealloc methods, with owned native ObjC/NSZone transport.

This adapter tests transaction cleanup, not Darling Foundation/CG semantics.
"""
from pathlib import Path
import subprocess,os,argparse
ap=argparse.ArgumentParser();ap.add_argument('--component',type=Path,default=Path(__file__).resolve().parents[1]);ap.add_argument('--source-file',type=Path);ap.add_argument('--output',type=Path,required=True);args=ap.parse_args();args.output.mkdir(exist_ok=True,parents=True)
src=(args.source_file or args.component/'AppKit/NSBitmapImageRep.m').read_text();copy=src[src.index('- copyWithZone:(NSZone *)zone {'):src.index('- (void) dealloc {')];dealloc=src[src.index('- (void) dealloc {'):src.index('- (int) incrementalLoadFromData:')]
transport=r'''
#include <objc/Object.h>
#include <objc/runtime.h>
#include <objc/objc-exception.h>
#include <stdint.h>
#include <limits.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <assert.h>
typedef size_t NSUInteger;
#define NSUIntegerMax SIZE_MAX
typedef void NSZone;
@class NSString;
static long failAt=-1, stages=0;static int throwMode;
static long liveObjects;static unsigned failures;
static void *allocations[1024];static size_t liveAllocations;
@interface NSObject:Object { @public NSUInteger _rc; }
+ alloc;+ new;- init;- retain;- (void)release;- (void)dealloc;
@end
@implementation NSObject
+ alloc{id object=class_createInstance(self,0);assert(object);((NSObject *)object)->_rc=1;liveObjects++;return object;}
+ new{return [[self alloc]init];}
- init{return self;}
- retain{_rc++;return self;}
- (void)release{assert(_rc);if(--_rc==0)[self dealloc];}
- (void)dealloc{liveObjects--;object_dispose(self);}
@end
@interface NSException:NSObject
+ (void)raise:(id)kind format:(id)format;
@end
static NSException *injectedException;
static id NSInvalidArgumentException,NSMallocException;
@implementation NSException
+ (void)raise:(id)kind format:(id)format{assert(injectedException);@throw injectedException;}
@end
static BOOL fail(void){BOOL match=stages++==failAt;if(match&&throwMode)[NSException raise:nil format:nil];return match;}
static void remember(void *p){assert(p&&liveAllocations<1024);allocations[liveAllocations++]=p;}
static void *NSZoneCalloc(NSZone *zone,NSUInteger n,NSUInteger size){if(fail())return NULL;void *p=calloc(n,size);assert(p);remember(p);return p;}
static void *NSZoneMalloc(NSZone *zone,NSUInteger size){if(fail())return NULL;void *p=malloc(size);assert(p);remember(p);return p;}
static void NSZoneFree(NSZone *zone,void *p){if(!p)return;size_t i;for(i=0;i<liveAllocations;i++)if(allocations[i]==p)break;assert(i<liveAllocations);allocations[i]=allocations[--liveAllocations];free(p);}
@interface QVResource:NSObject { @public unsigned tag; }
- copyWithZone:(NSZone *)zone;- mutableCopyWithZone:(NSZone *)zone;
@end
@implementation QVResource
- copyWithZone:(NSZone *)zone{if(fail())return nil;QVResource *copy=[QVResource new];copy->tag=tag;return copy;}
- mutableCopyWithZone:(NSZone *)zone{return [self copyWithZone:zone];}
@end
static id CGImageRetain(id image){return [image retain];}
static void CGImageRelease(id image){[image release];}
@interface NSBitmapImageRep:NSObject {
 @public
 int _samplesPerPixel,_bytesPerRow,_pixelsHigh;
 BOOL _isPlanar,_freeWhenDone;
 unsigned char **_bitmapPlanes;
 QVResource *_colorSpaceName,*_properties;
 id _cgImage;
}
- (int)numberOfPlanes;- copyWithZone:(NSZone *)zone;- (void)dealloc;
@end
static id NSCopyObject(id object,NSUInteger extraBytes,NSZone *zone){
 if(fail())return nil;
 id result=class_createInstance(object_getClass(object),extraBytes);assert(result);
 memcpy(result,object,class_getInstanceSize(object_getClass(object)));((NSObject *)result)->_rc=1;liveObjects++;return result;
}
@implementation NSBitmapImageRep
- (int)numberOfPlanes{return _isPlanar?_samplesPerPixel:1;}
'''
main=r'''
@end
static NSBitmapImageRep *source(BOOL owned,BOOL planes){
 NSBitmapImageRep *image=[NSBitmapImageRep new];image->_isPlanar=YES;image->_samplesPerPixel=3;image->_bytesPerRow=17;image->_pixelsHigh=5;image->_freeWhenDone=owned;
 image->_colorSpaceName=[QVResource new];image->_colorSpaceName->tag=1;image->_properties=[QVResource new];image->_properties->tag=2;image->_cgImage=[QVResource new];((QVResource *)image->_cgImage)->tag=3;
 if(planes){image->_bitmapPlanes=NSZoneCalloc(NULL,3,sizeof(unsigned char *));for(unsigned p=0;p<3;p++){image->_bitmapPlanes[p]=NSZoneMalloc(NULL,85);for(unsigned i=0;i<85;i++)image->_bitmapPlanes[p][i]=(unsigned char)(p*47+i*13+7);}}
 return image;
}
static void checkSource(NSBitmapImageRep *image,BOOL planes){
 assert(image->_rc==1&&image->_colorSpaceName->_rc==1&&image->_properties->_rc==1&&((QVResource *)image->_cgImage)->_rc==1);
 assert(image->_colorSpaceName->tag==1&&image->_properties->tag==2&&((QVResource *)image->_cgImage)->tag==3);
 if(planes)for(unsigned p=0;p<3;p++)for(unsigned i=0;i<85;i++)assert(image->_bitmapPlanes[p][i]==(unsigned char)(p*47+i*13+7));
}
static BOOL completeCopy(NSBitmapImageRep *copy,NSBitmapImageRep *original,BOOL planes){
 if(!copy||!copy->_colorSpaceName||!copy->_properties||copy->_colorSpaceName==original->_colorSpaceName||copy->_properties==original->_properties||copy->_cgImage!=original->_cgImage)return NO;
 if(planes)for(unsigned p=0;p<3;p++)if(!copy->_bitmapPlanes||!copy->_bitmapPlanes[p]||copy->_bitmapPlanes[p]==original->_bitmapPlanes[p]||memcmp(copy->_bitmapPlanes[p],original->_bitmapPlanes[p],85))return NO;
 return YES;
}
int main(void){
 injectedException=[NSException new];long baseline=liveObjects;
 NSBitmapImageRep *original=source(YES,YES);stages=0;NSBitmapImageRep *copy=[original copyWithZone:NULL];assert(completeCopy(copy,original,YES));long points=stages;[copy release];checkSource(original,YES);
 long objectBaseline=liveObjects;size_t allocationBaseline=liveAllocations;
 for(int mode=0;mode<2;mode++)for(long point=0;point<points;point++){
  stages=0;failAt=point;throwMode=mode;copy=nil;BOOL caught=NO;
  @try{copy=[original copyWithZone:NULL];}@catch(NSException *error){assert(error==injectedException);caught=YES;}
  failAt=-1;
  if(copy){fprintf(stderr,"FAIL allocation stage %ld mode %s returned a nonnull incomplete/silent-success copy\n",point,mode?"throw":"nil");failures++;[copy release];copy=nil;}
  assert(caught||!copy);assert(liveObjects==objectBaseline&&liveAllocations==allocationBaseline);checkSource(original,YES);
 }
 // Invalid declared extents/pointers must reject before constructing anything.
 for(unsigned invalid=0;invalid<4;invalid++){
  int row=original->_bytesPerRow,height=original->_pixelsHigh,count=original->_samplesPerPixel;unsigned char *plane=original->_bitmapPlanes[1];
  if(invalid==0)original->_bytesPerRow=0;else if(invalid==1)original->_pixelsHigh=-1;else if(invalid==2)original->_samplesPerPixel=0;else original->_bitmapPlanes[1]=NULL;
  stages=0;BOOL caught=NO;copy=nil;@try{copy=[original copyWithZone:NULL];}@catch(NSException *error){caught=YES;}
  original->_bytesPerRow=row;original->_pixelsHigh=height;original->_samplesPerPixel=count;original->_bitmapPlanes[1]=plane;
  assert(caught&&!copy&&stages==0&&liveObjects==objectBaseline&&liveAllocations==allocationBaseline);checkSource(original,YES);
 }
 [original release];assert(liveObjects==baseline&&liveAllocations==0);
 // Source borrowed planes remain caller-owned; copy owns its detached buffers.
 original=source(NO,YES);unsigned char *borrowed[3];memcpy(borrowed,original->_bitmapPlanes,sizeof(borrowed));copy=[original copyWithZone:NULL];assert(completeCopy(copy,original,YES));[original release];for(unsigned p=0;p<3;p++)NSZoneFree(NULL,borrowed[p]);for(unsigned p=0;p<3;p++)assert(copy->_bitmapPlanes[p][0]==(unsigned char)(p*47+7));[copy release];assert(liveObjects==baseline&&liveAllocations==0);
 original=source(YES,NO);copy=[original copyWithZone:NULL];assert(completeCopy(copy,original,NO)&&!copy->_bitmapPlanes);[original release];assert(((QVResource *)copy->_cgImage)->tag==3);[copy release];assert(liveObjects==baseline&&liveAllocations==0);
 NSBitmapImageRep *empty=[NSBitmapImageRep new];copy=[empty copyWithZone:NULL];assert(copy&&!copy->_bitmapPlanes&&!copy->_cgImage&&!copy->_properties&&!copy->_colorSpaceName);[empty release];[copy release];assert(liveObjects==baseline&&liveAllocations==0);
 [injectedException release];injectedException=nil;assert(liveObjects==0);
 printf("%s actual copy/dealloc method transaction adapter: %ld allocation stages x nil/throw, borrowed/CG/empty, zero tracked owned resources\n",failures?"FAIL":"PASS",points);
 return failures?1:0;
}
'''
file=args.output/'native-copy-faults.m';file.write_text(transport+copy+dealloc+main)
binary=args.output/'native-copy-faults';subprocess.run(['clang','-O1','-g','-I'+subprocess.check_output(['gcc','-print-file-name=include'],text=True).strip(),'-fobjc-runtime=gcc','-fobjc-exceptions','-fexceptions','-fsanitize=address,undefined','-fno-omit-frame-pointer',str(file),'-lobjc','-o',str(binary)],check=True)
result=subprocess.run([str(binary)],env={**os.environ,'ASAN_OPTIONS':'detect_leaks=0'});raise SystemExit(result.returncode)
