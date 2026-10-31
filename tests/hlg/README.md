# HLG gates

Original clean-room fixtures derived from the independently reviewed HLG
specification, official Apple API documentation and BT.2100-3 Table 5. They never
supply a local substitute for the exported name.

- `link.c`: strict typed data import, nonempty CFString and actual named creation.
  Before integration Stage24 strict linking fails only on the HLG data symbol.
- `metadata.c`: dynamic import distinguishes absence (77) from metadata success;
  checks name ownership, dynamic equal name, RGB classification and conservative
  matching rejection, with SDR and invalid-name controls.
- `render-limitation.m`: actual unsupported image/context/gradient/fill use must
  reject explicitly. This verifies a limitation, never rendering support.
- `transaction.m`: rejection preserves pixels/live path/PDF buffers and resource
  lifetimes; unused HLG colors don't block SDR operations; subsequent actual SDR
  glyph drawing completes; nested pattern and ramp cleanup; parent-shadow layer
  rejection preserves state/stacks and retries after a test-only explicit pending
  parent parameter replacement. The probe adds no production bypass.
- `transfer.c`: fixed independent normative reference vectors, branch neighbors,
  coupled OOTF at explicit reference peaks, invalid-domain/no-output-on-error.
- `reference-vectors.py`: independent Decimal evaluation of standard equations,
  without importing or parsing production helper code.
- `preflight-source.py`: compiles actual path-preflight C fragment and audits
  operation guard ordering. Source verification alone cannot prove transactions.

Native reference helper command (from checkout, choose an external output path):

```
cc -std=c11 -Wall -Wextra -Werror -x c Onyx2D/O2HLGTransfer.m \
  tests/hlg/transfer.c -I Onyx2D -lm -o /absolute/external/output/hlg-transfer
/absolute/external/output/hlg-transfer
python3 tests/hlg/preflight-source.py /absolute/external/output/preflight
```

Guest controls require the project's own Darwin compiler/linker, CoreGraphics,
CoreFoundation and Foundation; transaction additionally links Onyx2D. Use the
host's serialized runtime harness and disposable prefix. In Stage24 actual before
runs metadata/render/transaction exit77, so semantic assertions are not reached.
Relink `link.c` strictly against the actual new stage for after proof; don't reuse
baseline expected failure as after success. Root still must run candidate controls.

No fixture result substitutes for actual HLG matching, retagging, managed drawing,
SDR/display adaptation, GPU correctness, physical UI or application qualification.

The original transaction probe exposed a missing declaration for Onyx's existing
bitmap instance initializer: the untyped call supplied an incorrect incoming row
on source-built Stage26. A fresh control declaring the exact own-source signature
passed all transaction, nested-pattern, shadow-retry and PDF assertions on that
runtime. The header now declares that existing method; the canonical fixture uses
the header directly, with no local stand-in, and compiles with
`-Werror=objc-method-access`. This corrects caller type checking; it does not add
new rendering behavior or establish full HLG support.
