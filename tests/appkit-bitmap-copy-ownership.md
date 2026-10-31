# Real bitmap copy and metadata ownership prerequisite

This fixture copies actual NSBitmapImageRep objects through `copy`, not NSImage
(which only retains its representations) and not an archive-format shortcut.
Run modes with an isolated prefix and the coordinator's known staged runtime:

```
appkit-bitmap-copy-ownership owned-source-first
appkit-bitmap-copy-ownership owned-copy-first
appkit-bitmap-copy-ownership borrowed-source-first
appkit-bitmap-copy-ownership borrowed-copy-first
appkit-bitmap-copy-ownership cg-source-first
appkit-bitmap-copy-ownership cg-copy-first
appkit-bitmap-copy-ownership dual-source-first
appkit-bitmap-copy-ownership dual-copy-first
appkit-bitmap-copy-ownership properties
appkit-bitmap-copy-ownership property-copy-source-first
appkit-bitmap-copy-ownership property-copy-copy-first
appkit-bitmap-copy-ownership empty
appkit-bitmap-copy-ownership invalid
appkit-bitmap-copy-ownership color-space
appkit-bitmap-copy-ownership copy-failure
appkit-bitmap-copy-ownership copy-nil
```

Owned/borrowed tests require distinct raw-plane pointers, exact complete contents
including padding, and preserved scalar/layout metadata. Source mutation must not
change a copied plane. The surviving object is checked after releasing the other;
borrowed source buffers are explicitly freed before checking the surviving copy.
Borrowed formats include gray1, gray16, planar RGB16, CMYK8, floating-point RGBA32,
planar gray1 with alpha, and CMYKA8. No renderer or PNG encoder is a copy oracle.

CG workflows use real RGB and gray CGImage construction, original full provider
bytes including canaries after the pixel extent, and the provider's own release
callback. After releasing the first bitmap, the callback must not have fired and
the survivor must still return all original provider bytes. It must fire exactly
once after the final owner. This catches the old missing retain *before* reading
a dangling object and does not infer safety from CFGetRetainCount. Dual workflows
also materialize a component plane, deliberately change it, and require both the
new independent copied plane and the original retained CG backing to survive.
Gray CG materialization is deliberately not invoked as a proxy for ownership.

Property tests use an original value deallocation sentinel, exercise first set,
replacement, independent copied dictionary insertion and nil clearing, and check
both release orders. Property dictionaries copy their container and retain values
with ordinary shallow semantics; deep metadata snapshots are a separate archive
responsibility. Empty bitmap copying must not materialize pixels. The invalid
case uses the public metadata setter to declare a negative height and requires
an explicit project error before plane copying; it is not a claim about the exact
native macOS exception for invalid bitmap state.

`color-space` uses an original NSString subclass with a genuine copy/deallocation
sentinel through the public color-space setter. Source/copy must each own and
release their copied string. `copy-failure` creates a real CG-backed bitmap and
materialized plane, installs that string and an original metadata object whose
next retain throws, and first proves a real dictionary mutableCopy invokes the
failure. The bitmap copy must propagate it, release its newly copied string and
CG ownership, preserve source pixels, and leave no string/provider owner after
finally releasing the source. If the public property prerequisite fails first,
that before result does not qualify the staged exception path.

On the old implementation, the raw-plane test exits at pointer alias detection
without deliberately releasing two aliases. Likewise, a CG test exits at the own
provider callback failure before dereferencing the freed CG backing. Failed before
cases intentionally leave those retained test objects to process teardown rather
than triggering a second known-invalid release. Successful after cases release
all source/copy owners and every borrowed buffer normally.

Source model: existing NSCopyObject and NSZone allocation/deallocation patterns
(rung2), documented NSCopying/property behavior and original public fixture calls
(rungs3/4). Apple's NSBitmapImageRep Class Reference dated2009-01-06, page30,
explicitly documents nil clearing. Original public reference mirrored at:
https://leopard-adc.pepas.com/documentation/Cocoa/Reference/ApplicationKit/Classes/NSBitmapImageRep_Class/NSBitmapImageRep_Class.pdf
Modern official API:
https://developer.apple.com/documentation/appkit/nsbitmapimagerep/setproperty(_:withvalue:)

This does not qualify standalone bitmap NSCoding, native NIB schemas, generalized
materialization, render/color fidelity or vendor app behavior. The new image codec
must separately copy a decoded bitmap directly; an NSImage.copy assertion cannot
stand in for this prerequisite.

`copy-nil` arms the original owned NSString field to return nil from its next copy,
then requires an explicit allocation error and intact source ownership. The actual
production method also guards a nil mutable-copy of a nonnil property dictionary.
The source/native adapter below separately exercises both outcomes.

## Native transaction adapter

```
python3 tests/native-bitmap-copy-faults.py --output SCRATCH_DIRECTORY
```

With Clang, GNU libobjc headers/runtime and GCC's include directory available, this
extracts the complete current production copy/dealloc methods unchanged. A small
owned native object/NSZone transport supplies the surrounding ABI, metadata-copy
returns and immutable CG retain/release; it is explicitly not Darling Foundation
or a guest/public CG implementation. Source NSCopyObject is a shallow object_copy
transport, so the adapter likewise starts with aliased owned pointers.

ASan/UBSan exercise seven source-visible construction stages (object clone, string
copy, dictionary mutable-copy, plane table and three plane buffers), failing each
with nil or an exception. A failed copy must never return a nonnull incomplete
object, source state/refcounts/bytes must remain intact, and all tracked new
resources must be cleaned. Borrowed/CG-only/empty and four invalid raw declaration
cases also run. This covers source-visible ownership transitions, not every
internal allocation inside real Foundation or the system runtime. LSan is disabled
because sandbox process inspection is unavailable; explicit owned-resource and
NSZone ledgers are required instead.

Before the two nil-result guards, the actual candidate method returned a nonnull
copy after failing its string or dictionary copy. The same adapter failed with
those two guards removed and passes with them present; this candidate-level
negative is separate from the installed-runtime copy before/after checks.
