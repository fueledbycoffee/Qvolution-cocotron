# PNG destination samples and completion

This original fixture supplies public `CGImageCreate` inputs to the destination.
Run each invocation with an explicit existing, private, empty output directory:

```
imageio-png-encode-contract vectors OUTPUT_DIRECTORY
python3 tests/check-png-encode.py HOST_OUTPUT_DIRECTORY
imageio-png-encode-contract draw OUTPUT_DIRECTORY
imageio-png-encode-contract short-write OUTPUT_DIRECTORY
imageio-png-encode-contract no-image OUTPUT_DIRECTORY
imageio-png-encode-contract repeated-image OUTPUT_DIRECTORY
imageio-png-encode-contract null-image OUTPUT_DIRECTORY
```

`vectors` attempts all 13 inputs independently. Program success means files were
emitted, not that their pixels are correct. The host checker independently reads
IHDR and uses Pillow to compare actual straight RGBA samples, including source
row padding, alpha 0/1/64/128/254/255, straight/premultiplied alpha, alpha-first/
last, skipped first/last samples, and explicit 32-bit byte order. Missing files
are reported separately from mismatched emitted files. `vector:CASE_NAME` isolates
one input. `draw` independently exercises each constructed image through a padded
public bitmap context and checks premultiplied pixels within one LSB and untouched
padding. It does not use the PNG encoder or decoder as its draw oracle.

`short-write` checks a real consumer returning fewer bytes than requested.
The three completion modes require false completion for zero supplied images, a
second supplied image, or a null image; absent images must emit no PNG bytes.
`depth16` requires successful public 16-bit RGB image construction before checking
the current encoder support boundary. A constructor failure is a separate missing
reader prerequisite, not a passing writer-rejection check.

## Before and verification boundaries

The coordinator's initial unmodified runtime emitted RGBA straight and RGBA
premultiplied before the third constructor rejected alpha-first/32-bit big endian.
The straight file passed the independent checker; the premultiplied file did not.
The public short consumer incorrectly finalized successfully. The depth16 control
failed at construction and never reached the writer. Those observations justify
the writer normalization/status correction; they do not prove that every packed
layout constructor or drawing path works. The revised all-case and drawing runs
remain separate before/after runtime gates. No native macOS encoder byte identity,
compression policy, ICC/profile metadata or 16-bit support is claimed.

The source adapter runs the actual C-only normalizer and fallback implementation,
extracted afresh from this checkout, using the vendored enum declarations:

```
python3 tests/onyx-png-encode-native.py SCRATCH_OUTPUT_DIRECTORY
```

It compares the canonical raw samples against the independent formula, compares
all 13 actual fallback PNG outputs using Pillow/IHDR, and runs malformed descriptor,
length, stride, unsupported flags/depth and allocation failures under ASan/UBSan.
All 39 allocation sites reached by the original 6x2 RGBA fallback workload are
individually failed, requiring no returned image and zero live tracked allocations.
LSan is disabled because the sandbox prevents its process inspection; allocation
balance is explicitly tracked, not reported as a LeakSanitizer result. This adapter
is not a synthetic public `CGImage` and does not qualify guest callback behavior.

## Source specification

The bitmap enums and image/provider interfaces are vendored in Onyx2D (rung 2).
PNG third edition section 6.2 specifies unassociated color samples:
https://www.w3.org/TR/png-3/#6AlphaRepresentation . The inverse-premultiply integer
rounding is existing project capture policy (`WaylandClientCapture.m`), not measured
native macOS quantization. The public destination completion result and the original
short-consumer observation (rung 4) require a genuine failed write to remain failed.

Both libpng and the existing fallback consume owned canonical RGB/RGBA rows. The
encoder explicitly rejects other depth/color models, floating/masked images and
unsupported bitmap flags before emission instead of silently labeling their bytes
8-bit RGB. These are current support boundaries, not invalid-input claims about
macOS or PNG. Add real typed implementations and focused tests to extend them.
