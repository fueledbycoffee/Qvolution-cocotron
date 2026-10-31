# Bounded popup viewport

Build `appkit-popup-viewport.m` with AppKit and private headers (`-I` the
Cocotron component root). Run against the staged runtime in a dedicated prefix,
then shut down that exact prefix. The parent should fail its frame-containment
assertion on the first 400-item menu.

The fixture executes production popup preparation and view scrolling using a
synthetic screen whose usable area has a nonzero/negative origin. Window ordering
and modal tracking are overridden to return immediately; this is not a native
input or compositor test. It verifies first/middle/last selection visibility,
scroll clamps, keyboard action visibility and unchanged short-menu height.
Actual wheel-event delivery, pointer-edge scrolling, Escape/Return/outside-click
dismissal and visual workarea placement need a staged interactive check.

Provenance: vendored NSScreen.visibleFrame, NSView.setBoundsOrigin and existing
NSPopUpView keyboard/tracking implementation (rung 2); Apple's public
NSPopUpButton preferredEdge documentation describes restrictive screen conditions
and positioning the selected item over the button (rung 3):
https://developer.apple.com/documentation/appkit/nspopupbutton/preferrededge
The reported overflowing font popup is a user observation at the UI boundary
(rung 4). Bounding and scrolling content instead of moving an oversized native
window is our conservative implementation policy, not a claim about Apple's
internal layout, edge-scroll speed or pixel appearance (rung 6).

This change covers NSPopUpButton's independent NSPopUpWindow/NSPopUpView path.
NSMenuWindow/NSSubmenuView (ordinary and nested menu windows) is a different path
and is deliberately not changed. Wayland positioners already slide/flip popups;
those constraints cannot make a menu taller than its output fit. No native IDs,
Wayland roles or compositor settings are changed.

WaylandDisplay currently exposes each output's full logical frame as its
visibleFrame, so this bounds to known output geometry; panel/dock exclusion is
not independently known. Exact usable-workarea enforcement still depends on the
compositor. A future popup-only compositor resize negotiation must preserve
scrolling when its configured viewport is smaller; globally resizing ordinary
NSMenuWindow would clip content without making it reachable.
