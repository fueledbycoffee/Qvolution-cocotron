# Native byte-path differential and damage coverage

From the component checkout, prepare and build (fleet workers must wrap ninja
with `dashboard/qv-slot build`):

```sh
python3 tests/onyx-fastpaths-native.py --prepare /tmp/onyx-fastpaths
ninja -C /tmp/onyx-fastpaths -j6
ninja -C /tmp/onyx-fastpaths -n
for scalar in float double float-O0 double-O0; do
    ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1 \
        /tmp/onyx-fastpaths/equivalence-$scalar
done
/tmp/onyx-fastpaths/benchmark --benchmark
```

The benchmark compiled with **-O2** is the headline. `benchmark-O0` is a separate
unoptimized-build diagnostic. Record `/proc/loadavg` before and after measuring;
fleet workers use a perf slot for the measurement only. Each row reports the
median/min/max of seven groups of three draws. A full-buffer checksum runs
outside the timed section. Fill/clear use a 1932x1144 backing store, blits 512x512.

The reference is the sweep, spans, cached paint readers, blend functions,
samplers and conversions from a360e4d95. Current entry helpers are extracted
verbatim, with one Objective-C layer-count message replaced by a native count.
The adapters model the byte/float dispatch and object storage; they do not
qualify Objective-C dispatch, ownership, path tessellation or clip replay.

The real damage accumulator and Add/Take functions are compiled from the
checkout. For each accepted entry path, every changed byte must be inside
recorded damage, including checking that row padding did not change. Refused
paths must leave pixels and damage unchanged. Separate cases require exact
viewport intersections (and empty damage for empty writes) for fill, clear,
copy blit and source-over blit, both formats and Y orientations.

To validate the regression test, remove the O2SurfaceAddDamage call from either
tryFastSolidRect or tryFastImage in a disposable checkout: equivalence-float
must abort with UNCOVERED (or the exact-damage assertion). Never use the mutated
source for installation.

The isolated full-window span/sweep benchmark does not reproduce the app's
reported 550 ms fill. It omits the app's graphics-state setup, clip replay,
Objective-C path/paint allocation, actual window draw call sequence and guest
runtime. An app-level timing needs those inputs and a runnable guest; adding
an artificial repeat count or delay would not reproduce the cause.
