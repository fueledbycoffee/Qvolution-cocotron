#!/usr/bin/env python3
"""SPEC.md Round 3 CPS bridge and standalone-load regression on the host.

Extract only our production bridge. A native HIServices adapter supplies the
specified public sibling; the path adapter substitutes its host filename only.
Each load case runs in a new process without the sibling library preloaded.
This does not execute the full Mach-O frameworks (use the companion fixture).
"""
import argparse
import os
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--arch', choices=['i386', 'x86_64'], default='x86_64')
parser.add_argument('--build-only', action='store_true', help='compile all fixtures without launching them')
args = parser.parse_args()
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
root = Path(__file__).resolve().parents[1]
source = (root / 'CoreGraphics/CGS.m').read_text()
match = re.search(r'^OSErr CPSGetCurrentProcess\(', source, re.MULTILINE)
assert match
start = match.start()
end = source.index('{', start) + 1
depth = 1
while depth:
    depth += (source[end] == '{') - (source[end] == '}')
    end += 1
bridge = r'''
#include <dlfcn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
typedef int16_t OSErr;
typedef struct { uint32_t highLongOfPSN, lowLongOfPSN; } ProcessSerialNumber;
typedef struct { uint32_t highLongOfPSN, lowLongOfPSN; } CPSProcessSerNum;
_Static_assert(sizeof(OSErr) == 2, "OSErr return is signed 16-bit");
_Static_assert(sizeof(ProcessSerialNumber) == 8, "public PSN is eight bytes");
_Static_assert(sizeof(CPSProcessSerNum) == 8, "CPS PSN is eight bytes");
_Static_assert(_Alignof(ProcessSerialNumber) == _Alignof(uint32_t), "PSN alignment");
enum { noErr = 0, paramErr = -50, unimpErr = -4 };
OSErr GetCurrentProcess(ProcessSerialNumber *);
static __attribute__((unused)) void *native_dlopen(const char *path, int flags) {
    if (strcmp(path, "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices")) abort();
    return dlopen(getenv("CGS_TEST_HISERVICES"), flags);
}
#define dlopen native_dlopen
''' + source[start:end] + '\n'
(out / 'bridge.c').write_text(bridge)
(out / 'sibling.c').write_text(r'''
#include <stdint.h>
#include <stdlib.h>
typedef struct { uint32_t highLongOfPSN, lowLongOfPSN; } ProcessSerialNumber;
int16_t GetCurrentProcess(ProcessSerialNumber *psn) {
    psn->highLongOfPSN = 0xabcdef01u;
    psn->lowLongOfPSN = 0x76543210u;
    return (int16_t)strtol(getenv("CGS_TEST_STATUS"), NULL, 10);
}
''')
(out / 'empty.c').write_text('int unrelated_symbol;\n')
(out / 'imports.c').write_text(r'''
#include <stdint.h>
extern int16_t CPSGetCurrentProcess(void *);
int16_t imports_bridge(void *psn) { return CPSGetCurrentProcess(psn); }
''')
(out / 'loader.c').write_text(r'''
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
typedef struct { uint32_t highLongOfPSN, lowLongOfPSN; } CPSProcessSerNum;
#define CHECK(x) do { if (!(x)) { fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#x); return 1; } } while (0)
int main(int argc, char **argv) {
    CHECK(argc == 3);
    CHECK(sizeof(void *) == CGS_TEST_POINTER_BYTES);
    CHECK(dlsym(RTLD_DEFAULT, "GetCurrentProcess") == NULL);
    CHECK(dlopen(getenv("CGS_TEST_HISERVICES"), RTLD_NOW | RTLD_NOLOAD) == NULL);
    void *image = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!image) fprintf(stderr,"dlopen failed: %s\n",dlerror());
    CHECK(image != NULL);
    CHECK(dlsym(RTLD_DEFAULT, "GetCurrentProcess") == NULL);
    int16_t (*current)(CPSProcessSerNum *) = dlsym(image, "CPSGetCurrentProcess");
    CHECK(current != NULL);
    CHECK(current(NULL) == -50);
    CHECK(dlopen(getenv("CGS_TEST_HISERVICES"), RTLD_NOW | RTLD_NOLOAD) == NULL);
    int16_t expected = (int16_t)strtol(argv[2], NULL, 10);
    for (unsigned i = 0; i < 3; ++i) {
        struct { uint32_t before; CPSProcessSerNum psn; uint32_t after; } out = {0x12345678, {3,4}, 0x87654321};
        CHECK(current(&out.psn) == expected);
        CHECK(out.before == 0x12345678 && out.after == 0x87654321);
        if (!expected) CHECK(out.psn.highLongOfPSN == 0xabcdef01 && out.psn.lowLongOfPSN == 0x76543210);
        else CHECK(out.psn.highLongOfPSN == 3 && out.psn.lowLongOfPSN == 4);
    }
    CHECK(dlclose(image) == 0);
    return 0;
}
''')
cc = os.environ.get('CC', 'clang')
flags = [cc, '-m32' if args.arch == 'i386' else '-m64',
         '-DCGS_TEST_POINTER_BYTES=' + ('4' if args.arch == 'i386' else '8'),
         '-Wall', '-Wextra', '-Werror']
def run(command, **kwargs):
    subprocess.run(command, check=True, **kwargs)

# Strict linking catches the original flat-namespace undefined even before load.
run(flags + ['-shared', '-fPIC', str(out / 'bridge.c'), '-Wl,--no-undefined', '-ldl', '-o', str(out / 'libbridge.so')])
assert '-Wl,-U,_GetCurrentProcess' not in (root / 'CoreGraphics/CMakeLists.txt').read_text()
for name in ['sibling', 'empty']:
    run(flags + ['-shared', '-fPIC', str(out / (name + '.c')), '-o', str(out / ('lib' + name + '.so'))])
run(flags + ['-shared', '-fPIC', str(out / 'imports.c'), '-L' + str(out), '-lbridge',
             '-Wl,-rpath,$ORIGIN', '-Wl,--no-undefined', '-o', str(out / 'libimports.so')])
run(flags + [str(out / 'loader.c'), '-ldl', '-o', str(out / 'loader')])
run(flags + [str(root / 'tests/coregraphics-load-control.c'), '-ldl', '-o', str(out / 'control')])
run(flags + [str(root / 'tests/coregraphics-launch-control.c'), '-o', str(out / 'trivial')])
print(f'PASS {args.arch}: compiled strict-link bridge, sibling, loader and trivial control', flush=True)
if args.build_only:
    raise SystemExit(0)
print(f'RUN {args.arch}: trivial native launch control before bridge tests', flush=True)
run([str(out / 'trivial')])
cases = 0
for image in ['libbridge.so', 'libimports.so']:
    for sibling, status, expected in [('libsibling.so', s, s) for s in [0, -4, -50, 1, -32768, 32767]] + [
            ('libempty.so', 0, -4), ('absent.so', 0, -4)]:
        run([str(out / 'loader'), str(out / image), str(expected)], env={**os.environ,
            'CGS_TEST_HISERVICES': str(out / sibling), 'CGS_TEST_STATUS': str(status)})
        cases += 1
print(f'PASS {args.arch}: {cases} fresh-process native loads; strict link, sibling success/errors, null and output preservation')
