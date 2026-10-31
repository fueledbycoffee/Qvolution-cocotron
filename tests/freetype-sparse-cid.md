# Raw sparse CID fixture

Generate only from a legitimately installed open Noto CJK font under its SIL OFL 1.1 licence:

```
python3 tests/make-sparse-cid.py /usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc /absolute/scratch/sparse-cid.cff
python3 tests/freetype-charmap-selection.py /absolute/scratch/sparse-cid.cff /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf
```

The generator uses fontTools, retains `.notdef`, `cid00034` and `cid01000`, strips the SFNT wrapper and renames the output. No generated font bytes are committed. This is a source-derived local test fixture, not an Apple font or an assertion about native macOS implementation. Independently observed native FreeType shape: raw CID, not SFNT, 1001 glyph indices, zero charmaps; reachable CIDs 0/34/1000 have unscaled advances 1000/608/1000. Holes return `FT_Err_Invalid_Argument`.

The native charmap test extracts the actual production initialization selection block, replacing only logging. The previous block exits 139 on this valid zero-charmap face; the corrected block preserves the absence of a charmap and retains the real Unicode mapping on DejaVu Sans. This is native source-adapter coverage. Public CGFont guest execution remains a separate coordinator gate; cache support for sparse indices is a separate correction.
