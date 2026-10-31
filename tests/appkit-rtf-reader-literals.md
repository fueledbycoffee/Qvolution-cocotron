# Original RTF lexical reader regression

Uses public NSAttributedString initWithRTF/documentAttributes with own hand-authored payloads. Primary format reference: Microsoft [RTF1.9.1](https://officeprotocoldoc.z19.web.core.windows.net/files/Archive_References/%5BMSFT-RTF%5D.pdf), lexical escaped backslash/braces and fs halfpoint character formatting. No sample implementation copied, no vendor/Apple document input.

No args. First payload is exactly `A{B}\\C` with fs35 (17.5points); second checks literal braces inside nested groups and ignored unknown destination never leaks content. No writer output used, so producer/reader errors cannot cancel. Public font identity/traits manager conversion is deliberately outside this lexical/halfpoint fixture; existing full RTF readiness keeps its strong formatting assertions.

Root stage22 grouped read already fails text/plain-reset, but the independent stage23 fixture fails escaped text, fractional17.5size and nested ignored-destination checks (exit1,1.834793908seconds, exactshutdown0); valid-reader control passes. Production/fixture compile x86_64+i386 using existing isolated recipes; runtime candidate not yet measured. This implements no paragraph, font-selection or color reset change and does not qualify full RTF support.
