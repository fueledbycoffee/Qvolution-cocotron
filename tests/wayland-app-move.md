Run from the cocotron root:

```sh
ASAN_OPTIONS=detect_leaks=0 python3 tests/wayland-app-move.py a360e4d95
ASAN_OPTIONS=detect_leaks=0 python3 tests/wayland-app-move.py
```

The first command must fail at the first expected move request; the second must
pass. Leak detection is disabled only for sandbox runners where LeakSanitizer
cannot enumerate threads under ptrace. Address/undefined-behavior checks remain
on. This follows `wayland-decoration-inputs.py`: production method bodies run
natively with protocol/rendering doubles, without AppKit or a compositor.

The test checks an origin-only content drag emits one `xdg_toplevel.move` with
the initiating seat and serial, repeated frame changes do not emit another,
and release/focus loss allow a later press. An implicit move requires changed
pointer coordinates with the left button held after this window's content press,
plus a current left-drag event for that window. A click action that calls
center/setFrameOrigin without motion must not issue a compositor move. Motion
in another window or without the held left button must not qualify the press. It also covers no held press,
unchanged frames, size changes, right buttons, our decorations, popup roles,
missing seats, explicit window dragging, and retention of the requested frame.
Event decoder and teardown wiring are checked separately in source.

`NSWindow` and the backend retain the requested frame origin; neither claims it
is the compositor's actual position. `performWindowDragWithEvent:` uses the
same press as the frame-change path. Its Wayland bridge accepts this window's
left-down/drag events while a content press is armed. This conservative bridge
is GUESS for real macOS behavior. `isMovableByWindowBackground` already has a
working getter/setter; automatic background dragging remains unchanged because
`NSView mouseDownCanMoveWindow` is unimplemented and choosing eligible views is
not a trivial backend bridge.

A real compositor/user run is still required: rebuild AppKit and the Wayland
backend, launch Stickies on GNOME Wayland, drag a note by its own chrome, release,
and drag again. Confirm both drags move the visible note; a successful compositor
move loses pointer focus, so the initiating release need not reach the client.
Protocol source: installed stable xdg-shell XML, `xdg_toplevel.move` (rung 1/3).
The triggering app behavior comes from the user's Stickies report and our API
boundary records in `logs/qv3apps/stickies-s10/trace.txt` (rung 4).
