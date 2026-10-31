#!/usr/bin/env python3
"""Actual private inspector type + own NSButtonCell mask/predicate source."""
from pathlib import Path
import argparse,re,subprocess,tempfile
repo=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--baseline',help='own-source git revision');args=parser.parse_args()
def read(name):
 return subprocess.check_output(['git','show',args.baseline+':'+name],cwd=repo,text=True)if args.baseline else(repo/name).read_text()
bar=read('AppKit/NSTextView.subproj/NSTextInspectorBar.m');cell=read('AppKit/NSButtonCell.m');header=read('AppKit/include/AppKit/NSButtonCell.h')
kind=re.search(r'\[button setButtonType:(\w+)\]',bar).group(1)
case=re.search(r'case '+kind+r':(.*?)break;',cell,re.S).group(1)
highlights=re.search(r'_highlightsBy\s*=\s*([^;]+)',case).group(1);shows=re.search(r'_showsStateBy\s*=\s*([^;]+)',case).group(1)
constants='\n'.join('enum {'+name+'='+value+'};'for name,value in re.findall(r'\b(NS\w+CellMask)\s*=\s*(0x[0-9A-Fa-f]+|\d+)',header))
predicate=re.search(r'- \(BOOL\) isVisuallyHighlighted \{(.*?)\n\}',cell,re.S).group(1)
for message,value in [('[self highlightsBy]','highlights'),('[self showsStateBy]','shows'),('[self isHighlighted]','pressed'),('[self state]','state')]:predicate=predicate.replace(message,value)
program='#include <stdio.h>\n'+constants+'\nstatic int visual(int state,int pressed){int highlights='+highlights+',shows='+shows+';'+predicate+'}\nint main(void){printf("releasedOff=%d releasedOn=%d pressedOff=%d\\n",visual(0,0),visual(1,0),visual(0,1));return visual(0,0)||!visual(1,0)||!visual(0,1);}\n'
with tempfile.TemporaryDirectory(prefix='qv-inspector-state-')as d:
 path=Path(d);(path/'probe.c').write_text(program);subprocess.run(['cc',str(path/'probe.c'),'-o',str(path/'probe')],check=True);raise SystemExit(subprocess.run([str(path/'probe')]).returncode)
