#ifndef QV_GPU_PRESENT_BENCH_POLICY_H
#define QV_GPU_PRESENT_BENCH_POLICY_H
#include <stdint.h>
#include <string.h>

/* A requested fallback can consume one initialization failure before any EGL
 * swap/check. Keep further errors visible, including a fallback after rendering.
 * Rung 4: backend statistics at the authored benchmark's API boundary. */
static inline uint64_t qvBenchFailures(const char *requested, const char *renderer,
        const char *expected, const char *reason, uint64_t backendFailures,
        uint64_t swaps, uint64_t checks) {
    const char *want = expected && *expected ? expected : requested;
    if (strcmp(want, renderer)) return backendFailures ? backendFailures : 1;
    if (expected && !strcmp(expected, "shm") && !strcmp(requested, "egl") &&
        !strcmp(renderer, "shm") && reason &&
        !strcmp(reason, "EGL is unavailable on this Wayland display") &&
        backendFailures == 1 && swaps == 0 && checks == 0) return 0;
    return backendFailures;
}
#endif
