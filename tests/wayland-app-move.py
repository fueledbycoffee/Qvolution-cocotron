#!/usr/bin/env python3
"""Run production WaylandWindow move/frame methods with native protocol doubles.

Like wayland-decoration-inputs.py, compile the actual method bodies as C++ with
unrelated rendering mocked out. Optional revision tests the unchanged baseline:
  python3 tests/wayland-app-move.py a360e4d95
No compositor, guest application, or Objective-C runtime is needed.
"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]

def read(path):
    if len(sys.argv) > 1:
        return subprocess.check_output(['git', 'show', f'{sys.argv[1]}:{path}'], cwd=root, text=True)
    return (root / path).read_text()

window = read('AppKit/Wayland.backend/WaylandWindow.m')
display = read('AppKit/Wayland.backend/WaylandDisplay.m')

def body(selector, fallback=None):
    match = re.search(r'- \(void\) ' + re.escape(selector) + r'[^\{]*\{\n(.*?)\n}', window, re.S)
    if match:
        return match[1]
    if fallback is not None:
        return fallback
    raise AssertionError(f'missing method {selector}')

def adapt(code):
    replacements = {
        '[self invalidateContextWithNewSize: frame.size]': 'invalidateContextWithNewSize(frame.size)',
        '[self isDecorationPoint: point]': 'isDecorationPoint(point)',
        '[_display seat]': '_display->seat()', '[_display flush]': '_display->flush()',
        '[NSApp currentEvent]': 'NSApp->currentEvent()',
        '[event window]': 'event->window()', '[event type]': 'event->type()',
        '[self setButtonHover: NO shownPressed: NSTitlebarButtonNone]': 'setButtonHover(NO, 0)',
    }
    for before, after in replacements.items():
        code = code.replace(before, after)
    return re.sub(r'\[self (\w+)\]', r'\1()', code)

source = r'''
#include <cassert>
#include <cstdio>
#include <algorithm>
#include "WaylandProtocol.h"
struct wl_proxy;
using BOOL = bool;
#define YES true
#define NO false
#define MAX(a,b) std::max(double(a), double(b))
struct Point {double x,y;};
struct Size {double width,height;};
struct O2Rect {Point origin; Size size;};
using CGPoint = Point;
using NSEvent = struct Event;
constexpr int NSLeftMouseDown=1, NSLeftMouseDragged=2, NSRightMouseDown=3;
bool NSEqualPoints(Point a, Point b) {return a.x==b.x && a.y==b.y;}
bool NSEqualSizes(Size a, Size b) {return a.width==b.width && a.height==b.height;}
int WaylandFullscreenRound(double x) {return x;}
void WaylandFullscreenApplicationResized(int *, int, int) {}
int topObject, seatObject, otherSeatObject, popupObject;
auto top = reinterpret_cast<wl_proxy *>(&topObject);
auto seat = reinterpret_cast<wl_proxy *>(&seatObject);
auto otherSeat = reinterpret_cast<wl_proxy *>(&otherSeatObject);
auto popup = reinterpret_cast<wl_proxy *>(&popupObject);
unsigned moves=0, repositions=0, lastSerial=0;
wl_proxy *lastSeat=nullptr;
void WaylandMarshal(wl_proxy *object, uint32_t op, const void *, uint32_t, wl_argument *args) {
    if (object==top) {
        assert(op==WP_TOPLEVEL_MOVE); moves++;
        lastSeat=reinterpret_cast<wl_proxy *>(args[0].o); lastSerial=args[1].u;
    } else {assert(object==popup && op==WP_POPUP_REPOSITION); repositions++;}
}
void sendRequest(wl_proxy *, int, int) {}
constexpr int WL_MARSHAL_FLAG_DESTROY=1, NSTitlebarButtonNone=0;
struct {unsigned (*wl_proxy_get_version)(wl_proxy *);} WL = {[](wl_proxy *) {return 3u;}};
struct Display {wl_proxy *currentSeat=::seat; unsigned flushes=0;
    wl_proxy *seat() {return currentSeat;} void flush() {flushes++;}};
struct Event {void *owner; int kind; void *window() {return owner;} int type() {return kind;}};
struct Application { Event event{nullptr,0}; Event *currentEvent() {return &event;} } application;
auto NSApp=&application;
struct Window {
    Display display, *_display=&display;
    wl_proxy *_toplevel=top, *_popup=nullptr, *_appMoveSeat=nullptr;
    uint32_t _appMoveSerial=0, _repositionToken=0;
    int _fullscreenTracker=0, owner=0; void *_delegate=&owner;
    BOOL _clientDecorated=false, _appMoveDragged=false;
    O2Rect _frame={{10,20},{200,100}};
    bool isDecorationPoint(Point p) {return _clientDecorated && p.y<20;}
    void invalidateContextWithNewSize(Size) {} void updateSubwindows() {}
    void updateSizeLimits() {} void updateFullscreen() {} void setButtonHover(bool,int) {}
    wl_proxy *newPopupPositioner() {return nullptr;}
'''
methods = [
    ('cancelAppMovePress', 'void cancelAppMovePress()', ''),
    ('appMoveMotion:', 'void appMoveMotion(BOOL leftHeld)', ''),
    ('beginWindowDrag', 'void beginWindowDrag()', ''),
    ('appMoveButton:', 'void appMoveButton(uint32_t button, BOOL pressed, uint32_t serial, CGPoint point)', ''),
    ('performWindowDragWithEvent:', 'void performWindowDragWithEvent(Event *event)', ''),
    ('decorationPointerLeft', 'void decorationPointerLeft()', None),
    ('setFrame:', 'void setFrame(O2Rect frame)', None),
]
for selector, signature, fallback in methods:
    source += signature + '{\n' + adapt(body(selector, fallback)) + '\n}\n'
source += r'''
    void press(unsigned serial=41) {
        NSApp->event={_delegate,NSLeftMouseDown};
        appMoveButton(WP_BTN_LEFT, YES, serial, {50,50});
    }
    void drag() {appMoveMotion(YES); NSApp->event={_delegate,NSLeftMouseDragged};}
    void release() {appMoveButton(WP_BTN_LEFT, NO, 900, {50,50});}
    void shift() {O2Rect f=_frame; f.origin.x+=5; setFrame(f);}
};
int main() {
    // Review negative control: mouseDown action repositions before any motion.
    Window click;
    click.press(104); click.shift(); assert(moves==0);
    click.appMoveMotion(NO); click.shift(); assert(moves==0); // motion without left held
    Window unrelated;
    unrelated.drag(); click.shift(); assert(moves==0); // different window
    click.appMoveMotion(YES); click.shift(); assert(moves==0); // wrong event window
    NSApp->event={click._delegate,NSLeftMouseDown};
    click.shift(); assert(moves==0); // motion alone is not app drag context
    click.drag(); click.release(); click.shift(); assert(moves==0);
    // Explicit API still supports a content left-down without prior motion.
    click.press(105); Event down{click._delegate,NSLeftMouseDown};
    click.performWindowDragWithEvent(&down); assert(moves==1 && lastSerial==105);
    moves=0;
    Window w;
    w.shift(); assert(moves==0); // programmatic movement
    w.press(); w.setFrame(w._frame); assert(moves==0); // unchanged frame
    O2Rect resized=w._frame; resized.origin.y+=3; resized.size.width+=10;
    w.setFrame(resized); assert(moves==0); // size+origin is not a drag
    w.drag(); w.shift(); assert(moves==1 && lastSerial==41 && lastSeat==seat);
    for (int i=0;i<144;i++) w.shift();
    assert(moves==1 && w._frame.origin.x==740); // requested bookkeeping is retained
    w.release(); w.shift(); assert(moves==1);
    w.press(42); w.release(); w.shift(); assert(moves==1); // released before frame update
    w.appMoveButton(WP_BTN_RIGHT, YES, 43, {50,50}); w.shift(); assert(moves==1);
    w.press(44); w.decorationPointerLeft(); w.shift(); assert(moves==1);
    // A compositor move may swallow release. A new press must still work.
    w.press(45); w.drag(); w.shift(); assert(moves==2 && lastSerial==45);
    w.decorationPointerLeft(); w.press(46); w.drag(); w.shift(); assert(moves==3 && lastSerial==46);
    w.press(47); w.cancelAppMovePress(); w.shift(); assert(moves==3); // unmap/device loss
    w._clientDecorated=true;
    w.appMoveButton(WP_BTN_LEFT, YES, 48, {50,10}); w.shift(); assert(moves==3); // our chrome
    w._clientDecorated=false; w._toplevel=nullptr; w._popup=popup;
    w.press(49); w.shift(); assert(moves==3 && repositions==1); // popup placement survives
    w._popup=nullptr; w.shift(); assert(moves==3); // no toplevel role
    w._toplevel=top; w.display.currentSeat=nullptr;
    w.press(50); w.shift(); assert(moves==3); // no seat
    w.display.currentSeat=seat; w.press(51); w.display.currentSeat=otherSeat;
    w.appMoveButton(WP_BTN_RIGHT, NO, 80, {50,50}); w.drag(); w.shift();
    assert(moves==4 && lastSeat==seat && lastSerial==51); // initiating seat, not current serial
    Event event{w._delegate, NSLeftMouseDown};
    w.performWindowDragWithEvent(&event); assert(moves==4); // no held press
    w.press(52); event.owner=nullptr; w.performWindowDragWithEvent(&event); assert(moves==4);
    event.owner=w._delegate; event.kind=NSRightMouseDown;
    w.performWindowDragWithEvent(&event); assert(moves==4);
    event.kind=NSLeftMouseDragged; w.performWindowDragWithEvent(&event);
    w.shift(); assert(moves==5 && lastSerial==52 && lastSeat==otherSeat);
    puts("PASS: one move per content press, exact seat/serial, no programmatic/resize/popup/decoration moves, reset and explicit drag");
}
'''
with tempfile.TemporaryDirectory(prefix='wayland-app-move-') as directory:
    path = Path(directory)
    (path / 'test.cpp').write_text(source)
    subprocess.run(['c++', '-std=c++17', '-Wall', '-Wextra', '-Wno-unused-parameter',
                    '-fsanitize=address,undefined', '-I' + str(root / 'AppKit/Wayland.backend'),
                    str(path / 'test.cpp'), '-o', str(path / 'test')], check=True)
    subprocess.run([str(path / 'test')], check=True)

# Check that the event decoder reaches the tested method before app delivery,
# and that both protocol focus loss and device/unmap teardown clear the press.
button = display.split('case WP_POINTER_EV_BUTTON: {', 1)[1].split('case WP_POINTER_EV_AXIS:', 1)[0]
assert button.index('appMoveButton: args[2].u') < button.index('[self pointerButton:')
assert 'serial: args[0].u atPoint: _pointerSurfacePoint' in button
leave = display.split('case WP_POINTER_EV_LEAVE:', 1)[1].split('case WP_POINTER_EV_MOTION:', 1)[0]
assert '[_pointerWindow decorationPointerLeft]' in leave
loss = display.split('!(capabilities & WP_SEAT_CAPABILITY_POINTER)', 1)[1].split('WP_SEAT_CAPABILITY_KEYBOARD', 1)[0]
assert '[_pointerWindow decorationPointerLeft]' in loss
assert '[self cancelAppMovePress]' in body('unmap')
assert '[platform performWindowDragWithEvent: event]' in read('AppKit/NSWindow.m')
motion = display.split('- (void) pointerMotionToX:', 1)[1].split('- (void) pointerButton:', 1)[0]
assert 'if (!NSEqualPoints(location, last))' in motion
assert '[window appMoveMotion: (_pressedButtons & 1) != 0]' in motion
assert motion.index('[window appMoveMotion:') < motion.index('[self postEvent:')
print('PASS: pointer decoder, focus/device loss, unmap, and NSWindow drag bridge wiring')
