# Original portable system-symbol regressions

Public identifiers/configuration interfaces come from Apple public documentation (clean-room rung3). The14allowlisted identifiers are documented in the primary public references below; no Apple font/asset outlines, guest resources or runtime argument contents were inspected. All normalized geometry is original Qvolution source using existing NSBezierPath and block-backed NSCustomImageRep, with no new image codec or third-party asset dependency. This is portable semantic artwork, not SF Symbols pixel/metric parity.

Run appkit-semantic-symbols with no arguments. Root's original stage18 baseline: exit1,1.818160662s,shutdown0; unknown nonempty name incorrectly returns image and plus/minus/gear differ by0pixels. Nonempty output/copy/config controls pass. The strengthened fixture compares reconfigured plus/minus using the SAME merged configuration, and nested-pool gear/minus with the SAME scale, so size differences cannot conceal lost identity. Root strict baseline: exit1,1.88787571s,shutdown0; four failures for unknown, identical basic glyphs, same-configuration identity and lifetime identity.

Run appkit-symbol-rendering with no arguments. Original independent region checks require plus's vertical arm, both horizontal arms and gear's center hole; a constant glyph fails. It also checks14known symbols/unknown variant, actual ink change with weight, immutable palette-array snapshot and red/blue pixels on two gear layers, monochrome-vs-palette template intent, and one retained destination context across Aqua repeats, Dark repeats and Aqua restoration. The destination/cache key remains eligible for reuse; no cache-hit counter is claimed. Root stage19 before: exit1,1.942165934s,shutdown0; eight failures in arm geometry/gear hole/unknown variant/weight/palette/template intent/dark cache. All14known nonempty ink controls pass; light/heavy718identical ink pixels and red/blue0. Candidate runtime pending. After review, additional same-destination repeat/restoration checks replaced the former new-context-per-draw appearance test; the exact final stage20 baseline exit1 in1.949478545s/shutdown0 reproduces the same8failures while all3same-destination repeat/restoration controls pass. The earlier stage19 record remains separate.

Sizing retains the existing project policy (13point fallback,0.8/1/1.3scale factors,+3padding); stroke width is bounded original optical policy, not measured native weight. One-layer symbols use first palette color; gears and folder-plus have two semantic layers, second color falling back to first. Third palette entries have no layer here. Monochrome draws current semantic labelColor and sets template intent; this does not implement selected/disabled control template-mask tint. Palette images retain their explicit colors and are not marked template. Every catalog entry is static; variableValue does not turn it into a variable symbol. Unknown variants return nil rather than suffix synthesis.

Existing destination-transform/appearance-aware block image cache is reused. More extensive2x/crop/flip/fraction tests and actual control board/client raster remain follow-up gates. No native presentation, Keka icon coverage or full SF catalog qualification is claimed by these CPU raster fixtures.

## Primary identifier references

- https://developer.apple.com/documentation/macos-release-notes/macos-big-sur-11_0_1-release-notes — gearshape and gearshape.2
- https://developer.apple.com/documentation/swiftui/view/symbolvariant(_:) — folder/person/list.bullet
- https://developer.apple.com/documentation/swiftui/symbolvariants/rectangle-swift.type.property — plus/minus/xmark/checkmark
- https://developer.apple.com/documentation/swiftui/view/findnavigator(ispresented:) — magnifyingglass
- https://developer.apple.com/tutorials/sample-apps/capturingphotos-browsephotos — trash
- https://developer.apple.com/videos/play/wwdc2020/10207/ — folder.badge.plus
- https://developer.apple.com/documentation/UIKit/configuring-and-displaying-symbol-images-in-your-ui — multiply.circle.fill; public symbol rendering concepts, not implicit UIKit-to-AppKit pixel parity
- https://developer.apple.com/documentation/swiftui/view/menuindicator(_:) — chevron.backward
- https://developer.apple.com/documentation/AppKit/NSImage/SymbolConfiguration-swift.class — immutable attribute and palette configuration
