#!/usr/bin/env python3
"""Compare exact ruler methods using native drawing-command doubles.
No font raster or guest pixel claim. Coordinates retain repeated addition.
"""
from pathlib import Path
import subprocess,tempfile,sys
root=Path(__file__).resolve().parents[1]
reference=Path(sys.argv[1])
new=(Path(sys.argv[2]) if len(sys.argv)>2 else root/'AppKit/NSRulerView.m').read_text();old=reference.read_text()
def adapt(s,name):
 a=s.index('- (void) drawHashMarksAndLabelsInRect:');b=s.index('\n- (void) drawMarkersInRect:',a);f=s[a:b]
 f=f.replace('- (void) drawHashMarksAndLabelsInRect: (NSRect) dirtyRect {',f'void {name}(Config *self, NSRect dirtyRect) {{')
 for a,b in {'self.bounds':'self->bounds','[self _drawingScale]':'self->scale','[self _drawingOrigin]':'self->offset','self.clientView.frame':'self->clientFrame','self.clientView':'self->hasClient','[_measurementUnit pointsPerUnit]':'72.', 'NSMutableArray *cycles =\n            [[[_measurementUnit stepDownCycle] mutableCopy] autorelease];':'std::vector<double> cycles={.5,.25,.125};', '[[self enclosingScrollView] hasVerticalRuler]':'self->otherRuler','[[self enclosingScrollView] hasHorizontalRuler]':'self->otherRuler','[_markers count]':'0','[self reservedThicknessForMarkers]':'0','_accessoryView != nil':'false','[self reservedThicknessForAccessoryView]':'0','[[NSColor controlShadowColor] setStroke];':'', 'NSString *label = [NSString stringWithFormat: @"%d", i];':'int label=i;', '[label drawAtPoint: textOrigin\n                withAttributes: [self attributesForLabel]];':'drawLabel(label,textOrigin);', '[[cycles objectAtIndex: 0] doubleValue]':'cycles[0]', '[cycles removeObjectAtIndex: 0];':'cycles.erase(cycles.begin());','[cycles count]':'cycles.size()','_orientation':'self->orientation'}.items():f=f.replace(a,b)
 return f
preamble=r'''
#include <vector>
#include <cmath>
#include <cassert>
#include <cstdio>
#include <cstring>
using CGFloat=double;using BOOL=bool;
#define NSHorizontalRuler 0
#define NO false
#define HASH_MARK_WIDTH 1.0
#define HASH_MARK_THICKNESS_FACTOR .5
#define HASH_MARK_REQUIRED_WIDTH 2.0
#define LABEL_TEXT_CORRECTION 2.0
#define LABEL_TEXT_PRIMARY_OFFSET 3.0
#define LABEL_TEXT_SECONDARY_OFFSET 3.0
struct NSPoint{double x,y;};struct NSSize{double width,height;};struct NSRect{NSPoint origin;NSSize size;};
double NSMaxX(NSRect r){return r.origin.x+r.size.width;}double NSMaxY(NSRect r){return r.origin.y+r.size.height;}
bool NSIntersectsRect(NSRect a,NSRect b){return a.size.width>0&&a.size.height>0&&b.size.width>0&&b.size.height>0&&a.origin.x<NSMaxX(b)&&b.origin.x<NSMaxX(a)&&a.origin.y<NSMaxY(b)&&b.origin.y<NSMaxY(a);}
NSRect NSInsetRect(NSRect r,double x,double y){r.origin.x+=x;r.origin.y+=y;r.size.width-=2*x;r.size.height-=2*y;return r;}
NSRect NSIntersectionRect(NSRect a,NSRect b){double x=fmax(a.origin.x,b.origin.x),y=fmax(a.origin.y,b.origin.y);double w=fmin(NSMaxX(a),NSMaxX(b))-x,h=fmin(NSMaxY(a),NSMaxY(b))-y;return w>0&&h>0?NSRect{{x,y},{w,h}}:NSRect{};}
struct Config{NSRect bounds,clientFrame;double scale,offset;bool hasClient,otherRuler;int orientation;};
struct Command{int kind,label;NSRect rect;};std::vector<Command> commands;NSRect visible;unsigned rawMarks;
void NSFrameRect(NSRect r){rawMarks++;if(NSIntersectsRect(NSInsetRect(r,-.5,-.5),visible))commands.push_back({0,0,r});}
void drawLabel(int label,NSPoint p){commands.push_back({1,label,{p,{0,0}}});}
'''
a=new.index('static BOOL rulerMarkIntersectsRect(');b=new.index('\n@implementation NSRulerView',a)
control=r'''
int main(){unsigned cases=0,maxSaved=0;
 for(int orientation=0;orientation<2;orientation++)for(double offset:{0.,-720.,-7200.,17.25})for(double scale:{.75,1.,1.125})for(double length:{620.,4800.,48000.})for(bool other:{false,true})for(int dirty=0;dirty<5;dirty++){
 Config c{{{0,0},{orientation?16.:620.,orientation?420.:16.}},{{0,0},{length,length}},scale,offset,true,other,orientation};visible=c.bounds;
 if(dirty==1){if(orientation)visible={{-.4,0},{.3,420}};else visible={{0,-.4},{620,.3}};}
 if(dirty==2){visible.origin.x+=17.1;visible.origin.y+=.25;visible.size.width=20;visible.size.height=5;}
 if(dirty==3){if(orientation)visible={{-.4,-.4},{16.8,420.8}};else visible={{-.4,-.4},{620.8,16.8}};}
 if(dirty==4){if(orientation)visible={{-.4,0},{.5,420}};else visible={{0,-.4},{620,.5}};}
 commands.clear();rawMarks=0;reference(&c,visible);auto before=commands;unsigned oldCount=rawMarks;
 commands.clear();rawMarks=0;candidate(&c,visible);assert(before.size()==commands.size());
 for(size_t i=0;i<commands.size();i++)assert(!memcmp(&before[i],&commands[i],sizeof(Command)));
 assert(rawMarks<=oldCount);maxSaved=std::max(maxSaved,oldCount-rawMarks);cases++;
 }
 assert(maxSaved>1000);printf("PASS %u ruler cases: identical visible stroke and label commands; up to %u invisible strokes removed\n",cases,maxSaved);
}
'''
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp);(p/'control.cpp').write_text(preamble+new[a:b]+adapt(old,'reference')+adapt(new,'candidate')+control)
 subprocess.run(['c++','-std=c++17','-fsanitize=address,undefined',str(p/'control.cpp'),'-o',str(p/'control')],check=True)
 subprocess.run([str(p/'control')],check=True)
