// Source-owned fixture policy: menu handoff, configure and key churn delay sampling.
#include "window-frame-settle-state.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    FixtureFrameState s = {0};
    FixtureFrameSample f = {100, 100, 720, 366, 720, 340, 1, 1, 1};
    assert(fixtureFrameObserve(&s, f, 0) == 0);
    assert(fixtureFrameObserve(&s, f, .25) == 0); // initial quiet is insufficient
    f.height -= 26;
    assert(fixtureFrameObserve(&s, f, .8) == 0);
    assert(fixtureFrameObserve(&s, f, 1.0) == 0);
    assert(fixtureFrameObserve(&s, f, 1.31) == 1);
    s = (FixtureFrameState){0};
    f.configured = 0;
    assert(fixtureFrameObserve(&s, f, 0) == 0);
    assert(fixtureFrameObserve(&s, f, 1.1) == 0);
    f.configured = 1;
    assert(fixtureFrameObserve(&s, f, 1.2) == 0);
    f.key = 0;
    assert(fixtureFrameObserve(&s, f, 1.6) == 0);
    f.key = 1;
    assert(fixtureFrameObserve(&s, f, 2.0) == 0);
    assert(fixtureFrameObserve(&s, f, 2.51) == 1);
    s = (FixtureFrameState){0};
    assert(fixtureFrameObserve(&s, f, 0) == 0);
    f.scale = 2;
    assert(fixtureFrameObserve(&s, f, .9) == 0);
    f.contentHeight -= 26;
    assert(fixtureFrameObserve(&s, f, 1.3) == 0);
    assert(fixtureFrameObserve(&s, f, 1.81) == 1);
    s = (FixtureFrameState){0};
    assert(fixtureFrameObserve(&s, f, 0) == 0);
    for (int i = 1; i < 100; i++) {
        f.x += 1;
        assert(fixtureFrameObserve(&s, f, i * .05) == 0);
    }
    assert(fixtureFrameObserve(&s, f, 5.0) == -1);
    puts("PASS frame settle: delayed 26px shrink, configure/key/scale/content churn, bounded failure");
}
