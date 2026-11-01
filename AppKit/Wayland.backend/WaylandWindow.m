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

#define GL_GLEXT_PROTOTYPES 1
#import "WaylandWindow.h"
#import "WaylandClientCapture.h"
#import <OpenGL/CGLInternal.h>
#import <OpenGL/glext.h>
#import <QuartzCore/CAWindowOpenGLContext.h>
#import "WaylandSubWindow.h"
#import "WaylandLibrary.h"
#import "../X11.backend/X11GlobalMenu.h"
#import "WaylandProtocol.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSWindow-Private.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSAppearance.h>
#import <AppKit/NSStringDrawing.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSRunLoop.h>
#import <Onyx2D/O2Context_builtin_FT.h>
#import <Onyx2D/O2Surface.h>
#include <errno.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <limits.h>
#include <time.h>
#import "WaylandScale.h"
#include <math.h>
#import "../NSWindowFrameTrace.h"

// NSView replaces the user CTM whenever it locks focus. Keep scaling in the
// device transform, alongside Onyx2D's bottom-left to top-left conversion.
@interface WaylandDrawingContext : O2Context_builtin_FT
- (id) initWithSurface: (O2Surface *) surface logicalSize: (NSSize) logicalSize border: (CGFloat) border;
- (void) clipTitlebarAtHeight: (CGFloat) height;
@end

@implementation WaylandDrawingContext
- (id) initWithSurface: (O2Surface *) surface logicalSize: (NSSize) logicalSize border: (CGFloat) border {
    if ((self = [super initWithSurface: surface flipped: NO]) != nil) {
        CGFloat sx = O2SurfaceGetWidth(surface) / logicalSize.width;
        CGFloat sy = O2SurfaceGetHeight(surface) / logicalSize.height;
        _userToDeviceTransform = O2AffineTransformMake(sx, 0, 0, -sy, border * sx,
                                                       O2SurfaceGetHeight(surface) - border * sy);
        O2ContextSetCTM(self, O2AffineTransformIdentity);
    }
    return self;
}

- (void) clipTitlebarAtHeight: (CGFloat) height {
    O2Point edge = O2ContextConvertPointToDeviceSpace(self, O2PointMake(0, height));
    // NSStringDrawer lays out in a rectangle but does not clip glyph writes.
    // Keep title overhang out of content without changing byte glyph blending.
    O2RasterizerSetViewport(self, 0, 0, O2ImageGetWidth(_surface),
            MAX(0, MIN(O2ImageGetHeight(_surface), floor(edge.y))));
}
@end

@implementation WaylandWindow

static const CGFloat WaylandTitleHeight = NSTitlebarHeight;

static void sendRequest(struct wl_proxy *proxy, uint32_t opcode, uint32_t flags) {
    union wl_argument args[1] = {{.o = NULL}};
    WaylandMarshal(proxy, opcode, NULL, flags, args);
}

- (instancetype) initWithDelegate: (NSWindow *) delegate {
    if ((self = [super init]) == nil)
        return nil;

    NSString *renderer = [[[NSProcessInfo processInfo] environment] objectForKey:@"DARLING_APPKIT_RENDERER"];
    if (renderer && ![renderer isEqualToString:@"shm"] && ![renderer isEqualToString:@"egl"])
        [NSException raise:NSInvalidArgumentException format:@"Unknown DARLING_APPKIT_RENDERER: %@", renderer];
    _eglRequested = [renderer isEqualToString:@"egl"];
    _eglVerify = [[[[NSProcessInfo processInfo] environment] objectForKey:@"DARLING_APPKIT_EGL_VERIFY"] isEqualToString:@"1"];
    _eglCorrupt = [[[[NSProcessInfo processInfo] environment] objectForKey:@"DARLING_APPKIT_EGL_TEST_CORRUPT"] isEqualToString:@"1"];
    _damageVerify = [[[[NSProcessInfo processInfo] environment] objectForKey:@"DARLING_APPKIT_DAMAGE_VERIFY"] isEqualToString:@"1"];
    if (_eglCorrupt && !_eglVerify)
        [NSException raise:NSInvalidArgumentException format:@"EGL test corruption requires verification"];
    _presentTiming = [[[[NSProcessInfo processInfo] environment] objectForKey:@"DARLING_APPKIT_PRESENT_TIMING"] isEqualToString:@"1"];
    NSString *captureDirectory=[[[NSProcessInfo processInfo] environment] objectForKey:@"DARLING_APPKIT_CAPTURE_DIR"];
    _captureRequested=captureDirectory!=nil;
    if(captureDirectory) _clientCapture=[[WaylandClientCapture alloc] initWithDirectory:captureDirectory];
    _delegate = delegate;
    _level = [delegate level];
    _styleMask = [delegate styleMask];
    _backingType = (CGSBackingStoreType) [delegate backingType];
    _isOpaque = [delegate isOpaque];
    _deviceDictionary = [NSMutableDictionary new];
    _surfaceOutputs = [NSMutableSet new];
    _bufferScale = 1; _renderScale120 = 120;
    _display = [(WaylandDisplay *) [NSDisplay currentDisplay] retain];
    _subwindows = [NSMutableArray new];
    _buttonTracker.pressed = _shownPressed = NSTitlebarButtonNone;

    _frame = [delegate frame];
    _frame.size.width = MAX(_frame.size.width, 1.0);
    _frame.size.height = MAX(_frame.size.height, 1.0);

    [_display windowCreated: self];
    return self;
}

- (void) dealloc {
    [self invalidate];
    if (_fractionalScale) sendRequest(_fractionalScale, WP_FRACTIONAL_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    if (_viewport) sendRequest(_viewport, WP_VIEWPORT_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    if (_surface)
        sendRequest(_surface, WP_SURFACE_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    [_subwindows release];
    [_display release];
    [_deviceDictionary release];
    [_surfaceOutputs release];
    [_clientCapture release];
    [_title release];
    [_eglFallbackReason release];
    [super dealloc];
}

- (void) invalidate {
    // Like X11Window, this can run several times.
    if (_invalidated) return;
    _invalidated = YES;
    [_context release];
    _context = nil;

    [_delegate platformWindowDidInvalidateCGContext: self];
    _delegate = nil;

    [self unmap];
    if (_display != nil) {
        [_display windowDestroyed: self];
        // Children retain this window until their EGL surfaces are released.
        // Keep the native parent surface/display alive for that whole lifetime.
    }
}

- (void) setDelegate: (id) delegate {
    _delegate = delegate;
}

- (id) delegate {
    return _delegate;
}

- (void) syncDelegateProperties {
}

- (struct wl_proxy *) surface {
    return _surface;
}

- (struct wl_proxy *) ensureSurface {
    if (!_surface && !_invalidated) {
        union wl_argument args[] = {{.o = NULL}};
        _surface = WaylandCreateObject(_display->_compositor, WP_COMPOSITOR_CREATE_SURFACE,
            &wl_surface_interface, args, WaylandObjectSurface, self);
        _fractionalScale = [_display newFractionalScaleForSurface: _surface owner: (id)self];
        if (_fractionalScale) {
            union wl_argument viewportArgs[] = {{.o = NULL}, {.o = (struct wl_object *)_surface}};
            _viewport = WaylandCreateObject(_display->_viewporter, WP_VIEWPORTER_GET_VIEWPORT,
                &wp_viewport_interface, viewportArgs, 0, nil);
        }
    }
    return _surface;
}
- (WaylandDisplay *) waylandDisplay { return _display; }
- (BOOL) isInvalidated { return _invalidated; }
- (void) addSubwindow: (WaylandSubWindow *) child {
    [_subwindows addObject: [NSValue valueWithPointer: child]];
}
- (void) removeSubwindow: (WaylandSubWindow *) child {
    [_subwindows removeObject: [NSValue valueWithPointer: child]];
}
- (void) stackSubwindows {
    struct wl_proxy *below = _surface;
    for (NSValue *value in _subwindows) {
        WaylandSubWindow *child = [value pointerValue];
        if ([child presentedSurface]) {
            [child placeAboveSurface: below];
            below = [child presentedSurface];
        }
    }
}
- (void) updateSubwindows {
    for (NSValue *value in _subwindows)
        [(WaylandSubWindow *) [value pointerValue] updateGeometry];
}

- (void) scheduleSubwindowRedraw {
    _subwindowRedrawNeeded = YES;
    if (_subwindowRedrawPending) return;
    _subwindowRedrawPending = YES;
    [_display performAfterDispatch: ^{
        self->_subwindowRedrawPending = NO;
        if (!self->_mapped || self->_invalidated || !self->_delegate) return;
        self->_subwindowRedrawNeeded = NO;
        [self->_delegate display];
    }];
}

- (BOOL) isMapped {
    return _mapped;
}

- (BOOL) isPopup { return _popup != NULL; }
- (WaylandWindow *) popupParent { return _popupParent; }
- (uint32_t) popupGrabSerial { return _popupGrabSerial; }
- (struct wl_proxy *) xdgSurface { return _xdgSurface; }

#pragma mark - Mapping

- (void) ensureMapped {
    if (_mapped || _invalidated)
        return;
    _surfaceGeneration++;
    _configureUpdatePending = NO;
    // Client-side chrome everywhere keeps one look; "server" opts out where
    // the compositor offers xdg-decoration.
    const char *decorations = getenv("DARLING_WAYLAND_DECORATIONS");
    BOOL serverSide = decorations != NULL && strcmp(decorations, "server") == 0;
    _pendingClientDecorated = _display->_decorationManager == NULL || !serverSide;

    union wl_argument args[4];

    [self ensureSurface];

    args[0].o = NULL;
    args[1].o = (struct wl_object *) _surface;
    _xdgSurface = WaylandCreateObject(_display->_wmBase,
                                      WP_WM_BASE_GET_XDG_SURFACE,
                                      &xdg_surface_interface, args,
                                      WaylandObjectXdgSurface, self);

    BOOL menu = [_delegate isKindOfClass: NSClassFromString(@"NSMenuWindow")] ||
                [_delegate isKindOfClass: NSClassFromString(@"NSPopUpWindow")];
    WaylandWindow *parent = menu ? [_display popupParentForWindow: self] : nil;
    if (parent != nil && parent->_configured) {
        _popupParent = [parent retain];
        [self createPopupRole];
    } else {
        args[0].o = NULL;
        _toplevel = WaylandCreateObject(_xdgSurface, WP_XDG_SURFACE_GET_TOPLEVEL,
                                    &xdg_toplevel_interface, args,
                                    WaylandObjectToplevel, self);

        [self updateTitle];
        args[0].s = [[[NSProcessInfo processInfo] processName] UTF8String];
        if (args[0].s != NULL)
            WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_APP_ID, NULL, 0, args);
        _fullscreenRequested = NO;
        [self updateFullscreen];
        [self updateSizeLimits];

        if (_display->_decorationManager != NULL && (_styleMask & NSWindowStyleMaskTitled)) {
            args[0].o = NULL;
            args[1].o = (struct wl_object *) _toplevel;
            _decoration = WaylandCreateObject(
                    _display->_decorationManager,
                    WP_DECORATION_MANAGER_GET_TOPLEVEL_DECORATION,
                    &zxdg_toplevel_decoration_v1_interface, args,
                    WaylandObjectDecoration, self);
            args[0].u = serverSide ? WP_TOPLEVEL_DECORATION_MODE_SERVER_SIDE
                                   : WP_TOPLEVEL_DECORATION_MODE_CLIENT_SIDE;
            WaylandMarshal(_decoration, WP_TOPLEVEL_DECORATION_SET_MODE, NULL, 0, args);
        }
    }

    _pendingWidth = _pendingHeight = 0;
    _pendingActivated = NO;
    _pendingFullscreen = NO;
    // The initial commit has no buffer; content follows the first configure.
    sendRequest(_surface, WP_SURFACE_COMMIT, 0);
    _mapped = YES;
    [self scheduleScaleUpdate];
    if (_subwindowRedrawNeeded) [self scheduleSubwindowRedraw];
    _configured = NO;
    _needsPresent = _context != nil;
    [_display flush];
    if (!menu && ![_delegate isKindOfClass: NSClassFromString(@"NSPanel")]) {
        [self retain];
        X11GlobalMenu *globalMenu = [X11GlobalMenu sharedGlobalMenu];
        [globalMenu registerWaylandApplicationMenu: [NSApp mainMenu]];
        if ([globalMenu isEngaged] && !_invalidated)
            [_delegate _hideMenuViewIfNeeded];
        [self release];
    }
}

- (CGSize) maximumPopupSize {
    WaylandWindow *parent = _popupParent ?: [_display popupParentForWindow: self];
    if (parent == nil)
        return CGSizeZero;
    WaylandFullscreenOutput outputs[32];
    struct wl_proxy *proxies[32];
    size_t count = [_display fullscreenOutputs: outputs proxies: proxies max: 32
                                      entered: parent->_surfaceOutputs];
    BOOL hasEntered = NO;
    for (size_t i = 0; i < count; ++i)
        hasEntered |= outputs[i].entered;
    CGSize limit = CGSizeZero;
    for (size_t i = 0; i < count; ++i) {
        if ((hasEntered && !outputs[i].entered) ||
                outputs[i].width <= 0 || outputs[i].height <= 0)
            continue;
        if (limit.width == 0) {
            limit = CGSizeMake(outputs[i].width, outputs[i].height);
        } else {
            limit.width = MIN(limit.width, outputs[i].width);
            limit.height = MIN(limit.height, outputs[i].height);
        }
    }
    return limit;
}

- (struct wl_proxy *) newPopupPositioner {
    union wl_argument args[4] = {{.o = NULL}};
    struct wl_proxy *positioner = WaylandCreateObject(_display->_wmBase,
            WP_WM_BASE_CREATE_POSITIONER, &xdg_positioner_interface, args, 0, nil);
    args[0].i = MAX(1, (int32_t) ceil(_frame.size.width));
    args[1].i = MAX(1, (int32_t) ceil(_frame.size.height));
    WaylandMarshal(positioner, WP_POSITIONER_SET_SIZE, NULL, 0, args);
    NSRect parent = [_popupParent frame];
    NSPoint offset = [_popupParent geometryContentOffset];
    int32_t x = (int32_t) floor(_frame.origin.x - parent.origin.x + offset.x);
    int32_t y = (int32_t) floor(NSMaxY(parent) - NSMaxY(_frame) + offset.y);
    // A submenu can start beyond its parent edge. Keep the anchor inside the
    // parent geometry, expressing the remaining displacement as an offset.
    int32_t anchorX = MAX(0, MIN(x, (int32_t) ceil(parent.size.width + 2 * offset.x) - 1));
    int32_t anchorY = MAX(0, MIN(y, (int32_t) ceil(parent.size.height + offset.x + offset.y) - 1));
    args[0].i = anchorX;
    args[1].i = anchorY;
    args[2].i = args[3].i = 1;
    WaylandMarshal(positioner, WP_POSITIONER_SET_ANCHOR_RECT, NULL, 0, args);
    args[0].i = x - anchorX;
    args[1].i = y - anchorY;
    WaylandMarshal(positioner, WP_POSITIONER_SET_OFFSET, NULL, 0, args);
    args[0].u = WP_POSITIONER_ANCHOR_TOP_LEFT;
    WaylandMarshal(positioner, WP_POSITIONER_SET_ANCHOR, NULL, 0, args);
    args[0].u = WP_POSITIONER_GRAVITY_BOTTOM_RIGHT;
    WaylandMarshal(positioner, WP_POSITIONER_SET_GRAVITY, NULL, 0, args);
    args[0].u = WP_POSITIONER_SLIDE_X | WP_POSITIONER_SLIDE_Y |
                WP_POSITIONER_FLIP_X | WP_POSITIONER_FLIP_Y;
    if ([_delegate isKindOfClass: NSClassFromString(@"NSPopUpWindow")])
        args[0].u |= WP_POSITIONER_RESIZE_Y;
    WaylandMarshal(positioner, WP_POSITIONER_SET_CONSTRAINT_ADJUSTMENT, NULL, 0, args);
    return positioner;
}

- (void) createPopupRole {
    struct wl_proxy *positioner = [self newPopupPositioner];
    union wl_argument args[3];
    args[0].o = NULL;
    args[1].o = (struct wl_object *) [_popupParent xdgSurface];
    args[2].o = (struct wl_object *) positioner;
    _popup = WaylandCreateObject(_xdgSurface, WP_XDG_SURFACE_GET_POPUP,
            &xdg_popup_interface, args, WaylandObjectPopup, self);
    sendRequest(positioner, WP_POSITIONER_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    _popupGrabSerial = [_display popupGrabSerialForParent: _popupParent];
    if (_popupGrabSerial != 0 && [_display seat] != NULL) {
        args[0].o = (struct wl_object *) [_display seat];
        args[1].u = _popupGrabSerial;
        WaylandMarshal(_popup, WP_POPUP_GRAB, NULL, 0, args);
    }
}

- (void) destroyBuffers {
    for (int i = 0; i < 2; i++) {
        struct WaylandBuffer *buffer = &_buffers[i];
        if (buffer->buffer != NULL)
            sendRequest(buffer->buffer, WP_BUFFER_DESTROY, WL_MARSHAL_FLAG_DESTROY);
        if (buffer->data != NULL)
            munmap(buffer->data, buffer->size);
        memset(buffer, 0, sizeof(*buffer));
    }
    _committedWidth = _committedHeight = 0;
    _committedFormat = 0;
}

// Unmapping an xdg surface requires a new configure sequence before it can be
// shown again, so the role objects are destroyed and created again on show.
- (void) unmap {
    [self cancelAppMovePress];
    if (!_mapped)
        return;

    [_display unmapPopupsForParent: self];
    [self destroyEGLPresenter];

    if (_frameCallback != NULL) {
        WL.wl_proxy_destroy(_frameCallback);
        _frameCallback = NULL;
    }
    if (_decoration != NULL) {
        sendRequest(_decoration, WP_TOPLEVEL_DECORATION_DESTROY,
                    WL_MARSHAL_FLAG_DESTROY);
        _decoration = NULL;
    }
    if (_popup != NULL) {
        sendRequest(_popup, WP_POPUP_DESTROY, WL_MARSHAL_FLAG_DESTROY);
        _popup = NULL;
        [_popupParent release];
        _popupParent = nil;
        _popupGrabSerial = 0;
    }
    if (_toplevel != NULL)
        sendRequest(_toplevel, WP_TOPLEVEL_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    sendRequest(_xdgSurface, WP_XDG_SURFACE_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    // Retain the parent wl_surface across hide/show: EGL child surfaces keep
    // their native-window identity. A NULL buffer unmaps the entire subtree.
    union wl_argument detach[] = {{.o = NULL}, {.i = 0}, {.i = 0}};
    WaylandMarshal(_surface, WP_SURFACE_ATTACH, NULL, 0, detach);
    sendRequest(_surface, WP_SURFACE_COMMIT, 0);
    _toplevel = _xdgSurface = NULL;
    [_surfaceOutputs removeAllObjects];
    [self destroyBuffers];
    _sentGeometry = O2RectZero;
    _buttonTracker.pressed = _shownPressed = NSTitlebarButtonNone;
    _buttonHover = NO;

    _mapped = NO;
    _configureUpdatePending = NO;
    _configured = NO;
    _activated = NO;
    _decorationsDirty = YES;
    // The tracker survives hiding: _frame keeps the fullscreen size, so the size
    // from before fullscreen would be lost if the next map saved it again.
    _fullscreenRequested = _pendingFullscreen = _fullscreenRecheckPending = NO;
    [_display windowUnmapped: self];
    [_display flush];
}

- (void) showWindowWithoutActivation {
    [self ensureMapped];
}

- (void) showWindowForAppActivation: (NSRect) frame {
    [self ensureMapped];
}

- (void) hideWindowForAppDeactivation: (NSRect) frame {
}

- (void) hideWindow {
    [self unmap];
}

- (void) sheetOrderFrontFromFrame: (NSRect) frame
                      aboveWindow: (CGWindow *) aboveWindow
{
    [self setFrame: frame];
    [self ensureMapped];
}

- (void) sheetOrderOutToFrame: (NSRect) frame {
    [self unmap];
}

// Clients can't restack or focus toplevels; the compositor decides.
- (void) placeAboveWindow: (NSInteger) otherNumber {
    [self ensureMapped];
}

- (void) placeBelowWindow: (NSInteger) otherNumber {
    [self ensureMapped];
}

- (void) makeKey {
    [self ensureMapped];
}

- (void) makeMain {
}

- (void) captureEvents {
}

- (void) miniaturize {
    if (_toplevel != NULL) {
        sendRequest(_toplevel, WP_TOPLEVEL_SET_MINIMIZED, 0);
        [_display flush];
    }
}

- (void) deminiaturize {
    [self ensureMapped];
}

- (BOOL) isMiniaturized {
    // xdg-shell doesn't report whether a toplevel is minimized.
    return NO;
}

- (void) flashWindow {
}

#pragma mark - Properties

- (NSUInteger) styleMask {
    return _styleMask;
}

- (void) setStyleMask: (NSUInteger) mask {
    NSUInteger buttons = NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable |
                         NSWindowStyleMaskResizable;
    if ((_styleMask ^ mask) & buttons)
        _decorationsDirty = YES;
    _styleMask = mask;
    [self updateSizeLimits];
    [self updateFullscreen];
}

#pragma mark - Fullscreen

// Whether the window should be fullscreen, and on which output (NULL: the
// compositor chooses; always NULL for a window that asked through the style mask).
- (BOOL) wantsFullscreenOn: (struct wl_proxy **) output {
    *output = NULL;
    if (_popup != NULL || _popupParent != nil)
        return NO;
    WaylandFullscreenOutput outputs[32];
    struct wl_proxy *proxies[32];
    size_t count = [_display fullscreenOutputs: outputs proxies: proxies max: 32
                                       entered: _surfaceOutputs];
    WaylandFullscreenWindow window = {
        .fullScreenStyle = (_styleMask & NSWindowStyleMaskFullScreen) != 0,
        .titled = (_styleMask & NSWindowStyleMaskTitled) != 0,
        .canBecomeKey = [_delegate canBecomeKeyWindow],
        .popupOrMenu = [_delegate isKindOfClass: NSClassFromString(@"NSMenuWindow")] ||
                       [_delegate isKindOfClass: NSClassFromString(@"NSPopUpWindow")],
        .width = WaylandFullscreenRound(_frame.size.width),
        .height = WaylandFullscreenRound(_frame.size.height),
    };
    int target;
    BOOL wanted = WaylandFullscreenDecide(&window, outputs, count, &target);
    if (target >= 0)
        *output = proxies[target];
    return wanted;
}

// Asks the compositor to enter or leave fullscreen when the answer changed.
- (void) updateFullscreen {
    if (_toplevel == NULL)
        return;
    struct wl_proxy *output;
    BOOL wanted = [self wantsFullscreenOn: &output];
    if (wanted == _fullscreenRequested)
        return;
    _fullscreenRequested = wanted;
    if (wanted)
        WaylandToplevelSetFullscreen(_toplevel, output);
    else
        WaylandToplevelUnsetFullscreen(_toplevel);
    [_display flush];
}

- (void) outputsChanged {
    if (_toplevel == NULL)
        return;
    _fullscreenRecheckPending = YES;
    NSUInteger generation = _surfaceGeneration;
    [_display performAfterDispatch: ^{
        if (self->_surfaceGeneration == generation)
            [self recheckFullscreen];
    }];
}

// A configure that is still queued carries the size the compositor chose for
// the new output layout; applyConfigure runs this once it has applied it.
- (void) recheckFullscreen {
    if (!_fullscreenRecheckPending || _configureUpdatePending)
        return;
    _fullscreenRecheckPending = NO;
    [self updateFullscreen];
}

- (void) setLevel: (int) value {
    _level = value;
}

- (void) updateTitle {
    if (_toplevel == NULL)
        return;
    const char *title = [_title UTF8String];
    union wl_argument args[1] = {{.s = title ? title : ""}};
    WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_TITLE, NULL, 0, args);
}

- (void) setTitle: (NSString *) title {
    if (_title != title && ![_title isEqualToString: title])
        _decorationsDirty = YES;
    [_title release];
    _title = [title copy];
    [self updateTitle];
    if (_clientDecorated)
        [self flushBuffer];
    [_display flush];
}

- (void) updateSizeLimits {
    if (_toplevel == NULL)
        return;

    union wl_argument args[2] = {{.i = 0}, {.i = 0}};
    if (!(_styleMask & NSWindowStyleMaskResizable)) {
        // Window geometry units: the visible window, without the shadow margin.
        args[0].i = (int32_t) _frame.size.width;
        args[1].i = (int32_t) _frame.size.height + (_clientDecorated ? WaylandTitleHeight : 0);
    }
    WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_MIN_SIZE, NULL, 0, args);
    WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_MAX_SIZE, NULL, 0, args);
}

- (void) setOpaque: (BOOL) value {
    if (value == _isOpaque)
        return;
    _isOpaque = value;
    // The opaque region is resent only when the visible rectangle changes;
    // forget the last one so the next commit carries the new region.
    _sentGeometry = O2RectZero;
}

- (void) setAlphaValue: (CGFloat) value {
    // No client-side opacity on Wayland without an extra protocol.
}

- (void) setHasShadow: (BOOL) value {
    _hasShadow = value;
}

- (CGLContextObj) cglContext {
    return NULL;
}

- (void) addEntriesToDeviceDictionary: (NSDictionary *) entries {
    [_deviceDictionary addEntriesFromDictionary: entries];
}

- (CGSubWindow *) createSubWindowWithFrame: (CGRect) frame {
    if (!_display->_eglAvailable || _invalidated) return nil;
    return [[[WaylandSubWindow alloc] initWithParentWindow: self frame: frame] autorelease];
}

#pragma mark - Geometry

- (O2Rect) frame {
    return _frame;
}

- (void) setFrame: (O2Rect) frame {
    frame.size.width = MAX(frame.size.width, 1.0);
    frame.size.height = MAX(frame.size.height, 1.0);

    NSWindowTraceFrame("WaylandWindow.setFrame", _frame, frame);
    BOOL moved = !NSEqualPoints(frame.origin, _frame.origin);
    BOOL sized = !NSEqualSizes(frame.size, _frame.size);
    // Apps with their own chrome drag by setting the origin. Wayland only
    // permits the compositor to move a toplevel, using the initiating press.
    NSEvent *event = [NSApp currentEvent];
    if (moved && !sized && _appMoveDragged &&
        [event type] == NSLeftMouseDragged && [event window] == _delegate)
        [self beginWindowDrag];
    [self invalidateContextWithNewSize: frame.size];
    // Like NSWindow, retain the requested frame, not an invented compositor
    // position: xdg-shell never reports the toplevel's global origin.
    _frame = frame;
    // The application chose a new size: leaving fullscreen returns to it, even
    // when the compositor answers unset_fullscreen with the size it remembered.
    if (sized)
        WaylandFullscreenApplicationResized(&_fullscreenTracker,
                                            WaylandFullscreenRound(frame.size.width),
                                            WaylandFullscreenRound(frame.size.height));
    if (_popup != NULL && (moved || sized) && WL.wl_proxy_get_version(_popup) >= 3) {
        struct wl_proxy *positioner = [self newPopupPositioner];
        union wl_argument args[2] = {{.o = (struct wl_object *) positioner},
                                     {.u = ++_repositionToken}};
        WaylandMarshal(_popup, WP_POPUP_REPOSITION, NULL, 0, args);
        sendRequest(positioner, WP_POSITIONER_DESTROY, WL_MARSHAL_FLAG_DESTROY);
        [_display flush];
    }
    [self updateSubwindows];
    if (sized) {
        [self updateSizeLimits];
        [self updateFullscreen];
        [_display flush];
    }
}

- (NSPoint) transformPoint: (CGPoint) surfacePoint {
    NSPoint offset = [self contentOffset];
    return NSMakePoint(surfacePoint.x - offset.x, _frame.size.height - surfacePoint.y + offset.y);
}

- (NSPoint) contentOffset {
    return _clientDecorated ? NSMakePoint(_margin, _margin + WaylandTitleHeight) : NSZeroPoint;
}

- (NSPoint) geometryContentOffset {
    return _clientDecorated ? NSMakePoint(0, WaylandTitleHeight) : NSZeroPoint;
}

- (BOOL) isDecorationPoint: (CGPoint) point {
    if (!_clientDecorated)
        return NO;
    NSPoint offset = [self contentOffset];
    return point.x < offset.x || point.y < offset.y ||
           point.x >= offset.x + _frame.size.width || point.y >= offset.y + _frame.size.height;
}

- (NSTitlebarFrame) titlebarFrame {
    NSTitlebarFrame frame = {
        .margin = _margin,
        .width = ceil(_frame.size.width),
        .height = ceil(_frame.size.height) + WaylandTitleHeight,
        .rounded = _margin > 0,
        .shadow = _margin > 0,
    };
    NSAppearanceName appearance = [[_delegate effectiveAppearance] bestMatchFromAppearancesWithNames:
            @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    frame.state = (NSTitlebarState) {
        .active = _activated,
        .dark = [appearance isEqualToString: NSAppearanceNameDarkAqua],
        .hover = _buttonHover,
        .pressed = _shownPressed,
        .enabled = {(_styleMask & NSWindowStyleMaskClosable) != 0,
                    (_styleMask & NSWindowStyleMaskMiniaturizable) != 0,
                    (_styleMask & NSWindowStyleMaskResizable) != 0},
        .hairline = YES,
    };
    return frame;
}

- (void) setButtonHover: (BOOL) hover shownPressed: (NSTitlebarButton) shown {
    if (hover == _buttonHover && shown == _shownPressed)
        return;
    _buttonHover = hover;
    _shownPressed = shown;
    _decorationsDirty = YES;
    [self flushBuffer];
}

- (void) decorationPointerMoved: (CGPoint) point {
    if (!_clientDecorated)
        return;
    CGFloat x = point.x - _margin, y = point.y - _margin;
    NSTitlebarButton pressed = _buttonTracker.pressed;
    [self setButtonHover: NSTitlebarPointInButtonGroup(x, y)
            shownPressed: NSTitlebarButtonAtPoint(x, y) == pressed ? pressed : NSTitlebarButtonNone];
}

- (void) decorationPointerLeft {
    [self cancelAppMovePress];
    if (_clientDecorated)
        [self setButtonHover: NO shownPressed: NSTitlebarButtonNone];
}

- (void) cancelAppMovePress {
    _appMoveSeat = NULL;
    _appMoveSerial = 0;
    _appMoveDragged = NO;
}

// Called only for changed pointer coordinates, before the drag event is queued.
// The receiver is the current pointer window, so another window cannot qualify
// this window's content press. Frame changes also require its drag event context.
- (void) appMoveMotion: (BOOL) leftHeld {
    if (_appMoveSeat != NULL && leftHeld)
        _appMoveDragged = YES;
}

- (void) appMoveButton: (uint32_t) button pressed: (BOOL) pressed
                serial: (uint32_t) serial atPoint: (CGPoint) point
{
    if (button != WP_BTN_LEFT)
        return;
    [self cancelAppMovePress];
    if (pressed && _toplevel != NULL && ![self isDecorationPoint: point]) {
        _appMoveSeat = [_display seat];
        _appMoveSerial = serial;
    }
}

- (void) beginWindowDrag {
    if (_toplevel == NULL || _appMoveSeat == NULL)
        return;
    union wl_argument args[2] = {{.o = (struct wl_object *) _appMoveSeat},
                                 {.u = _appMoveSerial}};
    // Consume before sending: the compositor may take pointer focus and the
    // release may never reach us. Further frame updates cannot reuse this press.
    [self cancelAppMovePress];
    WaylandMarshal(_toplevel, WP_TOPLEVEL_MOVE, NULL, 0, args);
    [_display flush];
}

- (void) performWindowDragWithEvent: (NSEvent *) event {
    if ([event window] == _delegate &&
        ([event type] == NSLeftMouseDown || [event type] == NSLeftMouseDragged))
        [self beginWindowDrag];
}

- (void) performTitlebarButton: (NSTitlebarButton) action {
    switch (action) {
    case NSTitlebarButtonClose:
        [self closeRequested];
        break;
    case NSTitlebarButtonMinimize:
        [self miniaturize];
        break;
    case NSTitlebarButtonZoom:
        if (_toplevel != NULL)
            sendRequest(_toplevel, _maximized ? WP_TOPLEVEL_UNSET_MAXIMIZED : WP_TOPLEVEL_SET_MAXIMIZED, 0);
        break;
    default:
        break;
    }
}

- (BOOL) decorationButton: (uint32_t) button pressed: (BOOL) pressed
                   serial: (uint32_t) serial atPoint: (CGPoint) point
{
    CGFloat x = point.x - _margin, y = point.y - _margin;
    if (!pressed && button == WP_BTN_LEFT && _buttonTracker.pressed != NSTitlebarButtonNone) {
        // The press began on a disc, so the release is ours wherever it lands;
        // the button acts only when released over the disc it pressed.
        NSTitlebarButton action = NSTitlebarTrackerRelease(&_buttonTracker, x, y);
        [self setButtonHover: NSTitlebarPointInButtonGroup(x, y) shownPressed: NSTitlebarButtonNone];
        [self performTitlebarButton: action];
        [_display flush];
        return YES;
    }
    if (![self isDecorationPoint: point])
        return NO;
    if (!pressed || button != WP_BTN_LEFT || _toplevel == NULL || [_display seat] == NULL)
        return YES;
    NSTitlebarFrame frame = [self titlebarFrame];
    uint32_t edge = NSTitlebarResizeEdgesAtPoint(&frame, point.x, point.y);
    union wl_argument args[3] = {{.o = (struct wl_object *) [_display seat]},
                                 {.u = serial}, {.u = edge}};
    if (edge != 0) {
        if (_styleMask & NSWindowStyleMaskResizable)
            WaylandMarshal(_toplevel, WP_TOPLEVEL_RESIZE, NULL, 0, args);
    } else if (y >= 0 && y < WaylandTitleHeight && x >= 0 && x < frame.width) {
        if (NSTitlebarTrackerPress(&_buttonTracker, &frame.state, x, y))
            [self setButtonHover: YES shownPressed: _buttonTracker.pressed];
        else
            WaylandMarshal(_toplevel, WP_TOPLEVEL_MOVE, NULL, 0, args);
    }
    [_display flush];
    return YES;
}

- (void) setLastKnownCursorPosition: (CGPoint) point {
    _lastMotionPos = point;
}

- (NSPoint) mouseLocationOutsideOfEventStream {
    return _lastMotionPos;
}

#pragma mark - Drawing

- (int32_t) bufferScale { return _bufferScale; }
- (CGFloat) backingScaleFactor { return _renderScale120 / 120.0; }
- (uint32_t) renderScale120 { return _renderScale120; }
// The fastest output the surface is on, 0 before it has entered one.
- (uint32_t) refreshMillihertz {
    uint32_t refresh = 0;
    for (NSValue *output in _surfaceOutputs)
        refresh = MAX(refresh, [_display refreshForOutput: [output pointerValue]]);
    return refresh;
}
- (void) preferredScaleChanged: (uint32_t) scale120 {
    if (!_fractionalScale || scale120 == 0 || scale120 == _preferredScale120) return;
    _preferredScale120 = scale120;
    [self scheduleScaleUpdate];
}
- (NSSize) logicalSurfaceSize {
    return NSMakeSize(ceil(_frame.size.width) + 2 * _margin,
        ceil(_frame.size.height) + 2 * _margin + (_clientDecorated ? WaylandTitleHeight : 0));
}

- (void) outputRemoved: (struct wl_proxy *) output {
    [_surfaceOutputs removeObject: [NSValue valueWithPointer: output]];
    [self scheduleScaleUpdate];
}

- (void) scheduleScaleUpdate {
    if (_scaleUpdatePending)
        return;
    _scaleUpdatePending = YES;
    [_display performAfterDispatch: ^{
        self->_scaleUpdatePending = NO;
        if (!self->_mapped || self->_delegate == nil)
            return;
        int32_t scale = 1;
        if (self->_display->_compositorVersion >= 3)
            for (NSValue *output in self->_surfaceOutputs)
                scale = MAX(scale, [self->_display scaleForOutput: [output pointerValue]]);
        uint32_t render = self->_fractionalScale && self->_preferredScale120
            ? self->_preferredScale120 : (uint32_t)MIN((uint64_t)scale * 120, UINT32_MAX);
        if (scale == self->_bufferScale && render == self->_renderScale120) return;
        self->_bufferScale = scale;
        self->_renderScale120 = render;
        [self updateSubwindows];
        [self->_context release];
        self->_context = nil;
        self->_needsPresent = NO;
        [self->_delegate platformWindowDidInvalidateCGContext: self];
        [self->_delegate platformWindowExposed: self
                                      inRect: NSMakeRect(0, 0, self->_frame.size.width,
                                                         self->_frame.size.height)];
        // Expose only posts a notification in Cocotron. A new backing surface
        // needs a full redraw, even when no view has invalidated its contents.
        [self->_delegate display];
        [self->_display windowScaleChanged: self];
    }];
}

- (O2Context *) createCGContextIfNeeded {
    if (_context == nil) {
        NSSize logical = [self logicalSurfaceSize];
        int32_t width, height;
        if (!isfinite(logical.width) || !isfinite(logical.height) || logical.width < 1 || logical.height < 1 ||
            logical.width > INT32_MAX || logical.height > INT32_MAX ||
            !WaylandScaleExtent((int32_t)logical.width, _renderScale120, INT32_MAX / 4, &width) ||
            !WaylandScaleExtent((int32_t)logical.height, _renderScale120, INT32_MAX / (width * 4), &height)) {
            NSLog(@"Wayland backend: window buffer dimensions exceed wl_shm limits");
            return nil;
        }
        O2ColorSpaceRef colorSpace = O2ColorSpaceCreateDeviceRGB();
        O2Surface *surface = [[O2Surface alloc]
                   initWithBytes: NULL
                           width: width
                          height: height
                bitsPerComponent: 8
                     bytesPerRow: 0
                      colorSpace: colorSpace
                      bitmapInfo: kO2ImageAlphaPremultipliedFirst |
                                  kO2BitmapByteOrder32Little];
        O2ColorSpaceRelease(colorSpace);
        // Presentation copies and announces only what drawing wrote.
        O2SurfaceSetTracksDamage(surface, YES);
        _context = [[WaylandDrawingContext alloc] initWithSurface: surface logicalSize: logical
                                                          border: _margin];
        _decorationsDirty = YES;
        _damageAll = YES;
        [surface release];
    }
    return _context;
}

- (void)desktopSettingsDidChange {
    _decorationsDirty=YES;
    [_delegate setViewsNeedDisplay:YES];
}

- (O2Context *) cgContext {
    return [self createCGContextIfNeeded];
}

- (void) invalidateContextWithNewSize: (NSSize) size {
    if (!NSEqualSizes(_frame.size, size)) {
        NSRect resized = _frame; resized.size = size;
        NSWindowTraceFrame("WaylandWindow.invalidateContextWithNewSize", _frame, resized);
        _frame.size = size;
        [_context release];
        _context = nil;
        [_delegate platformWindowDidInvalidateCGContext: self];
    }
}

- (NSTitlebarBitmap) titlebarBitmap {
    O2Surface *surface = [_context surface];
    size_t width = O2SurfaceGetWidth(surface);
    return (NSTitlebarBitmap) {
        .pixels = O2SurfaceGetPixelBytes(surface),
        .bytesPerRow = O2SurfaceGetBytesPerRow(surface),
        .width = (int) width,
        .height = (int) O2SurfaceGetHeight(surface),
        .scale = width / [self logicalSurfaceSize].width,
    };
}

// The title keeping `keep` characters around a middle ellipsis, cut at
// character boundaries; nil when the boundaries overlap.
static NSString *titleKeeping(NSString *title, NSUInteger keep) {
    NSUInteger length = [title length];
    NSUInteger headEnd = (keep + 1) / 2, tailStart = length - keep / 2;
    if (headEnd > 0)
        headEnd = NSMaxRange([title rangeOfComposedCharacterSequenceAtIndex: headEnd - 1]);
    if (tailStart < length)
        tailStart = [title rangeOfComposedCharacterSequenceAtIndex: tailStart].location;
    if (headEnd > tailStart)
        return nil;
    return [NSString stringWithFormat: @"%@\u2026%@",
            [title substringToIndex: headEnd], [title substringFromIndex: tailStart]];
}

// Shortens the middle of a title that does not fit. Keeping more characters
// never makes the title narrower, so the longest fitting cut is found by
// bisection: O(log n) measurements per redraw instead of O(n).
static NSString *titleFittingWidth(NSString *title, NSDictionary *attributes, CGFloat width) {
    if ([title sizeWithAttributes: attributes].width <= width)
        return title;
    NSString *best = @"";
    NSUInteger low = 0, high = [title length];
    while (low < high) {
        NSUInteger keep = low + (high - low) / 2;
        NSString *candidate = titleKeeping(title, keep);
        if (candidate != nil && [candidate sizeWithAttributes: attributes].width <= width) {
            best = candidate;
            low = keep + 1;
        } else
            high = keep;
    }
    return best;
}

- (void) drawTitle {
    if ([_title length] == 0)
        return;
    [NSGraphicsContext saveGraphicsState];
    O2ContextSaveGState(_context);
    @try {
        [NSGraphicsContext setCurrentContext:
            [NSGraphicsContext graphicsContextWithGraphicsPort: (CGContextRef) _context flipped: NO]];
        O2ContextResetClip(_context);
        O2ContextSetCTM(_context, O2AffineTransformIdentity);
        // The renderer and the surface place the title strip at the ceiled height.
        CGFloat w = ceil(_frame.size.width), h = ceil(_frame.size.height);
        NSDictionary *attributes = @{
            NSFontAttributeName: [NSFont titleBarFontOfSize: NSTitlebarFontSize],
            NSForegroundColorAttributeName: _activated ? [NSColor labelColor] : [NSColor tertiaryLabelColor],
        };
        double room;
        NSTitlebarTitleOriginX(w, 0, &room);
        NSString *title = titleFittingWidth(_title, attributes, room);
        NSSize size = [title sizeWithAttributes: attributes];
        CGFloat x = NSTitlebarTitleOriginX(w, size.width, &room);
        [(WaylandDrawingContext *)_context clipTitlebarAtHeight: h];
        [title drawAtPoint: NSMakePoint(x, h + floor((WaylandTitleHeight - size.height) / 2))
            withAttributes: attributes];
    } @finally {
        O2ContextRestoreGState(_context);
        [NSGraphicsContext restoreGraphicsState];
    }
}

- (void) drawDecorations {
    // Content drawing is clipped inside the frame; the backing surface retains
    // its decoration pixels until an input changes or the context is recreated.
    if (!_clientDecorated || _context == nil || !_decorationsDirty)
        return;
    NSTitlebarBitmap bitmap = [self titlebarBitmap];
    NSTitlebarFrame frame = [self titlebarFrame];
    NSTitlebarRenderFrame(&bitmap, &frame);
    O2SurfaceAddDamage([_context surface], 0, 0, bitmap.width, bitmap.height);
    [self drawTitle];
    _decorationsDirty = NO;
    _damageAll = YES;
}

static BOOL sameCornerMask(const NSTitlebarFrame *a, const NSTitlebarFrame *b) {
    return a->margin == b->margin && a->width == b->width && a->height == b->height &&
           a->rounded == b->rounded && a->shadow == b->shadow &&
           a->state.active == b->state.active && a->state.dark == b->state.dark;
}

// The application redraws its content every flush, including the bottom
// corners, so they are cut again each time. Cutting stores the same pixels
// again unless content drew there (already damaged) or the frame changed.
- (void) maskContentCorners {
    if (!_clientDecorated || _margin <= 0 || _context == nil)
        return;
    NSTitlebarBitmap bitmap = [self titlebarBitmap];
    NSTitlebarFrame frame = [self titlebarFrame];
    NSTitlebarMaskContentCorners(&bitmap, &frame);
    if (!_maskedFrameValid || !sameCornerMask(&frame, &_maskedFrame))
        O2SurfaceAddDamage([_context surface], 0, 0, bitmap.width, bitmap.height);
    _maskedFrame = frame;
    _maskedFrameValid = YES;
}

- (void) flushBuffer {
    if (_context == nil)
        return;
    _needsPresent = YES;
    if ([_delegate isFlushWindowDisabled])
        return;
    [self drawDecorations];
    [self maskContentCorners];
    O2ContextFlush(_context);
    [self presentIfPossible];
}

- (struct WaylandBuffer *) bufferWithWidth: (int32_t) width
                                    height: (int32_t) height
                                    format: (uint32_t) format
{
    struct WaylandBuffer *reusable = NULL;

    for (int i = 0; i < 2; i++) {
        struct WaylandBuffer *buffer = &_buffers[i];
        if (buffer->busy)
            continue;
        if (buffer->buffer != NULL && buffer->width == width &&
            buffer->height == height && buffer->format == format)
            return buffer;
        if (reusable == NULL)
            reusable = buffer;
    }
    // Both buffers are still in use: present again when one is released.
    if (reusable == NULL)
        return NULL;

    if (width < 1 || height < 1 || width > INT32_MAX / 4 ||
        height > INT32_MAX / (width * 4))
        return NULL;

    if (reusable->buffer != NULL)
        sendRequest(reusable->buffer, WP_BUFFER_DESTROY, WL_MARSHAL_FLAG_DESTROY);
    if (reusable->data != NULL)
        munmap(reusable->data, reusable->size);
    memset(reusable, 0, sizeof(*reusable));

    int32_t stride = width * 4;
    size_t size = (size_t) stride * (size_t) height;
    int fd = WaylandCreateAnonymousFile(size);
    if (fd < 0) {
        NSLog(@"Wayland backend: cannot allocate a %dx%d window buffer", width,
              height);
        return NULL;
    }

    void *data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (data == MAP_FAILED) {
        NSLog(@"Wayland backend: cannot map a %dx%d window buffer: %s", width,
              height, strerror(errno));
        close(fd);
        return NULL;
    }

    // libwayland duplicates the descriptor when it marshals the request.
    union wl_argument poolArgs[3] = {{.o = NULL}, {.h = fd}, {.i = (int32_t) size}};
    struct wl_proxy *pool = WaylandCreateObject(_display->_shm, WP_SHM_CREATE_POOL,
                                                &wl_shm_pool_interface, poolArgs,
                                                0, nil);
    close(fd);

    union wl_argument bufferArgs[6] = {{.o = NULL},    {.i = 0},
                                       {.i = width},   {.i = height},
                                       {.i = stride},  {.u = format}};
    struct wl_proxy *proxy = WaylandCreateObject(pool, WP_SHM_POOL_CREATE_BUFFER,
                                                 &wl_buffer_interface, bufferArgs,
                                                 WaylandObjectBuffer, self);
    sendRequest(pool, WP_SHM_POOL_DESTROY, WL_MARSHAL_FLAG_DESTROY);

    reusable->buffer = proxy;
    reusable->data = data;
    reusable->size = size;
    reusable->width = width;
    reusable->height = height;
    reusable->format = format;
    O2SurfaceDamageAdd(&reusable->stale, 0, 0, width, height, width, height);
    return reusable;
}

- (NSDictionary *) eglPresentationStatistics {
    O2Surface *surface = [_context surface];
    BOOL egl = _eglRequested && _eglFallbackReason == nil;
    return @{@"renderer": egl ? @"egl" : @"shm", @"requested": _eglRequested ? @"egl" : @"shm",
             @"fallbackReason": _eglFallbackReason ? _eglFallbackReason : @"", @"swaps": @(_eglSwaps),
             @"captureRequested": @(_captureRequested), @"captureReady": @(_clientCapture!=nil),
             @"captureError": @(_captureRequested&&!_clientCapture?1:[_clientCapture errorCode]),
             @"clientPresents": @(_clientPresents), @"captured": @([_clientCapture writtenCount]),
             @"checks": @(_eglChecks), @"uploadedBytes": @(_eglBytes), @"failures": @(_eglFailures),
             @"width": @(_eglWidth), @"height": @(_eglHeight), @"scale120": @(_renderScale120),
             @"damageRects": @(_damageRects), @"damagePixels": @(_damagePixels),
             @"copiedPixels": @(_copiedPixels), @"wholeDamagePresents": @(_wholeDamagePresents),
             @"damageVerify": @(_damageVerify), @"verifiedPresents": @(_verifiedPresents),
             @"staleVerifiedPresents": @(_staleVerifiedPresents),
             @"fullUploads": @(_eglFullUploads), @"partialUploads": @(_eglPartialUploads),
             @"lastUploadBytes": @(_eglLastUploadBytes),
             @"presentsTimed": @(_presentsTimed), @"presentNanoseconds": @(_presentNanoseconds),
             @"lastPresentNanoseconds": @(_lastPresentNanoseconds), @"maxPresentNanoseconds": @(_maxPresentNanoseconds),
             @"surfaceWidth": @(surface ? O2SurfaceGetWidth(surface) : 0),
             @"surfaceHeight": @(surface ? O2SurfaceGetHeight(surface) : 0),
             @"eglScale120": @(_renderScale120)};
}

- (void) addDamageRect: (CGRect) rect {
    if (_damageCount == sizeof(_damage) / sizeof(_damage[0]))
        _damageAll = YES;
    else
        _damage[_damageCount++] = rect;
}

- (void) destroyEGLPresenter {
    if (!_eglContext && !_eglWindow) return;
    CGLContextObj previous = CGLGetCurrentContext();
    if (previous == _eglContext) previous = NULL;
    if (CGLGetCurrentContext() == _eglContext) CGLSetCurrentContext(NULL);
    [_eglPresenter release]; _eglPresenter = nil;
    // EGL drawable must die before its wl_egl_window, then the wl_surface.
    if (_eglDrawable) CGLDestroyWindow(_eglDrawable);
    _eglDrawable = NULL;
    if (_eglWindow) WL.wl_egl_window_destroy(_eglWindow);
    _eglWindow = NULL;
    if (_eglContext) CGLReleaseContext(_eglContext);
    _eglContext = NULL;
    _eglWidth = _eglHeight = 0;
    if (CGLGetCurrentContext() != previous && CGLSetCurrentContext(previous) != kCGLNoError)
        NSLog(@"AppKit EGL: cannot restore caller context during teardown");
}

// Verification exists to catch wrong pixels, so there a failure stays fatal.
// Otherwise EGL is only an accelerator: the window continues on wl_shm.
- (void) failEGLPresentation: (NSString *) reason {
    ++_eglFailures;
    if (_frameCallback) { WL.wl_proxy_destroy(_frameCallback); _frameCallback = NULL; }
    if (_eglVerify) {
        _eglFailed = YES;
        [NSException raise:NSInternalInconsistencyException format:@"Requested AppKit EGL presentation failed: %@", reason];
    }
    [self destroyEGLPresenter];
    _eglFallbackReason = [reason copy];
    static BOOL logged;
    if (!logged || _eglSwaps) {
        NSLog(@"AppKit EGL: %@; presenting with wl_shm", reason);
        logged = YES;
    }
}

- (NSString *) ensureEGLPresenterWidth: (int32_t) width height: (int32_t) height {
    if (!_display->_eglAvailable) return @"EGL is unavailable on this Wayland display";
    if (!_eglContext) {
        CGLPixelFormatAttribute attributes[] = {kCGLPFAAccelerated, 0};
        CGLPixelFormatObj format = NULL; GLint count = 0;
        CGLError error = CGLChoosePixelFormat(attributes, &format, &count);
        if (error == kCGLNoError && format && count)
            error = CGLCreateContext(format, NULL, &_eglContext);
        if (format) CGLReleasePixelFormat(format);
        if (error != kCGLNoError || !_eglContext) return @"no accelerated CGL context";
        _eglWindow = WL.wl_egl_window_create((struct wl_surface *)_surface, width, height);
        if (!_eglWindow) return @"wl_egl_window_create failed";
        _eglDrawable = CGLGetWindowForContext(_eglContext, _eglWindow);
        if (!_eglDrawable) return @"no EGL window surface";
    }
    WL.wl_egl_window_resize(_eglWindow, width, height, 0, 0);
    if (CGLContextMakeCurrentAndAttachToWindow(_eglContext, _eglDrawable) != kCGLNoError) return @"cannot make the EGL context current";
    GLint interval = 0;
    if (CGLSetParameter(_eglContext, kCGLCPSwapInterval, &interval) != kCGLNoError) return @"cannot disable the swap interval";
    if (_eglPresenter) {
        _eglWidth = width; _eglHeight = height;
        return nil;
    }
    const char *name = (const char *)glGetString(GL_RENDERER), *version = (const char *)glGetString(GL_VERSION);
    if (!name || !version || strtol(version, NULL, 10) < 3) return @"OpenGL 3 or later is required";
    NSString *renderer = [[NSString stringWithUTF8String:name] lowercaseString];
    for (NSString *software in @[@"llvmpipe", @"softpipe", @"swrast", @"software", @"swiftshader", @"lavapipe"])
        if ([renderer rangeOfString:software].location != NSNotFound)
            return [NSString stringWithFormat:@"software renderer %s", name];
    GLint red, green, blue, alpha;
    glGetIntegerv(GL_RED_BITS, &red); glGetIntegerv(GL_GREEN_BITS, &green);
    glGetIntegerv(GL_BLUE_BITS, &blue); glGetIntegerv(GL_ALPHA_BITS, &alpha);
    if (red < 8 || green < 8 || blue < 8 || alpha < 8) return @"no RGBA8 EGL drawable";
    _eglPresenter = [[CAWindowOpenGLContext alloc] initWithCGLContext:_eglContext];
    static BOOL announced;
    if (!announced) {
        NSLog(@"AppKit EGL: presenting windows through %s", name);
        announced = YES;
    }
    _eglWidth = width; _eglHeight = height;
    return nil;
}

// Returns NO when the window could not be presented with EGL and must use wl_shm.
- (BOOL) presentEGLSurface: (O2Surface *) surface {
    if (_eglFailed) return YES;
    size_t width = O2SurfaceGetWidth(surface), height = O2SurfaceGetHeight(surface);
    CGLContextObj previous = CGLGetCurrentContext();
    NSString *failure = nil;
    BOOL whole = _damageAll || _damageCount == 0;
    @try {
        if (width > INT32_MAX || height > INT32_MAX)
            failure = @"surface too large for EGL";
        else
            failure = [self ensureEGLPresenterWidth:(int32_t)width height:(int32_t)height];
        if (failure)
            ;
        else if (![_eglPresenter presentSurface:surface opaque:[self presentsOpaque]
                                         damage:_damage count:whole ? 0 : _damageCount
                                         verify:_eglVerify corrupt:_eglCorrupt])
            failure = @"texture upload, GPU output or CPU reference verification failed";
        else {
            if (_eglVerify) ++_eglChecks;
            if (_display->_compositorVersion >= 3) {
                union wl_argument scale[] = {{.i = _fractionalScale ? 1 : _bufferScale}};
                WaylandMarshal(_surface, WP_SURFACE_SET_BUFFER_SCALE, NULL, 0, scale);
            }
            NSSize logical = [self logicalSurfaceSize];
            if (_viewport) {
                union wl_argument destination[] = {{.i = (int32_t)logical.width}, {.i = (int32_t)logical.height}};
                WaylandMarshal(_viewport, WP_VIEWPORT_SET_DESTINATION, NULL, 0, destination);
            }
            [self updateSurfaceRegions];
            // Request pacing before swap's implicit surface commit. Never commit twice.
            union wl_argument args[] = {{.o = NULL}};
            _frameCallback = WaylandCreateObject(_surface, WP_SURFACE_FRAME,
                &wl_callback_interface, args, WaylandObjectFrameCallback, self);
            if (!_frameCallback || CGLFlushDrawable(_eglContext) != kCGLNoError)
                failure = @"native EGL swap failed";
            else {
                ++_clientPresents;
                [_clientCapture captureSurface:surface opaque:[self presentsOpaque] scale120:_renderScale120];
                ++_eglSwaps;
                _eglLastUploadBytes = [_eglPresenter lastUploadBytes];
                _eglBytes += _eglLastUploadBytes;
                if (whole) ++_eglFullUploads; else ++_eglPartialUploads;
                _damageAll = NO; _damageCount = 0;
                _needsPresent = NO;
                if (_eglVerify && (_eglChecks == 1 || _eglChecks % 100 == 0))
                    NSLog(@"AppKit EGL: verified frame %llu of window %p (%zux%zu) against the CPU surface",
                          (unsigned long long)_eglChecks, self, width, height);
                [_display flush];
            }
        }
    } @finally {
        if (CGLSetCurrentContext(previous) != kCGLNoError && !failure)
            failure = @"cannot restore the caller CGL context";
    }
    if (failure) {
        [self failEGLPresentation:failure];
        return NO;
    }
    return YES;
}

- (void) setSurfaceRegion: (uint32_t) opcode rects: (const O2Rect *) rects count: (int) count {
    union wl_argument args[4] = {{.o = NULL}};
    struct wl_proxy *region = NULL;
    if (count > 0) {
        region = WaylandCreateObject(_display->_compositor, WP_COMPOSITOR_CREATE_REGION,
                                     &wl_region_interface, args, 0, nil);
        for (int i = 0; i < count; i++) {
            args[0].i = (int32_t) rects[i].origin.x;
            args[1].i = (int32_t) rects[i].origin.y;
            args[2].i = (int32_t) rects[i].size.width;
            args[3].i = (int32_t) rects[i].size.height;
            WaylandMarshal(region, WP_REGION_ADD, NULL, 0, args);
        }
    }
    args[0].o = (struct wl_object *) region;
    WaylandMarshal(_surface, opcode, NULL, 0, args);
    if (region != NULL)
        sendRequest(region, WP_REGION_DESTROY, WL_MARSHAL_FLAG_DESTROY);
}

// Window geometry (so the compositor snaps, tiles and sizes the visible edge),
// the input region (visible window plus the resize band; the rest of the
// shadow passes clicks through) and the opaque region (without the rounded
// corners). All are applied by the next commit.
- (void) updateSurfaceRegions {
    if (_toplevel == NULL)
        return;
    NSSize logical = [self logicalSurfaceSize];
    O2Rect visible = O2RectMake(_margin, _margin, logical.width - 2 * _margin, logical.height - 2 * _margin);
    if (NSEqualRects(visible, _sentGeometry))
        return;
    _sentGeometry = visible;
    union wl_argument args[4] = {{.i = (int32_t) visible.origin.x}, {.i = (int32_t) visible.origin.y},
                                 {.i = (int32_t) visible.size.width}, {.i = (int32_t) visible.size.height}};
    WaylandMarshal(_xdgSurface, WP_XDG_SURFACE_SET_WINDOW_GEOMETRY, NULL, 0, args);
    O2Rect input = NSInsetRect(visible, -NSTitlebarResizeOutside, -NSTitlebarResizeOutside);
    [self setSurfaceRegion: WP_SURFACE_SET_INPUT_REGION rects: &input count: _margin > 0 ? 1 : 0];
    CGFloat r = _margin > 0 ? NSTitlebarCornerRadius : 0;
    O2Rect opaque[3] = {
        O2RectMake(visible.origin.x + r, visible.origin.y, visible.size.width - 2 * r, r),
        O2RectMake(visible.origin.x, visible.origin.y + r, visible.size.width, visible.size.height - 2 * r),
        O2RectMake(visible.origin.x + r, NSMaxY(visible) - r, visible.size.width - 2 * r, r),
    };
    [self setSurfaceRegion: WP_SURFACE_SET_OPAQUE_REGION rects: r > 0 ? opaque : &visible
                     count: !_isOpaque ? 0 : r > 0 ? 3 : 1];
}

// Rounded corners and the shadow margin need alpha even in opaque windows.
- (BOOL) presentsOpaque {
    return _isOpaque && !_clientDecorated;
}

// DARLING_APPKIT_DAMAGE_VERIFY=1: the buffer about to be committed must equal
// the backing store everywhere, not only where damage was copied.
- (void) verifyBuffer: (struct WaylandBuffer *) buffer pixels: (const uint8_t *) pixels stride: (size_t) stride {
    size_t width = (size_t) buffer->width, stale = 0;
    for (size_t row = 0; row < (size_t) buffer->height; row++) {
        const uint8_t *have = (const uint8_t *) buffer->data + row * width * 4, *want = pixels + row * stride;
        if (memcmp(have, want, width * 4) != 0)
            for (size_t x = 0; x < width; x++)
                stale += memcmp(have + x * 4, want + x * 4, 4) != 0;
    }
    ++_verifiedPresents;
    if (stale != 0) {
        ++_staleVerifiedPresents;
        NSLog(@"Wayland damage verification: %zu stale pixels in present %llu", stale,
              (unsigned long long) _clientPresents + 1);
    }
}

// Copies what changed into a shm buffer and commits it, at most once per
// frame callback.
- (void) presentIfPossible {
    if ([_delegate isFlushWindowDisabled] || !_needsPresent || !_mapped || !_configured || _configureUpdatePending || _frameCallback != NULL ||
        _context == nil)
        return;

    O2Surface *surface = [_context surface];
    size_t width = O2SurfaceGetWidth(surface);
    size_t height = O2SurfaceGetHeight(surface);
    size_t sourceStride = O2SurfaceGetBytesPerRow(surface);
    const uint8_t *pixels = O2SurfaceGetPixelBytes(surface);
    if (pixels == NULL || width == 0 || height == 0 || sourceStride < width * 4)
        return;

    struct timespec started;
    if (_presentTiming) clock_gettime(CLOCK_MONOTONIC, &started);
    if (_eglRequested && _eglFallbackReason == nil && [self presentEGLSurface:surface]) {
        [self recordPresentTime:&started];
        return;
    }

    // Onyx2D's premultiplied, little-endian ARGB is wl_shm's ARGB8888.
    uint32_t format = [self presentsOpaque] ? WP_SHM_FORMAT_XRGB8888 : WP_SHM_FORMAT_ARGB8888;
    struct WaylandBuffer *buffer = [self bufferWithWidth: (int32_t) width
                                                  height: (int32_t) height
                                                  format: format];
    if (buffer == NULL)
        return;

    // Both buffers lack what was drawn since the last present; the one filled
    // two presents ago also lacks what the previous present carried. Copy
    // only what this buffer lacks (both start with the top row).
    O2SurfaceDamage damage;
    O2SurfaceTakeDamage(surface, &damage);
    for (int i = 0; i < 2; i++)
        if (_buffers[i].buffer != NULL)
            O2SurfaceDamageUnion(&_buffers[i].stale, &damage, (int32_t) width, (int32_t) height);
    for (int i = 0; i < buffer->stale.count; i++) {
        O2SurfaceDamageRect r = buffer->stale.rects[i];
        for (int32_t row = r.y; row < r.y + r.height; row++)
            memcpy((uint8_t *) buffer->data + (size_t) row * width * 4 + (size_t) r.x * 4,
                   pixels + (size_t) row * sourceStride + (size_t) r.x * 4, (size_t) r.width * 4);
    }
    _copiedPixels += O2SurfaceDamagePixelCount(&buffer->stale);
    buffer->stale.count = 0;
    if (_damageVerify)
        [self verifyBuffer: buffer pixels: pixels stride: sourceStride];

    union wl_argument args[4] = {{.o = (struct wl_object *) buffer->buffer},
                                 {.i = 0},
                                 {.i = 0}};
    if (_display->_compositorVersion >= 3) {
        union wl_argument scale[1] = {{.i = _fractionalScale ? 1 : _bufferScale}};
        WaylandMarshal(_surface, WP_SURFACE_SET_BUFFER_SCALE, NULL, 0, scale);
    }
    NSSize logical = [self logicalSurfaceSize];
    if (_viewport) {
        union wl_argument destination[] = {{.i = (int32_t)logical.width}, {.i = (int32_t)logical.height}};
        WaylandMarshal(_viewport, WP_VIEWPORT_SET_DESTINATION, NULL, 0, destination);
    }
    WaylandMarshal(_surface, WP_SURFACE_ATTACH, NULL, 0, args);

    // Damage is relative to what the compositor holds. Without
    // damage_buffer (surface coordinates under a scale), or when the size or
    // format changed, the whole surface is damaged.
    if (_display->_compositorVersion < 4 || _committedWidth != (int32_t) width ||
        _committedHeight != (int32_t) height || _committedFormat != format) {
        args[0].i = 0;
        args[1].i = 0;
        args[2].i = _display->_compositorVersion >= 4 ? (int32_t)width : (int32_t)logical.width;
        args[3].i = _display->_compositorVersion >= 4 ? (int32_t)height : (int32_t)logical.height;
        WaylandMarshal(_surface,
                       _display->_compositorVersion >= 4 ? WP_SURFACE_DAMAGE_BUFFER
                                                         : WP_SURFACE_DAMAGE,
                       NULL, 0, args);
        ++_wholeDamagePresents;
        ++_damageRects;
        _damagePixels += (uint64_t) width * height;
    } else {
        for (int i = 0; i < damage.count; i++) {
            args[0].i = damage.rects[i].x;
            args[1].i = damage.rects[i].y;
            args[2].i = damage.rects[i].width;
            args[3].i = damage.rects[i].height;
            WaylandMarshal(_surface, WP_SURFACE_DAMAGE_BUFFER, NULL, 0, args);
        }
        _damageRects += damage.count;
        _damagePixels += O2SurfaceDamagePixelCount(&damage);
    }
    _committedWidth = (int32_t) width;
    _committedHeight = (int32_t) height;
    _committedFormat = format;

    args[0].o = NULL;
    _frameCallback = WaylandCreateObject(_surface, WP_SURFACE_FRAME,
                                         &wl_callback_interface, args,
                                         WaylandObjectFrameCallback, self);

    [self updateSurfaceRegions];
    sendRequest(_surface, WP_SURFACE_COMMIT, 0);
    ++_clientPresents;
    [_clientCapture captureSurface:surface opaque:[self presentsOpaque] scale120:_renderScale120];
    buffer->busy = YES;
    _needsPresent = NO;
    _damageAll = NO; _damageCount = 0;
    [_display flush];
    [self recordPresentTime:&started];
}

- (void) recordPresentTime: (const struct timespec *) started {
    if (!_presentTiming) return;
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    uint64_t elapsed = (uint64_t)(now.tv_sec - started->tv_sec) * 1000000000ull + now.tv_nsec - started->tv_nsec;
    ++_presentsTimed; _presentNanoseconds += elapsed; _lastPresentNanoseconds = elapsed;
    if (elapsed > _maxPresentNanoseconds) _maxPresentNanoseconds = elapsed;
}

#pragma mark - Events

- (void) handleEvent: (uint32_t) opcode
                kind: (WaylandObjectKind) kind
               proxy: (struct wl_proxy *) proxy
           arguments: (union wl_argument *) args
{
    switch (kind) {
    case WaylandObjectSurface:
        if (opcode == WP_SURFACE_EV_ENTER) {
            [_surfaceOutputs addObject: [NSValue valueWithPointer: args[0].o]];
            [self scheduleScaleUpdate];
        } else if (opcode == WP_SURFACE_EV_LEAVE) {
            [self outputRemoved: (struct wl_proxy *) args[0].o];
        }
        break;
    case WaylandObjectXdgSurface:
        if (opcode == WP_XDG_SURFACE_EV_CONFIGURE)
            [self configure: args[0].u];
        break;

    case WaylandObjectToplevel:
        if (opcode == WP_TOPLEVEL_EV_CONFIGURE) {
            _pendingWidth = args[0].i;
            _pendingHeight = args[1].i;
            struct wl_array *states = args[2].a;
            _pendingActivated = WaylandStatesContain(states, WP_TOPLEVEL_STATE_ACTIVATED);
            _pendingMaximized = WaylandStatesContain(states, WP_TOPLEVEL_STATE_MAXIMIZED);
            _pendingFullscreen = WaylandStatesContain(states, WP_TOPLEVEL_STATE_FULLSCREEN);
            _pendingTiled = WaylandStatesContain(states, WP_TOPLEVEL_STATE_TILED_LEFT) ||
                            WaylandStatesContain(states, WP_TOPLEVEL_STATE_TILED_RIGHT) ||
                            WaylandStatesContain(states, WP_TOPLEVEL_STATE_TILED_TOP) ||
                            WaylandStatesContain(states, WP_TOPLEVEL_STATE_TILED_BOTTOM);
        } else if (opcode == WP_TOPLEVEL_EV_CLOSE) {
            [self closeRequested];
        }
        break;

    case WaylandObjectDecoration:
        if (opcode == WP_TOPLEVEL_DECORATION_EV_CONFIGURE)
            _pendingClientDecorated = args[0].u != WP_TOPLEVEL_DECORATION_MODE_SERVER_SIDE;
        break;

    case WaylandObjectPopup:
        if (opcode == WP_POPUP_EV_CONFIGURE) {
            _pendingPopupX = args[0].i;
            _pendingPopupY = args[1].i;
            _pendingWidth = args[2].i;
            _pendingHeight = args[3].i;
        } else if (opcode == WP_POPUP_EV_DONE) {
            NSUInteger generation = _surfaceGeneration;
            [_display performAfterDispatch: ^{
                if (self->_mapped && self->_surfaceGeneration == generation)
                    [self->_display cancelPopupMenus];
            }];
        }
        break;

    case WaylandObjectFrameCallback:
        if (proxy == _frameCallback) {
            WL.wl_proxy_destroy(_frameCallback);
            _frameCallback = NULL;
            [self presentIfPossible];
        }
        break;

    case WaylandObjectBuffer:
        for (int i = 0; i < 2; i++)
            if (_buffers[i].buffer == proxy)
                _buffers[i].busy = NO;
        [self presentIfPossible];
        break;

    default:
        break;
    }
}

// xdg_surface.configure ends a configure sequence: apply the toplevel state.
- (void) configure: (uint32_t) serial {
    union wl_argument args[1] = {{.u = serial}};
    WaylandMarshal(_xdgSurface, WP_XDG_SURFACE_ACK_CONFIGURE, NULL, 0, args);

    if (_configureUpdatePending)
        return;
    _configureUpdatePending = YES;
    NSUInteger generation = _surfaceGeneration;
    [_display performAfterDispatch: ^{
        if (!self->_mapped || self->_surfaceGeneration != generation)
            return;
        self->_configureUpdatePending = NO;
        [self applyConfigure];
    }];
}

- (void) applyConfigure {
    // A fullscreen window has no frame of its own to draw.
    BOOL clientDecorated = _toplevel != NULL && (_styleMask & NSWindowStyleMaskTitled) &&
            _pendingClientDecorated && !_pendingFullscreen;
    // Maximized and tiled windows meet the output or a neighbour edge to edge.
    CGFloat margin = clientDecorated && !_pendingMaximized && !_pendingTiled ? NSTitlebarMargin : 0;
    BOOL decorationChanged = clientDecorated != _clientDecorated || margin != _margin;
    _clientDecorated = clientDecorated;
    _margin = margin;
    _maximized = _pendingMaximized;
    if (decorationChanged) {
        [_context release];
        _context = nil;
        _needsPresent = NO;
        [_delegate platformWindowDidInvalidateCGContext: self];
        [self updateSizeLimits];
    }
    int32_t width, height;
    WaylandFullscreenConfigure(&_fullscreenTracker, _pendingFullscreen,
            WaylandFullscreenRound(_frame.size.width), WaylandFullscreenRound(_frame.size.height),
            _pendingWidth,
            _pendingHeight - (_clientDecorated ? WaylandTitleHeight : 0),
            &width, &height);
    BOOL firstConfigure = !_configured;
    _configured = YES;

    BOOL sized = NO;
    BOOL moved = NO;
    if (_popupParent != nil) {
        NSRect parent = [_popupParent frame];
        NSPoint offset = [_popupParent geometryContentOffset];
        NSPoint origin = NSMakePoint(parent.origin.x + _pendingPopupX - offset.x,
                NSMaxY(parent) - _pendingPopupY + offset.y - _pendingHeight);
        moved = !NSEqualPoints(_frame.origin, origin);
        _frame.origin = origin;
    }
    if (width > 0 && height > 0 &&
        (width != WaylandFullscreenRound(_frame.size.width) ||
         height != WaylandFullscreenRound(_frame.size.height)))
    {
        // Keep the top edge where it was, as the compositor does on screen.
        O2Rect frame = _frame;
        if (_popupParent == nil)
            frame.origin.y += frame.size.height - height;
        frame.size = NSMakeSize(width, height);
        NSWindowTraceFrame("WaylandWindow.configure", _frame, frame);
        [self invalidateContextWithNewSize: frame.size];
        _frame = frame;
        sized = YES;
    }

    [self updateSubwindows];
    [self recheckFullscreen];

    BOOL activationChanged = _pendingActivated != _activated;
    if (activationChanged)
        _decorationsDirty = YES;
    BOOL activated = _pendingActivated;
    _activated = activated;

    if (firstConfigure || sized || moved || activationChanged || decorationChanged) {
        [_display performAfterDispatch: ^{
          NSWindow *delegate = self->_delegate;
          if (delegate == nil)
              return;
          if (sized || moved)
              [delegate platformWindow: self
                          frameChanged: self->_frame
                               didSize: sized];
          if (firstConfigure || sized)
              [delegate platformWindowExposed: self
                                       inRect: NSMakeRect(0, 0,
                                                          self->_frame.size.width,
                                                          self->_frame.size.height)];
          if (firstConfigure || sized || decorationChanged)
              [delegate display];
          else if (activationChanged)
              [self flushBuffer];
          if (activationChanged && activated) {
              [self->_display windowActivated: self];
              if ([delegate attachedSheet] != nil)
                  [[delegate attachedSheet] makeKeyAndOrderFront: delegate];
              else
                  [delegate platformWindowActivated: self displayIfNeeded: YES];
          } else if (activationChanged) {
              [delegate platformWindowDeactivated: self
                          checkForAppDeactivation: NO];
          }
        }];
    }

    [self presentIfPossible];
}

- (void) closeRequested {
    [[NSRunLoop currentRunLoop]
            cancelPerformSelector: @selector(platformWindowWillClose:)
                           target: _delegate
                         argument: self];
    [[NSRunLoop currentRunLoop]
            performSelector: @selector(platformWindowWillClose:)
                     target: _delegate
                   argument: self
                      order: 0
                      modes: @[
                          NSDefaultRunLoopMode, NSModalPanelRunLoopMode,
                          NSEventTrackingRunLoopMode
                      ]];
}

@end
