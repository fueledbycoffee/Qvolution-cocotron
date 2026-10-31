# Title visibility raster regression

Original Qvolution fixture; no Apple assets or application resources. Public titleVisibility behavior is documented at https://developer.apple.com/documentation/appkit/nswindow/titlevisibility-swift.property (clean-room rung 3).

Run appkit-title-visibility with no arguments. It creates its own window and invokes its actual NSThemeFrame title drawing entry point into RGBA bitmaps; the toolbar label uses actual NSToolbarItem drawing. An empty-title raster is the independent no-title control. Visible-Hidden-Visible, preserved General metadata/label pixels, dynamic title updates and frame invalidation are checked. No method interposition or substitute renderer.

Root's stage18 baseline: title-visibility-before.json, exit1 in1.851914972s, exact shutdown0. Visible title235pixels, toolbar244pixels controls pass; Hidden still235pixels. Four failures: title hiding, both visibility setter invalidations and title setter invalidation. Toolbar and metadata checks pass. Candidate runtime pending coordinator integration.

This is a source-renderer pixel and invalidation test, not native displayed-window delivery, Keka title-intent proof or unified-toolbar layout qualification. It preserves traffic-light/titlebar geometry and toolbar-label policy. Root owns full runtime tests.
