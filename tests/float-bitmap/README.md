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

## Raw float drawing and byte consumers

`draw-source.py`, `sampler-source.py`, and `g1-source.py` execute the current
production functions through small native memory adapters. They compile with
ASan/UBSan (including float-to-integer overflow for sampling) and use temporary
output directories. Run from the component root:

```
ASAN_OPTIONS=detect_leaks=0 python3 tests/float-bitmap/draw-source.py
ASAN_OPTIONS=detect_leaks=0 python3 tests/float-bitmap/sampler-source.py
ASAN_OPTIONS=detect_leaks=0 python3 tests/float-bitmap/g1-source.py
```

These cover bounded float raster/text spans, source-over against nonzero pixels,
nonuniform internal clip alpha multiplied by glyph coverage, viewport edges,
positive/negative bitmap pitch, skipped paint spans, row padding, distinct source
and mask transforms, nearest/bilinear edges, real repeating pattern samples,
300-pixel alpha spans, finite/nonfinite byte mapping, and partial one-bit reads
across byte boundaries. They establish arithmetic and memory behavior of the
extracted production functions; Objective-C dispatch, actual fonts, runtime
ownership, allocation fault injection, and display output require separate tests.
Leak detection is disabled because this host's ptrace environment prevents LSan.

The following original runtime fixtures require the actual Darwin runtime and
Foundation/CoreFoundation/CoreGraphics/Onyx2D:

- `drawing.m`: solid, blend, image, text.
- `image-masks.m`: alpha, nearest, bilinear.
- `consumer-export.m`: copy, jpeg, tiff, png, pdf, nested, bitmask, stencil,
  shortwrite, reject. `copy` tests both explicit byte orders, row padding, more
  than256 pixels, and independent rounded byte values. Export compares float
  images to independently packed byte images with zero/fractional/opaque alpha.
  PDF also checks independent RGB/alpha stream bytes and unequal2:3 mask mapping.
  Reject controls cover malformed backing/rows and a valid-backed cyclic graph.
  Short-write controls check failure propagation and consumer ownership after
  failed finalization and release without finalization.
- `text-clip.m`: no arguments. An original subclass injects a real float clip
  surface, then checks every actual open-font glyph pixel against independent
  glyph-coverage times clip-alpha times source-over equations. This explicitly
  does not test production construction of a public path/mask clip.

Runtime results must be recorded against the exact source/runtime manifest.
The repository's separately reviewed stored-bpp getter correction is a runtime
prerequisite for `drawing.m`. Do not count native adapters or successful fixture
compilation as runtime passes.

Float export uses the existing bitmap-surface component mapping: rounded,
saturated eight-bit premultiplied RGBA, with the same color-space metadata and
without a color/transfer transform. JPEG retains the existing byte encoder's
black-composite behavior when alpha is discarded; TIFF retains associated alpha;
PNG applies its existing unassociation; PDF emits unassociated RGB plus an actual
gray soft-mask stream. Internal RGB masks use the image-paint red-channel
convention, sampled at pixel centers; nested PDF mask coverage shares the original
normalized image position. Public clip masks are a separate path with inverse image-mask coverage and stored decode pairs; encoded-image mask/decode compatibility remains unqualified.
The complete source/mask graph is checked for cycles, row capacity, and signed
reader bounds before destination count or PDF resources change. Destination
counts advance only on encoder success. Short writes report failure; already
written external bytes cannot be rolled back. TIFF row/strip allocations are
checked heap allocations. JPEG's existing default fatal codec error handler is
not an allocation-fault recovery guarantee.

Public clipping now rasterizes actual saved nonzero/evenodd path phases with the
existing edge rasterizer. Path clips and drawing geometry share256 samples per
pixel; path intersections use sample-bit AND before averaging, preserving repeated
clips and clip(P);fill(P) edges. Scalar gray masks multiply separately. Clip phases
freeze their antialias policy and mask CTM. Save/restore/reset rebuild from phases.
Layer drawing uses conditional coverage within inherited path samples, while the
parent applies that domain and inherited soft masks once at final composition.
Nested layers and locally reset clip phases retain phase identity rather than
relying on an absolute phase count.

Clip masks support existing constructible one-bit/eight-bit DeviceGray images with
no alpha or attached mask, and true image masks. Image masks use1-S, ordinary gray
images useS, after their decode pair. Derived forward/inverse mappings and source/
destination corners are checked before image sampling. Unsupported or invalid clip
masks produce an empty clip. Existing two/four-bit image construction remains
unsupported; named grayscale/profile conversion is not established by this path.

Public runtime controls (no injected clip surface):

- `public-clipping.m`: triangle, nonzero, evenodd, mask, image-mask, decode,
  transform, accumulate, restore, reset, image, layer, nested-layer, text. Each
  runs Copy and SourceOver on a nonzero float destination; optional `byte` argument
  repeats with a padded byte destination. Every pixel has an independent area/
  sample/glyph and premultiplied equation oracle.
- `public-clipping-geometry.m`: repeated, overlap, same-fill, opposite-fill,
  layer-reset, aa-state. Independent polygon intersection areas and immutable clip
  policy checks; both blend modes.
- Prefer `public-clipping-layer-geometry-v4.m`: layer-same, nested-layer-same,
  layer-overlap, layer-opposite. Inherited/local path edges and group Copy versus
  SourceOver are checked against independent polygon areas. The frozen prior
  `public-clipping-layer-geometry.m` is preserved but its layer-overlap setup clips
  the second path before the layer and has an invalid Copy oracle; do not count
  that mode as valid evidence. V4 removes that pre-layer clip without changing
  tolerances.

Native source checks, each with float and LP64 double O2Float adapters:

```
python3 tests/float-bitmap/raster-samples-source.py
python3 tests/float-bitmap/public-clip-source.py
python3 tests/float-bitmap/public-clip-transform-source.py
```

These execute actual sampling/raster/intersection/layer-domain/normalization and
transform guards with ASan/UBSan/float-cast-overflow. Native adapters do not prove
Objective-C phase/CTM ownership, dispatch, actual layers/fonts or public runtime
behavior. Fixtures are frozen before the corresponding implementation and linked
against a recorded unchanged-runtime manifest; root must run genuine before and
exact committed candidate controls. No candidate public runtime pass is claimed
by compilation or these native checks.

The layer and drawing surfaces retain per-pixel premultiplied color; this is not a
fully multisampled color pipeline or native Quartz antialiasing equivalence.
Extended-range solid paints, managed profile/HLG transforms, standalone eight-bit
PDF stencils, native GDI float text, GPU composition, and display/app qualification
remain separate. The enabled FreeType path consumes the public clip coverage.
