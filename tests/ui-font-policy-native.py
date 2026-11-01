#!/usr/bin/env python3
from pathlib import Path
import os, shlex, subprocess, tempfile, sys
repo=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='qv-theme-p2-') as directory:
    binary=Path(directory)/'policy'
    flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','dbus-1','fontconfig','freetype2','pango'],text=True))
    subprocess.run(['clang','-std=gnu11','-Wall','-Wextra','-Werror','-UNDEBUG','-fsanitize=address,undefined',str(repo/'tests/ui-font-policy-native.c'),'-o',str(binary),*flags],check=True)
    queue=Path(directory)/'queue'
    wrapped=['dbus_bus_get_private','dbus_connection_set_exit_on_disconnect','dbus_bus_request_name',
        'dbus_connection_pop_message','dbus_connection_read_write','dbus_connection_send',
        'dbus_connection_flush','dbus_connection_close','dbus_connection_unref']
    subprocess.run(['clang','-std=gnu11','-Wall','-Wextra','-Werror','-UNDEBUG','-fsanitize=address,undefined',
        str(repo/'tests/ui-font-portal-queue-native.c'),'-o',str(queue),*flags,
        *['-Wl,--wrap='+name for name in wrapped]],check=True)
    subprocess.run([str(queue)],env={**os.environ,'ASAN_OPTIONS':'detect_leaks=0'},check=True)
    subprocess.run((['dbus-run-session','--',str(binary),'--portal'] if '--portal' in sys.argv else [str(binary)]),env={**os.environ,'ASAN_OPTIONS':'detect_leaks=0'},check=True)
