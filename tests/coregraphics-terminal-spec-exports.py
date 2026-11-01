#!/usr/bin/env python3
"""Audit our built Mach-O images for SPEC.md Round 3 demand and companions.

Pass only Darling build outputs via --image, never guest or Apple images. The
check covers exports, not ABI correctness, behavior, or umbrella re-export paths.
A missing name is a failing gate, including when its ABI is deliberately pending.
"""
import argparse
import json
from pathlib import Path
import subprocess

DEMAND = [
    'CGContextGetAllowsAntialiasing',
    'CGContextSetAllowsAntialiasing',
    'CGSDefaultConnectionForThread',
    'CGSSetSecureEventInput',
    'CGSSetWindowBackgroundBlurRadius',
    'CPSGetCurrentProcess',
    'CPSReleaseKeyFocus',
    'CPSStealKeyFocus',
]
COMPANIONS = [
    'CGContextSetShouldAntialias', 'CGContextGetShouldAntialias',
    'CGContextSetAllowsFontSmoothing', 'CGContextGetAllowsFontSmoothing',
    'CGContextSetShouldSmoothFonts', 'CGContextGetShouldSmoothFonts',
    'CGContextSetFontSmoothingStyle', 'CGContextGetFontSmoothingStyle',
    'CGSSetWindowBackgroundBlurRadiusWithOpacityHint',
    'CGSSetWindowBackgroundBlurRadiusStyle',
]
SPEC_NAMES = DEMAND + COMPANIONS
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--image', action='append', type=Path, required=True,
                    help='a framework image built from our source (repeatable)')
parser.add_argument('--arch', action='append', required=True,
                    help='Mach-O architecture to inspect (repeatable)')
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
results = {}
for arch in args.arch:
    providers = {name: [] for name in SPEC_NAMES}
    for image in args.image:
        raw = subprocess.check_output([
            'llvm-nm', '--arch=' + arch, '--defined-only', '--extern-only',
            '--format=posix', str(image.resolve())], text=True)
        exports = {line.split()[0] for line in raw.splitlines() if line.split()}
        for name in SPEC_NAMES:
            if '_' + name in exports:
                providers[name].append(str(image.resolve()))
    missing = [name for name, images in providers.items() if not images]
    results[arch] = {'providers': providers, 'missing': missing}
report = {'source': 'parallel/cgs-cleanroom/SPEC.md Round 3; rung 5 demand, rung 2/6 companions',
          'scope': 'specified built images; export presence only',
          'architectures': results,
          'passed': all(not result['missing'] for result in results.values())}
args.output.write_text(json.dumps(report, indent=2) + '\n')
for arch, result in results.items():
    print(f'{arch}: {len(SPEC_NAMES) - len(result["missing"])}/{len(SPEC_NAMES)} SPEC names exported')
    for name in result['missing']:
        print('MISSING ' + name)
raise SystemExit(0 if report['passed'] else 1)
