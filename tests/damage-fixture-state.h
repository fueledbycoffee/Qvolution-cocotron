#ifndef DAMAGE_FIXTURE_STATE_H
#define DAMAGE_FIXTURE_STATE_H
#include <stdbool.h>
#include <stdint.h>

// Verify uses declared key/chrome appearance, independent of compositor focus.
// Wait for the initial display to settle before damage mutations start.
static inline bool DamageFixtureSettled(bool key, bool activated, uint64_t presents,
                                        uint64_t *previous, unsigned *quietTicks) {
    if (!key || !activated || presents != *previous) {
        *previous = presents;
        *quietTicks = 0;
        return false;
    }
    return ++*quietTicks >= 25;
}
#endif
