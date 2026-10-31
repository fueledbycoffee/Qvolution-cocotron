# Compact inspector font-family popup

Build `appkit-compact-font-picker.m` with AppKit and the component-private headers, then run its four modes in an isolated guest prefix:

```
appkit-compact-font-picker geometry
appkit-compact-font-picker configured
appkit-compact-font-picker inspector
appkit-compact-font-picker cell
```

The original fixture is before-capable. Missing new private preference selectors are treated as the old unbounded policy, allowing actual production popup sizing to run and fail the compact-height assertion on a 400-item menu. The failure is not merely absence of a new method. The inspector mode checks the real rich-text bar's family request, complete installed family catalog, default size policy, and real family action on selected text. The cell mode executes the actual cell-created popup path, intercepting only tracking/order/bounds for a deterministic result; it verifies the propagated preference and last-item selection.

Geometry controls retain all400 entries, compare the popup height with the first16 actual cached row rectangles plus real borders, test first/middle/last selection, negative/nonzero-origin screens, smaller native caps, wheel scrolling, keyboard/type-ahead last-row reachability and unchanged generic/short menus. Configured mode exercises the actual own frame-changed callback for shrink and enlargement: the outer frame follows the supplied configuration, while the opt-in viewport stays no taller than its preferred extent and available content, remains at the content top, and reveals the selection. This does not claim the physical outer frame stays16 rows if a compositor explicitly imposes a larger one.

Zero means existing generic geometry. The inspector family control opts into16 as explicit Qvolution UX policy; font size and other popup controls remain unbounded by this preference. This preference is private project state, copied with the cell, and is not a native Cocoa method/constant or guessed archive key. For heterogeneous opted-in menus the preferred extent comes from their first requested rows; it is not a universal row-count guarantee when subsequent item heights differ. No family filtering or catalog truncation occurs.

Retain and run the existing `appkit-popup-viewport`, `appkit-popup-parent-output`, `appkit-popup-configured-viewport` and `appkit-popup-hit-throughput` regressions. This fixture avoids a modal wait by overriding own tracking and window ordering. Actual pointer delivery, Return/Escape/outside-click dismissal, compositor placement, menu latency and visual polish need separate interactive acceptance; direct method calls do not qualify those behaviors.

Provenance: existing own cell/inspector/window/view source and geometry APIs (rung2), original regression and user-observed oversized list (rung4), explicit16-row project preference (rung6). No Apple implementation or binary internals used.

The coordinator's actual stage23 baseline reached all four modes with clean prefix shutdowns: geometry failed6 compact-height checks (840/900 actual versus326 points from16 cached rows); configured failed1 enlarged-content check; inspector failed1 preference check while its real family action passed; cell failed1 compact-height transfer check while last-index399 selection and all400 entries passed. After-runtime verification remains required; successful compilation and source review alone do not establish the fixed UI behavior.
