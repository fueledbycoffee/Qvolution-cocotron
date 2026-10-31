#!/usr/bin/env python3
"""Build an entirely original two-glyph registered-axis SFNT; no font bytes committed."""
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
import sys
fb=FontBuilder(1000,isTTF=True);fb.setupGlyphOrder(['.notdef','W']);fb.setupCharacterMap({87:'W'})
glyphs={}
for name in ('.notdef','W'):
 pen=TTGlyphPen(None)
 if name=='W':pen.moveTo((0,0));pen.lineTo((600,0));pen.lineTo((600,700));pen.lineTo((0,700));pen.closePath()
 glyphs[name]=pen.glyph()
fb.setupGlyf(glyphs);fb.setupHorizontalMetrics({'.notdef':(600,0),'W':(600,0)});fb.setupHorizontalHeader(ascent=800,descent=-200)
fb.setupNameTable({'familyName':'Qvolution Variable Style Vector','styleName':'Regular','uniqueFontIdentifier':'QvolutionVariableStyleVector1','fullName':'Qvolution Variable Style Vector Regular','psName':'QvolutionVariableStyleVector-Regular','version':'Version 1.0'})
fb.setupOS2(sTypoAscender=800,sTypoDescender=-200,usWinAscent=800,usWinDescent=200);fb.setupPost();fb.setupMaxp()
fb.setupFvar([('wght',1,400,1000,'Weight'),('ital',0,0,1,'Italic'),('slnt',-20,0,20,'Slant')],[]);fb.setupGvar({})
fb.save(sys.argv[1])
