# GNOME Orbit local-menu presentation

Run `python3 tests/appkit-orbit-presentation-host.py`. It needs host Clang, the
GNU Objective-C runtime/development headers, libdbus development headers and
`dbus-run-session`. The test creates a bounded temporary native fixture and
private session bus. It never boots a guest, changes the desktop or reads app
binaries. `--baseline 1c154eb2` exercises the same test against parent source.

The harness extracts production registration, query, watch/owner/state handling,
reply construction/send, engagement, socket progress, timeout callbacks and
window/theme layout methods verbatim. View/application/runtime, CoreFoundation
socket/timer and main-queue shims supply deterministic behavior. A real private
D-Bus daemon supplies owner identity, owner changes and asynchronous query
replies; poll readiness and monotonic deadlines drive the production callbacks.
The menu-tree shim supplies an empty canonical root while the actual GetLayout
reply construction/send path runs. Existing serialization/action fixtures and
literal source comparisons cover those unchanged menu-item paths separately.

Checks include both zero and 30-point titlebar policies; content geometry,
toolbar placement, frame conversion and repeated hide/restore without drift;
no Shell, no reader, unrelated readers, authenticated ACTIVE state and current
Orbit reads; forged/irrelevant state and query senders; stale state/owner query
replies; disable/error and owner/query failure; initial and previously engaged
reply-send failures; allocation failure; window-list mutation from synchronous
resize observers; actual canonical reply receipt; writable-only progress with
queued transport; silent-peer timeout; daemon loss/restart and Shell/transport
loss. The baseline's missing allocation guard is reported as an assertion
instead of intentionally passing NULL into its legacy serializer.

The Shell contract is documented in the installed primary interface
`/usr/share/dbus-1/interfaces/org.gnome.Shell.Extensions.xml`:
GetExtensionInfo(s) returns a{sv}, double `state` value 1 means ACTIVE,
and ExtensionStateChanged(s,a{sv}) reports changes. The existing project Orbit
bridge uses RegisterWaylandMenu(o) and canonical dbusmenu GetLayout. This is an
explicit project/user presentation preference. No Orbit rendering
acknowledgement exists or is claimed.

New integration watch/query/write/deadline paths avoid waiting for replies or
flushing the transport synchronously. Existing startup `dbus_bus_get` and
registrar owner checks remain synchronous; this change does not claim otherwise.
A progress-scheduling allocation failure permanently retains local menus and
queues presentation refresh outside the libdbus callback lock.

The host test substitutes runtime, views, menu tree, CoreFoundation and queue
behavior. It is implementation/transport evidence, not desktop acceptance.
Actual GNOME pixels, guest menu action/check/disabled/keyboard behavior,
multiple-app focus, restart behavior and stability still need staged runtime
acceptance. The live TextEdit and all 24-app UI/GPU/stability qualifications
remain unchanged and open.
