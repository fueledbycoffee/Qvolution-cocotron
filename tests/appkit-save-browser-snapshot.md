# Save browser directory snapshots

The save panel's real `_NSFileSystemDataSource` is exercised with 1024 empty
files (`file-0000` through `file-1023`) and one empty `nested` directory.
The fixture counts calls to its directory-reading method, delegating each call
to the production implementation and real filesystem.

Before the fix, fetching the children enumerates and sorts the directory again
for every row. After the fix, a count query takes a fresh snapshot and child
queries reuse it. Interleaving another directory must preserve the first
snapshot. A file created after the first count becomes visible after the next
count. URL identity remains stable across refresh, and invalid indices return nil.
The test removes its own added file on success; use a dedicated fixture directory.

Build the superproject's `qvolution_save_browser_snapshot` target with
`ENABLE_TESTS=ON` and `QVOLUTION_BUILD_TEXTEDIT=ON`, then run the executable
under Darling with the fixture directory as its only argument. Current Qvolution
GUI tests require the diagnostic Swift CoreCompat/flat-namespace override.
This regression does not validate save completion, Wayland flicker, or runtime
survival while interacting with the actual TextEdit dialog.

Provenance: existing Cocotron data-source and NSOutlineView source (rung 2),
with source-built runtime API observations (rung 4). No Apple binary inspection.
