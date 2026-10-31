#import <Foundation/NSObject.h>
#import <AppKit/NSMenu.h>
#import <X11/Xlib.h>
#import <CoreFoundation/CoreFoundation.h>

@class NSWindow;
typedef struct DBusConnection DBusConnection;

@interface X11GlobalMenu : NSObject {
    DBusConnection *_connection;
    CFSocketRef _cfSocket;
    CFRunLoopSourceRef _runLoopSource;
    NSMenu *_currentMenu;
    NSMutableDictionary *_itemsByID;
    NSMutableDictionary *_idByItem;
    int _nextID;
    unsigned int _revision;
    BOOL _available;
    BOOL _globalMenuEngaged;
    BOOL _waylandApplicationMenu;
    BOOL _orbitOwnerMatchAdded;
    BOOL _orbitProgressFailed;
    BOOL _orbitOwnerWatchReady;
    BOOL _orbitStateWatchReady;
    BOOL _orbitExtensionActive;
    BOOL _orbitMenuRead;
    NSString *_orbitOwner;
    NSString *_orbitShellOwner;
    unsigned int _orbitShellGeneration;
    unsigned int _orbitOwnerGeneration;
}

+ (instancetype) sharedGlobalMenu;
- (BOOL) isAvailable;
- (BOOL) isEngaged;
- (void) registerWindow: (Window) x11Window forMenu: (NSMenu *) menu;
- (void) unregisterWindow: (Window) x11Window;
- (void) updateMenu: (NSMenu *) menu;
- (void) registerWaylandApplicationMenu: (NSMenu *) menu;

@end
