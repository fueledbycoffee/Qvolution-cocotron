# PDF lexical token regression controls

Run `onyx-pdf-token-roundtrip numbers`, `names`, and `hex` as separate modes.
All modes require their explicit PASS line and exit zero. The fixture was frozen
before the scanner correction in Qvolution-work/parallel/pdf-model-next/probe.
The root coordinator records actual source-control before/after execution.

Numbers check exact binary fractions used in annotation bounds, correctly rounded
long/tiny decimals, signed leading-dot syntax, signed integer limits, and rejection
of integer overflow/exponent syntax. Names check canonical #xx dictionary keys and
name values plus malformed/#00 rejection. Hex checks empty strings, leading
whitespace and the required zero padding of an odd final nibble.

Provenance: ISO 32000-1:2008 sections 7.2 and 7.3.3-7.3.5 specify lexical delimiters,
integer/real syntax, byte strings and escaped names. This tree's vendored xlocale
headers specify LC_C_LOCALE and strtod_l/strtoll_l; the scanner reuses those genuine
libc conversions instead of overflowing integer arithmetic or accumulating
fractions at reduced precision. Names are stored decoded and escaped again when
O2PDFObject_Name or O2PDFDictionary serializes them. No Apple implementation or
proprietary SDK source supplied the behavior.
