#!/usr/bin/env python3
"""Execute our loader/launch methods on libobjc with controlled bundle/decoder doubles.
No Darling process, Apple code, GNUstep implementation or network is involved.
"""
import argparse,pathlib,re,subprocess,tempfile
p=pathlib.Path(__file__).resolve().parents[1]
a=argparse.ArgumentParser();a.add_argument('--source-ref');a.add_argument('--foundation-root',type=pathlib.Path);a.add_argument('--case',choices=['all','absent','collision'],default='all');args=a.parse_args()
def source(path):
 return subprocess.check_output(['git','show',args.source_ref+':'+path],cwd=p,text=True) if args.source_ref else (p/path).read_text()
def method(s,start):
 at=s.index(start);beg=s.index('{',at);depth=1;i=beg+1
 while depth:
  if s[i]=='{':depth+=1
  elif s[i]=='}':depth-=1
  i+=1
 return s[at:i]
loading=source('AppKit/nib.subproj/NSNibLoading.m')
methods=[method(loading,x) for x in ['+ (BOOL) loadNibNamed:', '- (BOOL) loadNibFile: (NSString *) fileName', '- (BOOL) loadNibNamed: (NSString *) name']]
init=method(source('AppKit/nib.subproj/NSNib.m'),'- initWithNibNamed:')
shared=method(source('AppKit/NSApplication.m'),'+ (NSApplication *) sharedApplication')
main=method(source('AppKit/NSApplication.m'),'int NSApplicationMain(')
principal=method((args.foundation_root/'src/NSBundle.m').read_text(),'- (Class)principalClass') if args.foundation_root else '- (Class)principalClass { return subclass ? [SubApplication class] : [NSApplication class]; }'
# Legacy GNU libobjc's compiler mode does not support dictionary subscripting.
main=main.replace('[bundle infoDictionary][@"NSMainNibFile"]','[[bundle infoDictionary] objectForKey: @"NSMainNibFile"]')
program=r'''
#include <objc/objc.h>
#include <objc/runtime.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define DARLING 1
#define NIBDEBUG(...)
#define NSLog(...)
typedef unsigned long NSUInteger;
typedef void NSZone;
static void *NSDefaultMallocZone(void) { return NULL; }
__attribute__((objc_root_class))
@interface NSObject { Class isa; }
+ (id)self; + (id)alloc; + (id)new; + (id)allocWithZone:(void *)z; + (Class)class;
- (id)init; - (id)autorelease; - (void)release; - (Class)class;
- (BOOL)isKindOfClass:(Class)c;
@end
@implementation NSObject
+ (id)self { return self; }
+ (id)alloc { return class_createInstance(self,0); }
+ (id)new { return [[self alloc] init]; }
+ (id)allocWithZone:(void *)z { return [self alloc]; }
+ (Class)class { return self; }
- (id)init { return self; }
- (id)autorelease { return self; }
- (void)release {}
- (Class)class { return object_getClass(self); }
- (BOOL)isKindOfClass:(Class)c { for(Class k=object_getClass(self);k;k=class_getSuperclass(k)) if(k==c)return YES; return NO; }
@end
@interface NSString : NSObject
- (NSUInteger)length; - (const char *)UTF8String; - (id)copy;
- (NSString *)stringByDeletingLastPathComponent;
- (NSString *)stringByDeletingPathExtension;
- (NSString *)stringByAppendingFormat:(NSString *)format,...;
- (NSString *)stringByAppendingPathExtension:(NSString *)ext;
- (NSString *)lastPathComponent;
- (BOOL)isEqualToString:(NSString *)s;
+ (id)stringWithUTF8String:(const char *)s;
@end
@interface FixtureString : NSString { const char *bytes; unsigned int size; } @end
@implementation NSString
- (NSUInteger)length { return 0; }
- (const char *)UTF8String { return ""; }
- (id)copy { return self; }
- (NSString *)stringByDeletingLastPathComponent { return @""; }
- (NSString *)stringByDeletingPathExtension { return self; }
- (NSString *)stringByAppendingFormat:(NSString *)s,... { return @"platform-variant"; }
- (NSString *)stringByAppendingPathExtension:(NSString *)s { return @"Main.nib"; }
- (NSString *)lastPathComponent { return self; }
- (BOOL)isEqualToString:(NSString *)s { return s && strcmp([self UTF8String],[s UTF8String])==0; }
+ (id)stringWithUTF8String:(const char *)s { return @"unused argument"; }
@end
@implementation FixtureString
- (NSUInteger)length { return size; }
- (const char *)UTF8String { return bytes; }
@end
static NSString *NSNibOwner=@"NSOwner",*NSPlatformResourceNameSuffix=@"linux";
@class NSBundle, NSArray;
static NSBundle *mainBundle,*frameworkBundle;
static id recordedOwner;
static NSString *recordedPath;
static int lookups,instantiations,runs,missingName,subclass,mainHasNib=1;
@interface NSDictionary : NSObject { @public id owner; }
+ (id)dictionaryWithObject:(id)obj forKey:(id)key;
- (id)objectForKey:(NSString *)key; - (NSUInteger)count;
@end
@implementation NSDictionary
+ (id)dictionaryWithObject:(id)obj forKey:(id)key { NSDictionary *d=[self new];d->owner=obj;return d; }
- (id)objectForKey:(NSString *)key {
 if ([key isEqualToString:NSNibOwner]) return owner;
 if ([key isEqualToString:@"NSMainNibFile"]) return missingName?nil:@"Main";
 if ([key isEqualToString:@"NSPrincipalClass"]) return subclass?@"SubApplication":@"NSApplication";
 return nil;
}
- (NSUInteger)count { return 1; }
@end
@interface NSAutoreleasePool : NSObject @end
@implementation NSAutoreleasePool @end
@interface NSMutableArray : NSObject
+ (id)arrayWithCapacity:(NSUInteger)n; - (void)addObject:(id)o; - (NSUInteger)count; - (id)lastObject;
@end
@implementation NSMutableArray
+ (id)arrayWithCapacity:(NSUInteger)n { return [self new]; }
- (void)addObject:(id)o {} - (NSUInteger)count { return 0; } - (id)lastObject { return nil; }
@end
@interface NSUserDefaults : NSObject
+ (id)standardUserDefaults; - (void)setObject:(id)obj forKey:(id)key;
@end
@implementation NSUserDefaults
+ (id)standardUserDefaults { return nil; } - (void)setObject:(id)obj forKey:(id)key {}
@end
@interface NSApplication : NSObject
+ (NSApplication *)sharedApplication; - (void)run;
@end
static NSApplication *NSApp;
@implementation NSApplication
SHARED_METHOD
- (id)init { NSApp=self; return self; }
- (void)run { runs++; }
@end
@interface SubApplication : NSApplication @end
@implementation SubApplication @end
static Class NSClassFromString(NSString *s) { return [s isEqualToString:@"SubApplication"]?[SubApplication class]:([s isEqualToString:@"NSApplication"]?[NSApplication class]:Nil); }
@interface NSStoryboard : NSObject
+ (id)mainStoryboard; - (void)_instantiateAsMainStoryboard;
@end
@implementation NSStoryboard
+ (id)mainStoryboard { return nil; } - (void)_instantiateAsMainStoryboard {}
@end
@interface NSNib : NSObject
- (id)initWithContentsOfFile:(NSString *)path;
- (id)initWithNibNamed:(NSString *)name bundle:(NSBundle *)bundle;
- (BOOL)instantiateNibWithExternalNameTable:(NSDictionary *)table;
- (BOOL)instantiateWithOwner:(id)owner topLevelObjects:(NSArray **)objects;
@end
@interface NSBundle : NSObject { Class _principalClass; }
- (BOOL)isLoaded; - (BOOL)load;
+ (id)mainBundle; + (id)bundleForClass:(Class)c;
+ (void)pushNibPath:(id)p; + (void)popNibPath;
+ (void)pushNibLoadingBundle:(id)b; + (void)popNibLoadingBundle;
+ (BOOL)loadNibNamed:(NSString *)name owner:(id)owner;
- (BOOL)loadNibFile:(NSString *)name externalNameTable:(NSDictionary *)table withZone:(void *)zone;
- (BOOL)loadNibNamed:(NSString *)name owner:(id)owner topLevelObjects:(NSArray **)objects;
- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)type;
- (NSDictionary *)infoDictionary; - (Class)principalClass;
@end
@implementation NSBundle
+ (id)mainBundle { return mainBundle; }
+ (id)bundleForClass:(Class)c { return frameworkBundle; }
+ (void)pushNibPath:(id)p {} + (void)popNibPath {}
+ (void)pushNibLoadingBundle:(id)b {} + (void)popNibLoadingBundle {}
- (NSDictionary *)infoDictionary { return [NSDictionary new]; }
- (BOOL)isLoaded {return YES;} - (BOOL)load {return YES;}
PRINCIPAL_METHOD
- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)type {
 lookups++;
 if (![name length]) return @"NSColorPickerColorList.nib";
 if ([name isEqualToString:@"platform-variant"]) return nil;
 // Same basename in both bundles proves which bundle launch selected.
 if ([name isEqualToString:@"Main"]) return self==mainBundle ? (mainHasNib?@"app/Main.nib":nil) : @"framework/Main.nib";
 return nil;
}
LOADER_METHODS
@end
@implementation NSNib
- (id)initWithContentsOfFile:(NSString *)path { recordedPath=path; return path?self:nil; }
- (BOOL)instantiateNibWithExternalNameTable:(NSDictionary *)table { instantiations++;recordedOwner=[table objectForKey:NSNibOwner];return YES; }
- (BOOL)instantiateWithOwner:(id)owner topLevelObjects:(NSArray **)objects { recordedOwner=owner;return YES; }
NIB_INIT
@end
MAIN_FUNCTION
int main(void) {
 mainBundle=[NSBundle new];frameworkBundle=[NSBundle new];
 id owner=[NSObject new];
 if (FIXTURE_CASE != 2) for (int empty=0;empty<2;empty++) {
  NSString *name=empty?@"":nil;
  lookups=instantiations=0;
  BOOL a=[NSBundle loadNibNamed:name owner:owner];
  BOOL b=[mainBundle loadNibFile:name externalNameTable:[NSDictionary dictionaryWithObject:owner forKey:NSNibOwner] withZone:NULL];
  BOOL c=[mainBundle loadNibNamed:name owner:owner topLevelObjects:NULL];
  id d=[[NSNib alloc] initWithNibNamed:name bundle:frameworkBundle];
  if (a||b||c||d||lookups||instantiations) { puts("FAIL: absent nib name selected a resource"); return 1; }
 }
 if (FIXTURE_CASE != 1) for(subclass=0;subclass<2;subclass++) {
  mainBundle=[NSBundle new];
  NSApp=nil;missingName=0;runs=0;recordedPath=nil;recordedOwner=nil;
  const char *argv[]={"owned-fixture"};
  NSApplicationMain(1,argv);
  if (![recordedPath isEqualToString:@"app/Main.nib"]) { puts("FAIL: main launch selected the owner framework nib"); return 1; }
  assert(recordedOwner==NSApp && runs==1);
  assert([NSApp isKindOfClass:subclass?[SubApplication class]:[NSApplication class]]);
  NSApp=nil;missingName=1;lookups=instantiations=0;runs=0;
  NSApplicationMain(1,argv);
  assert(runs==1 && lookups==0 && instantiations==0);
 }
 lookups=instantiations=0;mainHasNib=0;
 assert(![mainBundle loadNibFile:@"Missing" externalNameTable:[NSDictionary new] withZone:NULL]);
 assert(instantiations==0);
 puts("PASS: absent names, missing resource, main-bundle collision, owner identity, principal subclass and nibless launch");
 return 0;
}
'''
for key,value in [('PRINCIPAL_METHOD',principal),('SHARED_METHOD',shared),('LOADER_METHODS','\n'.join(methods)),('NIB_INIT',init),('MAIN_FUNCTION',main)]:program=program.replace(key,value)
inc=subprocess.check_output(['gcc','-print-file-name=include'],text=True).strip()
with tempfile.TemporaryDirectory(prefix='qv-launch-nib-') as tmp:
 src=pathlib.Path(tmp)/'fixture.m';exe=pathlib.Path(tmp)/'fixture';src.write_text(program)
 subprocess.run(['clang','-O1','-g','-fobjc-runtime=gcc','-fconstant-string-class=FixtureString','-DDARLING','-DFIXTURE_CASE='+str({'all':0,'absent':1,'collision':2}[args.case]),'-I'+inc,'-Wno-objc-method-access','-Wno-incompatible-pointer-types','-fsanitize=undefined','-fno-sanitize-recover=all',str(src),'-lobjc','-o',str(exe)],check=True)
 subprocess.run([str(exe)],check=True)
