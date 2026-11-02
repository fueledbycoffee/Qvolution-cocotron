#ifndef FIXTURE_WINDOW_FRAME_SETTLE_STATE_H
#define FIXTURE_WINDOW_FRAME_SETTLE_STATE_H
// Fixture policy, not a protocol guarantee: observe >=1s and >=0.5s of quiet.
typedef struct {
    double x, y, width, height, contentWidth, contentHeight, scale;
    int configured, key;
} FixtureFrameSample;
typedef struct {
    FixtureFrameSample previous;
    double began, changed;
    int sampled;
} FixtureFrameState;
static int fixtureFrameObserve(FixtureFrameState *state, FixtureFrameSample f, double now) {
    if (!state->sampled) {
        state->sampled = 1; state->began = state->changed = now; state->previous = f;
    }
    FixtureFrameSample p = state->previous;
    if (f.x != p.x || f.y != p.y || f.width != p.width || f.height != p.height ||
        f.contentWidth != p.contentWidth || f.contentHeight != p.contentHeight ||
        f.scale != p.scale || f.configured != p.configured || f.key != p.key)
        state->changed = now;
    state->previous = f;
    if (now - state->began >= 5) return -1;
    return f.configured && f.key && now - state->began >= 1 && now - state->changed >= .5;
}
#endif
