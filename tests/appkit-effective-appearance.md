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
effective object changes; explicit branches are protected. Private app-change
notifications cover detached roots and private windows omitted from NSApp.windows.
Observers are removed during teardown. Lifecycle parent/window mutations compare
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
