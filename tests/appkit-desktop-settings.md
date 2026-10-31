# Portal settings and P1 palette

This is an original Qvolution implementation. The supplied
`parallel/visual-theme/SPEC.md` §§2, 3, 8 defines the design tokens and acceptance
colors. None are sampled Apple colors. The public interfaces are declared in
`AppKit/include/AppKit/{NSColor,NSAppearance,NSApplication}.h` (clean-room rung 2).
The wire contract is the freedesktop public Settings v2 interface:
`ReadAll(as) -> a{sa{sv}}`, `SettingChanged(ssv)`, appearance `u` preferences,
and an sRGB `(ddd)` accent. GNOME interface settings are the forwarded public
`font-name`, `text-scaling-factor`, and `overlay-scrolling` keys.

Native command, from the workspace root:

```
dashboard/qv-slot build python3 parallel/theme-p1/cocotron/tests/appkit-desktop-settings-native.py
```

It uses in-process libdbus message objects as a fake portal, with the production
ReadAll builder, decoder, palette, appearance precedence and actual socket-drain
method. Only the Cocoa receiver and socket queue are shims. It exercises -O0 and
-O2 with ASan/UBSan. It proves one callback produces one change transaction, but
does not claim to exercise CF's socket readiness or the actual NSApplication
notification implementation. The guest fixture checks those boundaries.

The guest fixture runs through a private dbus-run-session with
`appkit-desktop-settings-portal.py`. It renders the text-selection token and the
actual menu/default-button renderer into CPU `O2Surface`s at 1x and 2x, checking
center pixels within ±2/255. The fake portal starts dark/pink, and the app must
remain Aqua because the dark gate defaults off. A blue signal must update a
retained color and post exactly one NSSystemColorsDidChangeNotification. The
runner repeats this on three fresh prefixes and includes a no-portal control:

```
parallel/theme-p1/run-guest-fixtures.sh
parallel/theme-p1/run-textedit.sh
```

The TextEdit check is manual and has no timeout: select the supplied sample text,
open a menu, check a default button and save a desktop screenshot before quitting.
The raster fixture checks the text selection **fill token**, not NSTextView's
layout and painting. TextEdit is the visual integration check for that consumer.
No container or desktop check is asserted as passed by native-only execution.

No provider cache exists in NSColor_dynamic. Retained catalog providers read the
latest singleton state at each resolution. Explicit app/window/view appearances
keep their existing precedence. `QvolutionFollowSystemAppearance` defaults NO;
it gates automatic dark, including the test environment override. High contrast
still works in Aqua. An app's Info.plist Aqua opt-out wins over portal/override.
Unavailable bus/portal uses the light design defaults and #0A7AFF accent;
out-of-range or non-finite accents also use #0A7AFF. Disconnection retains the
last valid snapshot, removes the socket source, and performs no live updates.

The on-accent algorithm uses the specified >=3:1 white contrast rule. The spec's
unverified named yellow #C88800 has white contrast 3.00966:1, so the normative
algorithm selects white there; bright #FFFF00 selects black at 85%. This follows
the algorithm rather than treating every named yellow as a special case.

AppleInterfaceStyle and AppleInterfaceThemeChangedNotification are deliberately
GUESS-grade compatibility conventions from the supplied spec, not public AppKit
API. P4 owns default-button gradients, pressed/disabled polish and bezel geometry;
P1 changes its active fill/text to accent/on-accent without introducing P4 shapes.
