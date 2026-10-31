# Experimental ordinary AppKit EGL presentation

Opt in per process with DARLING_APPKIT_RENDERER=egl on the Wayland backend.
Unset or `shm` retains the current wl_shm path. Each root or popup window uses
its own private compatibility CGL context and native root wl_egl_window. Requested
EGL failures are explicit, including unavailable EGL, known software renderers,
insufficient RGBA channel precision, upload/output/verification or swap failure;
there is no silent shm fallback. This prototype requires desktop OpenGL3+ and
RGBA8 native buffers. Existing default runtime/device policy is unchanged.

Classification: Onyx2D still rasterizes all AppKit drawing on CPU. The actual
stride-aware CATexImage2DCGImage helper uploads the backing surface; a texture
copy draws it into the real EGL default backbuffer, and EGL swaps that ordinary
window surface. This is GPU presentation, not GPU glyph/path rasterization,
zero-copy, a performance result, or full application qualification.

DARLING_APPKIT_EGL_VERIFY=1 enables a full-frame pre-swap reference check. It
reads actual default backbuffer BGRA pixels and independently compares every
pixel to the CPU backing surface, accounting for top-row-first storage and
opaque-window alpha semantics. It does not reuse GL texture contents as its
oracle. It costs CPU readback and must not be used for performance comparisons.
DARLING_APPKIT_EGL_TEST_CORRUPT=1 (requires verification) deliberately changes one
uploaded texel without changing CPU source/reference, so the native path must
reject the frame before swap. No custom shader/triangle substitutes for AppKit.

The original appkit-egl-presentation.m fixture links AppKit/Foundation, OpenGL
and Onyx2D, with assertions enabled. Run with no arguments for positive mode;
--negative-control requests the deliberately corrupted native texture. Both
explicitly request EGL+verification before window creation. Parent backend must
fail the actual backend availability check, not pass merely because an app
window appeared. Negative mode must fail the output verification and log a pixel
mismatch; a loader/startup failure is not a successful negative control.

Positive sequence uses real ordinary borderless Wayland NSWindows and a custom
NSView's AppKit drawRect: calls, with distinct colors/transparency. CPU samples
also assert actual asymmetric view rasterization and premultiplied alpha. Every
submitted frame is compared in full before swap. It exercises updates, paused
flushing across frame callbacks, resume, resize, unmap/remap, a second opaque
window, caller CGL context preservation and teardown. Statistics report actual
successful swaps, checks, source upload bytes, dimensions, failures and actual
scale120; no inferred FPS or acceleration speedup is reported. The scale follows
real backend/output preferences. Running on one output does not establish a
multi-scale transition; an actual alternate output/scale is a separate gate.

The same explicit renderer applies to native popups. Their geometry, grabs,
menus and mixed child-surface content still require user/compositor QA. No
silent popup fallback is implemented and no popup/global-menu/app qualification
is implied by these ordinary-window checks. Child EGL surfaces retain their
existing synchronized-parent geometry path; integration with this root presenter
is not claimed tested until separately exercised.

Frame pacing requests the existing wl_surface frame callback before swap's
implicit commit. Own swap interval is0, and no second parent commit is issued
for the root frame. needsPresent remains pending until successful swap; disabled
flushing and pending configure/frame callback guards remain in the shared entry
path. Unmap destroys the CGL EGL drawable before wl_egl_window, and preserves the
parent wl_surface identity required by existing EGL children.

Sources: repository WaylandWindow/SubWindow, X11Window and
CAWindowOpenGLContext presentation patterns; existing O2Surface/CARenderer
stride upload; vendored CGLInternal/OpenGL interfaces (rung2). Original fixtures
exercise only those public/own-source boundaries (rung4 after coordinator run).
No Apple binaries/SDK internals or vendor resources were inspected/copied.

Candidate isolated production and fixture compile/link; all runtime results,
negative control, resize/remap and compositor-visible output remain pending.
A successful swap/readback alone does not prove compositor-visible correctness.
