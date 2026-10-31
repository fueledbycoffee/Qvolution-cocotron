# Execute the actual C preflight fragment and audit its placement. This is a
# source-level gate only; public transaction fixture supplies actual runtime proof.
from pathlib import Path
import re, subprocess, sys
root=Path(__file__).resolve().parents[2]
base=root/'Onyx2D'
builtin=(base/'O2Context_builtin.m').read_text()
path=builtin.split('- (void) drawPath:',1)[1].split('- (void) showGlyphs:',1)[0]
fragment=path[path.index('    BOOL usesFill'):path.index('    O2AffineTransform paintMatrix')]
assert path.index('O2ColorSpaceRequireSupportedRendering') < path.index('paintFromColor') < path.index('O2PathApplyTransform')
ft=(base/'O2Context_builtin_FT.m').read_text().split('- (void) showGlyphs:',1)[1]
assert ft.index('O2ColorSpaceRequireSupportedRendering') < ft.index('malloc(') < ft.index('O2SurfaceLock(')
assert '@finally' in ft and ft.index('@finally') < ft.index('O2SurfaceUnlock(')
pdf=(base/'O2PDFContext.m').read_text()
for method in ['drawPath:', 'showGlyphs:', 'drawImage:', 'drawShading:']:
    body=pdf.split('- (void) '+method,1)[1].split('\n- (',1)[0]
    preflight='O2ColorSpaceRequireSupportedRendering' if method=='drawShading:' else 'requirePDFColors'
    assert body.index(preflight) < body.index('[self emitSaveGState]'),method
header=(base/'include/Onyx2D/O2Context.h').read_text()
mode=re.search(r'typedef enum \{\s*kO2PathFill,.*?\} O2PathDrawingMode;',header,re.S).group()
assert len(sys.argv)==2, 'pass an explicit output directory outside the checkout'
out=Path(sys.argv[1]).resolve();assert out.is_absolute() and not out.is_relative_to(root)
out.mkdir(parents=True,exist_ok=True)
source='''#include <stdbool.h>
#include <stdio.h>
typedef bool BOOL;
'''+mode+'''
typedef struct { int _fillColor, _strokeColor; double _lineWidth; } O2GState;
static unsigned checked;
static int O2ColorGetColorSpace(int color) { return color; }
static void O2ColorSpaceRequireSupportedRendering(int color) { checked |= 1u << color; }
static unsigned preflight(O2GState *gState, O2PathDrawingMode drawingMode) {
 checked=0;
'''+fragment+'''return checked;
}
int main(void) {
 O2GState state={0,1,1};
 if(preflight(&state,kO2PathFill)!=1 || preflight(&state,kO2PathEOFill)!=1 ||
    preflight(&state,kO2PathStroke)!=2 || preflight(&state,kO2PathFillStroke)!=3 ||
    preflight(&state,kO2PathEOFillStroke)!=3) return 1;
 state._lineWidth=0;
 if(preflight(&state,kO2PathStroke)!=0 || preflight(&state,kO2PathFillStroke)!=1) return 2;
 puts("ACTUAL_PREFLIGHT_SOURCE_PASS_RUNTIME_TRANSACTION_PENDING"); return 0;
}
'''
(out/'actual-preflight.c').write_text(source)
subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror',str(out/'actual-preflight.c'),'-o',str(out/'actual-preflight')],check=True)
subprocess.run([str(out/'actual-preflight')],check=True)
