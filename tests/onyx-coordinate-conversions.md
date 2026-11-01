# User/device coordinate conversion

Run the native regression without a guest or display server:

```sh
python3 tests/onyx-coordinate-conversions-native.py --output /path/to/scratch
```

Expected: `RESULT onyx-coordinate-conversions failures=0 checks=133`. The
previous rectangle stubs fail 69 checks. The adapter compiles the production
O2GState conversion methods and CTM concatenation with the complete production
O2AffineTransform.m and O2Geometry.m, using host libobjc and ASan/UBSan. Only
Foundation geometry types and allocation are adapted. This does not test the
CoreGraphics bridge or the guest renderer.

Independent expected coordinates cover identity, translation, nonuniform scale,
90 and 45 degree rotation, shear, a flipped device transform, and concatenated
transforms over that device transform. All six methods are checked. Sizes ignore
translation and retain signed vector components. Rectangles enclose all four
transformed corners; inverse rectangle conversion bounds the inverse-transformed
input rectangle, rather than assuming a bounding box can round-trip a rotation.
The one-pixel samples used by menu-state-marks.m must remain distinct and nonzero.

Specification (rung 3): Apple's public Quartz CGContext reference,
`CGContextConvertPointToDeviceSpace`, `CGContextConvertPointToUserSpace`,
`CGContextConvertSizeToDeviceSpace`, `CGContextConvertSizeToUserSpace`,
`CGContextConvertRectToDeviceSpace`, and `CGContextConvertRectToUserSpace`:

https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CGContext/Reference/reference.html

The task supplies the CTM/inverse and rectangle bounding-box contract; the
network-isolated lane cannot retrieve that documentation. Rung 2 declarations
are in CoreGraphics/include/CoreGraphics/CGContext.h and
Onyx2D/include/Onyx2D/O2GraphicsState.h. No Apple binary was inspected.

Run tests/menu-state-marks.m in a real Darling Wayland session to verify that the
shared AppKit vector renderer produces checkmark and mixed-state pixels in both
normal and highlighted states. That fixture also rejects invalid or aliased
device-space samples. Native coordinate checks alone do not establish pixels.
