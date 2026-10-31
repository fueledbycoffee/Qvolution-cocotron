# Packed RGB24 PNG

The public fixture creates a 3-by-2, 8-bit RGB bitmap with a 12-byte row stride,
including three padding bytes per row. Give it a fresh output path, then inspect
its PNG with the independent Pillow and IHDR oracle:

```
appkit-rgb24-png OUTPUT.png
python3 tests/check-appkit-rgb24-png.py HOST_OUTPUT.png
```

The fixture requires nonempty output; the oracle checks RGB PNG type, dimensions,
and all six exact colors. Before the metadata correction, the coordinator ran
`rgb24-public-before-stage27` with the original fixture under the staged runtime:
it exited 1 with `FAIL RGB24 public PNG generation, bytes=0`; shutdown exited 0.
The after runtime and oracle remain pending. The fixture and oracle do not claim
native macOS behavior or coverage of other bitmap layouts.
