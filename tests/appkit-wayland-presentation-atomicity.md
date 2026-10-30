# Wayland presentation during drawing

Build `qvolution_presentation_atomicity` from the superproject with
`ENABLE_TESTS=ON` and `QVOLUTION_BUILD_TEXTEDIT=ON`. Run it with the Wayland
backend and a dedicated prefix, then shut down that prefix. Qvolution currently
needs the diagnostic Swift flat-namespace/CoreCompat override for these tests.

The regression calls the real NSWindow pause/enable/getter methods and the real
WaylandWindow presentation gate. It pauses drawing twice and tries a pending
presentation at each nesting depth, then checks that pixel access resumes after
the balanced enables. A probe context raises before any backing pixels or
Wayland requests are accessed. No fake surface is submitted to the compositor.

The backend bundle is loaded through NSApplication and located by class name.
Only source-defined ivars in test-owned objects are populated to model a pending,
configured, mapped frame. Objects bypass platform initialization and teardown so
the test isolates the gate; a normal compositor connection is still required to
load the backend. It does not simulate a real frame callback or measure flicker.

The parent reports drawing enabled at both nesting depths and attempts to read
pixels while drawing is paused. The getter used an unused boolean instead of the
counter modified by disable/enable, and Wayland's gate did not check that state.
A visual menu/scroll test is still required before claiming flicker is fixed.

Provenance: existing Cocotron NSWindow, NSView and WaylandWindow source and
vendored Objective-C runtime interfaces (rung 2), plus the source-built methods
called by this fixture (rung 4). No Apple binary inspection.
