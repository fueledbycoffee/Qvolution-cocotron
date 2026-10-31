# Explicit raw float bitmap prerequisites

`storage.m` is an original fixture with modes external-le, external-be, internal,
span-le, span-be, reject, nil-surface and eight-bit. It uses existing named SDR RGB,
explicit 32-bit float premultiplied RGBA and 32Little/32Big ordering. BE bytes are
hand-packed binary32 values, not relabeled host floats. Partial raw spans use
nonzero x/y, negative/over1/-0/alpha0 values and row/output guards. Raw storage
acceptance does not promise those values are valid managed color/alpha inputs.

Before source changes, actual source-built Stage25 controls reported fake contexts
with nil backing, working float readers followed by nil writer surfaces, invalid
format acceptance, and a failed forced-nil constructor control. Actual typed
Stage26 nil-surface still failed. Four existing 8-bit controls showed two unchanged
premultiplied successes and two skipped-alpha bpp metadata failures; the latter are
an independent getter correction, not repaired by this storage change.

`format-source.py` executes the actual shared validator in a small native adapter
and checks strict packing and signed-reader/storage bounds under ASan/UBSan:

```
ASAN_OPTIONS=detect_leaks=0 python3 tests/float-bitmap/format-source.py /absolute/external/output
```

The native adapter substitutes only the color-space model lookup. It does not test
Objective-C construction, provider ownership, drawing or guest behavior. Guest
storage fixture requires Foundation/CoreFoundation/CoreGraphics/Onyx2D and the
project's Darwin toolchain/runtime harness. Compile with
`-Werror=objc-method-access` so the declared bitmap initializer is used correctly.

Supported float storage is deliberately limited to the implemented explicit RGBA
layout and signed int reader coordinate/total-byte bounds. No new float alpha-first,
straight alpha, default/16-bit ordering, integer32, decode-array or callback-lifetime
contract is selected. Existing byte formats retain their dispatch behavior.
Construction now returns NULL when its surface/writer is unavailable; a getter
workaround is not success. Superclass nil propagation is maintained in builtin
and Windows GDI (the Windows edit is source-reviewed, not compiled on Linux).

Working storage must be paired with separately reviewed raw float drawing dispatch
before runtime integration. Full profile conversion, HLG, export formats, GPU and
actual display behavior are independent requirements. Existing superclass gstate
allocation weaknesses remain open; this is not exhaustive allocation-fault proof.
