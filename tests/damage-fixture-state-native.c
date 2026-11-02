#include "damage-fixture-state.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    uint64_t previous = 0;
    unsigned quiet = 0;
    // Reproduces Stage41e's EGL capture: key=YES, inactive chrome, idle frames.
    for (unsigned i = 0; i < 100; i++)
        assert(!DamageFixtureSettled(true, false, 4, &previous, &quiet));
    for (unsigned i = 0; i < 24; i++)
        assert(!DamageFixtureSettled(true, true, 4, &previous, &quiet));
    assert(DamageFixtureSettled(true, true, 4, &previous, &quiet));
    assert(!DamageFixtureSettled(true, true, 5, &previous, &quiet));
    assert(quiet == 0);
    for (unsigned i = 0; i < 24; i++)
        assert(!DamageFixtureSettled(true, true, 5, &previous, &quiet));
    assert(!DamageFixtureSettled(false, true, 5, &previous, &quiet));
    assert(quiet == 0);
    for (unsigned i = 0; i < 24; i++)
        assert(!DamageFixtureSettled(true, true, 5, &previous, &quiet));
    assert(!DamageFixtureSettled(true, false, 5, &previous, &quiet));
    assert(quiet == 0);
    for (unsigned i = 0; i < 24; i++)
        assert(!DamageFixtureSettled(true, true, 5, &previous, &quiet));
    assert(DamageFixtureSettled(true, true, 5, &previous, &quiet));
    puts("PASS damage fixture compositor activation and settling");
}
