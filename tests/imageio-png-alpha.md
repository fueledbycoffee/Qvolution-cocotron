# PNG alpha contract regression

Original test inputs use Python stdlib PNG chunk/CRC/zlib encoding. No vendor icons, native screenshots or Apple binary data are used. Run:

```
python3 tests/png-alpha-vectors.py /path/to/vectors
# Build imageio-png-alpha.m linked with Foundation, ImageIO, CoreGraphics.
./imageio-png-alpha /path/to/vectors
```

The generator requires host Pillow, independently decodes every input, checks source straight samples, uses Pillow RGBa conversion to produce the premultiplied oracle, and uses Pillow alpha_composite over white to produce the compositing oracle. Both oracle outputs are also compared against direct integer math. Inputs have no color-management chunks. This is sample/alpha correctness, not a gamma/color-profile audit.

Four 5x2 cases exercise RGBA, opaque RGB, grayscale-alpha and palette+tRNS; alpha values are 0,1,64,128,255. Colors both below/above alpha distinguish multiplication from clamping. Duplicate rows remove image orientation as a confounder while still exercising stride. The guest consumes original PNGs plus independent raw expected bytes. It inspects the public CGImageSource image provider and premultiplied metadata, then draws through CGContextDrawImage over transparent and opaque white backgrounds into explicit big-endian RGBA and little-endian BGRA contexts with 28-byte padded rows. Provider comparisons are exact; raster/composite comparisons allow one LSB for existing renderer rounding. Padding must remain untouched. The producer/decoder cannot cancel each other's mistake: inputs are not made by the runtime PNG encoder, and expected outputs come from independent host Pillow.

## Source contract and scope

[W3C PNG Third Edition section6.2](https://www.w3.org/TR/png-3/#6AlphaRepresentation) specifies unassociated source color samples. In O2ImageSource_PNG.m both libpng and the fallback loader produce RGBA; the shared postdecode path advertises kO2ImageAlphaPremultipliedLast with kO2BitmapByteOrder32Big. O2ImageRead_RGBA8888_to_argb8u multiplies only the distinct straight kO2ImageAlphaLast mode; already-premultiplied images pass through. Consequently the PNG decoder must multiply once before publishing premultiplied provider bytes. The existing MIN(channel,alpha) operation is not that conversion.

This does not audit malformed-input bounds, decoder allocation arithmetic, legacy fallback thread safety, PNG gamma management, high sample depths, interlacing, all PNG color types or the independent encoder. No exact native Apple pixel equivalence is claimed.

## Measured baseline and candidate validation

Coordinator stage6 parent run: exit1 in1.6165s, exact-prefix shutdown0. Exact provider bytes and all RGBA/BGRA transparent/white draws fail for RGBA, grayscale-alpha and palette cases; opaque RGB controls pass. Raw local evidence: `logs/png-alpha-before.json` (not a public artifact). Candidate compilation and host vector generation pass; candidate guest results remain coordinator-owned and pending.
