# Genuine bitmap/image object graph archive workflows

The fixture uses original pixels, real NSImage/NSBitmapImageRep objects and public
Foundation archive APIs. It consumes no vendor assets, Apple archives or guessed
native archive keys. Project image/bitmap envelopes are explicitly Qvolution
formats; native NIB/archive compatibility and NSSecureCoding remain open.

The complete mode list is `appkit-image-raw-coding-modes.json`. Run every mode with
an isolated prefix and the coordinator's known staged runtime. Program examples:

```
appkit-image-raw-coding keyed
appkit-image-raw-coding unkeyed
appkit-image-raw-coding shared-keyed
appkit-image-raw-coding shared-unkeyed
appkit-image-raw-coding standalone-keyed
appkit-image-raw-coding standalone-unkeyed
appkit-image-raw-coding decoded-copy-keyed
appkit-image-raw-coding decoded-copy-unkeyed
appkit-image-raw-coding live-state-keyed
appkit-image-raw-coding live-state-unkeyed
appkit-image-raw-coding legacy-bitmap
```

## Actual archive and lifetime checks

Plane workflows first prove the selected real Foundation archive preserves a
small data/container control. Five actual representations cover RGB and straight/
premultiplied first/last RGBA, nonzero RGB at straight alpha0, row padding,
representation sizes and all supported image scalars. Every original byte must
survive source/archive destruction and pool drainage. Derived versus explicit
image size is checked by later changing a representation's point size.

CG workflows preserve all provider bytes, including thirteen original canaries
beyond the pixel extent, and check layout/interpolation/rendering intent and
independent image/representation sizes. Dual workflows first materialize and
change a component plane while retaining different CG backing bytes; both must
survive. No PNG/TIFF conversion flattens that distinction. General materialization,
render/color fidelity and unsupported pixel formats remain separate work.

Decoded-copy modes directly copy an actual decoded NSBitmapImageRep for plane,
CG and dual storage, in both release orders, after source/archive pool drainage.
They prove independent plane/property mutation and surviving CG provider bytes.
NSImage.copy, which only retains representations, is not used as that proof.

Shared-graph modes archive an array containing two images, duplicate/cross-image
references to one bitmap, that standalone bitmap, and a shared mutable metadata
child. Decoded references must identify one decoded bitmap, and its mutations
must propagate through all decoded references while leaving source pixels intact.
Mutable dictionary/array classes, repeated metadata children and their reference
from the outer graph must survive and remain usable. This verifies actual
Foundation identity/mutability behavior; it is not inferred from a raw-record
comparison. Standalone modes also require real NSCoding conformance and a real
bitmap layout/content roundtrip.

Name modes preserve name metadata without replacing the original shared named
image. Empty modes preserve an intentional empty NSImage and point size; they do
not qualify populated coding. Properties modes require the real public bitmap
setter/getter before verifying nested decoded metadata independent of source
mutation. The generic bitmap ownership prerequisite supplies that setter.

## Explicit rejection and allocation checks

Recording NSCoder fixtures count graph writes. Delegates/background/custom or
unknown image/bitmap subclasses must reject before writing anything, including
an unsupported representation after supported ones. These recording coders are
not populated roundtrip or Foundation identity proof.

Malformed modes first require genuine image and standalone bitmap writer
schemas, then mutate versions, dimensions/products/stride/data/format/types and
cyclic metadata. Image wrapper class/state checks and bitmap raw-record parsing
are exercised separately. Live-state modes supply actual exact-class gray,
planar, empty and nonfinite-size bitmaps through a recording coder and require
explicit rejection without reconstructing them. Unknown image/bitmap receiver
subclasses must reject project dictionaries as well.

Allocation-failure modes use original NSString/NSData/dictionary field subclasses
with controlled nil copy results and positive type/content controls. Scalar
name/accessibility, bitmap color-space/dictionary ownership and CG provider
ownership must fail explicitly rather than returning populated objects with lost
metadata or bytes. These tests supplement source transaction review; they do not
inject every internal Foundation allocation or establish SecureCoding.

`legacy-bitmap` uses an original NSCoder transport selecting the unchanged own
version17+ DataObject branch, with a real generated PNG input. Its decodeObject
method throws if called, so the new project branch cannot accidentally consume
the legacy first datum. This is a regression for an existing own-source branch,
not a claim about native Mac archive schemas/version numbers.

## Typed model and graph preservation

A project NSImage dictionary carries tag `QvolutionNSImage`, schema1, its actual
ordered bitmap objects, raw image size, name/accessibility strings, alignment/
custom flag, insets, cache/resizing modes and nine logical boolean flags. Keyed
coding uses `QvolutionNSImageArchive`; unkeyed coding writes that tagged dictionary
as its first object. Existing keyed TIFF and version17+ name-first image legacy
branches remain separate.

NSBitmapImageRep now implements genuine NSCoding using project key
`QvolutionNSBitmapImageRepArchive`, tag `QvolutionBitmap`, schema1. Its previously
unsupported unkeyed version<17 branch recognizes the explicit project dictionary;
the existing version17+ NSImageRep DataObject branch is preserved. No native class
version is assigned or guessed. The allocated bitmap initializes itself rather
than substituting new representation objects, preserving unarchiver identities.

Bitmap records retain raw packed8 RGB/RGBX/RGBA descriptor, point size, opacity,
properties and storage `plane`, `cg` or `both`. Component plane bytes and complete
CG provider bytes remain distinct and decoded storage owns its data. A common
extent/layout validator checks both serialized records and live bitmap state.
Live validation is read-only: it never rebuilds representation objects, so image
decoding preserves the relationships Foundation already decoded. A retained CG
provider snapshot can be transferred to the encoder record; otherwise validation
releases it. Metadata is iteratively checked for cycles, string keys and valid
property-list leaves, then ordinary Foundation child objects are encoded. The
outer property dictionary is separately owned; children are not frozen/deep-
serialized by a private graph codec.

This follows Apple's archive identity/relationship contract:
https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Archiving/Articles/objectgraphs.html
Validation follows actual integer ABI/product limits and available data lengths,
not an arbitrary small image cap. Dynamic background/delegate/symbol/unknown/
planar/vector state and broader depths/models remain explicit unsupported work.
CG-backed coding requires the own Darling image mask-state check; the non-Darling
path rejects this model until lossless inspection exists. Successful source/native
checks are not guest, native archive, GPU, app workflow or UI qualification.

Unkeyed bitmap version boundary: project records require archived NSImageRep
version below17, including own current default0. The version17+ DataObject reader
remains untouched. Both bitmap writing and NSImage's representation preflight
now explicitly reject an unkeyed coder reporting version17 or above before any
project graph writes. This avoids creating records the preserved reader cannot
consume. Keyed coding does not use this legacy branch.

The separate `version-guard` mode temporarily sets the actual NSImageRep class
version to17 and restores it in @finally. It checks bitmap/image recording coders
write nothing, actual NSArchiver refuses with NSInvalidArchiveOperationException,
and real keyed coding still returns an object. The keyed object fidelity gates
are the existing30-mode matrix; this control establishes version dispatch only.
No native class version is assigned in production or inferred from this test.
The original30-mode fixture binary/source are preserved with .frozen30 suffixes
for root's already-started baseline. The new fixture has31 modes.

## Recorded before evidence

Root ran the unchanged frozen30 fixture against Stage26 before integrating this
codec: properties-control and legacy-bitmap passed;26 modes exited1; unkeyed and
derive-unkeyed exited139. All shutdowns exited0. The new version-guard mode then
exited1 with shutdown0. Several malformed/live-state/allocation modes stop at the
missing writer prerequisite: these failures do not prove their later decoder or
cleanup assertions were reached. Root preserves inputs and summaries in
parallel/root-probes/codec-before-stage26 and per-mode
logs/image-codec-before-stage26-*.json. No runtime after result is claimed here.
