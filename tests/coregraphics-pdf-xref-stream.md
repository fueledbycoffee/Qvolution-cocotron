# PDF1.5 cross-reference streams

Generate only original fixtures (no vendor/PDF input):

```
python3 tests/generate-pdf-xref-fixtures.py <work>/pdf-xref-fixtures
```

Build assertions enabled (-UNDEBUG), then run in an isolated runtime prefix:

- coregraphics-pdf-xref-stream.m <guest-path-to-fixtures>: actual public document
  creation, page count/box and raster center pixels. Red validates the ordinary
  page; incremental/hybrid overrides render green; newest free entry yields a
  valid blank white page instead of resurrecting stale red content. Internal
  typed Probe queries supplement the public path for final ObjStm scalar tokens.
- onyx-pdf-predictors.m <guest-path-to-fixtures>: link Onyx2D directly; its vectors
  can also be generated independently by generate-pdf-predictor-fixtures.py.
  It validates
  exact decoded bytes for PNG Up/all5rowtags/RGBbyte-stride and TIFF depths
  1/2/4/8/16. Six invalid framing/parameter vectors must return nil.
- coregraphics-pdf-invalid-input.m: public malformed creation must return NULL.
  An uncaught exception is a test failure, not an accepted rejection.

The26generated PDFs comprise16valid inputs and10malformed structural cases.
Valid files were independently accepted by Poppler pdfinfo as one page without
errors. This checks fixture construction independently of this reader; it is not
candidate-runtime evidence. Positive cases cover raw/Flate xrefs, W type and
zero-generation defaults, multi-range Index, PNG prediction, compressed object
catalog/pages, hybrid and Prev lookup, free tombstones, final integer/real/name/
boolean/null tokens without padding, and a compact First3 ObjStm header. Negative
cases cover short rows, oversized W, invalid Index range, Prev cycle, invalid
ObjStm First/N/index, the map reserved object-number key, and forbidden standalone indirect references.

Provenance/specification:

- Adobe's public ISO32000-1:2008, sections7.5.7,7.5.8 and7.4.4.4:
  https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf
- Apple's public CGPDFDocumentCreateWithProvider return contract (NULL on failure):
  https://developer.apple.com/documentation/coregraphics/cgpdfdocument/init(_:)-gbq6
- Rung2 existing Onyx2D parser/object/stream/filter interfaces; rung4 source-built
  public parse/render and byte-predictor fixtures. The vendor failure identified
  the needed format only; no vendor PDF resource was inspected, copied or used
  as a test input. No Apple binary implementation inspection.

The xref parser uses existing stream filters. It supports fields fitting native
O2PDFInteger (width0..sizeof, nonnegative representable values) and rejects wider
fields rather than truncating. Unknown entry types legitimately resolve to PDF
null per the specification; type2 objects are actually decoded/parsed, not stubbed.
Free entries prevent older sections resurrecting deleted objects. Type2 targets
must name an uncompressed stream container; nested/cyclic object-stream containers
are rejected. Bounded header/body buffers add only a lexical LF delimiter so final
scalar tokens work without reading into the next object.

The change does not add crypt/encrypted-document support, ASCIIHex/ASCII85/RunLength
filters, linearization optimization or new rendering operators. Existing stream
filter/decompression resource limits are not a new security guarantee. The whole
scanner's scalar numeric range remains implementation bounded; this feature does
not claim an exhaustive malformed-PDF or fuzzing audit. Real VLC resource rendering,
Preview workflows, fonts/images and long-document performance remain integration
and app acceptance gates after candidate staged tests pass.

Before evidence: public Flate xref fixture aborts in the old literal-xref reader;
PNG Up byte fixture fails its first byte comparison; malformed nonPDF header
throws instead of returning NULL. Coordinator recorded all3parent failures with
exact-prefix shutdown0. Candidate runtime results must be recorded separately;
compilation does not establish passing parse/render behavior.
