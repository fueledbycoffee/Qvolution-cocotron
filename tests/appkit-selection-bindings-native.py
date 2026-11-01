#!/usr/bin/env python3
"""Production binding methods on libobjc, with controlled collection/KVC/UI doubles."""
import argparse,pathlib,subprocess,tempfile,re
root=pathlib.Path(__file__).resolve().parents[1]
a=argparse.ArgumentParser();a.add_argument('--source-ref');a.add_argument('--case',default='all',choices=['all','scalar','selected-object','enabled','browser','path','marker','reverse-marker']);args=a.parse_args()
def source(path):
 return subprocess.check_output(['git','show',args.source_ref+':AppKit/'+path],cwd=root,text=True) if args.source_ref else (root/'AppKit'/path).read_text()
def method(s,start):
 at=s.index(start);beg=s.index('{',at);depth=1;i=beg+1
 while depth:
  if s[i]=='{':depth+=1
  elif s[i]=='}':depth-=1
  i+=1
 return s[at:i]
program=(root/'tests/appkit-selection-bindings-native.m').read_text()
# Extract production methods without any implementation substitution.
parts={
 'SUPPORT_METHODS':('NSKeyValueBinding/NSObject+BindingSupport.m',['- (id) _binderForBinding: (id) binding create:', '- (id) _replacementKeyPathForBinding:', '- (void) bind:', '- (void) unbind:', '- (NSArray *) _allUsedBinders']),
 'BINDER_METHODS':('NSKeyValueBinding/NSBinder.m',['- (id) source','- (void) setSource:', '- (id) destination','- (void) setDestination:', '- (NSString *) keyPath','- (void) setKeyPath:', '- (NSString *) binding','- (void) setBinding:', '- options','- (void) setOptions:', '- (id) bindingPath','- (void) setBindingPath:', '- (NSArray *) peerBinders','- (NSComparisonResult) compare:', '- (void) startObservingChanges','- (void) stopObservingChanges','- (void) observeValueForKeyPath:']),
 'BINDER_OPTIONS':('NSKeyValueBinding/NSBinder.m',['- (BOOL) conditionallySetsEditable','- (BOOL) conditionallySetsEnabled','- (BOOL) allowsEditingMultipleValues','- (BOOL) raisesForNotApplicableKeys','- (id) multipleValuesPlaceholder','- (id) noSelectionPlaceholder','- (id) nullPlaceholder','- valueTransformer','- (id) transformedObject:','- (id) reverseTransformedObject:', '- (BOOL) allowsReverseTransformation']),
 'KVO_METHODS':('NSKeyValueBinding/NSKVOBinder.m',['- (void) startObservingChanges','- (void) stopObservingChanges','- (void) writeDestinationToSource','- (void) syncUp','- (void) observeValueForKeyPath:','- (void) bind','- (void) unbind']),
 'POPUP_METHODS':('NSPopUpButton.m',['- (void) _setItemValues:', '- (id) _contentValues', '- (void) _setContentValues:', '- (id) _contentObjects', '- (void) _setContentObjects:', '- (id) _content {', '- (void) _setContent:', '- (NSInteger) _selectedTag', '- (void) _setSelectedTag:', '- (NSUInteger) _selectedIndex','- (void) _setSelectedIndex:']),
 'MATRIX_METHODS':('NSMatrix.m',['- (NSInteger) _selectedIndex', '- (void) _setSelectedIndex:','- (NSInteger) _selectedTag','- (void) _setSelectedTag:', '- (void) setCellClass:', '- (NSCell *) makeCellAtRow:']),
 'TAB_METHODS':('NSTabView.m',['- (NSInteger) _selectedIndex','- (void) _setSelectedIndex:', '- (void) selectTabViewItem:','- (void) selectTabViewItemAtIndex:']),
 'BROWSER_METHOD':('NSBrowser.m',['- (void) setCellClass:']),
 'PATH_METHODS':('NSPathControl.m',['- (id<NSPathControlDelegate>) delegate','- (void) setDelegate:']),
}
for key,(path,starts) in parts.items():
 s=source(path);program=program.replace(key,'\n'.join(method(s,x) for x in starts))
s=source('NSKeyValueBinding/NSBinder.m');program=program.replace('DESTINATION_METHOD',method(s,'- (id) destinationValue') if '- (id) destinationValue' in s else '')
s=source('NSPopUpButton.m');program=program.replace('SELECTED_OBJECT_METHODS','\n'.join(method(s,x) for x in ['- (id) _selectedObject','- (void) _setSelectedObject:']) if '- (id) _selectedObject' in s else '')
s=source('NSKeyValueBinding/NSKVOBinder.m');program=program.replace('SCALAR_FUNCTION',method(s,'static BOOL NSKVOBinderKeyIsScalar'))
s=source('NSColorPicker.subproj/NSColorPickerColorList.m');program=program.replace('OUTLET_METHOD',method(s,'- (void) setColorBrowser:') if '- (void) setColorBrowser:' in s else '')
program=program.replace('FIXTURE_CASE',str(['all','scalar','selected-object','enabled','browser','path','marker','reverse-marker'].index(args.case)))
inc=subprocess.check_output(['gcc','-print-file-name=include'],text=True).strip()
with tempfile.TemporaryDirectory(prefix='qv-bindings-') as tmp:
 src=pathlib.Path(tmp)/'fixture.m';exe=pathlib.Path(tmp)/'fixture';src.write_text(program)
 subprocess.run(['clang','-O1','-g','-fobjc-runtime=gcc','-fconstant-string-class=FixtureString','-fobjc-exceptions','-fexceptions','-I'+inc,'-Wno-objc-method-access','-Wno-incompatible-pointer-types','-Wno-incomplete-implementation','-Wno-incompatible-library-redeclaration','-fsanitize=undefined','-fno-sanitize-recover=all',str(src),'-lobjc','-o',str(exe)],check=True)
 subprocess.run([str(exe)],check=True)
