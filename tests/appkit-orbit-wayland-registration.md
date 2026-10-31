# Orbit native Wayland registration

Build `appkit-orbit-wayland-registration.m` as a Darling executable linked to
AppKit, Foundation and the Mach-O `dbus` native wrapper, with host dbus header
include paths as the existing X11 backend uses. Run with the Wayland backend,
a dedicated prefix, and a **private** `dbus-run-session` bus whose address is
passed into the guest. It creates no app window and does not touch desktop
settings. Always shut down the prefix afterward.

The fixture owns Orbit's name on a second private bus connection, calls the real
exporter registration method, and checks the native method's signature `o`,
endpoint `/MenuBar`, actual bus sender identity and no-reply flag. No X11 ID is
supplied. It invokes real GetLayout handling and requires local-menu engagement
to remain false, then releases/reacquires the fake Orbit owner and requires a
fresh registration. The parent reports the registration method missing.

Counterpart: the Orbit 1.1.3 companion patch accepts RegisterWaylandMenu(o) on
space.unmade.GlobalMenu, obtains host PID/UID from the bus daemon, and reuses
its canonical menu reader via GetMenuForProcess(u)->(so). Focus PID comes from
Meta.Window.get_pid(), never a guessed XID. Ambiguous or unavailable PIDs fail
closed. The installed extension and daemon are not changed by this fixture.

The native in-window menu deliberately remains visible even if Orbit reads the
layout. Orbit 1.1.3 has no rendering acknowledgement; hiding duplicates is a
later protocol/visual acceptance step. No consumer means no loss of access.

This does not verify a real GNOME top-bar menu, host/guest focus PID equivalence,
action clicks, menu mutation/toggle state, or GPU rendering. Those need an
activated patched Orbit session and real app testing. Provenance: existing
Cocotron source and Orbit 1.1.3 public source/interfaces (rung 2), protocol
fixtures at the D-Bus boundary (rung 4); no Apple binary inspection.
