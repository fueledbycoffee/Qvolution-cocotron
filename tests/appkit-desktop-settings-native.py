#!/usr/bin/env python3
"""Native in-process fake portal. Compiles the production decoder/palette and
production run-loop drain method; substitutes only Cocoa/CF and socket delivery.
No session bus, container, display, network or Apple binary is needed.
"""
from pathlib import Path
import os, shlex, subprocess, tempfile
assert os.environ.get("QV_SLOT", "").startswith("build-"), "run via dashboard/qv-slot build"
root=Path(__file__).resolve().parents[1]
source=(root/'AppKit/X11.backend/X11DesktopSettings.m').read_text()
start=source.index('- (void)processPendingEvents {');end=source.index('\n- (NSAppearance *)systemAppearance',start)
method=source[start:end]
harness=r'''
#include <dbus/dbus.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <math.h>
#include <string.h>
#include "X11DesktopSettingsCore.h"
#include "X11ThemePalette.h"
static DBusMessage *queue[16]; static int head,tail,will,did,notifications,disconnected;
__attribute__((objc_root_class)) @interface NSAppearance { Class isa; }
+ (id)new; - (id)retain; - (void)release;
@end
@implementation NSAppearance
+ (id)new { return class_createInstance(self,0); }
- (id)retain { return self; } - (void)release {}
@end
@class X11DesktopSettings;
@interface Application : NSAppearance
- (id)effectiveAppearance;
- (void)willChangeValueForKey:(id)key;
- (void)_desktopSettingsDidChangeFrom:(id)previous;
@end
@interface X11DesktopSettings : NSAppearance {
@public QVDesktopState _state; DBusConnection *_connection;
}
- (void)processPendingEvents; - (void)disconnect;
@end
static Application *NSApp;
static X11DesktopSettings *settings;
@implementation Application
- (id)effectiveAppearance { return self; }
- (void)willChangeValueForKey:(id)key { assert(settings->_state.accent[0]>.8); will++; }
- (void)_desktopSettingsDidChangeFrom:(id)previous { assert(settings->_state.accent[2]==1); did++; notifications++; }
@end
static dbus_bool_t fixtureRead(DBusConnection *c,int timeout) { assert(timeout==0);return 1; }
static DBusMessage *fixturePop(DBusConnection *c) { return head<tail?queue[head++]:NULL; }
static dbus_bool_t fixtureConnected(DBusConnection *c) { return !disconnected; }
#define dbus_connection_read_write fixtureRead
#define dbus_connection_pop_message fixturePop
#define dbus_connection_get_is_connected fixtureConnected
@implementation X11DesktopSettings
/* PRODUCTION */
- (void)disconnect { _connection=NULL; }
@end

static void appendAccent(DBusMessageIter *parent,const double a[3]) {
 DBusMessageIter variant,rgb;
 assert(dbus_message_iter_open_container(parent,DBUS_TYPE_VARIANT,"(ddd)",&variant));
 assert(dbus_message_iter_open_container(&variant,DBUS_TYPE_STRUCT,NULL,&rgb));
 for(int i=0;i<3;i++)assert(dbus_message_iter_append_basic(&rgb,DBUS_TYPE_DOUBLE,a+i));
 assert(dbus_message_iter_close_container(&variant,&rgb));
 assert(dbus_message_iter_close_container(parent,&variant));
}
static DBusMessage *signalAccent(const double a[3]) {
 DBusMessage *m=dbus_message_new_signal("/org/freedesktop/portal/desktop","org.freedesktop.portal.Settings","SettingChanged");assert(m);
 dbus_message_set_sender(m,":1.42");
 DBusMessageIter i;dbus_message_iter_init_append(m,&i);
 const char *space="org.freedesktop.appearance", *key="accent-color";
 dbus_message_iter_append_basic(&i,DBUS_TYPE_STRING,&space);dbus_message_iter_append_basic(&i,DBUS_TYPE_STRING,&key);
 appendAccent(&i,a);return m;
}
static DBusMessage *setting(const char *space,const char *key,int type,const void *value) {
 DBusMessage *m=dbus_message_new_signal("/org/freedesktop/portal/desktop","org.freedesktop.portal.Settings","SettingChanged");assert(m);
 DBusMessageIter i,v;dbus_message_iter_init_append(m,&i);
 dbus_message_iter_append_basic(&i,DBUS_TYPE_STRING,&space);dbus_message_iter_append_basic(&i,DBUS_TYPE_STRING,&key);
 char signature[]={type,0};dbus_message_iter_open_container(&i,DBUS_TYPE_VARIANT,signature,&v);
 dbus_message_iter_append_basic(&v,type,value);dbus_message_iter_close_container(&i,&v);return m;
}
static DBusMessage *snapshot(const double a[3]) {
 DBusMessage *m=dbus_message_new(DBUS_MESSAGE_TYPE_METHOD_RETURN);assert(m);
 DBusMessageIter i,spaces,entry,keys,pair;dbus_message_iter_init_append(m,&i);
 const char *space="org.freedesktop.appearance",*key="accent-color";
 assert(dbus_message_iter_open_container(&i,DBUS_TYPE_ARRAY,"{sa{sv}}",&spaces));
 assert(dbus_message_iter_open_container(&spaces,DBUS_TYPE_DICT_ENTRY,NULL,&entry));
 dbus_message_iter_append_basic(&entry,DBUS_TYPE_STRING,&space);
 assert(dbus_message_iter_open_container(&entry,DBUS_TYPE_ARRAY,"{sv}",&keys));
 assert(dbus_message_iter_open_container(&keys,DBUS_TYPE_DICT_ENTRY,NULL,&pair));
 dbus_message_iter_append_basic(&pair,DBUS_TYPE_STRING,&key);appendAccent(&pair,a);
 dbus_message_iter_close_container(&keys,&pair);dbus_message_iter_close_container(&entry,&keys);
 dbus_message_iter_close_container(&spaces,&entry);dbus_message_iter_close_container(&i,&spaces);return m;
}
static void pixel(QVThemeColor c,int r,int g,int b) {
 assert(abs((int)lround(c.r*255)-r)<=2);assert(abs((int)lround(c.g*255)-g)<=2);assert(abs((int)lround(c.b*255)-b)<=2);
}
int main(void) {
 const double pink[]={.835,.380,.600},blue[]={0,0,1},invalid[]={-1,0,0},nan[]={NAN,0,0};
 QVDesktopState s;QVDesktopStateInit(&s);assert(!s.hasAccent&&s.colorScheme==0&&s.accent[0]==10.0/255);
 s.colorScheme=1;s.contrast=1;
 assert(QVDesktopAppearance(&s,false,false,NULL)==2); // dark gate, HC still active
 assert(QVDesktopAppearance(&s,true,false,NULL)==3);
 assert(QVDesktopAppearance(&s,true,true,"dark")==0); // plist opt-out wins
 assert(QVDesktopAppearance(&s,true,false,"light")==2);
 assert(QVDesktopAppearance(&s,false,false,"dark")==2);
 s.colorScheme=0;s.contrast=0;
 DBusMessage *request=QVDesktopReadRequest();assert(dbus_message_has_signature(request,"as"));
 assert(!strcmp(dbus_message_get_member(request),"ReadAll"));
 DBusMessageIter i,array;dbus_message_iter_init(request,&i);dbus_message_iter_recurse(&i,&array);
 const char *space;dbus_message_iter_get_basic(&array,&space);assert(!strcmp(space,"org.freedesktop.appearance"));
 dbus_message_iter_next(&array);dbus_message_iter_get_basic(&array,&space);assert(!strcmp(space,"org.gnome.desktop.interface"));dbus_message_unref(request);
 DBusMessage *m=snapshot(pink);assert(QVDesktopReadAll(&s,m));assert(!QVDesktopReadAll(&s,m));dbus_message_unref(m);
 const char *font="Inter 11";double scale=1.25;dbus_bool_t overlay=FALSE;
 m=setting("org.gnome.desktop.interface","font-name",DBUS_TYPE_STRING,&font);assert(QVDesktopChanged(&s,m));assert(!strcmp(s.fontName,font));dbus_message_unref(m);
 m=setting("org.gnome.desktop.interface","text-scaling-factor",DBUS_TYPE_DOUBLE,&scale);assert(QVDesktopChanged(&s,m));assert(s.textScale==1.25);dbus_message_unref(m);
 m=setting("org.gnome.desktop.interface","overlay-scrolling",DBUS_TYPE_BOOLEAN,&overlay);assert(QVDesktopChanged(&s,m));assert(!s.overlayScrolling);dbus_message_unref(m);
 scale=NAN;m=setting("org.gnome.desktop.interface","text-scaling-factor",DBUS_TYPE_DOUBLE,&scale);assert(!QVDesktopChanged(&s,m));dbus_message_unref(m);
 uint32_t number=1;m=setting("org.freedesktop.appearance","color-scheme",DBUS_TYPE_UINT32,&number);assert(QVDesktopChanged(&s,m));assert(QVDesktopAppearance(&s,false,false,NULL)==0);dbus_message_unref(m);
 m=setting("org.freedesktop.appearance","accent-color",DBUS_TYPE_UINT32,&number);assert(!QVDesktopChanged(&s,m));dbus_message_unref(m);
 m=setting("org.unknown","color-scheme",DBUS_TYPE_UINT32,&number);assert(!QVDesktopChanged(&s,m));dbus_message_unref(m);
 QVThemeColor c;assert(QVThemeLookup("controlAccentColor",false,false,s.accent,&c));pixel(c,213,97,153);
 assert(QVThemeLookup("selectedMenuItemColor",false,false,s.accent,&c));pixel(c,213,97,153);
 assert(QVThemeLookup("selectedTextBackgroundColor",false,false,s.accent,&c));pixel(c,240,200,219);
 assert(QVThemeLookup("headerColor",false,false,s.accent,&c));pixel(c,255,255,255);
 assert(QVThemeLookup("windowBackgroundColor",true,false,s.accent,&c));pixel(c,46,46,46);
 assert(QVThemeLookup("separatorColor",true,true,s.accent,&c));assert(c.a==1);
 pixel(QVOnAccent(QVRGB(0xFFFF00)),0,0,0); // yellow uses dark text
 m=signalAccent(invalid);assert(QVDesktopChanged(&s,m));assert(!s.hasAccent&&s.accent[2]==1);dbus_message_unref(m);
 m=signalAccent(nan);assert(!QVDesktopChanged(&s,m));dbus_message_unref(m);
 m=dbus_message_new_signal("/wrong","org.freedesktop.portal.Settings","SettingChanged");assert(!QVDesktopChanged(&s,m));dbus_message_unref(m);
 m=signalAccent(pink);assert(QVDesktopChanged(&s,m));dbus_message_unref(m);
 // The actual production run-loop callback drains a fake portal's broadcast
 // queue, and delivers precisely one KVO/change notification transaction.
 settings=[X11DesktopSettings new];settings->_state=s;settings->_connection=(DBusConnection*)1;NSApp=[Application new];
 queue[tail++]=signalAccent(blue);queue[tail++]=signalAccent(blue);
 [settings processPendingEvents];assert(will==1&&did==1&&notifications==1);
 [settings processPendingEvents];assert(notifications==1);
 // Unicast messages can bypass bus matches and must never modify the state.
 m=signalAccent(pink);dbus_message_set_destination(m,":1.43");queue[tail++]=m;
 [settings processPendingEvents];assert(notifications==1&&settings->_state.accent[2]==1);
 disconnected=1;[settings processPendingEvents];assert(!settings->_connection);
 puts("PASS native fake portal: ReadAll, pink accent/menu/text pixels, invalid values, exact one-turn notification, duplicate/unicast rejection, disconnect");
 return 0;
}
'''.replace('/* PRODUCTION */',method)
flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','dbus-1'],text=True))
objc=subprocess.check_output(['gcc','-print-file-name=include'],text=True).strip()
with tempfile.TemporaryDirectory(prefix='theme-p1-native-') as tmp:
 tmp=Path(tmp);(tmp/'test.m').write_text(harness)
 for opt in ['-O0','-O2']:
  subprocess.run(['clang','-x','c','-std=c11',opt,'-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-I'+str(root/'AppKit/X11.backend'),*[f for f in flags if f.startswith('-I')],'-c',str(root/'AppKit/X11.backend/X11DesktopSettingsCore.m'),'-o',str(tmp/'core.o')],check=True)
  subprocess.run(['clang',opt,'-Wno-unused-parameter','-Wno-objc-root-class','-Wno-objc-method-access','-fsanitize=address,undefined','-I'+objc,'-I'+str(root/'AppKit/X11.backend'),str(tmp/'test.m'),str(tmp/'core.o'),'-lobjc','-lm',*flags,'-o',str(tmp/'test')],check=True)
  import os
  subprocess.run([str(tmp/'test')],check=True,env={**os.environ,'ASAN_OPTIONS':'detect_leaks=0','UBSAN_OPTIONS':'halt_on_error=1'})
