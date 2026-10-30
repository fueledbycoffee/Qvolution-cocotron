#!/usr/bin/env python3
"""Exercise the production backend selector against isolated Unix sockets.

The selector is compiled without the rest of AppKit. Only its diagnostic NSLog
is suppressed; getenv, access, getuid and path construction are unchanged.
"""
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import unittest


class BackendSelection(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.work = tempfile.TemporaryDirectory(prefix='qv-wl-')
        cls.addClassCleanup(cls.work.cleanup)
        cls.directory = Path(cls.work.name)
        source = (Path(__file__).resolve().parents[1] /
                  'AppKit/Wayland.backend/WaylandLibrary.m').read_text()
        start = source.index('bool WaylandBackendSelected(void) {')
        end = source.index('\nbool WaylandLibraryLoad(void)', start)
        harness = cls.directory / 'selector.c'
        harness.write_text('''#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>
#define NSLog(...) ((void)0)
''' + source[start:end] + '''
int main(void) { printf("%d\\n", WaylandBackendSelected()); }
''')
        cls.binary = cls.directory / 'selector'
        subprocess.run(['clang', '-Wall', '-Wextra', '-Werror',
                        str(harness), '-o', str(cls.binary)], check=True)
        cls.socket_path = cls.directory / 'wayland-test'
        cls.socket = socket.socket(socket.AF_UNIX)
        cls.addClassCleanup(cls.socket.close)
        cls.socket.bind(str(cls.socket_path))

    def select(self, display=None, requested=None, runtime=True):
        env = os.environ.copy()
        for key in ['WAYLAND_DISPLAY', 'XDG_RUNTIME_DIR', 'DARLING_APPKIT_BACKEND']:
            env.pop(key, None)
        if display is not None:
            env['WAYLAND_DISPLAY'] = display
        if requested is not None:
            env['DARLING_APPKIT_BACKEND'] = requested
        if runtime:
            env['XDG_RUNTIME_DIR'] = str(self.directory)
        result = subprocess.run([str(self.binary)], env=env, text=True,
                                capture_output=True, check=True)
        return result.stdout.strip() == '1'

    def test_relative_socket(self):
        self.assertTrue(self.select(self.socket_path.name))

    def test_absolute_socket(self):
        self.assertTrue(self.select(str(self.socket_path)))

    def test_absolute_socket_without_runtime_directory(self):
        self.assertTrue(self.select(str(self.socket_path), runtime=False))

    def test_explicit_x11_wins(self):
        self.assertFalse(self.select(str(self.socket_path), requested='X11'))

    def test_explicit_wayland_wins(self):
        self.assertTrue(self.select(requested='Wayland'))

    def test_unknown_override_uses_autodetection(self):
        self.assertTrue(self.select(self.socket_path.name, requested='unknown'))

    def test_no_advertised_display(self):
        self.assertFalse(self.select())

    def test_nonexistent_socket(self):
        self.assertFalse(self.select('missing-wayland-socket'))

    def test_overlong_display_is_rejected(self):
        self.assertFalse(self.select('/' + 'x' * 2048))


if __name__ == '__main__':
    unittest.main()
