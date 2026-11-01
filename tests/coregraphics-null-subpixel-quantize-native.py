#!/usr/bin/env python3
"""Compile the exact two setters with a host-only graphics-state shim.

No framework initialization, rendering, or guest ABI is exercised. Only the
named setter bodies are extracted; no neighboring setters or getters are used.
--baseline uses the lane's specified a360e4d95 source and should exit 139.
"""
import argparse
from pathlib import Path
import resource
import signal
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)


def setter(path, name):
    if args.baseline:
        source = subprocess.check_output(
            ['git', '-C', str(root), 'show', 'a360e4d95:' + path], text=True)
    else:
        source = (root / path).read_text()
    lines = source.splitlines(keepends=True)
    start = next(i for i, line in enumerate(lines)
                 if line.startswith('void ' + name + '('))
    end = next(i for i in range(start, len(lines)) if lines[i].strip() == '}')
    return ''.join(lines[start:end + 1])


functions = output / 'setters.inc'
functions.write_text('''
#include <stddef.h>
typedef signed char BOOL;
struct NativeState { BOOL _shouldSubpixelQuantizeFonts; };
struct NativeContext { struct NativeState *state; };
typedef struct NativeContext *O2ContextRef;
typedef struct NativeContext *CGContextRef;
static unsigned stateAccesses;
/* Minimal state lookup shim: NULL must never reach this layer. */
static struct NativeState *O2ContextCurrentGState(O2ContextRef context)
{
    ++stateAccesses;
    return context->state;
}
''' + setter('Onyx2D/O2Context.m', 'O2ContextSetShouldSubpixelQuantizeFonts')
    + '\n' + setter('CoreGraphics/CGContext.m',
                       'CGContextSetShouldSubpixelQuantizeFonts'))
binary = output / 'null-subpixel-quantize'
# Keep native build scheduling consistent with the fleet's ninja -j6 rule.
(output / 'build.ninja').write_text('''rule compile
  command = clang -std=c11 -O0 -g -Wall -Wextra -Werror -DNATIVE_FUNCTIONS='"''' +
    str(functions) + '''"' $in -o $out
build ''' + str(binary) + ': compile ' +
    str(root / 'tests/coregraphics-null-subpixel-quantize.c') + ' | ' +
    str(functions) + '\n')
subprocess.run(['ninja', '-C', str(output), '-n'], check=True)
subprocess.run(['ninja', '-C', str(output), '-j6'], check=True)
# Preserve failure evidence as the exit status without producing a core dump.
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
result = subprocess.run([str(binary)])
if result.returncode < 0:
    print('native signal=' + signal.Signals(-result.returncode).name, flush=True)
    raise SystemExit(128 - result.returncode)
raise SystemExit(result.returncode)
