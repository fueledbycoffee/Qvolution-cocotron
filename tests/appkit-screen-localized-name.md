# Screen display-name compatibility

Apple's public NSScreen.localizedName property is a read-only display-name string,
available from macOS 10.15. The repository's public screen header now declares it.
Wayland screens use an immutable snapshot of compositor-reported metadata:
nonempty xdg-output description, otherwise wl_output make/model, otherwise
xdg-output name. Identical make/model strings are not duplicated; surrounding
whitespace is removed. This selection order is conservative project policy,
not a claim that it reproduces Apple's naming or localization algorithm. No
physical manufacturer/model is invented or independently verified.

When metadata is empty, absent or invalid UTF8, base NSScreen returns the explicit
project fallback `Display <numeric display ID>`. Non-Wayland backends inherit
that fallback unless they supply their own name. Existing geometry, display IDs,
color space, scaling and protocol binding/version choices are unchanged. The
fallback is currently English; compositor-provided strings are not translated.

Wire strings are decoded through checked CFString UTF8 creation and copied during
the event. Pending make/model becomes current only at the existing wl_output.done
boundary (immediately for core v1). Already-bound xdg-output name/description becomes
current at xdg-output.done for versions below 3, or wl_output.done for version 3.
Cached screens are invalidated by existing publication/removal paths. Each rebuilt
WaylandScreen copies its display name; previously retained screens/names stay valid
and unchanged after new pending metadata, publication, output removal and pool drain.
No output name or physical metadata is printed in fixture/public logs.

Original `appkit-screen-localized-name.m` runs against actual NSScreen/WaylandScreen,
checks selector availability, nonempty stable strings, numeric fallback and retained
name lifetime. The unchanged parent failed selector availability: exit 1 in 1.717s,
exact-prefix shutdown 0. `appkit-screen-name-metadata.m` injects only original
synthetic output events into the actual own backend, with no fake wl_proxy/XID.
It temporarily saves/restores its process's output array and creates no windows.
It exercises copied mutable wire buffers, both done policies, v1 immediate
publication, cached snapshot immutability, Unicode, empty/nil/invalid UTF8, removal
and screen/name lifetime. This is not a physical compositor hotplug acceptance test.
Assertions are explicit CHECKs independent of NDEBUG.

Both production objects compile using copied real fat-target recipes; both original
fixture binaries compile/link. Candidate guest execution and KeePassXC retake remain
coordinator-owned staging gates. No application qualification is implied.

Provenance: Apple's public API documentation (rung 3):
https://developer.apple.com/documentation/appkit/nsscreen/localizedname
Repository NSScreen/Wayland pending/done/cache ownership and vendored protocol
interfaces (rung 2); public open-source Wayland XML geometry and xdg-output event
specifications. Original source fixtures are rung 4 after coordinator execution.
No Apple binary, SDK implementation, vendor resource or private display metadata
was inspected/copied into this implementation.
