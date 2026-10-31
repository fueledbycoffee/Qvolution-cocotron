#!/usr/bin/env python3
from pathlib import Path
import os, shlex, subprocess, tempfile, sys
repo=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='qv-theme-p2-') as directory:
    binary=Path(directory)/'policy'
    flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','dbus-1','fontconfig','freetype2','pango'],text=True))
    subprocess.run(['clang','-std=gnu11','-Wall','-Wextra','-Werror','-UNDEBUG','-fsanitize=address,undefined',str(repo/'tests/ui-font-policy-native.c'),'-o',str(binary),*flags],check=True)
    subprocess.run((['dbus-run-session','--',str(binary),'--portal'] if '--portal' in sys.argv else [str(binary)]),env={**os.environ,'ASAN_OPTIONS':'detect_leaks=0'},check=True)
