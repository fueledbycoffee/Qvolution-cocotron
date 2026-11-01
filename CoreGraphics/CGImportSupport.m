#import <CoreGraphics/CoreGraphics.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>

// No display capture or Metal device association is provided by this backend.
CGImageRef CGDisplayCreateImage(CGDirectDisplayID display) { return NULL; }
CGImageRef CGDisplayCreateImageForRect(CGDirectDisplayID display, CGRect rect) { return NULL; }
void *CGDirectDisplayCopyCurrentMetalDevice(CGDirectDisplayID display) { return NULL; }
bool CGPreflightScreenCaptureAccess(void) { return false; }
bool CGRequestScreenCaptureAccess(void) { return false; }

CFArrayRef CGWindowListCopyWindowInfo(CGWindowListOption options, CGWindowID relative)
{
    // NULL denotes inability to obtain the list, not an empty desktop.
    return NULL;
}
CFArrayRef CGWindowListCreateDescriptionFromArray(CFArrayRef windows) { return NULL; }
CGImageRef CGWindowListCreateImageFromArray(CGRect bounds, CFArrayRef windows,
    CGWindowImageOption options) { return NULL; }

// GUESS: audit-only private names (Spotify); no private layout or argument
// contents are inspected, and no mutation is reported as successful.
bool CGDisplayUsesForceToGray(void) { return false; }
bool CGFontRenderingGetFontSmoothingDisabled(void) { return true; }
void *CGRegionCreateWithRect(const CGRect *rect) { return NULL; }
CGError CGSSetWindowCaptureExcludeShape(CGSConnectionID cid, CGSWindowID wid, void *region)
{ return kCGErrorNotImplemented; }
CGError CGSSetWindowTransform(CGSConnectionID cid, CGSWindowID wid, CGAffineTransform transform)
{ return kCGErrorNotImplemented; }
CGError CGSSetWindowWarp(CGSConnectionID cid, CGSWindowID wid, int width, int height, const void *mesh)
{ return kCGErrorNotImplemented; }
