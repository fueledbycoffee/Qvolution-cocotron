#!/usr/bin/env python3
"""Reject silent omission of required x86_64 Swift imports at configure time."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
cmake = root / 'CoreGraphics/CMakeLists.txt'
gate = root / 'CoreGraphics/SwiftToolchain.cmake'
if gate.exists():
    body = f'include("{gate}")\n'
else:
    # Exercise the reviewed configure gate without the unrelated framework graph.
    source = cmake.read_text()
    start = source.index('set(DARLING_COREGRAPHICS_SWIFTC')
    end = source.index('    set(import_object', start)
    body = source[start:end] + '\nendif()\n'
with tempfile.TemporaryDirectory() as directory:
    script = Path(directory) / 'gate.cmake'
    script.write_text('set(BUILD_TARGET_64BIT TRUE)\nset(APPLE_ARCH_64BIT x86_64)\n' + body)
    result = subprocess.run(['cmake', '-P', str(script)], capture_output=True, text=True)
    print(result.stdout + result.stderr)
    assert result.returncode != 0, 'configure silently omitted the required Swift imports'
    assert 'DARLING_COREGRAPHICS_SWIFTC' in result.stderr, 'missing actionable toolchain diagnostic'
    print('PASS ordinary x86_64 configuration rejects missing Swift inputs')
