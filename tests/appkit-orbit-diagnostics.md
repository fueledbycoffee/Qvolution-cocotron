# Orbit presentation diagnostics

Set `DARLING_ORBIT_MENU_DIAGNOSTICS=1` for an opt-in append-only log at
`/tmp/qvolution-orbit-menu.log` inside the guest prefix. Unset, empty and `0`
disable it. An absolute value selects another guest path for isolated tests.
The parent directory must already exist. Open failures report to stderr.

The logger records only our exporter state and public D-Bus metadata: requested
and registered backend, session bus and registrar presence, query kind/serial,
sender authentication, current/query generations, extension state, reader
identity and each GetLayout predicate, reply queue/signature result, transport
queue progress, and every presentation decision with all gate values.
No menu content, guest internals or proprietary implementation is recorded.

Query kinds: 0 Orbit owner, 1 Shell owner, 2 extension info, 3 owner watch,
4 extension-state watch. A query's `error` is the D-Bus error name, including
access-denied, unknown-name and timeout errors. A stale reply is logged before
being rejected. Owner changes and layout requests identify both generations.

`layout-reply queued=1` is the existing successful `dbus_connection_send`
criterion. `transport-progress pending-write=0` means the local connection's
queue drained. Neither proves peer receipt or GNOME pixel presentation, and
there is no invented Orbit acknowledgement. Match request/reply serials to
follow an individual layout. `decision` includes the first unmet gate as
`reason`, plus every gate value so simultaneous failures remain visible.

Run `python3 tests/appkit-orbit-presentation-host.py`. The original native
private-bus assertions run with logging disabled and enabled. Diagnostic checks
cover authenticated/stale queries, accepted/rejected readers, send failure,
successful queueing, engagement and restoration. Shims and sandbox socket
restrictions remain as described in `appkit-orbit-presentation-host.md`.
Only a live GNOME/Orbit run can identify the failing gate in the user's case.
