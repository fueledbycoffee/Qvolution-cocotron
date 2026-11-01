#!/usr/bin/env python3
"""Public portal Settings v2 fake for the guest raster fixture. No host settings change."""
import dbus, dbus.service, dbus.mainloop.glib
from gi.repository import GLib
from pathlib import Path
import sys
dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus=dbus.SessionBus();owner=dbus.service.BusName('org.freedesktop.portal.Desktop',bus)
class Settings(dbus.service.Object):
    def __init__(self):
        super().__init__(bus,'/org/freedesktop/portal/desktop');self.accent=(.835,.380,.600)
    @dbus.service.method('org.freedesktop.portal.Settings',in_signature='as',out_signature='a{sa{sv}}')
    def ReadAll(self,spaces):
        assert list(spaces)==['org.freedesktop.appearance','org.gnome.desktop.interface']
        return {'org.freedesktop.appearance':{'accent-color':dbus.Struct(self.accent,signature='ddd',variant_level=1),'color-scheme':dbus.UInt32(1,variant_level=1),'contrast':dbus.UInt32(0,variant_level=1)},'org.gnome.desktop.interface':{'font-name':dbus.String('Inter 11',variant_level=1),'overlay-scrolling':dbus.Boolean(True,variant_level=1)}}
    @dbus.service.signal('org.freedesktop.portal.Settings',signature='ssv')
    def SettingChanged(self,space,key,value): pass
    @dbus.service.method('space.qvolution.ThemeFixture',in_signature='',out_signature='')
    def SetBlue(self):
        self.accent=(0.,0.,1.);self.SettingChanged('org.freedesktop.appearance','accent-color',dbus.Struct(self.accent,signature='ddd',variant_level=1))
settings=Settings()
Path(sys.argv[1]).write_text('ready\n')
GLib.MainLoop().run()
