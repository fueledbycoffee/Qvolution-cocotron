// Native doubles supply storage, KVC and observations; the runner inserts our
// production binding and selection methods. No guest or Apple code is loaded.
#include <objc/objc.h>
#include <objc/runtime.h>
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
typedef unsigned long NSUInteger;
typedef long NSInteger;
typedef int NSComparisonResult;
typedef unsigned short unichar;
typedef struct { NSUInteger location,length; } NSRange;
#define NSNotFound ((NSUInteger)-1)
static NSRange NSMakeRange(NSUInteger a,NSUInteger b){return (NSRange){a,b};}
#define NSBindingDebugLog(...)
#define NSLog(...)
#define NSUnimplementedMethod() do {exceptions++;} while(0)
static int exceptions;
@class NSString,NSArray,NSMutableArray,NSDictionary,NSNumber,NSTabViewItem;
__attribute__((objc_root_class))
@interface NSObject { Class isa; }
+ (id)alloc; + (id)new; + (Class)class;
- (void)willChangeValueForKey:(id)k; - (void)didChangeValueForKey:(id)k;
- (id)init; - (id)retain; - (id)autorelease; - (id)copy; - (id)mutableCopy; - (void)release;
- (Class)class; - (BOOL)isKindOfClass:(Class)c; - (BOOL)respondsToSelector:(SEL)s;
- (BOOL)isEqual:(id)o; - (id)description;
- (id)valueForKeyPath:(NSString *)k; - (void)setValue:(id)v forKeyPath:(NSString *)k;
- (void)addObserver:(id)o forKeyPath:(id)k options:(int)n context:(void *)c;
- (void)removeObserver:(id)o forKeyPath:(id)k;
- (void)observeValueForKeyPath:(id)k ofObject:(id)o change:(id)d context:(void *)c;
- (void)notify:(id)k;
- (BOOL)tabView:(id)t shouldSelectTabViewItem:(id)i;
@end
@implementation NSObject
+ (id)alloc{return class_createInstance(self,0);} + (id)new{return [[self alloc]init];} + (Class)class{return self;}
- (id)init{return self;} - (id)retain{return self;} - (id)autorelease{return self;}
- (id)copy{return self;} - (id)mutableCopy{return self;} - (void)release{}
- (Class)class{return object_getClass(self);}
- (BOOL)isKindOfClass:(Class)c{for(Class k=[self class];k;k=class_getSuperclass(k))if(k==c)return YES;return NO;}
- (BOOL)respondsToSelector:(SEL)s{return class_getInstanceMethod([self class],s)!=NULL;}
- (BOOL)isEqual:(id)o{return self==o;} - (id)description{return @"object";}
@end
@interface NSString : NSObject
- (const char *)UTF8String; - (NSUInteger)length; - (BOOL)isEqualToString:(id)s;
- (BOOL)hasPrefix:(id)s; - (id)substringFromIndex:(NSUInteger)i; - (id)substringToIndex:(NSUInteger)i;
- (id)substringWithRange:(NSRange)r; - (unichar)characterAtIndex:(NSUInteger)i;
- (NSRange)rangeOfString:(id)s; - (int)intValue; - (id)uppercaseString;
- (id)stringByAppendingString:(id)s; - (int)compare:(id)s;
+ (id)stringWithFormat:(id)f,...;
@end
@interface FixtureString : NSString { @public const char *bytes; unsigned int size; } @end
static id str(const char *s){FixtureString *r=[FixtureString new];r->bytes=strdup(s);r->size=strlen(s);return r;}
@implementation NSString
- (const char *)UTF8String{return "";} - (NSUInteger)length{return strlen([self UTF8String]);}
- (BOOL)isEqual:(id)s{return [s isKindOfClass:[NSString class]]&&![self compare:s];}
- (BOOL)isEqualToString:(id)s{return [self isEqual:s];}
- (BOOL)hasPrefix:(id)s{return !strncmp([self UTF8String],[s UTF8String],[s length]);}
- (id)substringFromIndex:(NSUInteger)i{assert(i<=[self length]);return str([self UTF8String]+i);}
- (id)substringToIndex:(NSUInteger)i{return [self substringWithRange:NSMakeRange(0,i)];}
- (id)substringWithRange:(NSRange)r{assert(r.location+r.length<=[self length]);char *b=strndup([self UTF8String]+r.location,r.length);id s=str(b);free(b);return s;}
- (unichar)characterAtIndex:(NSUInteger)i{assert(i<[self length]);return [self UTF8String][i];}
- (NSRange)rangeOfString:(id)s{const char *p=strstr([self UTF8String],[s UTF8String]);return NSMakeRange(p?(NSUInteger)(p-[self UTF8String]):NSNotFound,[s length]);}
- (int)intValue{return atoi([self UTF8String]);}
- (id)uppercaseString{char *b=strdup([self UTF8String]);for(char *p=b;*p;p++)if(*p>='a'&&*p<='z')*p-='a'-'A';id s=str(b);free(b);return s;}
- (id)stringByAppendingString:(id)s{char b[256];snprintf(b,sizeof(b),"%s%s",[self UTF8String],[s UTF8String]);return str(b);}
- (int)compare:(id)s{return strcmp([self UTF8String],[s UTF8String]);}
- (id)description{return self;}
+ (id)stringWithFormat:(id)f,...{va_list ap;va_start(ap,f);id a=va_arg(ap,id),b=va_arg(ap,id);va_end(ap);return [[@"set" stringByAppendingString:a]stringByAppendingString:[b stringByAppendingString:@":"]];}
@end
@implementation FixtureString
- (const char *)UTF8String{return bytes;} - (NSUInteger)length{return size;}
@end
static SEL NSSelectorFromString(id s){return sel_registerName([s UTF8String]);}
typedef struct {NSUInteger state; id *itemsPtr;NSUInteger *mutationsPtr;NSUInteger extra[5];} NSFastEnumerationState;
@interface NSArray : NSObject { @public id objects[128]; NSUInteger count; }
+ (id)array; + (id)arrayWithObject:(id)o; + (id)arrayWithObjects:(id)o,...;
- (NSUInteger)count; - (id)objectAtIndex:(NSUInteger)i; - (void)getObjects:(id *)p;
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)s objects:(id *)p count:(NSUInteger)n;
- (id)sortedArrayUsingSelector:(SEL)s; - (NSUInteger)indexOfObjectIdenticalTo:(id)o;
@end
@implementation NSArray
+ (id)array{return [self new];} + (id)arrayWithObject:(id)o{id r=[self array];((NSArray *)r)->objects[((NSArray *)r)->count++]=o;return r;}
+ (id)arrayWithObjects:(id)o,...{NSArray *r=[self array];va_list ap;va_start(ap,o);while(o){r->objects[r->count++]=o;o=va_arg(ap,id);}va_end(ap);return r;}
- (NSUInteger)count{return count;} - (id)objectAtIndex:(NSUInteger)i{assert(i<count);return objects[i];}
- (void)getObjects:(id *)p{memcpy(p,objects,sizeof(id)*count);}
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)s objects:(id *)p count:(NSUInteger)n{if(s->state)return 0;s->state=1;s->itemsPtr=objects;s->mutationsPtr=&count;return count;}
- (id)sortedArrayUsingSelector:(SEL)s{return self;}
- (NSUInteger)indexOfObjectIdenticalTo:(id)o{for(NSUInteger i=0;i<count;i++)if(objects[i]==o)return i;return NSNotFound;}
@end
@interface NSMutableArray : NSArray
- (void)addObject:(id)o;
@end
@implementation NSMutableArray
- (void)addObject:(id)o{assert(o&&count<128);objects[count++]=o;}
@end
@interface NSSet : NSArray
- (id)allObjects;
@end
@implementation NSSet
- (id)allObjects{return self;}
@end
@interface NSDictionary : NSObject { @public id keys[128],values[128]; NSUInteger count; }
+ (id)dictionary; - (id)objectForKey:(id)k; - (void)setObject:(id)o forKey:(id)k;
- (void)removeObjectForKey:(id)k; - (id)allValues; - (NSUInteger)count;
@end
@implementation NSDictionary
+ (id)dictionary{return [self new];}
- (id)objectForKey:(id)k{for(NSUInteger i=0;i<count;i++)if([keys[i]isEqual:k])return values[i];return nil;}
- (void)setObject:(id)o forKey:(id)k{assert(o&&k);for(NSUInteger i=0;i<count;i++)if([keys[i]isEqual:k]){values[i]=o;return;}keys[count]=k;values[count++]=o;assert(count<128);}
- (void)removeObjectForKey:(id)k{for(NSUInteger i=0;i<count;i++)if([keys[i]isEqual:k]){keys[i]=keys[--count];values[i]=values[count];break;}}
- (id)allValues{NSMutableArray *a=[NSMutableArray array];for(NSUInteger i=0;i<count;i++)[a addObject:values[i]];return a;}
- (NSUInteger)count{return count;}
@end
@interface NSMutableDictionary : NSDictionary @end
@implementation NSMutableDictionary @end
@interface NSValue : NSObject {id object;}
+ (id)valueWithNonretainedObject:(id)o;
@end
@implementation NSValue
+ (id)valueWithNonretainedObject:(id)o{NSValue *r=[self new];r->object=o;return r;}
- (BOOL)isEqual:(NSValue *)v{return [v isKindOfClass:[NSValue class]]&&object==v->object;}
@end
@interface NSNumber : NSObject {long number;}
+ (id)numberWithBool:(BOOL)b; + (id)numberWithInteger:(NSInteger)i;
- (BOOL)boolValue; - (NSInteger)integerValue;
@end
@implementation NSNumber
+ (id)numberWithBool:(BOOL)b{return [self numberWithInteger:b];}
+ (id)numberWithInteger:(NSInteger)i{NSNumber *r=[self new];r->number=i;return r;}
- (BOOL)boolValue{return !!number;} - (NSInteger)integerValue{return number;}
- (BOOL)isEqual:(NSNumber *)o{return [o isKindOfClass:[NSNumber class]]&&number==o->number;}
@end
@interface NSNull : NSObject
+ (id)null;
@end
@implementation NSNull
+ (id)null{static id n;if(!n)n=[self new];return n;}
@end
static id NSMultipleValuesMarker,NSNoSelectionMarker,NSNotApplicableMarker;
static BOOL NSIsControllerMarker(id o){return o==NSMultipleValuesMarker||o==NSNoSelectionMarker||o==NSNotApplicableMarker;}
static id NSConditionallySetsEditableBindingOption=@"editableOption",NSConditionallySetsEnabledBindingOption=@"enabledOption",NSAllowsEditingMultipleValuesSelectionBindingOption=@"allowsMultiple",NSRaisesForNotApplicableKeysBindingOption=@"raises",NSMultipleValuesPlaceholderBindingOption=@"multiple",NSNoSelectionPlaceholderBindingOption=@"none",NSNullPlaceholderBindingOption=@"null",NSValueTransformerBindingOption=@"transformer",NSValueTransformerNameBindingOption=@"transformerName",NSDisplayPatternBindingOption=@"pattern";
@interface NSValueTransformer : NSObject
+ (id)valueTransformerForName:(id)n; + (BOOL)allowsReverseTransformation;
- (id)transformedValue:(id)v; - (id)reverseTransformedValue:(id)v;
@end
@implementation NSValueTransformer
+ (id)valueTransformerForName:(id)n{return nil;} + (BOOL)allowsReverseTransformation{return YES;}
- (id)transformedValue:(id)v{return v;} - (id)reverseTransformedValue:(id)v{return v;}
@end
@interface NSDate : NSObject
+ (id)dateWithTimeIntervalSinceReferenceDate:(double)d;
@end
@implementation NSDate
+ (id)dateWithTimeIntervalSinceReferenceDate:(double)d{return [self new];}
@end
@interface NSFormatter : NSObject @end
@implementation NSFormatter @end
@interface NSDateFormatter : NSFormatter @end
@implementation NSDateFormatter @end
@interface NSControl : NSObject
- (id)formatter;
@end
@implementation NSControl
- (id)formatter{return nil;}
@end
struct Observation{id source,observer,key;void *context;};static struct Observation observations[256];static int observationCount;
@implementation NSObject (KVCFixture)
- (id)valueForKey:(NSString *)key{return [self valueForKeyPath:key];}
- (id)valueForKeyPath:(NSString *)key{
 NSRange dot=[key rangeOfString:@"."];
 if(dot.location!=NSNotFound)return [[self valueForKey:[key substringToIndex:dot.location]] valueForKeyPath:[key substringFromIndex:dot.location+1]];
 char b[128];const char *k=[key UTF8String];SEL sel=sel_registerName(k);Method m=class_getInstanceMethod([self class],sel);
 if(!m){snprintf(b,sizeof(b),"_%s",k);sel=sel_registerName(b);m=class_getInstanceMethod([self class],sel);}
 if(!m){exceptions++;@throw [NSObject new];}
 char t[16];method_getReturnType(m,t,sizeof(t));IMP imp=method_getImplementation(m);
 if(t[0]=='@')return ((id(*)(id,SEL))imp)(self,sel);
 return [NSNumber numberWithInteger:((NSInteger(*)(id,SEL))imp)(self,sel)];
}
- (void)setValue:(id)v forKeyPath:(NSString *)key{
 NSRange dot=[key rangeOfString:@"."];
 if(dot.location!=NSNotFound){[[self valueForKey:[key substringToIndex:dot.location]] setValue:v forKeyPath:[key substringFromIndex:dot.location+1]];return;}
 char b[128];const char *k=[key UTF8String];snprintf(b,sizeof(b),"set%c%s:",k[0]-'a'+'A',k+1);SEL sel=sel_registerName(b);Method m=class_getInstanceMethod([self class],sel);
 if(!m){memmove(b+1,b,strlen(b)+1);b[0]='_';sel=sel_registerName(b);m=class_getInstanceMethod([self class],sel);}
 if(!m){exceptions++;@throw [NSObject new];}
 char t[16];method_getArgumentType(m,2,t,sizeof(t));IMP imp=method_getImplementation(m);
 if(t[0]=='@')((void(*)(id,SEL,id))imp)(self,sel,v);
 else{if(!v||v==[NSNull null]){exceptions++;@throw [NSObject new];}((void(*)(id,SEL,NSInteger))imp)(self,sel,[v integerValue]);}
 [self notify:key];
}
- (void)addObserver:(id)o forKeyPath:(id)k options:(int)n context:(void *)c{assert(observationCount<256);observations[observationCount++]=(struct Observation){self,o,k,c};}
- (void)removeObserver:(id)o forKeyPath:(id)k{for(int i=observationCount-1;i>=0;i--)if(observations[i].source==self&&observations[i].observer==o&&[observations[i].key isEqual:k])observations[i]=observations[--observationCount];}
- (void)observeValueForKeyPath:(id)k ofObject:(id)o change:(id)d context:(void *)c{assert(0);}
- (void)willChangeValueForKey:(id)k{}
- (void)didChangeValueForKey:(id)k{[self notify:k];}
- (void)notify:(id)k{struct Observation copy[256];int n=observationCount;memcpy(copy,observations,sizeof(copy));for(int i=0;i<n;i++)if(copy[i].source==self&&[copy[i].key isEqual:k])[copy[i].observer observeValueForKeyPath:k ofObject:self change:nil context:copy[i].context];}
@end
static NSMutableDictionary *bindersForObjects;
static void *NSBinderChangeContext,*NSKVOBinderChangeContext;
@interface _NSBinder : NSObject { @public id _source,_destination;NSString *_keyPath,*_bindingPath,*_binding;NSMutableDictionary *_options; }
- (id)source; - (id)destination; - (id)keyPath; - (id)binding; - (id)bindingPath; - (id)options;
- (id)peerBinders; - (void)setBindingPath:(id)p; - (id)defaultBindingOptionsForBinding:(id)b;
- (void)startObservingChanges; - (void)stopObservingChanges; - (void)bind; - (void)unbind;
- (BOOL)allowsReverseTransformation; - (BOOL)allowsEditingMultipleValues;
- (BOOL)conditionallySetsEditable; - (BOOL)conditionallySetsEnabled; - (BOOL)raisesForNotApplicableKeys;
- (id)nullPlaceholder; - (id)noSelectionPlaceholder; - (id)multipleValuesPlaceholder;
- (id)transformedObject:(id)o; - (id)reverseTransformedObject:(id)o;
@end
@interface _NSKVOBinder : _NSBinder {BOOL _isObserving;}
- (void)syncUp;
@end
@interface NSObject (BindingSupport)
+ (Class)_binderClassForBinding:(id)b;
- (id)_binderForBinding:(id)b create:(BOOL)c; - (id)_binderForBinding:(id)b;
- (id)_replacementKeyPathForBinding:(id)b; - (NSArray *)_allUsedBinders;
- (void)bind:(id)b toObject:(id)o withKeyPath:(id)k options:(id)d; - (void)unbind:(id)b;
@end
@implementation NSObject (BindingSupport)
+ (Class)_binderClassForBinding:(id)b{return [_NSKVOBinder class];}
- (id)_binderForBinding:(id)b{return [self _binderForBinding:b create:NO];}
SUPPORT_METHODS
@end
@implementation _NSBinder
- (id)defaultBindingOptionsForBinding:(id)b{return [NSDictionary dictionary];}
BINDER_METHODS
DESTINATION_METHOD
BINDER_OPTIONS
@end
static id NSFormatDisplayPattern(id pattern,id *values,NSUInteger count){assert(0);return nil;}
SCALAR_FUNCTION
@implementation _NSKVOBinder
KVO_METHODS
@end
@interface Model : NSObject {id value;}
- (id)value; - (void)setValue:(id)v;
@end
@implementation Model
- (id)value{return value;} - (void)setValue:(id)v{value=v;}
@end
@interface NSMenuItem : NSObject {id represented,title;NSInteger tag;}
- (id)representedObject; - (void)setRepresentedObject:(id)o; - (id)title; - (void)setTitle:(id)o;
- (id)view; - (id)initialFirstResponder;
- (NSInteger)tag; - (void)setTag:(NSInteger)t;
@end
@implementation NSMenuItem
- (id)view{return nil;} - (id)initialFirstResponder{return nil;}
- (id)representedObject{return represented;} - (void)setRepresentedObject:(id)o{represented=o;}
- (id)title{return title;} - (void)setTitle:(id)o{title=o;}
- (NSInteger)tag{return tag;} - (void)setTag:(NSInteger)t{tag=t;}
@end
@interface PopCell : NSObject { @public NSMutableArray *items;NSMenuItem *selected;}
- (id)selectedItem; - (void)selectItemAtIndex:(NSUInteger)i; - (NSInteger)indexOfItemWithTag:(NSInteger)t;
- (void)removeAllItems; - (void)addItemWithTitle:(id)t; - (void)insertItemWithTitle:(id)t atIndex:(NSUInteger)i;
@end
@implementation PopCell
- (id)init{items=[NSMutableArray array];return self;}
- (id)selectedItem{return selected;} - (void)selectItemAtIndex:(NSUInteger)i{selected=[items objectAtIndex:i];}
- (NSInteger)indexOfItemWithTag:(NSInteger)t{for(NSUInteger i=0;i<[items count];i++)if([[items objectAtIndex:i]tag]==t)return i;return -1;}
- (void)removeAllItems{items=[NSMutableArray array];selected=nil;}
- (void)insertItemWithTitle:(id)t atIndex:(NSUInteger)i{assert(i==[items count]);[self addItemWithTitle:t];}
- (void)addItemWithTitle:(id)t{NSMenuItem *item=[NSMenuItem new];[item setTitle:t];[items addObject:item];}
@end
@interface NSPopUpButton : NSControl { @public PopCell *_cell;BOOL enabled;}
- (id)selectedItem; - (NSArray *)itemArray; - (id)itemAtIndex:(NSUInteger)i;
- (NSUInteger)numberOfItems; - (NSInteger)indexOfSelectedItem; - (void)selectItem:(id)o;
- (void)selectItemAtIndex:(NSUInteger)i; - (void)synchronizeTitleAndSelectedItem;
- (void)_setContent:(id)v; - (id)_content;
- (id)_selectedObject; - (void)_setSelectedObject:(id)o;
- (BOOL)enabled; - (void)setEnabled:(BOOL)b;
@end
@implementation NSPopUpButton
- (id)init{_cell=[PopCell new];return self;}
- (id)selectedItem{return [_cell selectedItem];} - (NSArray *)itemArray{return _cell->items;}
- (id)itemAtIndex:(NSUInteger)i{return [[self itemArray]objectAtIndex:i];}
- (NSUInteger)numberOfItems{return [[self itemArray]count];}
- (NSInteger)indexOfSelectedItem{return [[self itemArray]indexOfObjectIdenticalTo:[self selectedItem]];}
- (void)selectItem:(id)o{_cell->selected=o;} - (void)selectItemAtIndex:(NSUInteger)i{[_cell selectItemAtIndex:i];}
- (void)synchronizeTitleAndSelectedItem{}
- (BOOL)enabled{return enabled;} - (void)setEnabled:(BOOL)b{enabled=b;}
- (id)valueForKeyPath:(id)k{if([k hasPrefix:@"itemArray."]){NSMutableArray *a=[NSMutableArray array];for(id item in [self itemArray])[a addObject:[item valueForKeyPath:[k substringFromIndex:10]]];return a;}return [super valueForKeyPath:k];}
POPUP_METHODS
SELECTED_OBJECT_METHODS
@end
@interface NSCell : NSMenuItem @end
@implementation NSCell @end
@interface NSBrowserCell : NSCell @end
@implementation NSBrowserCell @end
@interface NSBrowserCellColorList : NSBrowserCell { @public id color;}
- (void)setColor:(id)c;
@end
@implementation NSBrowserCellColorList
- (void)setColor:(id)c{color=c;}
@end
@interface NSMatrix : NSControl { @public NSArray *_cells;NSInteger _selectedIndex;Class _cellClass;id _protoCell;}
- (void)selectCell:(id)c; - (id)selectedCell; - (void)selectCellWithTag:(NSInteger)t;
- (void)setCellClass:(Class)c; - (NSCell *)makeCellAtRow:(NSInteger)r column:(NSInteger)c;
@end
@implementation NSMatrix
- (void)selectCell:(id)c{_selectedIndex=[_cells indexOfObjectIdenticalTo:c];}
- (id)selectedCell{return _selectedIndex>=0&&_selectedIndex<[_cells count]?[_cells objectAtIndex:_selectedIndex]:nil;}
- (void)selectCellWithTag:(NSInteger)t{for(id cell in _cells)if([cell tag]==t){[self selectCell:cell];break;}}
MATRIX_METHODS
@end
@interface NSTabView : NSObject { @public NSArray *_items;id _selectedItem,_delegate;}
- (NSInteger)indexOfTabViewItem:(id)o; - (NSUInteger)numberOfTabViewItems; - (void)selectTabViewItem:(id)o; - (void)setNeedsDisplay:(BOOL)b; - (void)selectTabViewItemAtIndex:(NSInteger)i;
@end
@implementation NSTabView
- (NSInteger)indexOfTabViewItem:(id)o{return [_items indexOfObjectIdenticalTo:o];}
- (NSUInteger)numberOfTabViewItems{return [_items count];}
- (void)setNeedsDisplay:(BOOL)b{}
- (id)superview{return nil;}
TAB_METHODS
@end
@interface NSBrowser : NSObject { @public Class _cellClass;NSArray *_matrices;}
- (void)setCellClass:(Class)c;
@end
@implementation NSBrowser
BROWSER_METHOD
@end
@interface NSColorPickerColorList : NSObject { @public NSBrowser *colorBrowser;}
@end
@implementation NSColorPickerColorList
OUTLET_METHOD
@end
@protocol NSPathControlDelegate @end
@interface NSPathControl : NSControl {id<NSPathControlDelegate> _delegate;}
@end
@implementation NSPathControl
PATH_METHODS
@end
#define NSUnimplementedMethod() do {exceptions++;} while(0)
static void bind(id control,id name,id value,id options){Model *m=[Model new];[m setValue:value];[control bind:name toObject:m withKeyPath:@"value" options:options];}

static NSPopUpButton *popup(void){
 NSPopUpButton *p=[NSPopUpButton new];[p->_cell addItemWithTitle:@"first"];[p->_cell addItemWithTitle:@"second"];
 [[p itemAtIndex:0]setTag:0];[[p itemAtIndex:1]setTag:7];[p selectItemAtIndex:1];return p;
}
static NSDictionary *option(id key,id value){NSDictionary *d=[NSDictionary dictionary];[d setObject:value forKey:key];return d;}
static void scalarTests(void){
 NSNumber *one=[NSNumber numberWithInteger:1];NSPopUpButton *p=popup();
 bind(p,@"selectedTag",nil,nil);assert([p selectedItem]==[p itemAtIndex:0]);[p unbind:@"selectedTag"];
 bind(p,@"selectedTag",[NSNull null],option(NSNullPlaceholderBindingOption,[NSNumber numberWithInteger:7]));assert([p selectedItem]==[p itemAtIndex:1]);[p unbind:@"selectedTag"];
 Model *m=[Model new];[m setValue:one];[p bind:@"selectedIndex" toObject:m withKeyPath:@"value" options:nil];assert([p indexOfSelectedItem]==1);
 [m setValue:[NSNull null] forKeyPath:@"value"];assert([p indexOfSelectedItem]==0);
 [p setValue:one forKeyPath:@"selectedIndex"];assert([[m value]integerValue]==1);[p unbind:@"selectedIndex"];
 NSCell *a=[NSCell new],*b=[NSCell new];[b setTag:7];NSMatrix *matrix=[NSMatrix new];matrix->_cells=[NSArray arrayWithObjects:a,b,nil];matrix->_selectedIndex=1;
 bind(matrix,@"selectedTag",nil,nil);assert([matrix selectedCell]==a);[matrix unbind:@"selectedTag"];
 bind(matrix,@"selectedIndex",nil,nil);assert([matrix selectedCell]==a);[matrix unbind:@"selectedIndex"];
 bind(matrix,@"selectedIndex",NSNoSelectionMarker,option(NSNoSelectionPlaceholderBindingOption,one));assert([matrix selectedCell]==b);[matrix unbind:@"selectedIndex"];
 NSTabView *tab=[NSTabView new];tab->_items=[NSArray arrayWithObjects:a,b,nil];tab->_selectedItem=b;
 bind(tab,@"selectedIndex",nil,nil);assert(tab->_selectedItem==a);[tab unbind:@"selectedIndex"];
 bind(tab,@"selectedIndex",NSMultipleValuesMarker,option(NSMultipleValuesPlaceholderBindingOption,one));assert(tab->_selectedItem==b);[tab unbind:@"selectedIndex"];
 Model *selection=[Model new];[selection setValue:[NSNumber numberWithInteger:0]];
 [tab bind:@"selectedIndex" toObject:selection withKeyPath:@"value" options:nil];
 [tab selectTabViewItemAtIndex:1];assert([[selection value]integerValue]==1);[tab unbind:@"selectedIndex"];
 // Nil scalar defaults must also be safe for controls with no rows/items.
 bind([NSPopUpButton new],@"selectedIndex",nil,nil);
 NSMatrix *empty=[NSMatrix new];empty->_cells=[NSArray array];bind(empty,@"selectedIndex",nil,nil);
 NSTabView *emptyTab=[NSTabView new];emptyTab->_items=[NSArray array];bind(emptyTab,@"selectedIndex",nil,nil);
 assert(exceptions==0);puts("PASS scalar: popup tag/index, matrix tag/index, tab index, nil/NSNull/marker placeholders, reverse selection, empty controls");
}
static void contentValuesTests(void){
 for(int alias=0;alias<2;alias++) {
  NSPopUpButton *p=popup();id a=[NSObject new],b=[NSObject new];
  bind(p,alias?@"contentObjects":@"content",[NSArray arrayWithObjects:a,b,nil],nil);
  id first=[p itemAtIndex:0],second=[p itemAtIndex:1];
  Model *titles=[Model new];[titles setValue:[NSArray arrayWithObjects:@"A",@"B",nil]];
  [p bind:@"contentValues" toObject:titles withKeyPath:@"value" options:nil];
  for(int update=0;update<2;update++) {
   if(update)[titles setValue:[NSArray arrayWithObjects:@"AA",@"BB",nil] forKeyPath:@"value"];
   if([p itemAtIndex:0]!=first||[p itemAtIndex:1]!=second||
      [[p itemAtIndex:0]representedObject]!=a||[[p itemAtIndex:1]representedObject]!=b) {
    puts("FAIL: contentValues cleared content/contentObjects represented objects");exit(1);
   }
   assert([[[p itemAtIndex:0]title]isEqual:update?@"AA":@"A"]);
   assert([[[p itemAtIndex:1]title]isEqual:update?@"BB":@"B"]);
   [p _setSelectedObject:b];assert([p selectedItem]==second);
  }
 }
 puts("PASS contentValues: content and contentObjects identity, initial titles and KVO title updates");
}
static void selectedObjectTests(void){
 NSPopUpButton *p=popup();id a=[NSObject new],b=[NSObject new];
 [[p itemAtIndex:0]setRepresentedObject:a];[[p itemAtIndex:1]setRepresentedObject:b];
 assert([[p itemAtIndex:0]representedObject]==a&&[[p itemAtIndex:1]representedObject]==b);
 Model *m=[Model new];[m setValue:b];[p bind:@"selectedObject" toObject:m withKeyPath:@"value" options:nil];assert(exceptions==0);assert([p selectedItem]==[p itemAtIndex:1]);
 [m setValue:a forKeyPath:@"value"];assert([p selectedItem]==[p itemAtIndex:0]);
 [p setValue:b forKeyPath:@"selectedObject"];assert([m value]==b);
 [m setValue:nil forKeyPath:@"value"];assert([p selectedItem]==nil);
 [m setValue:NSNoSelectionMarker forKeyPath:@"value"];assert([p selectedItem]==nil);
 [p unbind:@"selectedObject"];
 bind(p,@"selectedObject",nil,option(NSNullPlaceholderBindingOption,a));assert([p selectedItem]==[p itemAtIndex:0]);[p unbind:@"selectedObject"];
 assert([[[NSPopUpButton new] _content]count]==0);
 assert([[popup() _content]count]==2);
 contentValuesTests();
 assert(exceptions==0);puts("PASS selectedObject: identity, model/UI updates, nil and marker placeholders, content/title composition");
}
static void enabledTests(void){
 NSPopUpButton *p=popup();Model *a=[Model new],*b=[Model new],*c=[Model new];
 [a setValue:[NSNumber numberWithBool:YES]];[b setValue:[NSNumber numberWithBool:NO]];[c setValue:[NSNumber numberWithBool:YES]];
 [p bind:@"enabled2" toObject:b withKeyPath:@"value" options:nil];assert(exceptions==0);assert(![p enabled]);
 [p bind:@"enabled" toObject:a withKeyPath:@"value" options:nil];assert(![p enabled]);
 [p bind:@"enabled12" toObject:c withKeyPath:@"value" options:nil];assert(![p enabled]);
 [b setValue:[NSNumber numberWithBool:YES] forKeyPath:@"value"];assert([p enabled]);
 [c setValue:nil forKeyPath:@"value"];assert(![p enabled]);
 [p unbind:@"enabled12"];assert([p enabled]);
 // Display-only boolean bindings never write the combined value into the model.
 [p setValue:[NSNumber numberWithBool:NO] forKeyPath:@"enabled"];assert([[a value]boolValue]&&[[b value]boolValue]);
 [a setValue:[NSNumber numberWithBool:NO] forKeyPath:@"value"];assert(![p enabled]);[p unbind:@"enabled"];assert([p enabled]);
 [p unbind:@"enabled2"];
 bind(p,@"enabled2",NSMultipleValuesMarker,option(NSMultipleValuesPlaceholderBindingOption,[NSNumber numberWithBool:YES]));assert([p enabled]);[p unbind:@"enabled2"];
 bind(p,@"enabled2",[NSNull null],nil);assert(![p enabled]);[p unbind:@"enabled2"];
 assert(exceptions==0);puts("PASS enabled: suffix-first bind, >9 peers, AND, nil/markers, observed updates, unbind recomputation, no model feedback");
}
static void browserTests(void){
 NSMatrix *matrix=[NSMatrix new];[matrix setCellClass:[NSBrowserCell class]];
 NSBrowser *browser=[NSBrowser new];browser->_matrices=[NSArray arrayWithObject:matrix];
 [browser setCellClass:[NSBrowserCellColorList class]];
 id cell=[matrix makeCellAtRow:0 column:0];
 assert([cell isKindOfClass:[NSBrowserCellColorList class]]);[cell setColor:@"red"];
 NSColorPickerColorList *picker=[NSColorPickerColorList new];
 assert([picker respondsToSelector:@selector(setColorBrowser:)]);
 [picker setColorBrowser:browser];assert(browser->_cellClass==[NSBrowserCellColorList class]);
 assert(!class_getInstanceMethod([NSBrowserCell class],@selector(setColor:)));
 assert(exceptions==0);puts("PASS picker/browser: class change reaches existing matrix, color stays on own subclass, early outlet configuration");
}
static void pathTests(void){NSPathControl *p=[NSPathControl new];id d=[NSObject new];[p setDelegate:d];assert([p delegate]==d);[p setDelegate:nil];assert([p delegate]==nil);assert(exceptions==0);puts("PASS path control: assigned delegate roundtrip and clearing");}
static void markerTests(void){
 NSPopUpButton *p=popup();Model *model=[Model new],*nested=[Model new];
 [nested setValue:[NSNumber numberWithBool:YES]];[model setValue:nested];
 [p bind:@"enabled" toObject:model withKeyPath:@"value.value" options:option(NSNoSelectionPlaceholderBindingOption,[NSNumber numberWithBool:NO])];assert([p enabled]);
 [model setValue:NSNoSelectionMarker forKeyPath:@"value"];[_NSKVOBinder class];[[p _binderForBinding:@"enabled"]syncUp];assert(![p enabled]);
 [model setValue:nested forKeyPath:@"value"];[[p _binderForBinding:@"enabled"]syncUp];assert([p enabled]);
 [model setValue:nil forKeyPath:@"value"];[[p _binderForBinding:@"enabled"]syncUp];assert(![p enabled]);
 [p unbind:@"enabled"];
 assert(exceptions==0);puts("PASS marker: nested path stops at no-selection marker, configured placeholder and selection recovery");
}
static void reverseMarkerTests(void){
 Model *source=[Model new],*model=[Model new],*nested=[Model new];
 _NSBinder *binder=[_NSBinder new];
 [binder setSource:source];[binder setBindingPath:@"value"];
 [binder setDestination:model];[binder setKeyPath:@"value.enabledEncodings"];
 [source setValue:[NSNumber numberWithInteger:7]];
 id markers[]={NSNoSelectionMarker,NSMultipleValuesMarker,NSNotApplicableMarker};
 for(int i=0;i<3;i++){
  [model setValue:markers[i]];
  BOOL caught=NO;@try{[binder observeValueForKeyPath:@"value" ofObject:source change:nil context:&NSBinderChangeContext];}@catch(id e){caught=YES;}
  assert(!caught&&[model value]==markers[i]&&exceptions==0);
 }
 [binder setKeyPath:@"value.value"];[model setValue:nested];
 [binder observeValueForKeyPath:@"value" ofObject:source change:nil context:&NSBinderChangeContext];
 assert([[nested value]integerValue]==7&&exceptions==0);
 puts("PASS reverse marker: placeholder edits preserve model; selected model writes resume");
}
int main(void){NSMultipleValuesMarker=[NSObject new];NSNoSelectionMarker=[NSObject new];NSNotApplicableMarker=[NSObject new];
 if(FIXTURE_CASE==0||FIXTURE_CASE==1)scalarTests();
 if(FIXTURE_CASE==0||FIXTURE_CASE==2)selectedObjectTests();
 if(FIXTURE_CASE==0||FIXTURE_CASE==3)enabledTests();
 if(FIXTURE_CASE==0||FIXTURE_CASE==4)browserTests();
 if(FIXTURE_CASE==0||FIXTURE_CASE==5)pathTests();
 if(FIXTURE_CASE==0||FIXTURE_CASE==6)markerTests();
 if(FIXTURE_CASE==0||FIXTURE_CASE==7)reverseMarkerTests();
 if(FIXTURE_CASE==8)contentValuesTests();
 return 0;
}
