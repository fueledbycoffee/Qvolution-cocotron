# Fractional glyph-origin diagnostic

This original regression renders one `f` from an explicit DejaVu Sans regular
file into a CPU RGBA bitmap through public CGContext calls. It performs no
window or AppKit operations. The same file bytes are validated through FreeType
and passed to CGFontCreateWithDataProvider: no family-name lookup or fallback.
Any other PostScript/family identity is rejected. Input font data must be an
original open DejaVu font, not an Apple font or copied proprietary artifact.

Link `coregraphics-font-fractional-origin.m` with Foundation, CoreGraphics and
FreeType. Supply the exact font file path; on a Darling prefix the host file is
usually `/Volumes/SystemRoot/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf`.
The tested host file SHA256 is
`b4c632e3cdf9acc7f28758fb5a323c8524d7fc6660d46904d9b6cbe2809c419c`.

At scales1 and2, request x origins10.0,10.25,10.5 and11.0. Enable font subpixel
positioning and disable its quantization. For each origin report alpha-weighted
centroid movement, number of changed pixels and total coverage ratio. The
expected x shift is `(origin - 10) * scale`, independently of any Apple image.
Tolerance0.15device pixels accommodates sampling/hinting coverage changes;
y-centroid tolerance0.05 catches unexpected baseline movement. Integer-origin
cases serve as controls and should preserve exactly translated masks. All six
translated cases are reported before failure. This tests x placement, not a
complete text quality/rotation/vertical/subpixel-AA contract.

The independent native FreeType reference verifies that the chosen glyph and
font meet the centroid tolerance when the requested fractional origin is
actually supplied to the rasterizer:

```sh
cc -O2 tests/freetype-fractional-origin-reference.c $(pkg-config --cflags --libs freetype2) -lm -o /path/to/scratch/fractional-origin-reference
/path/to/scratch/fractional-origin-reference /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf
```

Native reference results: at1x, requested0.25/0.5pixel shifts yielded0.221579 and
0.461414pixel centroids; at2x, requested0.5pixel shift yielded0.497085. All
integer controls matched exactly. This reference is neither an implementation
patch nor a pixel snapshot oracle.

Current source finding: O2Context_builtin_FT.showGlyphs computes floating point
text origins, but renderFreeTypeBitmap accepts NSInteger x/y. Calls implicitly
truncate before compositing. Glyph cache lookup uses point size+glyph only, and
rasterizeGlyph does not submit an FT_Set_Transform fractional delta. Public
subpixel positioning flags are stored but not consulted by this drawing path.
Thus the source predicts identical masks for fractional translations within an
integer device-pixel bin. The guest fixture must measure that prediction before
any raster change is proposed. No screenshot cause or pixelation fix is claimed.
