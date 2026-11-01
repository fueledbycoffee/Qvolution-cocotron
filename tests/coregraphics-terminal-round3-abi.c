/* ABI/layout checks derived only from SPEC.md Round 3, H1-H5 (rung 2).
 * Radius-only and integer-style blur declarations are explicit GUESS, rung 6.
 * Compile this with the production Darwin target flags on i386 and x86_64. */
#include <CoreGraphics/CoreGraphicsPrivate.h>
#include <HIServices/Processes.h>
#include <stddef.h>

#define ABI(name, result, ...) \
    _Static_assert(__builtin_types_compatible_p(__typeof__(&name), result (*)(__VA_ARGS__)), #name " ABI")
ABI(CGContextSetAllowsAntialiasing, void, CGContextRef, bool);
ABI(CGContextGetAllowsAntialiasing, bool, CGContextRef);
ABI(CGContextSetShouldAntialias, void, CGContextRef, bool);
ABI(CGContextGetShouldAntialias, bool, CGContextRef);
ABI(CGContextSetAllowsFontSmoothing, void, CGContextRef, bool);
ABI(CGContextGetAllowsFontSmoothing, bool, CGContextRef);
ABI(CGContextSetShouldSmoothFonts, void, CGContextRef, bool);
ABI(CGContextGetShouldSmoothFonts, bool, CGContextRef);
ABI(CGContextSetFontSmoothingStyle, void, CGContextRef, uint32_t);
ABI(CGContextGetFontSmoothingStyle, uint32_t, CGContextRef);
ABI(CGSDefaultConnectionForThread, CGSConnectionID, void);
ABI(CGSSetSecureEventInput, CGError, CGSConnectionID, bool);
ABI(CGSSetWindowBackgroundBlurRadius, CGError, CGSConnectionID, CGSWindowID, int);
ABI(CGSSetWindowBackgroundBlurRadiusWithOpacityHint, CGError, CGSConnectionID, CGSWindowID, int, float);
ABI(CGSSetWindowBackgroundBlurRadiusStyle, CGError, CGSConnectionID, CGSWindowID, int, int);
ABI(CPSGetCurrentProcess, OSErr, CPSProcessSerNum *);
ABI(CPSStealKeyFocus, OSErr, CPSProcessSerNum *, uint32_t);
ABI(CPSReleaseKeyFocus, OSErr, CPSProcessSerNum *);
_Static_assert(sizeof(CGSConnectionID) == 4 && sizeof(CGSWindowID) == 4, "CGS identifiers");
_Static_assert(sizeof(CGError) == 4 && sizeof(OSErr) == 2, "status widths");
_Static_assert((OSErr)-1 < 0, "OSErr signedness");
_Static_assert(sizeof(bool) == 1 && sizeof(float) == 4, "scalar widths");
_Static_assert(sizeof(CPSProcessSerNum) == 8, "CPS extent");
_Static_assert(_Alignof(CPSProcessSerNum) == _Alignof(uint32_t), "CPS alignment");
_Static_assert(offsetof(CPSProcessSerNum, highLongOfPSN) == 0, "CPS high field");
_Static_assert(offsetof(CPSProcessSerNum, lowLongOfPSN) == 4, "CPS low field");
_Static_assert(sizeof(ProcessSerialNumber) == 8, "public PSN extent");
