# Rich-text inspector and formatting prerequisites

Build and run these source fixtures against the staged AppKit in a dedicated
prefix with normal Objective-C loading (no diagnostic DYLD overrides), then
shut down that exact prefix:

- `appkit-text-font-selection.m`: full-selection font conversion, end-caret
  typing font conversion, and empty-document font conversion. The parent fails
  on the full selection with NSInvalidArgumentException.
- `appkit-text-underline-typing.m`: empty/end-caret underline toggle, subsequent
  typed character styles, selection toggle and formatting delegate veto. The
  parent fails because the end-caret action leaves typing underline enabled.
- `appkit-text-inspector-bar.m`: actual controls/actions, selected text versus
  typing attributes, selection state synchronization, read-only state, rich/plain
  and explicit toggles, repeated-setter identity/no duplicate accessory, wide and
  narrow layout, space reserved above ruler/content, nested page text views,
  and accessory removal during text-view detach. The parent lacks the inspector
  entirely and should fail its initial existence assertion.

Link each executable with AppKit. They create real AppKit views without ordering
a window, so actual mouse interaction and visual layout still need a TextEdit
rich-document check. Only the font and underline parent failures have been run
by the coordinating agent at implementation time; candidate runtime tests and
inspector parent execution are pending integration. Production modified objects
and all fixtures compile into isolated outputs using the existing Darling compile
recipes; no shared build, stage, or active source was changed by this task.

The first inspector includes font family, common point sizes, bold, italic,
underline and left/center/right alignment. It is intentionally basic: text color,
background color, arbitrary size entry, strike-through, lists, line spacing,
advanced font styles, mixed-selection state, and modern macOS visual fidelity
are not implemented here. Existing font-action undo behavior is unchanged;
selection underline continues through its existing undo-aware attribute helpers.
The active page can take over the existing bar when becoming first responder;
full multi-page editing and view archiving need broader application acceptance.

Provenance: vendored NSTextView, NSFontManager, NSScrollView, NSControl and
paragraph-style interfaces and source, plus TextEdit DocumentWindowController's
setUsesInspectorBar:rich request (rung 2). Baseline observations use source-built
AppKit public actions (rung 4). Private inspector class/identifiers and layout
metrics are new implementation details, not claims about Apple's internals.
No Apple binary inspection, copied UI artwork, or compatibility-symbol stubs.
