# Qvolution P2 UI font policy

Source: approved `parallel/visual-theme/SPEC.md` sections 6 and P2, amended by
this lane's instruction to use installed host fonts and never download/vendor
Inter. Typography sizes and fallbacks are Qvolution design policy, not measured
Apple software. API contracts are rung 2 (`AppKit/NSFont.h`, `CoreText/CTFont.h`)
and rung 3 (Apple's public NSFont/UI typography documentation named by the spec).
GNOME `org.gnome.desktop.interface font-name` is a string in the host's public
`/usr/share/glib-2.0/schemas/org.gnome.desktop.interface.gschema.xml:107`.
The installed public Pango API documentation at
`/usr/share/gir-1.0/Pango-1.0.gir` (`pango_font_description_from_string`)
specifies the description grammar; native tests compare extracted families
against that public Pango API. Fontconfig `<alias>`/`prefer` behavior is its installed public user manual,
`/usr/share/doc/fontconfig/fontconfig-user.html`. D-Bus fixed-arity iterator API
comes from public `dbus-message.h`; portal Settings Read comes from the public
freedesktop Settings contract and the spec. The installed public portal release
notes `/usr/share/doc/xdg-desktop-portal/NEWS.md.gz` (1.17.0 and 1.17.1) specify
that supported deprecated `Read` returns a variant inside a variant, whereas
`ReadOne` returns a single variant. We retain `Read` for older portal support;
the bounded decoder accepts both forms. The live fake checks path/destination and exact namespace/key args. It covers
the specified nested `Read` reply plus a single-variant compatibility reply
and a malformed value; both shapes also have direct decoder tests.
A socket-free queue regression runs the actual fake service with real libdbus
messages and mocked connection I/O: a prequeued NameAcquired signal and Read
must be popped before a blocking wait. The old wait-before-pop loop could delay
an already queued request by 1000ms, beyond the unchanged 250ms reader deadline.
This regression is supplementary; `--portal` still requires a real private bus.
No Apple binary was inspected.

The policy reads the portal once per process when Fontconfig is initialized.
It removes Pango-style size/style suffixes, ignores GNOME's point size, selects
an exact family (portal, installed Inter, Adwaita Sans, Cantarell, Noto Sans,
then fontconfig sans-serif), and installs in-memory aliases. Fixed pitch uses
DejaVu Sans Mono, then monospace. Existing application font registration remains
in place. A marked `FcConfigAppFontAddDir` hook describes where a later,
user-approved runtime font installation belongs; there are no bundled fonts.

`tests/ui-font-policy-native.py` compiles the production C header with
ASan/UBSan and exercises real Fontconfig/FreeType, fallback-order controls,
Pango suffixes, alias XML escaping, real D-Bus variant parsing, and a host H
bitmap at 1x/2x. Synthetic fontconfig family names are explicitly test catalog
entries pointing to an existing open font; they do not pretend Inter is
installed. `--portal` additionally runs a real fake portal in dbus-run-session.
This extra test needs Unix sockets, which this sandbox blocks. The native H
raster is supplementary evidence, not AppKit acceptance.

`tests/appkit-ui-font-theme.m` is the guest acceptance fixture: actual NSFont
roles/aliases, O2Surface H cap-height 9 +/- 1 logical pixels, transparent and
black sample tolerances 2/255, panel and format-bar PNGs at 1x/2x, and static
control title-rectangle measurements for zero truncation. Each group must check
at least one label, to reject a vacuous pass. Editable document values and
scrolling matrix content are excluded from the static-label count. Save panel,
Font panel, alert and format bar need human inspection as well as the automated
measurements. Fixture PNGs and TextEdit screenshots still require a host run.

Coordination: font-ui-latency's 55bf7022 changes NSFontFamily catalog snapshots;
3ccb3261/a9fa2516 add diagnostics/fixtures. This lane changes no catalog/cache
implementation. NSFont now preserves the actual CoreText-selected graphics
face instead of resolving its full name again. Shared Fontconfig initialization
is synchronized so the policy strings/aliases publish together.

Remaining work: live font-name changes require restarting the app in P2.
GNOME text-scaling-factor (document-only) and QvolutionUIFontScale width tuning
are not implemented: CoreText matrices are currently identity-only; width
adjustments need matched layout/raster support and actual zero-truncation
measurements first. Do not shrink all fonts or nib frames to hide a fixture
failure. These limitations are explicit and are not claimed as accepted P2
visual behavior. No dark/chrome/control rendering change is included.
