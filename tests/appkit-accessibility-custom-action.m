#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>
#define CHECK(c,m) do { if (!(c)) { fprintf(stderr,"FAIL: %s\n",m); return 1; } } while(0)
// Original before-capable caller types; no class is declared or implemented here.
@protocol QVCustomAction <NSObject>
- (id)initWithName:(NSString *)name handler:(BOOL (^)(void))handler;
- (id)initWithName:(NSString *)name target:(id<NSObject>)target selector:(SEL)selector;
@property(copy) NSString *name;
@property(copy) BOOL (^handler)(void);
@property(weak) id<NSObject> target;
@property SEL selector;
@end
static int capturedDeallocations,targetDeallocations;
@interface QVCapturedActionObject:NSObject
- (BOOL)result;
@end
@implementation QVCapturedActionObject
- (BOOL)result { return YES; }
- (void)dealloc { capturedDeallocations++;[super dealloc]; }
@end
@interface QVActionTarget:NSObject { @public int calls; }
- (BOOL)performFixture;
@end
@implementation QVActionTarget
- (BOOL)performFixture { calls++;return YES; }
- (void)dealloc { targetDeallocations++;[super dealloc]; }
@end
static id<QVCustomAction> createStackAction(Class cls,int *calls) {
 NSAutoreleasePool *creation=[NSAutoreleasePool new];
 NSMutableString *name=[[NSMutableString alloc] initWithString:@"Fixture action"];
 QVCapturedActionObject *captured=[QVCapturedActionObject new];
 id<QVCustomAction> action=[(id<QVCustomAction>)[cls alloc] initWithName:name handler:^BOOL { (*calls)++;return [captured result]; }];
 [name appendString:@" changed"];[name release];[captured release];[creation drain];return action;
}
int main(void) {
 NSAutoreleasePool *pool=[NSAutoreleasePool new];
 void *appkit=dlopen("/System/Library/Frameworks/AppKit.framework/AppKit",RTLD_LAZY|RTLD_LOCAL);CHECK(appkit,"actual AppKit framework loads");
 NSString *const *role=dlsym(appkit,"NSAccessibilityPopoverRole");
 CHECK(NSClassFromString(@"NSWindow")&&role&&[*role isEqual:@"AXPopover"],"existing AppKit class metadata and real accessibility data controls");
 Class cls=NSClassFromString(@"NSAccessibilityCustomAction");CHECK(cls,"public custom action class exists");
 CHECK([cls instancesRespondToSelector:@selector(initWithName:handler:)]&&[cls instancesRespondToSelector:@selector(initWithName:target:selector:)],"real documented initializers exist");
 int calls=0;id<QVCustomAction> action=createStackAction(cls,&calls);CHECK(action&&[[action name] isEqual:@"Fixture action"],"initializer copies mutable name");
 NSAutoreleasePool *handlerObservation=[NSAutoreleasePool new];
 CHECK(capturedDeallocations==0&&[action handler]!=NULL,"copied stack block retains captured object after function and creation pool end");
 BOOL (^handler)(void)=[action handler];CHECK(handler()&&calls==1,"own consumer receives actual true callback result and effect");
 [action setHandler:[action handler]];CHECK(capturedDeallocations==0&&[action handler]()&&calls==2,"handler self replacement preserves callback ownership");
 [handlerObservation drain];
 int *counter=&calls;[action setHandler:^BOOL { *counter+=10;return NO; }];CHECK(capturedDeallocations==1,"replacing callback releases original capture");
 CHECK(![action handler]()&&calls==12,"false callback result is preserved with actual effect");
 [action setHandler:nil];CHECK([action handler]==NULL,"cleared callback stays absent without fake success");
 NSMutableString *newName=[NSMutableString stringWithString:@"Replacement"];[action setName:newName];[newName appendString:@" changed"];
 CHECK([[action name] isEqual:@"Replacement"],"name setter copies mutable input");[action setName:[action name]];CHECK([[action name] isEqual:@"Replacement"],"name self replacement preserves value");
 QVActionTarget *target=[QVActionTarget new];id<QVCustomAction> targeted=[(id<QVCustomAction>)[cls alloc] initWithName:@"Target action" target:target selector:@selector(performFixture)];CHECK(targeted,"target constructor creates object");
 NSAutoreleasePool *observation=[NSAutoreleasePool new];
 CHECK([targeted target]==target&&[targeted selector]==@selector(performFixture),"stored actual weak target and selector");
 id actual=[targeted target];BOOL (*perform)(id,SEL)=(void *)[actual methodForSelector:[targeted selector]];
 CHECK(perform&&perform(actual,[targeted selector])&&target->calls==1,"own consumer invokes its actual typed target method");[observation drain];
 [target release];CHECK(targetDeallocations==1&&[targeted target]==nil,"last target owner release deallocates and zeroes weak property");
 target=[QVActionTarget new];[targeted setTarget:target];[targeted setSelector:@selector(description)];CHECK([targeted selector]==@selector(description),"selector setter preserves supplied identity");
 [targeted setTarget:nil];[target release];CHECK(targetDeallocations==2&&[targeted target]==nil,"weak target setter and clearing do not retain target");
 [targeted release];[(id)action release];
 id<QVCustomAction> finalCapture=createStackAction(cls,&calls);CHECK(capturedDeallocations==1,"fresh copied callback owns its capture");
 [(id)finalCapture release];CHECK(capturedDeallocations==2,"action deallocation releases stored callback capture");
 target=[QVActionTarget new];targeted=[(id<QVCustomAction>)[cls alloc] initWithName:@"Live target" target:target selector:@selector(performFixture)];
 [targeted release];CHECK(targetDeallocations==2,"action deallocation does not own live target");
 [target release];CHECK(targetDeallocations==3,"live target can deallocate after weak action holder is destroyed");
 [pool drain];
 puts("PASS: real custom action copy/weak lifetime and caller callback results; no accessibility-server dispatch qualification");return 0;
}
