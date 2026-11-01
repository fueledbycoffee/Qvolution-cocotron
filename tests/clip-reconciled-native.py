#!/usr/bin/env python3
"""Differential production clip replay/raster core with C memory/API adapters.
No Objective-C ownership, font dispatch, image sampler or guest qualification.
The existing public-clip generator supplies the exact raster/sample/mask helpers.
"""
from pathlib import Path
import argparse, os, re, subprocess
p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);p.add_argument('--source',type=Path);a=p.parse_args()
root=Path(__file__).resolve().parents[1]
namespace={'__file__':str(root/'tests/float-bitmap/public-clip-source.py')}
generator=(root/'tests/float-bitmap/public-clip-source.py').read_text().split("out=Path(tempfile.mkdtemp(",1)[0]
exec(compile(generator,str(namespace['__file__']),'exec'),namespace)
src=namespace['src'];source=(a.source or root/'Onyx2D/O2Context_builtin.m').read_text()
def function(name):
 start=source.rfind('\n',0,source.index(name))+1;end=source.index('{',start)+1;depth=1
 while depth:depth+=(source[end]=='{')-(source[end]=='}');end+=1
 return source[start:end]
# API doubles carry immutable phase identity; geometry is already in device space.
src=src.replace('typedef struct O2Context_builtin {',r'''
typedef struct {O2Point origin;struct {O2Float width,height;}size;} O2Rect;
enum {kO2PathElementMoveToPoint,kO2PathElementAddLineToPoint,kO2PathElementCloseSubpath};
typedef struct {size_t elements,count;unsigned char types[5];O2Point points[4];} O2Path;
typedef enum {O2ClipPhaseNonZeroPath,O2ClipPhaseEOPath,O2ClipPhaseMask} O2ClipPhaseType;
typedef struct {O2ClipPhaseType type;O2Path *path;BOOL aa;int soft;} O2ClipPhase;
typedef struct {size_t count;O2ClipPhase *items[8];} NSArray;
typedef struct {NSArray *phases;} O2ClipState;
static size_t O2PathNumberOfElements(O2Path*p){return p->elements;}
static size_t O2PathNumberOfPoints(O2Path*p){return p->count;}
static const unsigned char *O2PathElements(O2Path*p){return p->types;}
static const O2Point *O2PathPoints(O2Path*p){return p->points;}
static O2ClipPhaseType O2ClipPhasePhaseType(O2ClipPhase*p){return p->type;}
static O2Path *O2ClipPhaseObject(O2ClipPhase*p){return p->path;}
static BOOL O2ClipPhaseShouldAntialias(O2ClipPhase*p){return p->aa;}
static BOOL arrayEqual(NSArray*a,NSArray*b){return a&&b&&a->count==b->count&&!memcmp(a->items,b->items,a->count*sizeof(void*));}
static BOOL contains(NSArray*a,O2ClipPhase*p){for(size_t i=0;i<a->count;i++)if(a->items[i]==p)return YES;return NO;}
static NSArray *copyArray(NSArray*a){NSArray*b=calloc(1,sizeof(*b));if(a)*b=*a;return b;}
static BOOL forceGeneric;static size_t allocations,maskBytes;
typedef struct O2Context_builtin {
 NSArray *_viewportClipPhases,*_layerClipPhases,*statePhases;
 size_t _viewportClipWidth,_viewportClipHeight;
 int _viewportClipX,_viewportClipY,_viewportClipW,_viewportClipH;
''')
src=src.replace('static void O2ContextDeviceClipReset_builtin(O2Context_builtin *s){s->_clipContext=NULL;}', '''static void O2ContextDeviceClipReset_builtin(O2Context_builtin *s){free(s->_viewportClipPhases);s->_viewportClipPhases=NULL;s->_clipContext=NULL;O2RasterizerSetViewport(s,0,0,s->_surface->width,s->_surface->height);}''')
# Use full raster contexts for generic clip phase allocation, retained until case end.
start=src.index('static O2Context_builtin *createClipContext(');end=src.index('\n',start)
src=src[:start]+r'''
static void init(O2Context_builtin*,O2Surface*,int,int);
static O2Context_builtin *owned[128];static int ownedCount;
static O2Context_builtin *createClipContext(size_t w,size_t h){assert(ownedCount<128);O2Context_builtin*c=calloc(1,sizeof(*c));O2Surface*s=calloc(1,sizeof(*s));init(c,s,w,h);owned[ownedCount++]=c;allocations++;maskBytes+=w*h*sizeof(O2argb32f);return c;}
'''+src[end:]
src=src.replace('context->_clipSamples = calloc(width * height, 8 * sizeof(uint32_t));','maskBytes += width * height * 8 * sizeof(uint32_t);\n    context->_clipSamples = calloc(width * height, 8 * sizeof(uint32_t));')
# Existing fixture main is kept for its independent path/sample/mask controls.
src=src.replace('int main(void)', 'int original_fixture_main(void)')
if 'static BOOL integralRectBounds(' in source:
 src+=function('static BOOL integralRectBounds(')+'\n'+function('static BOOL clipToIntegralRect(')+'\n'
else:
 # Stage41b reference has no per-phase helper; use candidate recognition only
 # for independent input assertions, never in its generic replay.
 saved=source;source=(root/'Onyx2D/O2Context_builtin.m').read_text()
 src+=function('static BOOL integralRectBounds(')+'\n';source=saved
src+='static O2Rect O2RectMake(O2Float x,O2Float y,O2Float w,O2Float h){return (O2Rect){{x,y},{w,h}};}\n'
pathsource=(root/'Onyx2D/O2Path.m').read_text();saved=source;source=pathsource
recognition=function('BOOL O2PathIsRect(').replace('O2PathRef','O2Path *').replace('self->_numberOfElements','self->elements').replace('self->_elements','self->types').replace('self->_points','self->points').replace('O2SizeMake(self->points[2].x - self->points[0].x,\n                            self->points[2].y - self->points[0].y)', '(typeof(rect->size)){self->points[2].x-self->points[0].x,self->points[2].y-self->points[0].y}')
src+=recognition.replace('typeof(rect->size)', '__typeof__(rect->size)')+'\n';source=saved

f=function('static void clipToPath(')
f=f.replace('if (clipToIntegralRect(self, path))','if (!forceGeneric && clipToIntegralRect(self, path))')
f=f.replace('[phase release];','')
a0=f.index('        O2Paint *paint');b0=f.index('        VGPath *vgPath',a0);f=f[:a0]+f[b0:]
f=f.replace('VGPath *vgPath = [[VGPath alloc] initWithKGPath: path];','O2Path *vgPath = path;').replace('VGPathFill(vgPath, O2AffineTransformIdentity, phase);','for(size_t i=0;i<vgPath->count;i++)O2DContextAddEdge(phase,vgPath->points[i],vgPath->points[(i+1)%vgPath->count]);').replace('O2DContextClipAndFillEdges(phase, fillRule);','O2DContextFillEdgesOnSurface(phase,phase->_surface,NULL,NULL,fillRule);').replace('[vgPath release];','')
src+=f+'\n'
src+=r'''
#define VG_NON_ZERO -1
#define VG_EVEN_ODD 1
static void clipToMask(O2Context_builtin*self,O2ClipPhase*p){O2Context_builtin*c=createClipContext(self->_surface->width,self->_surface->height);c->_clipIsSoftPhase=YES;for(size_t i=0;i<c->_surface->width*c->_surface->height;i++){float v=((i+p->soft)%5)/4.f;c->_surface->pixels[i]=O2argb32fInit(v,v,v,v);}intersectClipContext(self,c);}
'''+function('static void applyClipPhase(')+'\n'
f=function('static BOOL clipToIntegralRects(').replace('for (O2ClipPhase *phase in phases)', 'for(size_t i=0;phases&&i<phases->count;i++)')
f=f.replace('        O2ClipPhaseType type', '        O2ClipPhase *phase=phases->items[i];\n        O2ClipPhaseType type')
src+=f+'\n'
f=function('- (void) clipToState:')
f=f.replace('- (void) clipToState: (O2ClipState *) clipState {','static void replay(O2Context_builtin *self,O2ClipState *clipState) {\n    self->statePhases=clipState->phases;')
for var in ['_surface','_viewportClipPhases','_viewportClipWidth','_viewportClipHeight','_layerClipPhases','_clipContext','_vpx','_vpy','_vpwidth','_vpheight','_viewportClipX','_viewportClipY','_viewportClipW','_viewportClipH']:
 f=re.sub(r'(?<![\w>])'+var+r'\b','self->'+var,f)
for old,new in {'[clipState clipPhases]':'clipState->phases','[self->_layerClipPhases count]':'(self->_layerClipPhases!=NULL)','[self->_layerClipPhases lastObject]':'self->_layerClipPhases','[self->_viewportClipPhases count]':'self->_viewportClipPhases->count','[phases isEqualToArray: self->_viewportClipPhases]':'arrayEqual(phases,self->_viewportClipPhases)','[phases copy]':'copyArray(phases)','[[NSArray alloc] init]':'copyArray(NULL)','[_clipContext retain]':'self->_clipContext','[self->_clipContext retain]':'self->_clipContext','[domain release];':'','[inherited indexOfObjectIdenticalTo: phase] != NSNotFound':'contains(inherited,phase)'}.items():f=f.replace(old,new)
f=f.replace('if (self->_viewportClipPhases != nil','if (!forceGeneric && self->_viewportClipPhases != nil').replace('&& clipToIntegralRects(self, phases)', '&& !forceGeneric && clipToIntegralRects(self, phases)')
for name in ['inherited','phases']:
 f=f.replace('for (O2ClipPhase *phase in '+name+') {','for(size_t i=0;'+name+'&&i<'+name+'->count;i++) {\n        O2ClipPhase *phase='+name+'->items[i];')
src+=f+'\n'
f=function('static BOOL hasViewportClip(')
f=f.replace('[O2GStateClipState(O2ContextCurrentGState(self)) clipPhases]', 'self->statePhases').replace('[self->statePhases count]', '(self->statePhases?self->statePhases->count:0)').replace('[phases count]', '(phases?phases->count:0)').replace('for (O2ClipPhase *phase in phases)', 'for(size_t i=0;phases&&i<phases->count;i++)\n        for(O2ClipPhase *phase=phases->items[i];phase;phase=NULL)').replace('[[O2GStateClipState(O2ContextCurrentGState(self)) clipPhases] count]', '(self->statePhases?self->statePhases->count:0)').replace('for (O2ClipPhase *phase in [self->_layerClipPhases lastObject])', 'for(size_t i=0;self->_layerClipPhases&&i<self->_layerClipPhases->count;i++)\n        for(O2ClipPhase *phase=self->_layerClipPhases->items[i];phase;phase=NULL)')
src+=f+'\n'
saved=source;source=(root/'Onyx2D/O2AffineTransform.m').read_text()
src+='typedef struct {O2Float a,b,c,d,tx,ty;} O2AffineTransform;\n'+function('O2Point O2PointApplyAffineTransform(')+'\n';source=saved
src+=r'''
#include <time.h>
static void cleanup(void){for(int i=0;i<ownedCount;i++){dispose(owned[i]);free(owned[i]->_surface);free(owned[i]);}ownedCount=0;}
static O2Path makePath(double x,double y,double w,double h,int kind){O2Path p={5,4,{0,1,1,1,2},{{x,y},{x+w,y},{x+w,y+h},{x,y+h}}};if(kind==1){p.elements=4;}if(kind==2){O2Point t=p.points[1];p.points[1]=p.points[3];p.points[3]=t;}if(kind==3){p.elements=4;p.count=3;}if(kind==4){p.points[1].y+=.375;}return p;}
static uint32_t rng=0xc11f2026;
static unsigned random32(void){rng^=rng<<13;rng^=rng>>17;rng^=rng<<5;return rng;}
static double unit(void){return (int)(random32()%41)-10;}
static void draw(O2Context_builtin*c,BOOL aa){BOOL sampled=(c->_clipContext&&c->_clipContext->_clipSamples)||hasViewportClip(c);O2RasterizerSetShouldAntialias(c,aa,aa?(sampled?MAX_SAMPLES:64):1);O2DContextAddEdge(c,(O2Point){-.25,1.125});O2DContextAddEdge(c,(O2Point){27.75,3.625});O2DContextAddEdge(c,(O2Point){4.375,22.5});O2DContextAddEdge(c,(O2Point){4.375,22.5},(O2Point){-.25,1.125});}
'''.replace('O2DContextAddEdge(c,(O2Point){-.25,1.125});O2DContextAddEdge(c,(O2Point){27.75,3.625});O2DContextAddEdge(c,(O2Point){4.375,22.5});','O2DContextAddEdge(c,(O2Point){-.25,1.125},(O2Point){27.75,3.625});O2DContextAddEdge(c,(O2Point){27.75,3.625},(O2Point){4.375,22.5});')
src+=r'''
static void render(NSArray*phases,NSArray*inherited,BOOL generic,BOOL aa,O2argb32f*out){O2Context_builtin c;O2Surface s;init(&c,&s,32,24);c._layerClipPhases=inherited;forceGeneric=generic;O2ClipState state={phases};replay(&c,&state);NSArray nested=*phases;if(nested.count){nested.count--;O2ClipState changed={&nested};replay(&c,&changed);replay(&c,&state);}replay(&c,&state);draw(&c,aa);O2DContextFillEdgesOnSurface(&c,&s,c._clipContext?c._clipContext->_surface:NULL,NULL,-1);memcpy(out,s.pixels,32*24*sizeof(*out));free(c._viewportClipPhases);dispose(&c);cleanup();}
static double now(void){struct timespec t;timespec_get(&t,TIME_UTC);return t.tv_sec+t.tv_nsec*1e-9;}
static int benchmark(void){O2Path p=makePath(10,10,2200,1300,0);O2ClipPhase phase={O2ClipPhaseNonZeroPath,&p,YES,0};NSArray stack={3,{&phase,&phase,&phase}},layer={0};for(int generic=0;generic<2;generic++){O2Context_builtin c;O2Surface s;init(&c,&s,2318,1373);c._layerClipPhases=&layer;O2ClipState state={&stack};forceGeneric=generic;allocations=maskBytes=0;int n=generic?2:100000;double start=now();for(int i=0;i<n;i++){replay(&c,&state);cleanup();}double seconds=now()-start;printf("BENCH generic=%d size=2318x1373 phases=3 replays=%d seconds=%.9f ns_per_replay=%.1f mask_allocations=%zu mask_bytes_total=%zu\n",generic,n,seconds,seconds*1e9/n,allocations,maskBytes);assert(generic||(!allocations&&!maskBytes));free(c._viewportClipPhases);dispose(&c);}return 0;}
int main(int argc,char**argv){(void)argv;setbuf(stdout,NULL);if(argc>1)return benchmark();
 O2argb32f fast[32*24],slow[32*24];unsigned cases=0;
 for(int trial=0;trial<1200;trial++){O2Path paths[6];O2ClipPhase phases[6];NSArray stack={0},domain={0};BOOL aa=trial%2;
  for(int i=0;i<6;i++){int kind=random32()%5;double x=unit(),y=unit(),w=unit(),h=unit();if(trial%3==0)x+=.25;if(trial%7==0)y+=.00005;paths[i]=makePath(x,y,w,h,kind);O2AffineTransform transforms[]={{1,0,0,1,0,0},{0,1,-1,0,24,0},{-1,0,0,1,32,0},{2,0,0,1,0,0},{1,0,0,1,.25,.5},{1,.25,.5,1,0,0},{.8,.6,-.6,.8,4,1}};O2AffineTransform transform=transforms[random32()%7];for(size_t j=0;j<paths[i].count;j++)paths[i].points[j]=O2PointApplyAffineTransform(paths[i].points[j],transform);phases[i]=(O2ClipPhase){random32()%9==0?O2ClipPhaseMask:(random32()%2?O2ClipPhaseEOPath:O2ClipPhaseNonZeroPath),&paths[i],random32()%2,(int)(random32()%5)};stack.items[stack.count++]=&phases[i];}
  if(trial%3){domain.count=trial%3;memcpy(domain.items,stack.items,domain.count*sizeof(void*));}
  // Every saved prefix followed by a smaller nested stack and restoration.
  for(int depth=0;depth<=6;depth++){stack.count=depth;NSArray *inherited=trial%4?&domain:NULL;
   render(&stack,inherited,NO,aa,fast);render(&stack,inherited,YES,aa,slow);cases++;
   if(memcmp(fast,slow,sizeof(fast))){for(int j=0;j<32*24;j++)if(memcmp(fast+j,slow+j,sizeof(*fast)))fprintf(stderr,"FAIL trial=%d depth=%d inherited=%zu aa=%d pixel=%d fast=%g slow=%g\n",trial,depth,inherited?inherited->count:0,aa,j,fast[j].a,slow[j].a);return 1;}
  }
 }
 // Inherited rectangle with current clip reset must retain clipped sampling/float dispatch.
 O2Path inheritedRect=makePath(0,0,32,24,0);O2ClipPhase inheritedPhase={O2ClipPhaseNonZeroPath,&inheritedRect,YES,0};NSArray inheritedDomain={1,{&inheritedPhase}},empty={0};render(&empty,&inheritedDomain,NO,YES,fast);render(&empty,&inheritedDomain,YES,YES,slow);assert(!memcmp(fast,slow,sizeof(fast)));
 // Reject B's near-integer tolerance and axis-aligned backtracking false positive.
 double x0,y0,x1,y1;O2Path near=makePath(.00005,0,8,8,0),backtrack={5,4,{0,1,1,1,2},{{0,0},{8,0},{0,0},{0,8}}};assert(!integralRectBounds(&near,&x0,&y0,&x1,&y1));assert(!integralRectBounds(&backtrack,&x0,&y0,&x1,&y1));
 // Explicit rectangle-only mixed orientation/open/degenerate cases in a layer.
 for(int k=0;k<4;k++){O2Path p=makePath(2,3,k==3?0:26,18,k%3);O2ClipPhase phase={O2ClipPhaseNonZeroPath,&p,YES,0};NSArray stack={1,{&phase}},domain={0};allocations=maskBytes=0;render(&stack,&domain,NO,YES,fast);assert(!allocations&&!maskBytes);render(&stack,&domain,YES,YES,slow);assert(!memcmp(fast,slow,sizeof(fast)));}
 puts("PASS exact randomized clip-stack/layer-prefix differential and zero rectangle mask allocations");printf("CASES %u seed=c11f2026\n",cases);return 0;}
'''
a.out.mkdir(parents=True,exist_ok=True)
for scalar in ['float','double']:
 c=a.out/(scalar+'.c');c.write_text(src.replace('typedef double O2Float;', 'typedef '+scalar+' O2Float;'))
 subprocess.run(['cc','-std=c11','-O2','-Wall','-Wextra','-Werror','-Wno-sign-compare','-Wno-unused-function','-Wno-missing-field-initializers','-fsanitize=address,undefined,float-cast-overflow',str(c),'-lm','-o',str(a.out/scalar)],check=True)
print(a.out)
