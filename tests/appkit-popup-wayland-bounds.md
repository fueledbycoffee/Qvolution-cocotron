# Wayland popup bounds and scrolling follow-up

The previous visibleFrame fixture passed but user acceptance still showed an
overflowing font list. Wayland toplevel origins are virtual; NSWindow.screen
intersects the application's requested frame, so it cannot identify the native
output. Also WaylandDisplay currently exposes full output frame as visibleFrame;
a full-height popup needs compositor resizing to fit panels/workarea.

The private CGWindow.maximumPopupSize hook is new implementation plumbing, not
an Apple API. The Wayland implementation uses its actual mapped popup parent's
entered-output membership and existing logical topology. Multiple entered outputs
use the smallest dimensions; before entry metadata arrives it conservatively
uses the smallest known output. X11/default returns unavailable and keeps the
existing visibleFrame path. Querying does not map a window. Bounded viewport
positioning keeps the selected row near the original control using relative
coordinates, rather than clamping to a guessed global output.

Only NSPopUpWindow enables xdg-positioner RESIZE_Y. Ordinary NSMenuWindow remains
unchanged. The compositor owns workarea exclusion. Its popup configure reaches
WaylandWindow.applyConfigure and NSWindow.platformWindow:frameChanged:didSize:;
NSPopUpWindow then explicitly resizes its view to real content bounds, clamps
scroll offset and reveals selection. It does not send a new setFrame/reposition
from the configure callback.

Run with AppKit, private component include root and CoreGraphics/include, with
assertions enabled (-UNDEBUG). Each fixture rejects NDEBUG:

- appkit-popup-parent-output.m: creates an own-source parent, runs normal AppKit
  with the existing stop-and-post timer idiom, prints actual logical topology
  and entered membership. --diagnostic only observes. Default temporarily
  substitutes each real output's membership on its own parent, then executes the
  actual backend hook and popup geometry, checking no map occurs on query.
- appkit-popup-configured-viewport.m: dispatches popup configure state to the
  actual backend and runs its production applyConfigure/after-dispatch/delegate
  path. A no-op display/orderFront avoids native mapping. It checks400→800→300
  viewport height, last-row reachability and growth offset clamp. It deliberately
  does not manufacture xdg configure acknowledgment serials.
- appkit-popup-hit-throughput.m: counts actual menu reads/rectangle lookups for
  1000 hits at row399. The old linear path performs400000 rectangle reads and
  1000 menu array reads. Binary search bounds row probes to10000 while leaving
  live visible-item enumeration intact. Enabled/hidden/removed last-row state
  remains live. No cross-event snapshot or nonexistent mutation revision is used.

Wheel distance is three rows/notch, matching this tree's existing NSScrollView
wheel convention; Wayland pointerAxis normalizes one physical notch to delta1.
This is a usability policy, not a measured Apple scrolling constant. The work
counter is not an end-to-end frame-rate benchmark. Native wheel/key delivery,
visual workarea fit and action/dismissal acceptance remain user/integration gates.

Provenance: vendored NSWindow/NSPopUpView/NSScrollView and Wayland backend source
and interfaces (rung2); xdg-shell protocol XML installed at
/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml, constraint_adjustment
resize_y=32 and popup configure behavior; own-source boundary observations
(rung4). Smallest-known-output and centering policies are conservative new
implementation choices (rung6); no Apple implementation inspection.
