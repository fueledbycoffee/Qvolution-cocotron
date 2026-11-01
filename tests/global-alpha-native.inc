#include <objc/runtime.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <math.h>
#define MIN(a,b) ((a)<(b)?(a):(b))
#define MAX(a,b) ((a)>(b)?(a):(b))
#define RI_INT_MIN MIN
#define RI_INT_MAX MAX
#define RI_FLOOR_TO_INT(v) ((int)floor(v))
#define RI_CLAMP(v,a,b) MIN(MAX(v,a),b)
#define RI_ISNAN isnan
#define RI_ASSERT assert
#define ONYX2D_STATIC static
#define ONYX2D_STATIC_INLINE static inline
#define TRUE true
#define FALSE false
#define RI_MIN MIN
#define RI_MAX MAX
typedef double O2Float;
typedef unsigned long NSUInteger;
typedef struct { O2Float x,y; } O2Point;
typedef struct { O2Float width,height; } O2Size;
typedef struct { O2Float a,b,c,d,tx,ty; } O2AffineTransform;
static const O2AffineTransform O2AffineTransformIdentity={1,0,0,1,0,0};
static O2Point O2PointMake(O2Float x,O2Float y){return (O2Point){x,y};}
static O2Size O2SizeMake(O2Float x,O2Float y){return (O2Size){x,y};}
static O2Point O2PointApplyAffineTransform(O2Point p,O2AffineTransform t){return (O2Point){p.x*t.a+p.y*t.c+t.tx,p.x*t.b+p.y*t.d+t.ty};}
static O2Size O2SizeApplyAffineTransform(O2Size p,O2AffineTransform t){return (O2Size){p.width*t.a+p.height*t.c,p.width*t.b+p.height*t.d};}
static O2Point Vector2Subtract(O2Point a,O2Point b){return (O2Point){a.x-b.x,a.y-b.y};}
static O2Float Vector2Dot(O2Point a,O2Point b){return a.x*b.x+a.y*b.y;}
typedef struct {uint8_t b,g,r,a;} O2argb8u;
typedef int O2SurfaceMode,O2InterpolationQuality;
typedef struct { int mask; } O2Image;
typedef O2Image *O2ImageRef;
static int alive;
@interface NSObject { Class isa; unsigned refs; }
+ (id)alloc;
+ (Class)class;
- (BOOL)isKindOfClass:(Class)c;
- (id)retain;
- (void)release;
- (void)dealloc;
@end
@implementation NSObject
+ (id)alloc {NSObject *o=class_createInstance(self,0);o->refs=1;alive++;return o;}
+ (Class)class {return self;}
- (BOOL)isKindOfClass:(Class)c {for(Class k=object_getClass(self);k;k=class_getSuperclass(k))if(k==c)return YES;return NO;}
- (id)retain {refs++;return self;}
- (void)release {assert(refs);if(!--refs)[self dealloc];}
- (void)dealloc {alive--;object_dispose(self);}
@end
static void *CFRetain(id o){return [o retain];}
static void CFRelease(id o){[o release];}
