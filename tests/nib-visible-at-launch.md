# Nib launch visibility

Specification: rung 3, Apple's public *Resource Programming Guide*, “Nib Files”
(https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/LoadingResources/CocoaNibs/CocoaNibs.html),
Nib Object Life Cycle: nib loading awakens objects and displays windows marked
visible at launch. NSWindow `init(contentRect:styleMask:backing:defer:)`
(https://developer.apple.com/documentation/appkit/nswindow/init(contentrect:stylemask:backing:defer:))
separately defers creation of the window-server window; it does not request display.
These are the public-doc behavior specified in this lane; no network or vendor nib
inspection was used. Archive keys and flag values come from this repository's
NSIBObjectData.m and NSWindowTemplate.h/.m (rung 2 existing source contracts).

`nib-visible-fixtures.py DIR` writes three own keyed nibs. Each has a regular
window, hidden NSPanel, and deferred regular window. Only the mixed fixture marks
its first window visible. Empty and missing metadata controls must show nothing.
The empty case fails on a8091e98: NSNib's heuristic shows ordinary hidden windows.
The guest fixture loads with NSBundle's NSApplicationMain-style entry point, then
checks visibility and our Wayland backend mapping at load, finishLaunching, and
activation. Explicit ordering must still work. Run each nib in a fresh process.

`python3 tests/nib-visible-native.py` compiles the production ordering block and
activation method with controlled Objective-C window/list objects and ASan/UBSan.
It tests mixed, empty, and absent visibility sets. It does not exercise real nib
decoding, awakeFromNib, or a compositor; the guest fixture is required for those.

## NIBArchive-format nibs

`nib-visible-fixtures.py` also writes `na-mixed`, `na-empty` and `na-missing`: the same three
windows in the NIBArchive layout that NSNibArchive.m converts (`nibfixture.write_nibarchive`,
specified by the header comment of NSNibArchive.m). `appkit-nibarchive-visible-windows.m`
converts one and checks the decoded `NSIBObjectData.visibleWindows`.

Guest results (Wayland backend, shm renderer, fresh prefixes, a8091e98 stage versus the
candidate): all 12 authored runs matched expectation. The conversion keeps NSVisibleWindows,
including an empty set, so the removed fallback is not needed for these nibs: `na-mixed` shows
exactly its Visible window in baseline and candidate, `na-empty`/`na-missing` show nothing only
in the candidate. The fixtures are authored from our own reader; a nib produced by Apple's
compiler was deliberately not inspected, so its exact set encoding is not verified.

VLC remains inconclusive: the window-list observer injected into it wrote no snapshot in any
run (gate_passed=false, cause not diagnosed), and its xdg_toplevel census varied between runs,
so these results make no claim about VLC's own launch-visible windows.
