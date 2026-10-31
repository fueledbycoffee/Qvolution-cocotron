#!/usr/bin/env python3
"""Execute the own backend's title viewport and FT bitmap writer natively.
The bitmap models title ink crossing into content; no text layout/guest claim.
"""
import argparse, os, subprocess, tempfile
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--source',type=Path);a=p.parse_args()
root=Path(__file__).resolve().parents[1];fixture=root/'tests/float-bitmap/draw-source.py'
ns={'__file__':str(fixture)};exec(compile(fixture.read_text().split("src+=ft+r'''",1)[0],str(fixture),'exec'),ns)
src=ns['src']
src=src.replace('void *_blend_argb8u_PRE; } O2Context_builtin;', 'void *_blend_argb8u_PRE; double scale,contentHeight; } O2Context_builtin;')
text=(a.source or root/'AppKit/Wayland.backend/WaylandWindow.m').read_text()
name='- (void) clipTitlebarAtHeight: (CGFloat) height {'
if name in text:
 body=text.split(name,1)[1].split('\n}',1)[0]
 body=body.replace('_surface','self->_surface')
 helper='static void clipTitlebar(O2Context_builtin *self,double height){'+body+'\n}\n'
else:helper='static void clipTitlebar(O2Context_builtin *self,double height){(void)self;(void)height;}\n'
src+=r'''
typedef struct{double x,y;} O2Point;
static O2Point O2PointMake(double x,double y){return (O2Point){x,y};}
static O2Point O2ContextConvertPointToDeviceSpace(O2Context_builtin *c,O2Point p){return (O2Point){p.x*c->scale+6*c->scale,(c->contentHeight+34-p.y)*c->scale};}
static int O2ImageGetWidth(O2Surface *s){return s->width;}
static int O2ImageGetHeight(O2Surface *s){return s->height;}
static void O2RasterizerSetViewport(O2Context_builtin *c,int x,int y,int w,int h){c->_vpx=x;c->_vpy=y;c->_vpwidth=w;c->_vpheight=h;}
'''+helper+ns['ft']+r'''
int main(void){
 for(int scale=1;scale<=3;scale++){
  // Four rows straddle the title/content boundary at device y=2.
  O2Surface surface;memset(&surface,0,sizeof(surface));surface.width=32;surface.height=4;
  O2Context_builtin c={0};c._surface=&surface;c._blend_argb32f_PRE=O2BlendSpanNormal_ffff;c._vpx=c._vpy=0;c._vpwidth=32;c._vpheight=4;c.scale=scale;c.contentHeight=96;
  // The source viewport uses the actual device transform, including scale.
  clipTitlebar(&c,96);
  assert(c._vpheight==4);
  c.contentHeight=96-34+2./scale;
  int boundary=MAX(0,MIN(4,floor(O2ContextConvertPointToDeviceSpace(&c,O2PointMake(0,96)).y)));
  clipTitlebar(&c,96);
  O2Paint paint={NULL,{1,1,1,1},-1};unsigned char ink[16];memset(ink,255,sizeof(ink));FT_Bitmap bitmap={4,4,4,ink};
  renderFreeTypeBitmap(&c,&surface,&bitmap,2,0,&paint);
  for(int y=0;y<4;y++)for(int x=0;x<32;x++){O2argb32f pixel;memcpy(&pixel,surface.bytes[y]+16*x,16);assert(pixel.a==(x>=2&&x<6&&y<boundary?1:0));}
 }
 puts("PASS production title viewport and FT writer preserve content under crossing title ink at 1x/2x/3x; native adapter, not guest layout");return 0;
}
'''
with tempfile.TemporaryDirectory(prefix='title-clip-') as folder:
 folder=Path(folder);path=folder/'probe.c';path.write_text(src);binary=folder/'probe'
 subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-Wno-unused-function','-Wno-unused-parameter','-fsanitize=address,undefined',str(path),'-lm','-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True,env={**os.environ,'ASAN_OPTIONS':'detect_leaks=0','UBSAN_OPTIONS':'halt_on_error=1'})
