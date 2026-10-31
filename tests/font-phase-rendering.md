# Explicit unquantized glyph positioning

The original CPU CGContext diagnostic established that requests at1x quarter/
half-pixel origins and2x quarter-point origins produced identical masks and
zero centroid movement. Integer controls passed. This correction rasterizes
scalable outlines at the requested FreeType26.6 phase rather than truncating
origins or filtering an already rasterized mask.

Official parameter contracts:

- [Should position](https://developer.apple.com/documentation/coregraphics/cgcontext/setshouldsubpixelpositionfonts%28_%3A%29): permits nonintegral placement when enabled, belongs to graphics state.
- [Allows positioning](https://developer.apple.com/documentation/coregraphics/cgcontext/setallowsfontsubpixelpositioning%28_%3A%29): context permission, requires enabled antialiased drawing, not saved graphics state.
- [Should quantize](https://developer.apple.com/documentation/coregraphics/cgcontext/setshouldsubpixelquantizefonts%28_%3A%29): may quantize subpixel positions when enabled, belongs to graphics state.
- [Allows quantization](https://developer.apple.com/documentation/coregraphics/cgcontext/setallowsfontsubpixelquantization%28_%3A%29): context permission, used only with enabled quantization, not saved graphics state.

Those pages and the vendored headers do not establish native defaults or a
numeric quantization grid. Preserve existing Cocotron zero defaults. Implement
the explicit allowed+enabled positioning path when both antialiasing flags permit
antialiased drawing and quantization is not both
allowed and requested. Quantization-enabled placement retains the previous
integral behavior pending a separate implementation; no quarter-pixel policy
or native compatibility claim is invented. Rendering remains grayscale, with
existing FT hinting and AA behavior. No global AppKit opt-in or default change.

The should flags now live in copied O2GState; allows flags remain on context.
Positive device-space phases use floor anchors and nearest1/64pixel FT deltas;
y deltas are negated for FreeType's upward axis. Cache keys pack size26.6,
16-bit glyph and6-bit x/y phases into60bits. Existing512entry limit remains.
Custom FT transforms bypass the phase cache; their matrix/delta are restored
on success and errors. Legacy/default and phase0 retain the old cached raster
method and mask. Non-scalable bitmap strikes retain legacy integral behavior.
Fractional scalable draws load outlines with FT_LOAD_NO_BITMAP; integer draws
can still use embedded strikes to preserve their previous output. Fonts with
embedded strikes may therefore vary in shape across phase0/fractional paths;
this is a stated compatibility boundary, not a complete bitmap phase feature.

Guest tests (coordinator owns runtime/prefix slot):

- `coregraphics-font-fractional-origin.m`: unchanged original diagnostic.
- `coregraphics-font-phase-flags.m`: CoreGraphics/Foundation/FreeType, explicit
  DejaVuSans.ttf argument. X/y shifts, negative user positions, integer/default
  equality, positioning permission/request, quantization permission, save/
  restore and cache revisits. Link includes `font-phase-probe.h` locally.
- `freetype-font-phase-cache.m`: Onyx2D/Foundation/FreeType. Explicit
  DejaVuSans.ttf and original open PCF bitmap paths. Success/failure/overflow
  FT transform preservation, phase and size keys,512entry bounds/eviction,
  phase0 reuse and bitmap compatibility.
- `coregraphics-font-phase-throughput.m`: same deps/file as public flags test.
  Measures10000glyph draws after128warmup draws for default integer, enabled
  integer,4phase and64phase requests. Report before/after absolute timings;
  no flaky speed threshold and no claimed full-app benchmark.
- `appkit-backing-scale-observation.m`: AppKit/CoreGraphics; maps a generated
  small probe window for2seconds so compositor scale events can settle.
  Compares NSWindow.backingScaleFactor, convertRectToBacking and actual
  CGContext device basis lengths, reports generated bitmap extent only.
  It does not publish host display names, resolution inventory or identifiers.
  It measures its own mapped window, not the user's TextEdit window or every
  monitor/fractional scale configuration.

Native lightweight check: `python3 tests/font-phase-origin-split.py` extracts
and executes the actual coordinate helper. Checks signed floor/carry cases,
precision bounds over200001coordinates per model and invalid/out-of-range rejection.
The extracted helper runs with explicit int64/double, int32/double and
int32/float models under undefined-behavior sanitization. Actual bitmap bearing
add/subtract and right/bottom extents are checked; fully clipped rectangles
are rejected before subtracting their intersection bounds.

All fonts are explicit open DejaVu/PCF files. No Apple artifacts, screenshots
or pixel snapshots provide an oracle. Placement/scale checks do not establish
the cause of perceived TextEdit pixelation or prove it fixed.
