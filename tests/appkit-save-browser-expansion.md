# Real save-panel expansion diagnostic

Build `qvolution_save_browser_expansion` in the Qvolution superproject with
`ENABLE_TESTS=ON` and `QVOLUTION_BUILD_TEXTEDIT=ON`. Run the executable inside
a dedicated Darling prefix using the staged runtime, then shut down the prefix.
The current runtime requires the explicitly diagnostic Swift CoreCompat and
flat-namespace override; this is not a normal-loading compatibility claim.

This test loads the real NSSavePanel nib, requires automatic column sizing to
be disabled, expands the filesystem root and `/tmp`, then displays and closes
the panel. It reports elapsed times and the resulting row count. It reads
directory names and metadata without creating or removing files in `/tmp`.
A brief diagnostic window can appear. `/tmp` must exist and its contents make
the timing host-dependent. Use an external timeout and always shut down the
prefix if the test hangs; elapsed time alone is not a portable pass threshold.

The parent fails the automatic-column-sizing assertion. Earlier diagnostic
runs on the parent with about 55,000 `/tmp` entries reached column sizing and
exceeded a 35-second timeout; disabling sizing allowed display to complete.
The focused 1024-file snapshot test covers refresh and URL identity separately.
This full-panel test still does not verify manual save, reopen, or modal input.

Provenance: existing Cocotron save-panel, outline and table source and vendored
Foundation interfaces (rung 2); source-built runtime API observations (rung 4).
