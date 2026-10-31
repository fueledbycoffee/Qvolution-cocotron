# Inspector visual state and ruler context

Build the original `.m` client with AppKit and component-private headers. Run each mode with an existing caller-owned absolute directory for its own CPU captures:

```
appkit-inspector-visual-state state /absolute/owned/output
appkit-inspector-visual-state icons /absolute/owned/output
appkit-inspector-visual-state ruler /absolute/owned/output
appkit-inspector-visual-state transition /absolute/owned/output
```

The client creates a real window, rich text editor, inspector and ruler with three explicit tabs using a known open DejaVu font. `state` exercises actual `performClick:` actions, checks released B/I/U and alignment state and raster differences, then changes selection to check synchronization. `icons` checks real image glyphs and readable identities; raw single-letter titles are insufficient. Captures are own button/ruler CPU output, not desktop screenshots or GPU evidence.

`ruler` records actual ruler client, marker count, required thickness, ruler/clip/inspector frames and own CPU captures while moving window focus from the editor to a formatting control, performing its genuine action and moving focus to an unrelated control. The format-focus phase should keep the editor's formatting ruler context; unrelated focus loss remains a control that clears it. This direct API test can reproduce focus/layout behavior but does not prove physical click delivery, pointer tracking timing, keyboard navigation or compositor presentation.

No source fix is implied merely by compiling this fixture. Run against the installed baseline before implementation, inspect actual failures/captures, and keep before/after runtime provenance. Icon geometry and focus-context UX are explicit Qvolution policy, not native macOS implementation facts. No Apple artwork or binary internals are used.

`transition` observes the synchronous end-editing notification and records/draws the ruler during the focus transfer, rather than relying only on its final appearance. It also checks rejected becoming, delegate-vetoed resignation, nested focus takeover and observer-driven inspector detachment. These controls use original project classes and public Objective-C facilities, not vendor internals.

The implementation scopes a proposed responder to each window focus transfer. The editor preserves its ruler only for its currently linked formatting inspector, before the synchronous editing notification. Completion reconciles failed or reentrant transfers; actual keyboard focus remains with the formatting button. State and original artwork are private inspector policy; generic buttons keep their existing behavior.

### Baseline evidence and limits

The root runner executed the original client against installed stage24, with exact clean guest shutdown after every run. The original v3 `state` run aborted (134) because the fixture sent `isHighlighted` to NSButton rather than its cell. That artifact is preserved and is not a product failure. Corrected v5 uses the declared NSCell method and compiled successfully. Its actual baseline state run failed nine assertions: model On/Off toggles passed, while released visual indicators and raster distinctions failed. The original baseline icons run failed seven assertions (missing images), ruler failed four (31→16 pixel collapse on format focus, then 31 after action), and transition failed four, including synchronous marker/geometry loss, nested takeover and detachment.

Immutable runner records are `logs/inspector-state-v5-before-stage24-next.json` and `logs/inspector-{icons,ruler,transition}-before-stage24-next.json` in the Qvolution project. Original CPU outputs and frozen input hashes are retained in `Qvolution-work/parallel/root-probes/stage24-next-before`. These paths describe external review evidence, not checked-in generated assets.

The source-extracted predicate check is reproducible with `python3 tests/inspector-active-state-source.py --baseline 20060e56` (expected failure: releasedOff=0/releasedOn=0/pressedOff=1) and without that argument on the candidate (expected success: 0/1/1). It extracts the actual inspector type, cell masks and visual predicate, not a substitute implementation. The three modified production translation units compiled with the actual component fat-build recipe; root and two independent peers reviewed the source. Candidate guest execution, physical input, compositor presentation, HiDPI/theme appearance and performance remain pending. No runtime after-pass or GPU claim is made here.
