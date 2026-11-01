#!/usr/bin/env python3
"""Author nibs from this repository's encoder fields; no vendor nib is read.

Each mode is written twice: <mode>.nib as a keyed archive, and na-<mode>.nib in the
NIBArchive layout that NSNibArchive.m converts (the format modern compilers emit).
"""
from pathlib import Path
import plistlib,sys
from nibfixture import Archive,write_nibarchive
out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
for mode in ['mixed','empty','missing']:
 a=Archive();owner=a.obj('NSCustomObject',['NSObject'],NSClassName=a.add('NSObject'))
 windows=[]
 for title,cls,defer in [('Visible','NSWindow',False),('Progress','NSPanel',False),('Deferred','NSWindow',True)]:
  windows.append(a.obj('NSWindowTemplate',['NSObject'],NSWindowClass=a.add(cls),NSWindowTitle=a.add(title),NSWindowStyleMask=3,NSWindowBacking=2,NSWTFlags=(1<<30)|((1<<29) if defer else 0),NSWindowRect=a.add('{{50, 50}, {240, 120}}'),NSScreenRect=a.add('{{0, 0}, {1024, 768}}'),NSWindowView=a.view(240,120)))
 fields=dict(NSRoot=owner,NSObjectsKeys=a.array(windows),NSObjectsValues=a.array([owner]*3),NSNamesKeys=a.array([owner]),NSNamesValues=a.array([a.add("File's Owner")]),NSConnections=a.array([]))
 if mode!='missing':fields['NSVisibleWindows']=a.obj('NSSet',['NSObject'],**{'NS.objects':windows[:1] if mode=='mixed' else []})
 data=a.obj('NSIBObjectData',['NSObject'],**fields)
 with (out/(mode+'.nib')).open('wb') as f:plistlib.dump({'$archiver':'NSKeyedArchiver','$version':100000,'$top':{'IB.objectdata':data},'$objects':a.objects},f,fmt=plistlib.FMT_BINARY)
 write_nibarchive(out/('na-'+mode+'.nib'),a,data)
