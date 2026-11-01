# Explicit Ubuntu family routing

The text inspector calls NSFontManager convertFont:toFamily:, then trait
conversions for Bold/Italic. The backend formerly substituted even installed
family names before catalog enumeration. A host rule assigning Ubuntu to a UI
family therefore made the Ubuntu catalog contain another font's PostScript
identities. The existing conservative conversions could retain the wrong face
or refuse a change. Preserve exact installed families before alias matching.

Provenance: rung 2, existing NSFontManager.h/NSFontFamily and X11Display catalog
contracts, and vendored Fontconfig/FreeType headers. Rung 4, own native fixture
with private Fontconfig/Open Ubuntu and DejaVu fonts. The host text configuration
~/.config/fontconfig/conf.d/60-q-ui-fonts.conf assigns Ubuntu/Ubuntu Sans to System
Font. Its proprietary font assets were neither opened nor used by these tests.
This is a backend routing policy for explicit document families, not a claim
about undocumented Apple matching algorithms. Generic/missing family aliases
continue through Fontconfig. UI role selection remains separate.

Run from Qvolution-work:

    parallel/font-regression/run-native.sh

The native test extracts literal production C routing, sorting, variable-trait
and exact-PS loader bodies. Only NSString argument/result transport is adapted.
It uses real private Fontconfig and FreeType, including raw file/index controls
and rendered WiAm widths. It does not execute NSFontManager Objective-C APIs.
The six installed Ubuntu instances cover Regular/Bold/Italic/Bold Italic and
Medium/Light. No font assets are committed or downloaded.

Stage24 fix point 16afdc06, Stage40 1c154eb2, Stage41b a8091e98, theme-p2 9a22754c
and integrated ae96125f all pass clean-config controls and fail 24 assertions
under the same strong substitution. The patched source passes both. These are
native source revision comparisons, not historical full-runtime bisect results;
there is no first bad source commit in this requested range. The Stage24 manager
14c68187, variable traits 1c4d7aef and pattern index 16afdc06 fixes remain ancestors.

appkit-ubuntu-family-routing.m is the actual manager/inspector fixture, built for
the Darling runtime. It checks resolved PS/catalog file/actual FT instance,
CT advances and own O2Surface raster widths against independently opened FT
faces, including family selection and real inspector Bold actions. Medium/Light
use explicit toFace: because the existing manager integer-weight API is incomplete.
The runner executes it with clean and substituted open-font-only policies, then
opens source-built TextEdit with a fresh owned prefix. Guest API/raster results
and manual TextEdit acceptance remain unverified until that script runs on the
host. LeakSanitizer is disabled in native tests because this sandbox cannot
suspend threads; ASan and UBSan remain enabled.
