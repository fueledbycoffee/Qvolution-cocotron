// Host-only boundary shims. The exercised methods are inserted verbatim from source.
#include <objc/runtime.h>
#include <dbus/dbus.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <unistd.h>
#include <time.h>
#include <poll.h>
#include <errno.h>
#include <stdarg.h>
#include <sys/time.h>
#define NSLog(...) ((void)0)
void *_NSConcreteStackBlock[32], *_NSConcreteGlobalBlock[32];
void _Block_object_assign(void *d, const void *s, int flags) {}
void _Block_object_dispose(const void *s, int flags) {}
#define dispatch_get_main_queue() 0
#define dispatch_async(queue, body) (body)()
static BOOL failQueryAllocation;
static size_t queryAllocationSize;
static void *fixtureCalloc(size_t n,size_t size) {
    if (failQueryAllocation && n*size==queryAllocationSize) { failQueryAllocation=NO; return NULL; }
    return calloc(n,size);
}
#define calloc fixtureCalloc
typedef double CFTimeInterval;
typedef struct FixtureTimer *CFRunLoopTimerRef;
typedef void (*CFRunLoopTimerCallBack)(CFRunLoopTimerRef,void *);
typedef struct { long version; void *info; void *retain, *release, *description; } CFRunLoopTimerContext;
struct FixtureTimer { double next, interval; BOOL valid; CFRunLoopTimerCallBack callback; void *info; };
static CFRunLoopTimerRef timers[256]; static int timerCount, timerFires;
#define kCFAllocatorDefault 0
#define kCFRunLoopCommonModes 0
static double CFAbsoluteTimeGetCurrent(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+t.tv_nsec/1e9; }
static void *CFRunLoopGetMain(void) { return NULL; }
static CFRunLoopTimerRef CFRunLoopTimerCreate(int a,double next,double interval,int flags,int order,CFRunLoopTimerCallBack callback,CFRunLoopTimerContext *context) {
    CFRunLoopTimerRef timer=calloc(1,sizeof(*timer)); timer->next=next; timer->interval=interval; timer->valid=YES; timer->callback=callback; timer->info=context->info; return timer;
}
static void CFRunLoopAddTimer(void *loop,CFRunLoopTimerRef timer,int mode) { timers[timerCount++]=timer; }
static void CFRunLoopTimerInvalidate(CFRunLoopTimerRef timer) { timer->valid=NO; }
static void CFRelease(void *object) {} // Keep invalidated shim timers inspectable until fixture exit.
static void *CFRetain(void *object) { return object; }
static BOOL CFRunLoopTimerIsValid(CFRunLoopTimerRef timer) { return timer->valid; }
struct FixtureSocket { int fd; unsigned enabled; };
typedef struct FixtureSocket *CFSocketRef;
#define kCFSocketReadCallBack 1
#define kCFSocketWriteCallBack 8
static void CFSocketEnableCallBacks(CFSocketRef socket,unsigned flags) { socket->enabled |= flags; }
static void CFSocketDisableCallBacks(CFSocketRef socket,unsigned flags) { socket->enabled &= ~flags; }
static BOOL failLayoutSend, failLayoutAllocation;
static DBusMessage *fixtureMethodReturn(DBusMessage *request) {
    if (failLayoutAllocation && dbus_message_is_method_call(request,"com.canonical.dbusmenu","GetLayout")) return NULL;
    return dbus_message_new_method_return(request);
}
#define dbus_message_new_method_return fixtureMethodReturn
static dbus_bool_t fixtureSend(DBusConnection *connection,DBusMessage *message,dbus_uint32_t *serial) {
    if (failLayoutSend && dbus_message_get_type(message)==DBUS_MESSAGE_TYPE_METHOD_RETURN && dbus_message_has_signature(message,"u(ia{sv}av)")) return FALSE;
    return dbus_connection_send(connection,message,serial);
}
#define dbus_connection_send fixtureSend
typedef unsigned long NSUInteger;
typedef unsigned long NSWindowStyleMask;
typedef double CGFloat;
typedef struct { double width, height; } NSSize;
typedef struct { double x, y; } NSPoint;
typedef struct { NSPoint origin; NSSize size; } NSRect;
static const NSRect NSZeroRect = {0};
static const NSSize NSZeroSize = {0};
#define NSMaxY(r) ((r).origin.y + (r).size.height)
#define NSMakeRect(x,y,w,h) ((NSRect){{x,y},{w,h}})
typedef struct { unsigned long state; id *itemsPtr; unsigned long *mutationsPtr; unsigned long extra[5]; } NSFastEnumerationState;
@interface NSObject { Class isa; }
+ (id)new; + (id)alloc; + (Class)class; - (Class)class;
- (id)retain; - (void)release; - (BOOL)isKindOfClass:(Class)c;
@end
@implementation NSObject
+ (id)alloc { return class_createInstance(self, 0); }
+ (id)new { return [self alloc]; }
+ (Class)class { return self; }
- (Class)class { return object_getClass(self); }
- (id)retain { return self; }
- (void)release {}
- (BOOL)isKindOfClass:(Class)c { for (Class k = [self class]; k; k = class_getSuperclass(k)) if (k == c) return YES; return NO; }
@end
@interface NSString : NSObject { char *text; }
- (id)initWithUTF8String:(const char *)s; - (const char *)UTF8String;
@end
@implementation NSString
- (id)initWithUTF8String:(const char *)s { text = strdup(s); return self; }
- (const char *)UTF8String { return text; }
@end
@interface NSArray : NSObject { @public id items[8]; NSUInteger count; }
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)buffer count:(NSUInteger)n;
@end
@implementation NSArray
- (id)copy { NSArray *result=[NSArray new]; result->count=count; memcpy(result->items,items,sizeof items); return result; }
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)buffer count:(NSUInteger)n {
    if (state->state) return 0; state->state = 1; state->itemsPtr = items; state->mutationsPtr = &count; return count;
}
@end
@class NSWindow;
@interface NSView : NSObject { @public NSRect rect; BOOL hidden, autoresizes; NSArray *_subviews; NSWindow *owner; }
- (NSRect)frame; - (NSRect)bounds; - (void)setFrame:(NSRect)f; - (void)setFrameSize:(NSSize)s;
- (BOOL)isHidden; - (void)setHidden:(BOOL)b; - (void)setAutoresizesSubviews:(BOOL)b;
- (void)resizeSubviewsWithOldSize:(NSSize)s; - (void)setNeedsDisplay:(BOOL)b; - (NSWindow *)window;
@end
@implementation NSView
- (NSRect)frame { return rect; } - (NSRect)bounds { return NSMakeRect(0,0,rect.size.width,rect.size.height); }
- (void)setFrame:(NSRect)f { if (memcmp(&rect, &f, sizeof f) == 0) return; NSSize old=rect.size; rect=f; if (autoresizes) [self resizeSubviewsWithOldSize:old]; }
- (void)setFrameSize:(NSSize)s { NSRect f=rect; f.size=s; [self setFrame:f]; }
- (BOOL)isHidden { return hidden; } - (void)setHidden:(BOOL)b { hidden=b; }
- (void)setAutoresizesSubviews:(BOOL)b { autoresizes=b; }
- (void)resizeSubviewsWithOldSize:(NSSize)s {} - (void)setNeedsDisplay:(BOOL)b {}
- (NSWindow *)window { return owner; }
@end
@interface NSMenuView : NSView @end
@implementation NSMenuView @end
@interface NSMainMenuView : NSMenuView
+ (CGFloat)menuHeight;
@end
@implementation NSMainMenuView
+ (CGFloat)menuHeight { return 22; }
@end
@interface NSToolbarView : NSView
- (void)layoutViews;
@end
@implementation NSToolbarView
- (void)layoutViews {}
@end
@interface NSToolbar : NSObject { @public NSToolbarView *view; }
- (NSToolbarView *)_view;
@end
@implementation NSToolbar
- (NSToolbarView *)_view { return view; }
@end
@class NSMenu;
@interface NSNumber : NSObject
+ (id)numberWithInt:(int)value;
@end
@implementation NSNumber
+ (id)numberWithInt:(int)value { return [self new]; }
@end
@interface NSMenuItem : NSObject
- (BOOL)hasSubmenu; - (NSMenu *)submenu;
@end
@implementation NSMenuItem
- (BOOL)hasSubmenu { return NO; } - (NSMenu *)submenu { return nil; }
@end
@interface NSMenu : NSObject @end
@implementation NSMenu @end
@interface NSThemeFrameButton : NSView @end
@implementation NSThemeFrameButton @end
@interface NSDisplay : NSObject
+ (id)currentDisplay; - (NSRect)insetRect:(NSRect)r forNativeWindowBorderWithStyle:(NSWindowStyleMask)s;
- (NSRect)outsetRect:(NSRect)r forNativeWindowBorderWithStyle:(NSWindowStyleMask)s;
@end
@implementation NSDisplay
+ (id)currentDisplay { return [self new]; }
- (NSRect)insetRect:(NSRect)r forNativeWindowBorderWithStyle:(NSWindowStyleMask)s { return r; }
- (NSRect)outsetRect:(NSRect)r forNativeWindowBorderWithStyle:(NSWindowStyleMask)s { return r; }
@end
@interface NSThemeFrame : NSView
+ (CGFloat)titleBarHeightForStyleMask:(NSWindowStyleMask)s; - (void)layoutTrafficLights;
@end
@interface NSWindow : NSObject { @public NSView *_backgroundView, *_menuView, *content; NSToolbar *_toolbar; NSRect rect; }
+ (BOOL)hasMainMenuForStyleMask:(NSWindowStyleMask)s; - (BOOL)hasMainMenu; - (NSWindowStyleMask)styleMask;
- (NSRect)frame; - (void)setFrame:(NSRect)f display:(BOOL)b;
- (void)_hideMenuViewIfNeeded; - (void)_showMenuViewIfNeeded; - (void)_resizeWithOldMenuViewSize:(NSSize)s;
+ (NSRect)contentRectForFrameRect:(NSRect)f styleMask:(NSWindowStyleMask)s;
- (NSRect)frameRectForContentRect:(NSRect)c; - (NSRect)contentRectForFrameRect:(NSRect)f;
@end
static void (*resizeObserver)(NSWindow *);
@implementation NSWindow
+ (BOOL)hasMainMenuForStyleMask:(NSWindowStyleMask)s { return YES; } - (BOOL)hasMainMenu { return YES; }
- (NSWindowStyleMask)styleMask { return 1; } - (NSRect)frame { return rect; }
- (void)setFrame:(NSRect)f display:(BOOL)b { rect=f; [_backgroundView setFrameSize:f.size]; if (resizeObserver) resizeObserver(self); }
/* WINDOW */
@end
static CGFloat titleHeight;
@implementation NSThemeFrame
+ (CGFloat)titleBarHeightForStyleMask:(NSWindowStyleMask)s { return titleHeight; }
- (void)layoutTrafficLights {}
/* THEME */
@end
@interface NSPanel : NSWindow @end
@implementation NSPanel @end
@interface NSApplication : NSObject { @public NSArray *allWindows; NSWindow *modal; }
- (NSArray *)windows; - (NSWindow *)modalWindow;
@end
@implementation NSApplication
- (NSArray *)windows { return allWindows; } - (NSWindow *)modalWindow { return modal; }
@end
static NSApplication *NSApp;
@interface X11GlobalMenu : NSObject { @public
    DBusConnection *_connection; CFSocketRef _cfSocket; id _itemsByID; unsigned int _revision; BOOL _available, _globalMenuEngaged, _waylandApplicationMenu, _orbitOwnerMatchAdded;
    BOOL _orbitProgressFailed, _orbitOwnerWatchReady, _orbitStateWatchReady;
    BOOL _orbitExtensionActive, _orbitMenuRead; NSString *_orbitOwner, *_orbitShellOwner;
    unsigned int _orbitShellGeneration, _orbitOwnerGeneration, _orbitOwnerWatchRetries, _orbitStateWatchRetries; NSMenu *_currentMenu;
}
- (void)deferDBusProgressFailure; - (void)processPendingDBusEvents; - (void)scheduleDBusWrite; - (void)handleDBusDisconnect;
- (void)appendMenu:(NSMenu *)menu asNode:(int32_t)node toIter:(DBusMessageIter *)iter depth:(int32_t)depth;
- (void)updateWaylandMenuPresentation; - (void)queryOrbitIntegration:(int)kind;
- (void)receiveOrbitReply:(DBusMessage *)reply kind:(int)kind generation:(unsigned int)generation;
- (void)registerWaylandApplicationMenu:(NSMenu *)menu; - (void)updateMenu:(NSMenu *)menu;
- (DBusHandlerResult)handleDBusMessage:(DBusMessage *)message onConnection:(DBusConnection *)connection;
@end
/* HELPERS */
@implementation X11GlobalMenu
- (void)updateMenu:(NSMenu *)menu { _currentMenu=menu; }
- (void)appendMenu:(NSMenu *)menu asNode:(int32_t)node toIter:(DBusMessageIter *)iter depth:(int32_t)depth {
    DBusMessageIter structure,dict,children;
    dbus_message_iter_open_container(iter,DBUS_TYPE_STRUCT,NULL,&structure);
    dbus_message_iter_append_basic(&structure,DBUS_TYPE_INT32,&node);
    dbus_message_iter_open_container(&structure,DBUS_TYPE_ARRAY,"{sv}",&dict); dbus_message_iter_close_container(&structure,&dict);
    dbus_message_iter_open_container(&structure,DBUS_TYPE_ARRAY,"v",&children); dbus_message_iter_close_container(&structure,&children);
    dbus_message_iter_close_container(iter,&structure);
}
/* EXPORTER */
@end
static int failures;
#define CHECK(ok, msg) do { if (!(ok)) { fprintf(stderr,"FAIL: %s\n",msg); failures++; } } while (0)
static DBusConnection *receiver;
static BOOL answerQueries = YES;
static double extensionState = 1;
static int writeOnlyProgress, layoutReplies, bulkReceived;
static void appendState(DBusMessage *reply, double state) {
    DBusMessageIter out, dict, entry, variant; const char *key="state";
    dbus_message_iter_init_append(reply,&out);
    dbus_message_iter_open_container(&out,DBUS_TYPE_ARRAY,"{sv}",&dict);
    dbus_message_iter_open_container(&dict,DBUS_TYPE_DICT_ENTRY,NULL,&entry);
    dbus_message_iter_append_basic(&entry,DBUS_TYPE_STRING,&key);
    dbus_message_iter_open_container(&entry,DBUS_TYPE_VARIANT,"d",&variant);
    dbus_message_iter_append_basic(&variant,DBUS_TYPE_DOUBLE,&state);
    dbus_message_iter_close_container(&entry,&variant); dbus_message_iter_close_container(&dict,&entry); dbus_message_iter_close_container(&out,&dict);
}
static DBusHandlerResult filter(DBusConnection *connection,DBusMessage *message,void *data) {
    return [(X11GlobalMenu *)data handleDBusMessage:message onConnection:connection];
}
static void pump(X11GlobalMenu *exporter) {
    for (int n=0;n<60;n++) {
        dbus_connection_read_write(receiver,1);
        DBusMessage *request;
        while ((request=dbus_connection_pop_message(receiver))) {
            if (answerQueries && dbus_message_is_method_call(request,"org.gnome.Shell.Extensions","GetExtensionInfo")) {
                DBusMessage *reply=dbus_message_new_method_return(request); appendState(reply,extensionState);
                dbus_connection_send(receiver,reply,NULL); dbus_message_unref(reply); dbus_connection_flush(receiver);
            }
            if (dbus_message_get_type(request)==DBUS_MESSAGE_TYPE_METHOD_RETURN && dbus_message_has_signature(request,"u(ia{sv}av)")) layoutReplies++;
            if (dbus_message_is_signal(request,"org.example.Fixture","Bulk")) bulkReceived++;
            dbus_message_unref(request);
        }
        struct pollfd fd={.fd=exporter->_cfSocket->fd,.events=0};
        if(exporter->_cfSocket->enabled & kCFSocketReadCallBack) fd.events |= POLLIN;
        if(exporter->_cfSocket->enabled & kCFSocketWriteCallBack) fd.events |= POLLOUT;
        if (poll(&fd,1,0)>0) {
            if((fd.revents&POLLOUT) && !(fd.revents&POLLIN)) writeOnlyProgress++;
            [exporter processPendingDBusEvents];
        }
        double now=CFAbsoluteTimeGetCurrent();
        for(int i=0;i<timerCount;i++) if(timers[i]->valid && timers[i]->next<=now) {
            CFRunLoopTimerRef timer=timers[i]; timer->next=now+timer->interval; timerFires++; timer->callback(timer,timer->info);
        }
    }
}
static void stateSignal(X11GlobalMenu *exporter,const char *uuid,double state, const char *sender) {
    DBusMessage *signal=dbus_message_new_signal("/org/gnome/Shell","org.gnome.Shell.Extensions","ExtensionStateChanged");
    appendBasic(signal,DBUS_TYPE_STRING,&uuid); appendState(signal,state); dbus_message_set_sender(signal,sender);
    [exporter handleDBusMessage:signal onConnection:exporter->_connection]; dbus_message_unref(signal);
}
static void readLayout(X11GlobalMenu *exporter,const char *sender) {
    DBusMessage *message=dbus_message_new_method_call(dbus_bus_get_unique_name(exporter->_connection),"/MenuBar","com.canonical.dbusmenu","GetLayout");
    int32_t root=0,depth=-1; appendBasic(message,DBUS_TYPE_INT32,&root); appendBasic(message,DBUS_TYPE_INT32,&depth);
    DBusMessageIter iter,array; dbus_message_iter_init_append(message,&iter); dbus_message_iter_open_container(&iter,DBUS_TYPE_ARRAY,"s",&array); dbus_message_iter_close_container(&iter,&array);
    if(strcmp(sender,dbus_bus_get_unique_name(receiver))==0) {
        dbus_connection_send(receiver,message,NULL); dbus_connection_flush(receiver); pump(exporter);
    } else {
        dbus_message_set_serial(message,1); dbus_message_set_sender(message,sender);
        [exporter handleDBusMessage:message onConnection:exporter->_connection];
        [exporter scheduleDBusWrite]; pump(exporter);
    }
    dbus_message_unref(message);
}
// A separate peer, like Orbit's reader process, whose unique name is not the registrar's.
static DBusConnection *reader;
static void readLayoutFrom(X11GlobalMenu *exporter,DBusConnection *connection,int32_t root) {
    DBusMessage *message=dbus_message_new_method_call(dbus_bus_get_unique_name(exporter->_connection),"/MenuBar","com.canonical.dbusmenu","GetLayout");
    int32_t depth=-1; appendBasic(message,DBUS_TYPE_INT32,&root); appendBasic(message,DBUS_TYPE_INT32,&depth);
    DBusMessageIter iter,array; dbus_message_iter_init_append(message,&iter); dbus_message_iter_open_container(&iter,DBUS_TYPE_ARRAY,"s",&array); dbus_message_iter_close_container(&iter,&array);
    dbus_connection_send(connection,message,NULL); dbus_connection_flush(connection); pump(exporter);
    dbus_message_unref(message);
}
static int resizeMutations;
static void mutateWindows(NSWindow *window) { resizeObserver=NULL; NSApp->allWindows->count=0; resizeMutations++; }
static NSWindow *layoutFixture(CGFloat title) {
    titleHeight=title;
    NSWindow *window=[NSWindow new]; NSThemeFrame *theme=[NSThemeFrame new]; NSMainMenuView *menu=[NSMainMenuView new];
    NSView *content=[NSView new]; NSToolbarView *toolbar=[NSToolbarView new]; NSToolbar *bar=[NSToolbar new];
    NSArray *views=[NSArray new]; views->items[0]=menu; views->items[1]=toolbar; views->items[2]=content; views->count=3;
    theme->_subviews=views; theme->owner=window; theme->autoresizes=YES; theme->rect=NSMakeRect(0,0,400,350);
    menu->rect=NSMakeRect(0,328,400,22); toolbar->rect=NSMakeRect(0,300,400,28); bar->view=toolbar;
    window->_backgroundView=theme; window->_menuView=menu; window->_toolbar=bar; window->rect=theme->rect;
    [theme resizeSubviewsWithOldSize:NSZeroSize]; NSRect before=[content frame], beforeToolbar=[toolbar frame];
    NSRect beforeConverted=[window contentRectForFrameRect:window->rect];
    [window _hideMenuViewIfNeeded];
    CHECK(fabs(window->rect.size.height-328)<0.01,"hide removes the menu strip from the window");
    CHECK(fabs(NSMaxY([toolbar frame])-(window->rect.size.height-titleHeight))<0.01,"hidden menu leaves no blank strip above toolbar");
    CHECK(memcmp(&content->rect,&before,sizeof before)==0,"hide preserves content/ruler geometry");
    NSRect converted=[window contentRectForFrameRect:window->rect];
    CHECK(fabs(converted.size.height-beforeConverted.size.height)<0.01,"hidden-menu instance frame conversion matches tiled content");
    [theme resizeSubviewsWithOldSize:NSZeroSize]; CHECK(memcmp(&content->rect,&before,sizeof before)==0,"resize keeps content after menu hide");
    [window _showMenuViewIfNeeded]; CHECK(memcmp(&toolbar->rect,&beforeToolbar,sizeof beforeToolbar)==0,"fallback restores original toolbar position");
    CHECK(memcmp(&content->rect,&before,sizeof before)==0,"fallback restores content without drift");
    for(int n=0;n<4;n++){ [window _hideMenuViewIfNeeded]; [window _showMenuViewIfNeeded]; }
    CHECK(memcmp(&content->rect,&before,sizeof before)==0 && fabs(window->rect.size.height-350)<0.01,"repeated fallback cycles do not drift");
    return window;
}
int main(void) {
    alarm(15);
    layoutFixture(30);
    NSWindow *window=layoutFixture(0);
    NSView *menu=window->_menuView; NSToolbarView *toolbar=window->_toolbar->view;
    NSApp=[NSApplication new]; NSApp->allWindows=[NSArray new]; NSApp->allWindows->items[0]=window; NSApp->allWindows->count=1;
    DBusError error; dbus_error_init(&error);
    receiver=dbus_bus_get_private(DBUS_BUS_SESSION,&error);
    X11GlobalMenu *exporter=[X11GlobalMenu new]; exporter->_connection=dbus_bus_get_private(DBUS_BUS_SESSION,&error); exporter->_available=YES;
    struct FixtureSocket socket={.enabled=kCFSocketReadCallBack}; dbus_connection_get_unix_fd(exporter->_connection,&socket.fd); exporter->_cfSocket=&socket;
    dbus_connection_set_exit_on_disconnect(exporter->_connection,FALSE);
    dbus_connection_set_timeout_functions(exporter->_connection,orbitAddTimeout,orbitRemoveTimeout,orbitToggleTimeout,exporter,NULL);
    dbus_connection_add_filter(exporter->_connection,filter,exporter,NULL);
    CHECK(receiver && exporter->_connection,"private session bus connections");
    dbus_bus_request_name(receiver,"space.unmade.GlobalMenu",DBUS_NAME_FLAG_DO_NOT_QUEUE,&error);
    [exporter registerWaylandApplicationMenu:[NSMenu new]]; pump(exporter);
    const char *sender=dbus_bus_get_unique_name(receiver);
    readLayout(exporter,sender); CHECK(!menu->hidden,"Orbit outside GNOME retains local menu");
    DBusMessage *errorReply=dbus_message_new(DBUS_MESSAGE_TYPE_ERROR);
    const char *errorText="No such name"; appendBasic(errorReply,DBUS_TYPE_STRING,&errorText);
    [exporter receiveOrbitReply:errorReply kind:OrbitShellOwnerQuery generation:exporter->_orbitShellGeneration];
    CHECK(!exporter->_orbitShellOwner,"error replies never become owner names"); dbus_message_unref(errorReply);
    dbus_bus_request_name(receiver,"org.gnome.Shell",DBUS_NAME_FLAG_DO_NOT_QUEUE,&error); pump(exporter);
    CHECK(!menu->hidden,"active integration waits for actual Orbit menu read");
    reader=dbus_bus_get_private(DBUS_BUS_SESSION,&error);
    CHECK(reader && strcmp(dbus_bus_get_unique_name(reader),sender)!=0,"fake Orbit reader has a unique name different from the registrar owner");
    readLayoutFrom(exporter,reader,1); CHECK(!menu->hidden && !exporter->_orbitMenuRead,"submenu read from the reader does not count as top-level presentation");
    DBusMessage *unstamped=dbus_message_new_method_call(dbus_bus_get_unique_name(exporter->_connection),"/MenuBar","com.canonical.dbusmenu","GetLayout");
    int32_t unstampedRoot=0,unstampedDepth=-1; appendBasic(unstamped,DBUS_TYPE_INT32,&unstampedRoot); appendBasic(unstamped,DBUS_TYPE_INT32,&unstampedDepth);
    DBusMessageIter unstampedIter,unstampedArray; dbus_message_iter_init_append(unstamped,&unstampedIter); dbus_message_iter_open_container(&unstampedIter,DBUS_TYPE_ARRAY,"s",&unstampedArray); dbus_message_iter_close_container(&unstampedIter,&unstampedArray);
    dbus_message_set_serial(unstamped,1); [exporter handleDBusMessage:unstamped onConnection:exporter->_connection]; dbus_message_unref(unstamped);
    CHECK(!menu->hidden && !exporter->_orbitMenuRead,"request without a bus-stamped sender does not count");
    readLayoutFrom(exporter,reader,0); CHECK(menu->hidden && exporter->_orbitMenuRead,"root read from a reader whose name differs from the registrar hides the local menu");
    stateSignal(exporter,"global-menu@unmade.space",2,sender); CHECK(!menu->hidden,"distinct-reader engagement still follows the authenticated extension state");
    stateSignal(exporter,"global-menu@unmade.space",1,sender); CHECK(!menu->hidden,"reactivation waits for a fresh distinct-reader read");
    readLayoutFrom(exporter,reader,0); CHECK(menu->hidden,"fresh distinct-reader read engages again");
    failLayoutSend=YES; readLayout(exporter,sender); CHECK(!menu->hidden,"failed initial layout send retains local fallback"); failLayoutSend=NO;
    resizeObserver=mutateWindows;
    readLayout(exporter,sender); CHECK(menu->hidden,"active GNOME Orbit reader hides duplicate local menu");
    CHECK(resizeMutations==1 && NSApp->allWindows->count==0,"presentation tolerates resize observers mutating the live window list");
    NSApp->allWindows->items[0]=window; NSApp->allWindows->count=1;
    CHECK(layoutReplies>0,"actual canonical root reply reaches the private reader");
    char *blob=malloc(2*1024*1024); memset(blob,'x',2*1024*1024-1); blob[2*1024*1024-1]=0;
    DBusMessage *bulk=dbus_message_new_signal("/fixture","org.example.Fixture","Bulk");
    dbus_message_set_destination(bulk,sender); const char *bytes=blob; appendBasic(bulk,DBUS_TYPE_STRING,&bytes);
    dbus_connection_send(exporter->_connection,bulk,NULL); dbus_message_unref(bulk); free(blob); [exporter scheduleDBusWrite]; pump(exporter);
    CHECK(writeOnlyProgress>0,"queued requests progress on writable readiness without readable input");
    // Later checks assume a quiescent bus: let the 2 MiB transfer finish instead of racing it.
    for(int n=0;n<200 && (!bulkReceived || dbus_connection_has_messages_to_send(exporter->_connection));n++) pump(exporter);
    CHECK(bulkReceived==1 && !dbus_connection_has_messages_to_send(exporter->_connection),"bulk transfer drains before later reader checks");
    failLayoutSend=YES; readLayout(exporter,sender); CHECK(!menu->hidden && !exporter->_orbitMenuRead,"failed send after engagement restores fallback"); failLayoutSend=NO;
    readLayout(exporter,sender); CHECK(menu->hidden,"successful retry can engage after send failure");
    CHECK(FIXTURE_HAS_ALLOCATION_GUARD,"production reply allocation failure has a bounded fallback path");
#if FIXTURE_HAS_ALLOCATION_GUARD
    failLayoutAllocation=YES;
    DBusMessage *allocationRequest=dbus_message_new_method_call(dbus_bus_get_unique_name(exporter->_connection),"/MenuBar","com.canonical.dbusmenu","GetLayout");
    int32_t allocationRoot=0,allocationDepth=-1; appendBasic(allocationRequest,DBUS_TYPE_INT32,&allocationRoot); appendBasic(allocationRequest,DBUS_TYPE_INT32,&allocationDepth);
    DBusMessageIter allocationIter,allocationProperties; dbus_message_iter_init_append(allocationRequest,&allocationIter); dbus_message_iter_open_container(&allocationIter,DBUS_TYPE_ARRAY,"s",&allocationProperties); dbus_message_iter_close_container(&allocationIter,&allocationProperties);
    dbus_message_set_serial(allocationRequest,1); dbus_message_set_sender(allocationRequest,sender);
    DBusHandlerResult allocationResult=[exporter handleDBusMessage:allocationRequest onConnection:exporter->_connection];
    CHECK(allocationResult==DBUS_HANDLER_RESULT_NEED_MEMORY && !menu->hidden && !exporter->_orbitMenuRead,"failed reply allocation restores fallback");
    dbus_message_unref(allocationRequest); failLayoutAllocation=NO; readLayout(exporter,sender);
#endif
    CHECK(fabs(NSMaxY(toolbar->rect)-window->rect.size.height)<0.01,"integration hide tiles toolbar with no gap");
    DBusMessage *forged=dbus_message_new(DBUS_MESSAGE_TYPE_METHOD_RETURN); appendState(forged,1); dbus_message_set_sender(forged,":99.99");
    stateSignal(exporter,"global-menu@unmade.space",2,sender);
    [exporter receiveOrbitReply:forged kind:OrbitExtensionQuery generation:exporter->_orbitShellGeneration];
    CHECK(!menu->hidden,"extension query replies require the current unique Shell sender"); dbus_message_unref(forged);
    stateSignal(exporter,"global-menu@unmade.space",1,sender); readLayout(exporter,sender);
    DBusMessage *oldOwner=dbus_message_new(DBUS_MESSAGE_TYPE_METHOD_RETURN); const char *obsolete=":99.99";
    appendBasic(oldOwner,DBUS_TYPE_STRING,&obsolete); dbus_message_set_sender(oldOwner,DBUS_SERVICE_DBUS);
    [exporter receiveOrbitReply:oldOwner kind:OrbitShellOwnerQuery generation:exporter->_orbitShellGeneration-1];
    CHECK(exporter->_orbitShellOwner && strcmp([exporter->_orbitShellOwner UTF8String],sender)==0 && menu->hidden,"stale Shell owner reply cannot replace current owner state");
    dbus_message_unref(oldOwner);
    stateSignal(exporter,"other@extension",2,sender); CHECK(menu->hidden,"unrelated extension state leaves menu policy unchanged");
    stateSignal(exporter,"global-menu@unmade.space",2,":99.99"); CHECK(menu->hidden,"forged Shell state is ignored");
    stateSignal(exporter,"global-menu@unmade.space",2,sender); CHECK(!menu->hidden,"disabled Orbit restores local menu");
    DBusMessage *stale=dbus_message_new(DBUS_MESSAGE_TYPE_METHOD_RETURN); appendState(stale,1);
    [exporter receiveOrbitReply:stale kind:OrbitExtensionQuery generation:exporter->_orbitShellGeneration-1];
    CHECK(!menu->hidden && !exporter->_orbitExtensionActive,"late ACTIVE query cannot override a newer disable signal"); dbus_message_unref(stale);
    stateSignal(exporter,"global-menu@unmade.space",1,sender); CHECK(!menu->hidden,"reactivation waits for a fresh reader");
    readLayout(exporter,sender); CHECK(menu->hidden,"reactivated integration hides after read");
    errorReply=dbus_message_new(DBUS_MESSAGE_TYPE_ERROR); appendBasic(errorReply,DBUS_TYPE_STRING,&errorText);
    [exporter receiveOrbitReply:errorReply kind:OrbitExtensionQuery generation:exporter->_orbitShellGeneration];
    CHECK(!menu->hidden && !exporter->_orbitMenuRead,"Shell query failure restores fallback and requires a fresh reader"); dbus_message_unref(errorReply);
    stateSignal(exporter,"global-menu@unmade.space",1,sender); readLayout(exporter,sender);
    stateSignal(exporter,"global-menu@unmade.space",3,sender); CHECK(!menu->hidden,"extension errors restore local menu");
    stateSignal(exporter,"global-menu@unmade.space",1,sender); readLayout(exporter,sender);
    dbus_bus_release_name(receiver,"space.unmade.GlobalMenu",&error); pump(exporter); CHECK(!menu->hidden,"daemon loss restores local menu");
    dbus_bus_request_name(receiver,"space.unmade.GlobalMenu",DBUS_NAME_FLAG_DO_NOT_QUEUE,&error); pump(exporter); CHECK(!menu->hidden,"daemon restart waits for fresh menu read");
    readLayout(exporter,sender); CHECK(menu->hidden,"daemon restart can engage again");
    oldOwner=dbus_message_new(DBUS_MESSAGE_TYPE_ERROR); appendBasic(oldOwner,DBUS_TYPE_STRING,&obsolete); dbus_message_set_sender(oldOwner,DBUS_SERVICE_DBUS);
    [exporter receiveOrbitReply:oldOwner kind:OrbitOwnerQuery generation:exporter->_orbitOwnerGeneration-1];
    CHECK(exporter->_orbitOwner && strcmp([exporter->_orbitOwner UTF8String],sender)==0 && menu->hidden,"stale Orbit owner error cannot clear newer owner state"); dbus_message_unref(oldOwner);
    answerQueries=NO; int timersBefore=timerFires; [exporter queryOrbitIntegration:OrbitExtensionQuery];
    for(int n=0;n<30 && exporter->_orbitExtensionActive;n++) pump(exporter);
    CHECK(timerFires>timersBefore && !menu->hidden && !exporter->_orbitMenuRead,"silent Shell peer times out through production timeout callbacks and restores fallback");
    answerQueries=YES; stateSignal(exporter,"global-menu@unmade.space",1,sender); readLayout(exporter,sender);
    dbus_bus_release_name(receiver,"org.gnome.Shell",&error); pump(exporter); CHECK(!menu->hidden,"Shell loss restores local menu");
    CHECK(fabs(window->rect.size.height-350)<0.01,"all integration transitions preserve original window size on fallback");
    dbus_bus_request_name(receiver,"org.gnome.Shell",DBUS_NAME_FLAG_DO_NOT_QUEUE,&error); pump(exporter); readLayout(exporter,sender); CHECK(menu->hidden,"integration reengages before bus-loss check");
    dbus_connection_close(exporter->_connection); [exporter processPendingDBusEvents];
    CHECK(!menu->hidden && !exporter->_available,"transport disconnect restores local menu inline and leaves application alive");
    X11GlobalMenu *failureExporter=[X11GlobalMenu new];
    failureExporter->_connection=dbus_bus_get_private(DBUS_BUS_SESSION,&error); dbus_connection_set_exit_on_disconnect(failureExporter->_connection,FALSE);
    dbus_connection_set_timeout_functions(failureExporter->_connection,orbitAddTimeout,orbitRemoveTimeout,orbitToggleTimeout,failureExporter,NULL);
    failureExporter->_available=YES; failureExporter->_orbitOwnerWatchReady=YES; failureExporter->_orbitStateWatchReady=YES;
    failureExporter->_orbitExtensionActive=YES; failureExporter->_orbitMenuRead=YES;
    failureExporter->_orbitOwner=[[NSString alloc] initWithUTF8String:sender]; failureExporter->_orbitShellOwner=[[NSString alloc] initWithUTF8String:sender];
    [failureExporter updateWaylandMenuPresentation]; CHECK(menu->hidden,"query-setup failure control begins engaged");
    queryAllocationSize=sizeof(OrbitQuery); failQueryAllocation=YES; [failureExporter queryOrbitIntegration:OrbitExtensionQuery];
    CHECK(failureExporter->_orbitProgressFailed && !menu->hidden,"unobserved pending-query allocation failure permanently restores fallback");
    [failureExporter updateWaylandMenuPresentation]; CHECK(!menu->hidden,"progress failure cannot reengage from old ACTIVE/read evidence");
    dbus_connection_close(failureExporter->_connection);
    // A busy main loop can find a watch deadline due while the bus reply is already readable.
    X11GlobalMenu *raceExporter=[X11GlobalMenu new];
    raceExporter->_connection=dbus_bus_get_private(DBUS_BUS_SESSION,&error); dbus_connection_set_exit_on_disconnect(raceExporter->_connection,FALSE);
    struct FixtureSocket raceSocket={.enabled=kCFSocketReadCallBack}; dbus_connection_get_unix_fd(raceExporter->_connection,&raceSocket.fd); raceExporter->_cfSocket=&raceSocket;
    dbus_connection_set_timeout_functions(raceExporter->_connection,orbitAddTimeout,orbitRemoveTimeout,orbitToggleTimeout,raceExporter,NULL);
    raceExporter->_available=YES; raceExporter->_waylandApplicationMenu=YES;
    pump(raceExporter); // consume NameAcquired so only the watch reply can be readable
    int raceTimer=timerCount; [raceExporter queryOrbitIntegration:OrbitOwnerWatchQuery]; dbus_connection_flush(raceExporter->_connection);
    struct pollfd raceReadable={.fd=raceSocket.fd,.events=POLLIN}; poll(&raceReadable,1,5000);
    CHECK(timerCount==raceTimer+1 && (raceReadable.revents&POLLIN),"owner-watch reply is readable while its deadline timer is pending");
    if(timerCount==raceTimer+1){ CFRunLoopTimerRef timer=timers[raceTimer]; timer->callback(timer,timer->info); }
    CHECK(raceExporter->_orbitOwnerWatchReady,"deadline firing before socket dispatch still accepts the already-received owner-watch reply");
    CHECK(!timers[raceTimer]->valid,"received reply retires its deadline timer");
    // A watch that genuinely fails is retried rather than left unready until another window maps.
    raceExporter->_orbitOwnerWatchReady=NO; unsigned int raceGeneration=raceExporter->_orbitOwnerGeneration;
    DBusMessage *watchError=dbus_message_new(DBUS_MESSAGE_TYPE_ERROR); dbus_message_set_error_name(watchError,DBUS_ERROR_NO_REPLY);
    [raceExporter receiveOrbitReply:watchError kind:OrbitOwnerWatchQuery generation:raceExporter->_orbitShellGeneration]; dbus_message_unref(watchError);
    for(int n=0;n<20 && !raceExporter->_orbitOwnerWatchReady;n++) pump(raceExporter);
    CHECK(raceExporter->_orbitOwnerWatchRetries==1 && raceExporter->_orbitStateWatchRetries==0 && raceExporter->_orbitOwnerWatchReady,"failed owner watch is retried on its own budget and becomes ready");
    for(int n=0;n<20 && !raceExporter->_orbitOwner;n++) pump(raceExporter);
    CHECK(raceExporter->_orbitOwnerGeneration==raceGeneration+1 && raceExporter->_orbitOwner && strcmp([raceExporter->_orbitOwner UTF8String],sender)==0,"late owner watch refreshes the owner snapshot it guards");
    // Each watch has its own budget: exhausting the owner watch leaves the state watch's retries intact.
    raceExporter->_orbitOwnerWatchRetries=2; raceExporter->_orbitOwnerMatchAdded=YES;
    watchError=dbus_message_new(DBUS_MESSAGE_TYPE_ERROR); dbus_message_set_error_name(watchError,DBUS_ERROR_NO_REPLY);
    [raceExporter receiveOrbitReply:watchError kind:OrbitOwnerWatchQuery generation:raceExporter->_orbitShellGeneration]; dbus_message_unref(watchError);
    CHECK(!raceExporter->_orbitOwnerWatchReady && !raceExporter->_orbitOwnerMatchAdded,"exhausted owner watch waits for the next window registration");
    raceExporter->_orbitStateWatchReady=NO;
    watchError=dbus_message_new(DBUS_MESSAGE_TYPE_ERROR); dbus_message_set_error_name(watchError,DBUS_ERROR_NO_REPLY);
    [raceExporter receiveOrbitReply:watchError kind:OrbitStateWatchQuery generation:raceExporter->_orbitShellGeneration]; dbus_message_unref(watchError);
    for(int n=0;n<20 && !raceExporter->_orbitStateWatchReady;n++) pump(raceExporter);
    CHECK(raceExporter->_orbitStateWatchRetries==1 && raceExporter->_orbitStateWatchReady,"state watch retries independently of an exhausted owner watch");
    dbus_connection_close(raceExporter->_connection);
    dbus_connection_close(reader);
    dbus_connection_close(receiver);
    if(failures) return 1;
    puts("PASS: production layout, GNOME/Orbit activation, bus-delivered readers, state/owner fallback and repeated transitions");
    return 0;
}
