# Effective appearance inheritance

Primary contracts:

- https://developer.apple.com/documentation/appkit/nsappearance
- https://developer.apple.com/documentation/appkit/choosing-a-specific-appearance-for-your-macos-app

Explicit view appearances override ancestors; otherwise a view inherits its
nearest superview/window, then the app. The app's existing Aqua default is
preserved. A detached view without an application keeps the existing current-
appearance fallback, including the manual block fixture. No system preference,
portal, palette or global dark override is introduced.

Setters compare effective appearance object identity. Inheriting descendants
receive viewDidChangeEffectiveAppearance and drawing invalidation only when that
effective object changes; explicit branches are protected. A weak identity registry covers detached roots and private windows omitted from
NSApp.windows. Its complete allObjects snapshot strongly holds every recipient
through dispatch; callbacks run outside the registry monitor. Entries are removed
during teardown. Nested app/view changes supersede stale propagation using
generation checks, avoiding repeated callbacks for the latest appearance. Lifecycle parent/window mutations compare
before/after appearances; notification granularity follows those existing mutation
steps, without claiming exact native reparenting callback counts. AppearanceSource,
KVO dependencies for effectiveAppearance, archiving and system-change observation
are separate work.

Build/run `appkit-effective-appearance-inheritance.m` with AppKit. It checks app,
window and nearest-view overrides, repeated/cleared setters, dirty state and
callback counts, detached roots and private windows. This is source-built API
coverage; no screenshot or proprietary asset provides the expected output.

The original parent fixture fails detached-root app inheritance. Candidate runtime
results must be recorded independently; compilation alone is not a pass.

## Automatic view drawing scope and focus cleanup

`appkit-view-drawing-appearance.m` exercises actual displayRectIgnoringOpacity
and production focus machinery routed to its own CPU bitmap. It does not invoke
an appearance-scope helper manually. Dynamic providers return known red/blue
colors for light/dark, and the test checks actual pixel bytes and observed
provider appearance. Nested explicit light and dark views must restore the
parent scope. A real CALayer marker exercises updateLayer dispatch without a
native window or GPU context. Modes are --draw, --layer, --throw and --setup-throw.
Deliberate draw/setup exceptions must restore context, focus and thread appearance.

The first parent runs of all four modes failed earlier at nil context restoration,
so they are not provider-pixel mismatch evidence. Separate public regression
`appkit-graphics-context-nil-state.m` covers nil/non-nil context saves, nested
CGContext state, repeated nil saves and unchanged empty-stack restoration.
Candidate pixel/scope/exception results must be recorded after that prerequisite.

The implementation scopes automatic view drawing, including setUpGState, drawRect
and updateLayer, using the existing thread-local appearance block. It does not
change palettes, claim native macOS pixels, add global system appearance policy,
or qualify arbitrary manual lockFocus/drawing outside the automatic display path.

## Broadcast ownership and reentry

`appkit-appearance-observer-lifetime.m` directly releases another detached
recipient's last owner during a callback. It checks safe complete dispatch,
subsequent deallocation and registration by identity for distinct equal-valued
views. It deliberately does not rely on ordinary removeFromSuperview, which
retains/autoreleases the removed view. `appkit-appearance-reentrancy.m` checks
that nested view/app setters reach the latest value without stale duplicate
callbacks. Link both fixtures with AppKit.

Appearance mutation and propagation follow AppKit's UI-thread assumption. Registry
registration/snapshot/removal are monitored, and no registry monitor is held while
calling user code. This is not a general concurrent NSView property guarantee.
The AppKit-owned snapshot avoids depending on generic selector-notification
recipient lifetime. Foundation notification semantics are not changed or claimed
fixed by this work; a separate source-level known-issue record is handed to root.
