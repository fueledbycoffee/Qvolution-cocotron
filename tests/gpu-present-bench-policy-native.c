/* Native accounting regression; no Objective-C runtime, container or GPU. */
#include <assert.h>
#include <stdio.h>
#include "gpu-present-bench-policy.h"
int main(void) {
    assert(qvBenchFailures("egl", "shm", "shm", "EGL unavailable", 1, 0, 0) == 0);
    assert(qvBenchFailures("egl", "shm", "egl", "EGL unavailable", 1, 0, 0) != 0);
    assert(qvBenchFailures("egl", "shm", NULL, "EGL unavailable", 1, 0, 0) != 0);
    assert(qvBenchFailures("egl", "egl", "shm", "", 0, 30, 0) != 0);
    assert(qvBenchFailures("egl", "shm", "shm", "EGL unavailable", 2, 0, 0) != 0);
    assert(qvBenchFailures("egl", "shm", "shm", "", 1, 0, 0) != 0);
    assert(qvBenchFailures("egl", "shm", "shm", "EGL unavailable", 1, 1, 0) != 0);
    assert(qvBenchFailures("egl", "shm", "shm", "EGL unavailable", 1, 0, 1) != 0);
    assert(qvBenchFailures("shm", "shm", "shm", "", 0, 0, 0) == 0);
    assert(qvBenchFailures("shm", "shm", "shm", "", 1, 0, 0) != 0);
    assert(qvBenchFailures("egl", "egl", "egl", "", 0, 30, 0) == 0);
    assert(qvBenchFailures("egl", "egl", "egl", "", 1, 30, 0) != 0);
    puts("PASS: expected fallback, unexpected renderer, backend errors, no fallback masking after swaps/checks");
}
