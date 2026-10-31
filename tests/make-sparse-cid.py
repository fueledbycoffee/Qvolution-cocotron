#!/usr/bin/env python3
"""Original sparse CID fixture derived locally from licensed open Noto CJK; no font bytes committed."""
from fontTools.ttLib import TTFont
from fontTools import subset
from pathlib import Path
import sys,hashlib,json
font=TTFont(sys.argv[1],fontNumber=0)
options=subset.Options();options.glyph_names=True
subsetter=subset.Subsetter(options=options);subsetter.populate(glyphs=['.notdef','cid00034','cid01000']);subsetter.subset(font)
cff=font['CFF '].cff;top=cff.topDictIndex[0]
assert top.ROS and top.charset==['.notdef','cid00034','cid01000'],top.charset
cff.fontNames=['QvolutionSparseCID'];top.FullName='Qvolution Sparse CID';top.FamilyName='Qvolution Sparse CID'
for fd in top.FDArray:
 if hasattr(fd,'FontName'):fd.FontName='QvolutionSparseCIDFD'
data=font['CFF '].compile(font);output=Path(sys.argv[2]);output.write_bytes(data)
print(json.dumps({'output_sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data),'retained_CIDs':[0,34,1000],'source_sha256':hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest(),'source_license':'SIL Open Font License 1.1 (Noto CJK)'}))
