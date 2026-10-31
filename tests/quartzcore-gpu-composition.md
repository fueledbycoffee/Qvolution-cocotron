# CPU-raster layers composed through the real GPU layer renderer

Build `quartzcore-gpu-composition.m` as a source-built Darling guest, linked to
AppKit, CoreGraphics, Foundation, QuartzCore and OpenGL. It imports the vendored
private CGL drawable interface and component-relative CALayerInternal header.
No application bundle is modified. The coordinator owns the full build/stage,
dedicated guest prefix, runtime runs and exact-prefix shutdown.

Default invocation uses the actual CARenderer/CALayer contents and blending
path in an offscreen RGBA8 framebuffer. CoreGraphics CPU-rasterizes asymmetric
colored quadrants into 32-bit premultiplied BGRA images with padded rows. Two
overlapping layers exercise alpha and opacity. Every output pixel is compared
to an independent CPU source-over scene oracle expressed in logical bottom-left
coordinates. Replacement image contents and layer movement must redraw correctly
and clear the old region. This is not an unrelated shader triangle.

The first phase asserts the image retains its 80-byte stride. The updated image
uses a 77-byte stride to exercise row repacking when OpenGL cannot express that
stride as a pixel count. It also seeds unpack alignment, row length, row/pixel
skip, byte swap and a bound unpack buffer; the upload must both ignore those
caller states when reading CPU memory and restore them afterward. The probe
requires desktop GL 3 or later for its separate framebuffer-binding checks. Production upload
code checks the current context's version/extensions before touching PBO state.
This change handles supported 8-bit-component, 32-bit image layouts; it does not
claim general image pixel-format conversion support.

`--negative-control` corrupts one source image byte while leaving the oracle
unchanged. It must exit nonzero for a pixel mismatch; do not label that failure
a runtime regression. The unmodified mode must pass before using the negative
control as evidence of checker sensitivity.

`--present` additionally creates a real ordinary AppKit parent and a native
Wayland EGL child using the existing CGSubWindow/CGL interface. The same layer
renderer draws into the real drawable. Its pre-swap pixels must satisfy the
same oracle at the actual drawable pixel size; a successful CGL swap and child
flush then submit the native child and synchronized parent commit. Renderer
identity is printed and recognized software renderers are rejected. Require an
observed hardware identity matching the host device before claiming GPU work.

The first native attachment must preserve the already-bound offscreen read/draw
FBOs and their selections, and initialize the window default buffers to BACK.
Only after asserting those defaults does the scene render/read back. Repeated
attachment must preserve explicit NONE selections and independently bound
read/draw FBOs. The test then chooses BACK itself to resume presentation and
reruns the same oracle. There is no diagnostic buffer forcing before the first
native image check; the CGL production path must establish a usable drawable.

`--hold` performs that native path and leaves the app event loop running for
coordinator-authorized compositor-visible inspection/capture. No screenshot or
host session data is uploaded. Close the test window or use the exact-prefix
shutdown procedure when finished. A pre-swap glReadPixels match and successful
swap are not evidence that the compositor displayed the frame. Actual visible
output, placement, stacking, input and frame timing require separate acceptance.

Classification: CPU rasterization and upload, GPU texture composition, and
native EGL child presentation submission. The ordinary parent can still use
wl_shm. No GPU glyph/path rendering, zero-copy, app acceleration qualification,
stability qualification or UI performance speedup is established by this probe.

Source provenance: existing public/vendored CoreGraphics image/bitmap APIs,
CALayer/CARenderer, CGSubWindow and CGL interfaces and source-built boundary
observations (clean-room rungs 2 and 4). No Apple binary inspection or copied
application assets.
