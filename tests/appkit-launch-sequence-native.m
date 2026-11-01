// Controlled native storage surrounds the unchanged production launch methods.
#define NS_DURING @try {
#define NS_HANDLER } @catch(id localException) {
#define NS_ENDHANDLER }
static void _hookXcodeDevTools(void){}
static id NSApplicationWillFinishLaunchingNotification=@"will";
static id NSApplicationDidFinishLaunchingNotification=@"did";
static id NSApplicationLaunchIsDefaultLaunchKey=@"defaultLaunch";
static int order,willOrder,shouldOrder,openOrder,documentOrder,didOrder,reopens,documents,shadowWrites;
static BOOL documentClass,documentTypes,files,openSucceeded,shouldOpen,delegateOpened,defaultValue;
static id delegate,info;
@interface NSDictionary (LaunchFixture)
+ (id)dictionaryWithObject:(id)o forKey:(id)k;
@end
@implementation NSDictionary (LaunchFixture)
+ (id)dictionaryWithObject:(id)o forKey:(id)k{id d=[self dictionary];[d setObject:o forKey:k];return d;}
@end
@interface NSAutoreleasePool:NSObject @end
@implementation NSAutoreleasePool @end
@interface NSBundle:NSObject
+ (id)mainBundle; - (id)infoDictionary;
@end
@implementation NSBundle
+ (id)mainBundle{static id b;if(!b)b=[self new];return b;}
- (id)infoDictionary{return info;}
@end
@interface NSImage:NSObject
+ (id)imageNamed:(id)n;
@end
@implementation NSImage
+ (id)imageNamed:(id)n{return nil;}
@end
@interface NSTimer:NSObject
+ (id)scheduledTimerWithTimeInterval:(double)t target:(id)o selector:(SEL)s userInfo:(id)u repeats:(BOOL)r;
@end
@implementation NSTimer
+ (id)scheduledTimerWithTimeInterval:(double)t target:(id)o selector:(SEL)s userInfo:(id)u repeats:(BOOL)r{return nil;}
@end
@interface NSDocumentController:NSObject
+ (id)sharedDocumentController; - (id)openUntitledDocumentAndDisplay:(BOOL)d error:(id *)e;
- (void)_updateRecentDocumentsMenu; - (id)defaultType; - (Class)documentClassForType:(id)t;
- (void)newDocument:(id)sender;
@end
@implementation NSDocumentController
+ (id)sharedDocumentController{static id c;if(!c)c=[self new];return c;}
- (void)_updateRecentDocumentsMenu{}
- (id)defaultType{return documentClass?@"type":nil;}
- (Class)documentClassForType:(id)t{return documentClass?[NSObject class]:Nil;}
- (void)newDocument:(id)sender{documents++;documentOrder=++order;}
- (id)openUntitledDocumentAndDisplay:(BOOL)d error:(id *)e{assert(d);documents++;documentOrder=++order;return self;}
@end
@interface NSWindow:NSObject {BOOL _hasShadow;}
- (void)setHasShadow:(BOOL)v; - (BOOL)hasShadow; - (BOOL)isVisible;
@end
@implementation NSWindow
- (void)setHasShadow:(BOOL)v{_hasShadow=v;shadowWrites++;}
- (BOOL)hasShadow{return _hasShadow;}
- (BOOL)isVisible{return NO;}
@end
@interface NSNotificationCenter:NSObject
+ (id)defaultCenter; - (void)postNotificationName:(id)n object:(id)o;
- (void)postNotificationName:(id)n object:(id)o userInfo:(id)u;
@end
@interface NSObject (LaunchMethods)
- (BOOL)applicationShouldOpenUntitledFile:(id)a;
- (BOOL)applicationOpenUntitledFile:(id)a;
- (BOOL)applicationShouldHandleReopen:(id)a hasVisibleWindows:(BOOL)v;
@end
@interface NSApplication:NSObject { @public id _delegate;NSArray *_windows;BOOL _isHidden;}
- (void)finishLaunching; - (void)_reopen; - (BOOL)openFiles;
@end
@implementation NSApplication
- (BOOL)openFiles{return openSucceeded;}
// Controlled launch classification; the production NSOpen/argument helper is not extracted.
- (BOOL)_openFilesWithDefaultLaunch:(BOOL *)d{*d=!files;return openSucceeded;}
- (void)_closeSplashImage{}
- (void)setApplicationIconImage:(id)i{}
- (void)reportException:(id)e{assert(!"launch exception");}
- (void)unhide:(id)o{_isHidden=NO;}
FINISH_METHOD
REOPEN_METHOD
@end
@interface LaunchDelegate:NSObject
- (BOOL)applicationShouldOpenUntitledFile:(id)a; - (BOOL)applicationOpenUntitledFile:(id)a;
@end
@implementation LaunchDelegate
- (BOOL)applicationShouldOpenUntitledFile:(id)a{shouldOrder=++order;return shouldOpen;}
- (BOOL)applicationOpenUntitledFile:(id)a{openOrder=++order;return delegateOpened;}
- (void)applicationWillFinishLaunching:(id)n{willOrder=++order;}
- (void)applicationDidFinishLaunching:(id)n{didOrder=++order;}
- (BOOL)applicationShouldHandleReopen:(id)a hasVisibleWindows:(BOOL)v{reopens++;return YES;}
@end
@implementation NSNotificationCenter
+ (id)defaultCenter{static id c;if(!c)c=[self new];return c;}
- (void)postNotificationName:(id)n object:(id)o{[self postNotificationName:n object:o userInfo:nil];}
- (void)postNotificationName:(id)n object:(id)o userInfo:(id)u{
 if([n isEqual:NSApplicationWillFinishLaunchingNotification])[delegate applicationWillFinishLaunching:nil];
 else{defaultValue=[[u objectForKey:NSApplicationLaunchIsDefaultLaunchKey]boolValue];[delegate applicationDidFinishLaunching:nil];}
}
@end
static void launch(BOOL hasFiles,BOOL opened,BOOL allow,BOOL handled,BOOL types,BOOL viewerOnly){
 order=willOrder=shouldOrder=openOrder=documentOrder=didOrder=reopens=documents=0;
 files=hasFiles;openSucceeded=opened;documentClass=types&&!viewerOnly;shouldOpen=allow;delegateOpened=handled;documentTypes=types;
 defaultValue=NO;info=[NSDictionary dictionary];if(types)[info setObject:[NSArray arrayWithObject:@"type"] forKey:@"CFBundleDocumentTypes"];
 NSApplication *app=[NSApplication new];delegate=[LaunchDelegate new];app->_delegate=delegate;[app finishLaunching];
 assert(willOrder==1&&didOrder>willOrder);assert(defaultValue==!hasFiles);
 // No window is visible at the end of launch, so the launch-time reopen runs once.
 assert(reopens==1);
 if(opened){assert(!shouldOrder&&!openOrder&&!documents);}
 else{assert(shouldOrder>willOrder&&shouldOrder<didOrder);assert(!!openOrder==allow);assert(documents==(allow&&!handled&&types&&!viewerOnly));if(openOrder)assert(openOrder<didOrder);if(documents)assert(documentOrder<didOrder);}
 [app _reopen];assert(reopens==2);
}
int main(int argc,char **argv){
 launch(NO,NO,YES,YES,NO,NO);launch(NO,NO,NO,NO,YES,NO);launch(NO,NO,YES,NO,YES,NO);launch(YES,YES,YES,YES,YES,NO);launch(YES,NO,NO,NO,YES,NO);
 // Document types without a resolvable default class (a viewer-only app) never get an untitled document.
 launch(NO,NO,YES,NO,YES,YES);
 puts("PASS launch: key delivery for controlled default/file classification including failed open, notification ordering, delegate veto, handled untitled, untitled guard, launch-time reopen");return 0;
}
