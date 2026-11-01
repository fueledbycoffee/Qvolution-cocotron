Provenance (AGENTS.md section 1):
- Rung 3, Apple's Quartz 2D Programming Guide, Color and Color Spaces / Setting
  the Alpha Value, is the documented contract: CGContextSetAlpha scales the
  alpha of subsequent drawing. The author did NOT read that page (no network
  access; the lane brief only named it), so this is the brief's statement of
  it.
- Rung 2: vendored CoreGraphics CGContext.h and the Onyx2D paint/span headers.
- GUESS (rung 6), not specified by anything read here:
  - alpha outside [0, 1] is clamped and NaN counts as 0;
  - the transparency-layer shadow is composited through the image path, so the
    current alpha also scales it;
  - for blend modes other than Normal alpha scales the source before the blend
    function runs;
  - a path filled and stroked in one operation applies alpha per painted
    object, not per group.
- Observed, not specified: fractional-alpha images now round to the nearest
  byte where the old image path truncated the byte alpha.

`python3 tests/global-alpha-native.py` runs real production Objective-C paint
allocation/ownership, paint spans, shared setup admission, and shading math on
Linux, with a minimal NSObject and image sampling/storage adapters. It checks
RGB/gray fill, stroke/glyph admission, pattern, image interpolation branches and
masks, layers' image path, axial/radial skipped spans, exact alpha-one identity,
opacity/copy selection, float-only paints, and repeated setup. It is not guest
API dispatch, tessellation, real image sampling or font raster integration.
`--baseline-rev REV` compiles the same assertions against the Onyx2D sources of a
git revision (paints, shared setup, image and FreeType call sites, state setter),
so the pre-fix behaviour is run, not matched as text. The expected values are an
independent product of the pre-wrapper span and the clamped alpha. The complete
shared setup runs, including the 8u/float choice after the blend switch in
plain, clip, viewport, read-only-surface and layer environments.

`coregraphics-global-alpha.m` is the complementary public API fixture for the
container host: 12 drawing paths, byte/float output, no/integral/antialiased-path clip, alpha
0/.35/.9995/1 plus out-of-range 2/-1/NaN (clamped to [0,1], NaN as 0; GUESS), exact alpha-one bytes, nonempty ink, and padded-row guards. Guest
runner also retains the unchanged Stage41b 71 fixtures and decoration-cache
fixture, and reruns P4 controls on P4 AppKit plus the candidate Onyx2D.
