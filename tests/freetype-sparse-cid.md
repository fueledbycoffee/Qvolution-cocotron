# Raw sparse CID fixture

Generate only from a legitimately installed open Noto CJK font under its SIL OFL 1.1 licence:

```
python3 tests/make-sparse-cid.py /usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc /absolute/scratch/sparse-cid.cff
python3 tests/freetype-charmap-selection.py /absolute/scratch/sparse-cid.cff /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf
```

The generator uses fontTools, retains `.notdef`, `cid00034` and `cid01000`, strips the SFNT wrapper and renames the output. No generated font bytes are committed. This is a source-derived local test fixture, not an Apple font or an assertion about native macOS implementation. Independently observed native FreeType shape: raw CID, not SFNT, 1001 glyph indices, zero charmaps; reachable CIDs 0/34/1000 have unscaled advances 1000/608/1000. Holes return `FT_Err_Invalid_Argument`.

The native charmap test extracts the actual production initialization selection block, replacing only logging. The previous block exits 139 on this valid zero-charmap face; the corrected block preserves the absence of a charmap and retains the real Unicode mapping on DejaVu Sans. This is native source-adapter coverage. Public CGFont guest execution remains a separate coordinator gate; cache support for sparse indices is a separate correction.

Cache and shared-query coverage:

```
ASAN_OPTIONS=detect_leaks=0 python3 tests/freetype-sparse-cid-advances.py /absolute/scratch/sparse-cid.cff /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf /usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc /usr/share/fonts/X11/misc/8x13-ISO8859-9.pcf.gz
python3 tests/freetype-unscaled-advances.py /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf /usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc /usr/share/fonts/X11/misc/8x13-ISO8859-9.pcf.gz
```

The first probe extracts the actual cache helper and shared O2 query. Native ASan/UBSan coverage includes reachable CID widths, missing CID rejection without partial output, dense non-CID batching, selected bitmap strike units, batch boundaries, idempotence and live-size preservation. Controlled allocation and FreeType error injection validates unpublished state and tracked allocation cleanup. LeakSanitizer is explicitly disabled because the sandbox's tracing environment prevents it from running; tracked allocations do not qualify a general leak-free claim.

`cg-font-sparse-cid.m` is the separate original public CGFont provider regression. Its sole argument is the generated CFF's guest-visible absolute path. It checks provider identity, real bounds/units and reachable widths, then rejects missing/out-of-bounds CIDs while preserving the entire output array. It still requires execution against a built guest runtime. These tests do not establish full PDF, arbitrary CID font, UI or application compatibility.
