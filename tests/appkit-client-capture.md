# Opt-in CPU client-raster PNG diagnostic

Set `DARLING_APPKIT_CAPTURE_DIR` to an explicit existing absolute directory in
an isolated project/work run before starting a guest process. Unset is off.
Nothing is captured from existing processes, other windows on the desktop,
compositor surfaces or GPU child layers. This is framework debug output from
our own O2Surface, not a desktop screenshot or final visible-screen proof.
No input actions, vendor resource changes or host settings are involved.
Use only dedicated private run directories; never publish application captures.

After a successful natural shm surface commit or EGL swap, the window attempts
one PNG, up to 8 attempts over that window object's lifetime (including hide/show).
No extra present/redraw or input is induced. At most 64MiB of source-sized packed
pixels and dimensions 16384x16384 are accepted per capture. Encoding is synchronous
and adds diagnostic overhead; never enable it for performance comparisons. It
captures the submitted CPU client raster including client decoration when present,
not GPU children or compositor effects. It does not imply the application works.

The directory must already exist; a final-component symlink, missing or relative
path disables this diagnostic without affecting presentation, reporting one generic
code-only diagnostic per requested window. Default off remains quiet. Files are created
exclusively with mode 0600, with computed process/window/frame/dimension/scale120
names. Existing files are never overwritten/deleted. Failed newly created partial
files are removed on a best-effort basis. Directory ancestry/privacy are the caller's responsibility.
No path, title or content is written to logs. The first capture error per window
is logged once by code (1 invalid path, 2 directory open, 3 source/allocation, 4 encoder,
5 exclusive file open, 6 write, 7 close, 8 exception); backend statistics also expose
request/readiness and error state. Failures consume the bounded attempt
and do not prevent rendering. The default runtime/renderer policy remains intact.

PNG uses the existing Onyx2D libpng encoder. Source BGRA premultiplied rows are
copied using the real stride to a supported straight RGBA staging image. The
inverse-premultiplication rounds to 8 bits (zero-alpha colors become zero); opaque
windows force alpha 255 exactly as shm XRGB and the EGL presenter do. Source bytes
are immutable. Source raster dimensions and render scale120 are in the computed
filename; this does not encode compositor coordinates, physical display scale
proof or a new CSS/logical image size.

The original `appkit-client-capture.m` fixture needs its helper implementation
compiled/linked with Foundation and Onyx2D. It takes one existing absolute empty
run directory, uses no NSApplication/display, and leaves 9 synthetic PNGs in its
own unique child directory for independent checking. It verifies padded rows,
source immutability, alpha/dimensions,8 attempt budget, separate window budget,
0600 creation, invalid/symlink paths, deleted-directory failure and collision
preservation. The older O2 decoder clamps straight colors to alpha; decoder dimensions/alpha
only are checked and it is not used as the color pixel oracle.
Run `python3 tests/appkit-client-capture-pixels.py RUN_DIR` with Pillow on the
host to independently decode only those original synthetic PNGs, verify exact
RGBA/orientation and recover every original valid premultiplied component.
Remove the dedicated original-fixture run directory after verification.

`appkit-client-capture-window.m` links AppKit and takes an empty dedicated absolute
run directory plus `enabled`, `off` or `invalid`. It creates one actual Wayland
ordinary window and naturally redraws asymmetric colors for24timer ticks. It
requires at least8 successful backend client presentations in every mode, checks
8capture files only in enabled mode and zero otherwise, and checks backend counts.
Run all three modes against the staged candidate, each with its own directory and
bounded process timeout; run enabled with both shm and EGL. Parent code fails the
new successful-present count/capture assertion. Readback/presentation/scale/popup
or vendor acceptance remains separate. This fixture performs no input automation.

Provenance: repository Onyx2D PNG writer, image/surface headers, existing BGRA
Wayland backing and presentation boundaries (rung2); original synthetic fixtures
(rung4 after coordinator execution). No Apple binaries, SDK implementation,
vendor image resources, screen APIs or external UI automation were inspected.

Isolated helper/backend objects and both original fixture executables compile
with copied real recipes. The coordinator ran the reviewed standalone fixture:
exit0 in1.625seconds, exact-prefix shutdown0. The independent host Pillow check
passed all9 original PNGs (8 alpha,1 opaque), including exact mixed RGBA and
premultiplied reconstruction. Expected invalid-configuration/file/input codes
were1/2/5/3. Actual backend configuration/presentation and vendor captures remain
coordinator-owned pending gates.
