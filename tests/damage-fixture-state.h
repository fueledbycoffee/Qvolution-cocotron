#ifndef DAMAGE_FIXTURE_STATE_H
#define DAMAGE_FIXTURE_STATE_H
#include <stdbool.h>
#include <stdint.h>

// NSWindow's key status can precede (and outlive) compositor activation.
// Cross-renderer captures need both, with no intervening presentation.
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
