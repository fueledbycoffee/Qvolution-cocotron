/* Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 of the Software, and to permit persons to whom the Software is furnished to do
 so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE. */

#import <CoreGraphics/CGWindowPrivate.h>
#import <Onyx2D/O2Geometry.h>
#import <Onyx2D/O2SurfaceDamage.h>
#include <wayland-util.h>

#import "WaylandDisplay.h"
#import "WaylandFullscreen.h"
#import <AppKit/NSTitlebarRenderer.h>

@class WaylandClientCapture;
@class NSWindow, O2Context, WaylandSubWindow, CAWindowOpenGLContext;
struct wl_egl_window;

struct WaylandBuffer {
    struct wl_proxy *buffer;
    void *data;
    size_t size;
    int32_t width, height;
    uint32_t format;
    BOOL busy; // attached and not yet released by the compositor
    O2SurfaceDamage stale; // backing-store pixels changed since this buffer was filled
};

// A top-level window: an xdg_toplevel whose content is Onyx2D's CPU rendering,
// copied into wl_shm buffers.
@interface WaylandWindow : CGWindow {
    NSWindow *_delegate;
    WaylandClientCapture *_clientCapture;
    uint64_t _clientPresents;
    BOOL _captureRequested;
    WaylandDisplay *_display;
    BOOL _invalidated;
    NSMutableArray *_subwindows; // nonretained pointers; children retain their parent
    int _level;
    NSUInteger _styleMask;
    CGSBackingStoreType _backingType; // stored, but ignored
    O2Context *_context;
    NSMutableDictionary *_deviceDictionary;
    // AppKit screen coordinates. The origin is only what AppKit asked for: the
    // compositor places the window and doesn't say where.
    O2Rect _frame;
    NSString *_title;
    CGPoint _lastMotionPos;
    BOOL _isOpaque;
    BOOL _hasShadow;

    struct wl_proxy *_surface;
    struct wl_proxy *_xdgSurface;
    struct wl_proxy *_toplevel;
    struct wl_proxy *_popup;
    WaylandWindow *_popupParent;
    uint32_t _popupGrabSerial;
    uint32_t _repositionToken;
    int32_t _pendingPopupX, _pendingPopupY;
    struct wl_proxy *_decoration;
    struct wl_proxy *_frameCallback;
    struct WaylandBuffer _buffers[2];
    int32_t _pendingWidth, _pendingHeight;
    BOOL _pendingActivated;
    BOOL _mapped;
    BOOL _configured;
    BOOL _needsPresent;
    BOOL _activated;
    NSMutableSet *_surfaceOutputs;
    int32_t _bufferScale; // Integer output fallback, not fractional wire scale.
    uint32_t _preferredScale120, _renderScale120;
    struct wl_proxy *_fractionalScale, *_viewport;
    BOOL _scaleUpdatePending, _subwindowRedrawPending, _subwindowRedrawNeeded;
    BOOL _clientDecorated, _pendingClientDecorated;
    BOOL _decorationsDirty;
    BOOL _maximized, _pendingMaximized;
    BOOL _pendingTiled;
    // Logical shadow margin around the visible window; 0 when undecorated,
    // maximized or tiled.
    CGFloat _margin;
    O2Rect _sentGeometry;
    NSTitlebarTracker _buttonTracker;
    // Non-NULL only until this content press is released, loses focus, or is
    // consumed by an interactive move. The seat owns the serial's scope.
    struct wl_proxy *_appMoveSeat;
    uint32_t _appMoveSerial;
    BOOL _appMoveDragged;
    NSTitlebarButton _shownPressed;
    BOOL _buttonHover;
    // Whether the current xdg_toplevel was asked for fullscreen, what the last
    // configure said, and the size to go back to.
    BOOL _fullscreenRequested, _pendingFullscreen, _fullscreenRecheckPending;
    WaylandFullscreenTracker _fullscreenTracker;
    BOOL _configureUpdatePending;
    NSUInteger _surfaceGeneration;
    BOOL _eglRequested, _eglVerify, _eglCorrupt, _eglFailed;
    CGLContextObj _eglContext;
    void *_eglDrawable;
    struct wl_egl_window *_eglWindow;
    CAWindowOpenGLContext *_eglPresenter;
    uint64_t _eglSwaps, _eglChecks, _eglBytes, _eglFailures;
    int32_t _eglWidth, _eglHeight;
    // What the compositor holds: the last committed shm buffer's size and format.
    int32_t _committedWidth, _committedHeight;
    uint32_t _committedFormat;
    NSTitlebarFrame _maskedFrame; // frame the content corners were last cut for
    BOOL _maskedFrameValid, _damageVerify;
    uint64_t _damageRects, _damagePixels, _copiedPixels, _wholeDamagePresents;
    uint64_t _verifiedPresents, _staleVerifiedPresents;
    // Set when EGL was requested but cannot present this window; it then uses wl_shm.
    NSString *_eglFallbackReason;
    uint64_t _eglFullUploads, _eglPartialUploads, _eglLastUploadBytes;
    // Backing-surface damage since the last present; none reported means everything.
    CGRect _damage[16];
    unsigned _damageCount;
    BOOL _damageAll;
    // Opt-in present timing (DARLING_APPKIT_PRESENT_TIMING=1).
    BOOL _presentTiming;
    uint64_t _presentsTimed, _presentNanoseconds, _lastPresentNanoseconds, _maxPresentNanoseconds;
}

- (instancetype) initWithDelegate: (NSWindow *) delegate;

- (O2Rect) frame;
- (O2Context *) cgContext;
- (struct wl_proxy *) surface;
- (struct wl_proxy *) ensureSurface;
- (WaylandDisplay *) waylandDisplay;
- (void) addSubwindow: (WaylandSubWindow *) child;
- (void) removeSubwindow: (WaylandSubWindow *) child;
- (void) updateSubwindows;
- (void) scheduleSubwindowRedraw;
- (void) stackSubwindows;
- (BOOL) isInvalidated;
- (BOOL) isMapped;
- (int32_t) bufferScale;
- (uint32_t) renderScale120;
- (uint32_t) refreshMillihertz;
- (void) preferredScaleChanged: (uint32_t) scale120;
- (void) outputRemoved: (struct wl_proxy *) output;
- (void) scheduleScaleUpdate;
// An output was added, removed or changed mode: re-decide fullscreen once the
// events of the batch (including a configure for the new size) are in.
- (void) outputsChanged;
- (BOOL) isPopup;
- (WaylandWindow *) popupParent;
- (uint32_t) popupGrabSerial;
- (struct wl_proxy *) xdgSurface;
- (void) unmap;
- (NSDictionary *) eglPresentationStatistics;
// Adds a rectangle of the backing surface (pixels, origin at the top row) that
// changed since the last present. Presents with no reported damage are treated
// as whole-surface changes, so a caller must report every change or none.
- (void) addDamageRect: (CGRect) rect;
- (NSPoint) contentOffset;
- (BOOL) isDecorationPoint: (CGPoint) point;
// The content origin relative to the xdg window geometry (the visible window),
// which is what popup positioners and popup configures are relative to.
- (NSPoint) geometryContentOffset;
// Surface-local pointer position, for traffic-light hover feedback.
- (void) decorationPointerMoved: (CGPoint) point;
- (void) decorationPointerLeft;
- (void) appMoveMotion: (BOOL) leftHeld;
- (void) appMoveButton: (uint32_t) button pressed: (BOOL) pressed
                serial: (uint32_t) serial atPoint: (CGPoint) point;
- (void) cancelAppMovePress;
- (void) beginWindowDrag;
- (void) performWindowDragWithEvent: (NSEvent *) event;
- (BOOL) decorationButton: (uint32_t) button pressed: (BOOL) pressed
                   serial: (uint32_t) serial atPoint: (CGPoint) point;

// Converts a surface-local point (origin top left) to window coordinates.
- (NSPoint) transformPoint: (CGPoint) surfacePoint;
- (void) setLastKnownCursorPosition: (CGPoint) point;

- (void) handleEvent: (uint32_t) opcode
                kind: (WaylandObjectKind) kind
               proxy: (struct wl_proxy *) proxy
           arguments: (union wl_argument *) args;

@end
