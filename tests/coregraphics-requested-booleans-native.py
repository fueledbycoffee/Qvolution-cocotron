#!/usr/bin/env python3
"""Exercise the four public setters from the clean-room SPEC, on host libobjc.

Compile unchanged production bridge/backend bodies with allocation and state-access
adapters. Observe our internal storage, avoiding any private getter declaration.
This checks explicit caller requests only: no defaults, save/restore, null-context,
rendering, private ABI, or Apple compatibility claim is made.

Run under qv-slot build because this script invokes clang.
"""
import argparse
import os
from pathlib import Path
import re
import subprocess


def definition(source, prefix):
    """Copy a whole production definition, rejecting a missing/ambiguous match."""
    matches = list(re.finditer(r'^' + re.escape(prefix), source, re.MULTILINE))
    if len(matches) != 1:
        raise ValueError(f'expected one definition: {prefix}')
    start = matches[0].start()
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end] + '\n'


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
component = Path(__file__).resolve().parents[1]
args.output.mkdir(parents=True, exist_ok=True)
bridge = (component / 'CoreGraphics/CGContext.m').read_text()
backend = (component / 'Onyx2D/O2Context.m').read_text()
state = (component / 'Onyx2D/O2GraphicsState.m').read_text()
names = ['AllowsAntialiasing', 'ShouldAntialias', 'AllowsFontSmoothing',
         'ShouldSmoothFonts']
preamble = r'''
#include <objc/Object.h>
#include <objc/runtime.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
@interface O2GState : Object {
@public
    BOOL _shouldAntialias, _shouldSmoothFonts, _fontIsDirty;
}
- (void) setShouldAntialias: (BOOL) flag;
- (void) setShouldSmoothFonts: (BOOL) flag;
@end
@interface O2Context : Object {
@public
    BOOL _allowsAntialiasing, _allowsFontSmoothing;
    O2GState *_currentState;
}
@end
@implementation O2Context
@end
typedef O2Context *O2ContextRef;
typedef O2Context *CGContextRef;
static O2GState *O2ContextCurrentGState(O2ContextRef context) {
    return context->_currentState;
}
@implementation O2GState
'''
methods = ''.join(definition(state, '- (void) set' + name + ':')
                  for name in ['ShouldAntialias', 'ShouldSmoothFonts'])
functions = ''.join(definition(backend, 'void O2ContextSet' + name + '(')
                    for name in names)
functions += ''.join(definition(bridge, 'void CGContextSet' + name + '(')
                     for name in names)
main = r'''
typedef void (*Setter)(CGContextRef, bool);
static Setter setters[] = {
    CGContextSetAllowsAntialiasing, CGContextSetShouldAntialias,
    CGContextSetAllowsFontSmoothing, CGContextSetShouldSmoothFonts
};
static unsigned checks;
static void verify(O2Context *context, const bool expected[4]) {
    bool actual[] = {
        !!context->_allowsAntialiasing, !!context->_currentState->_shouldAntialias,
        !!context->_allowsFontSmoothing, !!context->_currentState->_shouldSmoothFonts
    };
    for (unsigned i = 0; i < 4; i++) {
        checks++;
        if (actual[i] != expected[i]) {
            fprintf(stderr, "FAIL explicit request slot %u: got %u expected %u\n",
                    i, actual[i], expected[i]);
            exit(1);
        }
    }
}
int main(void) {
    O2Context *contexts[2];
    bool expected[2][4];
    for (unsigned c = 0; c < 2; c++) {
        contexts[c] = class_createInstance(objc_getClass("O2Context"), 0);
        contexts[c]->_currentState = class_createInstance(objc_getClass("O2GState"), 0);
        if (!contexts[c]->_currentState) return 2;
        // Every setting is explicitly written before any observation.
        for (unsigned i = 0; i < 4; i++) {
            expected[c][i] = (c != 0);
            setters[i](contexts[c], expected[c][i]);
        }
    }
    for (unsigned mask = 0; mask < 16; mask++) {
        for (unsigned c = 0; c < 2; c++) {
            for (unsigned i = 0; i < 4; i++) {
                expected[c][i] = ((mask >> i) & 1) != 0;
                setters[i](contexts[c], expected[c][i]);
                // Check each requested value and both contexts after each write.
                verify(contexts[0], expected[0]);
                verify(contexts[1], expected[1]);
            }
        }
    }
    for (unsigned c = 0; c < 2; c++) {
        object_dispose(contexts[c]->_currentState);
        object_dispose(contexts[c]);
    }
    printf("PASS requested booleans: %u checks, four setters, two contexts\n", checks);
    return 0;
}
'''
source = args.output / 'requested-booleans.m'
source.write_text(preamble + methods + '\n@end\n' + functions + main)
include = subprocess.check_output(['gcc', '-print-file-name=include'], text=True).strip()
binary = args.output / 'requested-booleans'
subprocess.run(['clang', '-O1', '-g', '-Wall', '-Wextra', '-Werror',
                '-fobjc-runtime=gcc', '-fsanitize=address,undefined',
                '-fno-omit-frame-pointer', '-I' + include, str(source),
                '-lobjc', '-o', str(binary)], check=True)
# GNU libobjc keeps process-global registrations alive at exit.
subprocess.run([str(binary)], check=True,
               env={**os.environ, 'ASAN_OPTIONS': 'detect_leaks=0'})
