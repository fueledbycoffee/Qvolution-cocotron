#!/usr/bin/env python3
"""Run production menu-presentation methods with host view shims and a private bus.

Only repository source is read. No guest, installed runtime or desktop is touched.
Pass --baseline REV to extract the same methods from that component revision.
"""
import argparse
import os
from pathlib import Path
import shlex
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--baseline')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]

def source(path):
    if args.baseline:
        return subprocess.check_output(['git', 'show', f'{args.baseline}:{path}'], cwd=root, text=True)
    return (root / path).read_text()

def block(text, start):
    pos = text.index(start)
    brace = text.index('{', pos)
    depth = 1
    end = brace + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[pos:end]

global_menu = source('AppKit/X11.backend/X11GlobalMenu.m')
window = source('AppKit/NSWindow.m')
frame = source('AppKit/NSThemeFrame.m')
implementation = []
for name in ['updateWaylandMenuPresentation', 'scheduleDBusWrite', 'deferDBusProgressFailure', 'handleDBusDisconnect', 'processPendingDBusEvents', 'queryOrbitIntegration: (int) kind',
             'receiveOrbitReply: (DBusMessage *) reply kind: (int) kind generation: (unsigned int) generation']:
    marker = '- (void) ' + name + ' {'
    implementation.append(block(global_menu, marker) if marker in global_menu else marker + '}')
implementation.append(block(global_menu, '- (void) registerWaylandApplicationMenu:'))
handler = global_menu[global_menu.index('- (DBusHandlerResult) handleDBusMessage: (DBusMessage *) message\n'):]
handler = handler[:handler.index('    if (strcmp(member, "Introspect")')]
layout = block(global_menu, '    if (strcmp(member, "GetLayout") == 0)')
# Keep the entire production reply construction/send path. The boundary shim
# supplies an empty menu tree; canonical item serialization has its own fixture.
implementation.append(handler + layout + 'return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;\n}')
helpers = block(global_menu, 'static void appendBasic(')
if 'static void orbitDiagnostic(' in global_menu:
    helpers += '\n' + block(global_menu, 'static const char *orbitText(')
    helpers += '\n' + block(global_menu, 'static void orbitDiagnostic(')
if 'static BOOL orbitExtensionIsActive(' in global_menu:
    begin = global_menu.index('static BOOL orbitExtensionIsActive(')
    end = global_menu.index('static void dbusSocketCallback', begin)
    helpers += '\n' + global_menu[begin:end]
else:
    helpers += '\nenum { OrbitOwnerQuery, OrbitShellOwnerQuery, OrbitExtensionQuery, OrbitOwnerWatchQuery, OrbitStateWatchQuery };\ntypedef struct { X11GlobalMenu *exporter; int kind; unsigned int generation; } OrbitQuery;\nstatic dbus_bool_t orbitAddTimeout(DBusTimeout *t,void *d){return TRUE;}\nstatic void orbitRemoveTimeout(DBusTimeout *t,void *d){}\nstatic void orbitToggleTimeout(DBusTimeout *t,void *d){}\n'
methods = '\n'.join(block(window, marker) for marker in [
    '+ (NSRect) contentRectForFrameRect:',
    '- (NSRect) frameRectForContentRect:',
    '- (NSRect) contentRectForFrameRect:',
    '- (void) _resizeWithOldMenuViewSize:',
    '- (void) _hideMenuViewIfNeeded',
    '- (void) _showMenuViewIfNeeded'])
harness = (root / 'tests/appkit-orbit-presentation-host.inc').read_text()
harness = harness.replace('/* HELPERS */', helpers).replace('/* EXPORTER */', '\n'.join(implementation))
harness = ('#define FIXTURE_HAS_ALLOCATION_GUARD ' + str(int('if (!reply)' in layout)) + '\n') + harness
harness = harness.replace('/* WINDOW */', methods).replace('/* THEME */', block(frame, '- (void) resizeSubviewsWithOldSize:'))
with tempfile.TemporaryDirectory(prefix='orbit-presentation-host-') as directory:
    path = Path(directory)
    (path / 'fixture.m').write_text(harness)
    flags = shlex.split(subprocess.check_output(['pkg-config', '--cflags', '--libs', 'dbus-1'], text=True))
    objc_include = subprocess.check_output(['gcc', '-print-file-name=include'], text=True).strip()
    subprocess.run(['clang', '-x', 'objective-c', '-fblocks', '-Wno-objc-root-class', '-Wno-objc-method-access',
                    '-Wno-incompatible-pointer-types', '-I' + objc_include, str(path / 'fixture.m'),
                    '-o', str(path / 'fixture'), '-lobjc', '-lm', *flags], check=True)
    diagnostic = path / 'diagnostic.log'
    env = dict(os.environ, DARLING_ORBIT_MENU_DIAGNOSTICS='0')
    subprocess.run(['dbus-run-session', '--', str(path / 'fixture')], env=env, check=True)
    assert not diagnostic.exists()
    if 'static void orbitDiagnostic(' in global_menu:
        # The same original assertions run with diagnostics on and off.
        env['DARLING_ORBIT_MENU_DIAGNOSTICS'] = str(diagnostic)
        subprocess.run(['dbus-run-session', '--', str(path / 'fixture')], env=env, check=True)
        log = diagnostic.read_text()
        for token in ['event=query-request', 'event=query-authentication',
                      'event=query-rejected', 'reason=stale-generation',
                      'event=layout-request', 'sender-valid=0', 'qualified=1',
                      'event=layout-reply', 'queued=0', 'queued=1',
                      'delivery=queue-only', 'event=decision hide=1',
                      'reason=progress-failed', 'reason=disconnect']:
            assert token in log, token
        assert all('pid=' in line and 'event=' in line for line in log.splitlines())
        print('PASS: opt-in diagnostics record authenticated gates and failure controls')
