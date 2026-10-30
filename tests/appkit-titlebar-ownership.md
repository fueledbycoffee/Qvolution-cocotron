# Title-bar ownership regression

`appkit-titlebar-ownership.m` exercises the real NSThemeFrame title reservation and NSWindow frame/content conversions. Qvolution builds it as `qvolution_titlebar_policy` when ENABLE_TESTS and QVOLUTION_BUILD_TEXTEDIT are enabled.

Run with an expected height of `0` on Wayland and `28` on the unchanged X11 theme path. Borderless windows must reserve zero; frame/content conversion must round-trip. This is layout-policy coverage, not a pixel or input test.

The pre-fix Wayland run connects to the compositor but fails with `AppKit title height 28.0, expected 0.0`. The original source-built TextEdit visibly draws duplicate title bars and the user supplied a screenshot confirming the duplication. Wayland already supplies either client-side or compositor-managed decorations, so AppKit must not allocate a second theme title bar.

Current x86_64 Foundation/Swift overlay loading requires a separate diagnostic override (`DYLD_FORCE_FLAT_NAMESPACE=1` with the existing `libswiftCoreCompat.dylib` inserted). Keep that limitation explicit: a passing layout check with those flags does not establish normal app loading or Swift ABI correctness.
