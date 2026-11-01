#!/usr/bin/env python3
"""Byte-exact differential and benchmark of production clip replay/raster code.

Builds two independent translation units using clip-reconciled-native.py's C API
adapters. The bitmap, clip/sample intersections, viewport and raster functions
are production code. Objective-C dispatch/ownership, VGPath tessellation,
FreeType, image sampling and transparency allocation are not qualified here.
--reference must name an old O2Context_builtin.m saved from the pinned commit.
"""
import argparse
from pathlib import Path
import subprocess

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--reference', type=Path, required=True)
p.add_argument('--source', type=Path)
p.add_argument('--out', type=Path, required=True)
p.add_argument('--no-sanitize', action='store_true')
a = p.parse_args()
root = Path(__file__).resolve().parents[1]
a.out.mkdir(parents=True, exist_ok=True)

# Stop the existing generator before its build/run block. Route every production
# read (including its nested raster generator) to the selected translation unit.
generator_path = root / 'tests/clip-reconciled-native.py'
generator = generator_path.read_text().split('a.out.mkdir(parents=True,exist_ok=True)', 1)[0]
generator = generator.replace("source=(root/'Onyx2D/O2Context_builtin.m').read_text()", "source=Path(selected).read_text()")
generator = generator.replace("namespace={'__file__':str(root/'tests/float-bitmap/public-clip-source.py')}", "namespace={'__file__':str(root/'tests/float-bitmap/public-clip-source.py'), 'selected':selected}")
generator = generator.replace("exec(compile(generator,str(namespace['__file__']),'exec'),namespace)", "generator=generator.replace(\"source=(root/'Onyx2D/O2Context_builtin.m').read_text()\", \"source=Path(selected).read_text()\");exec(compile(generator,str(namespace['__file__']),'exec'),namespace)")
generator = generator.replace("p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);p.add_argument('--source',type=Path);a=p.parse_args()", "from types import SimpleNamespace\na=SimpleNamespace(source=Path(selected))")

extra = r'''
static void polygon(O2Context_builtin *c,O2Point *p,int n){for(int j=0;j<n;j++)O2DContextAddEdge(c,p[j],p[(j+1)%n]);}
static void operation(O2Context_builtin*c,int trial){
 double x=20.25+(trial%5),y=16.125;
 if(trial%3==0){O2Point p[]={{x,y},{x+17.5,y},{x+16.25,y+13.5},{x,y+13.5}};polygon(c,p,4);}
 else if(trial%3==1){O2Point p[]={{x,y},{x+22.5,y+10.25},{x+21.5,y+12.25},{x-1,y+2}};polygon(c,p,4);}
 else{O2Point p[]={{x,y},{x+3,y},{x+3,y+5},{x+7,y+5},{x+7,y},{x+10,y},{x+10,y+13},{x+7,y+13},{x+7,y+8},{x+3,y+8},{x+3,y+13},{x,y+13}};polygon(c,p,12);}
 O2RasterizerSetShouldAntialias(c,YES,256);
 O2DContextFillEdgesOnSurface(c,c->_surface,c->_clipContext?c->_clipContext->_surface:NULL,NULL,trial%2?1:-1);O2RasterizerClear(c);
}
size_t RENDER(unsigned trial,int width,int height,void*out){
 rng=0xc11f2026+trial;O2Context_builtin c;O2Surface s;init(&c,&s,width,height);
 // Nonzero destination makes skipped or overly broad painting observable.
 for(int i=0;i<width*height;i++){float v=(i%17)/16.f;s.pixels[i]=O2argb32fInit(v,.25f*v,.5f*v,.75f*v);}
 O2Path paths[6];O2ClipPhase phases[6];NSArray stack={0},domain={0};
 for(int i=0;i<6;i++){
  double x=unit(),y=unit(),w=unit()+14,h=unit()+12;int kind=random32()%5;
  if(trial%3)x+=.25;if(trial%7)y+=.125;
  if(trial%11==0){x=width-16.25;y=height-20.125;w=19;h=23;}
  paths[i]=makePath(x,y,w,h,kind);phases[i]=(O2ClipPhase){random32()%7==0?O2ClipPhaseMask:(random32()%2?O2ClipPhaseEOPath:O2ClipPhaseNonZeroPath),&paths[i],random32()%2,(int)(random32()%5)};
  stack.items[stack.count++]=&phases[i];
 }
 // An integral invalidation rect at a variety of positions in the stack.
 int at=trial%6;paths[at]=makePath(trial%5,trial%7,MAX(0,MIN(width-3,31)),MAX(0,MIN(height-5,29)),trial%3);
 phases[at].type=O2ClipPhaseNonZeroPath;
 if(trial%4){domain.count=trial%3;memcpy(domain.items,stack.items,domain.count*sizeof(void*));c._layerClipPhases=&domain;}
 forceGeneric=NO;O2ClipState state={&stack};
 for(int step=0;step<4;step++){
  stack.count=step==0?6:step==1?3:step==2?0:6;replay(&c,&state);operation(&c,trial+step);
  // Direct viewport changes invalidate cached clip replay.
  if(step==2)O2RasterizerSetViewport(&c,0,0,1,1);
 }
 size_t bytes=(size_t)width*height*sizeof(*s.pixels);memcpy(out,s.pixels,bytes);
 free(c._viewportClipPhases);dispose(&c);cleanup();return bytes;
}

size_t PATHRENDER(int kind,void*out){
 O2Context_builtin c;O2Surface s;init(&c,&s,664,532);
 // Fractional path phases only: no integral rectangle can pre-narrow this replay.
 O2Path path=makePath(15.25,11.125,52,53,kind);
 O2ClipPhase pp={O2ClipPhaseNonZeroPath,&path,YES,0};
 NSArray stack={2,{&pp,&pp}},domain={1,{&pp}};O2ClipState state={&stack};
 if(kind==4)c._layerClipPhases=&domain;
 forceGeneric=NO;replay(&c,&state);
#ifdef EXPECT_PATH_BOUNDED
 assert(c._clipContext && c._vpx==15 && c._vpy==11 && c._vpwidth==53 && c._vpheight==54);
#endif
 operation(&c,kind);
 size_t bytes=(size_t)664*532*sizeof(*s.pixels);memcpy(out,s.pixels,bytes);
 free(c._viewportClipPhases);dispose(&c);cleanup();return bytes;
}
static double benchSized(int width,int height,int repeats,int kind,int clipped,int side,int pathOnly){
 O2Context_builtin c;O2Surface s;init(&c,&s,width,height);
 O2Path invalid=makePath(17,13,side,side,0),path=makePath(15.25,11.125,side+4,side+5,4);
 O2ClipPhase ip={O2ClipPhaseNonZeroPath,&invalid,YES,0},pp={O2ClipPhaseNonZeroPath,&path,YES,0};
 NSArray stack={clipped?3:1,{&ip,&pp,&pp}};O2ClipState state={&stack};
 if(pathOnly){stack.count=2;stack.items[0]=stack.items[1]=&pp;}
 forceGeneric=NO;replay(&c,&state);cleanup();c._clipContext=NULL;
 pixelReads=allocations=maskBytes=0;double start=now();
 for(int i=0;i<repeats;i++){
  // A save/restore replay, with a changed temporary clip in the masked case.
  if(clipped){replay(&c,&state);}else O2RasterizerSetViewport(&c,17,13,side,side);
  operation(&c,kind);cleanup();c._clipContext=NULL;
 }
 double result=(now()-start)*1e6/repeats;
 printf("WORK %s %dx%d replay=%d n=%d mask_pixels_read=%zu mask_bytes_allocated=%zu side=%d path_only=%d\n",LABEL,width,height,clipped,repeats,pixelReads,maskBytes,side,pathOnly);
#ifdef EXPECT_BOUNDED
 if(clipped)assert(pixelReads<=(size_t)repeats*(side+(pathOnly?5:0))*(side+(pathOnly?6:0))*2);
#endif
 free(c._viewportClipPhases);dispose(&c);return result;
}
double BENCH(int width,int height,int repeats,int kind,int clipped){
 return benchSized(width,height,repeats,kind,clipped,48,0);
}
double MATRIX(int width,int height,int repeats,int side,int pathOnly){
 return benchSized(width,height,repeats,0,1,side,pathOnly);
}
'''
main = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
size_t candidate_render(unsigned,int,int,void*);size_t reference_render(unsigned,int,int,void*);
double candidate_bench(int,int,int,int,int);double reference_bench(int,int,int,int,int);
double candidate_matrix(int,int,int,int,int);double reference_matrix(int,int,int,int,int);
size_t candidate_path_render(int,void*);size_t reference_path_render(int,void*);
int main(int argc,char**argv){setbuf(stdout,NULL);
 int pathonly=argc>1&&!strcmp(argv[1],"path-only");
 if(argc==1||pathonly){
  size_t n=(size_t)664*532*16;void*a=malloc(n),*b=malloc(n);assert(a&&b);
  for(int i=0;i<4;i++){
   int kind=(int[]){0,1,2,4}[i];
   assert(candidate_path_render(kind,a)==n&&reference_path_render(kind,b)==n);
   assert(!memcmp(a,b,n));
  }
  free(a);free(b);puts("PASS 4 path-only full bitmap comparisons; candidate viewport=53x54 (including inherited layer)");
  if(pathonly)return 0;
 }

 if(argc>1&&!strcmp(argv[1],"matrix")){
  int old=argc>2&&!strcmp(argv[2],"reference"),repeats=argc>3?atoi(argv[3]):10;
  for(int surface=0;surface<4;surface++)for(int pathOnly=0;pathOnly<2;pathOnly++){
   int width=(int[]){96,664,1932,3864}[surface],height=(int[]){80,532,1144,2288}[surface];
   for(int scale=0;scale<(surface==1?4:1);scale++){
    int side=surface==1?(int[]){16,48,96,192}[scale]:48;
    double us=(old?reference_matrix:candidate_matrix)(width,height,repeats,side,pathOnly);
    printf("MATRIX %s %dx%d side=%d path_only=%d n=%d us_per_op=%.3f\n",old?"reference":"candidate",width,height,side,pathOnly,repeats,us);
   }
  }return 0;
 }
 if(argc>1){int repeats=argc>2?atoi(argv[2]):30;int old=strcmp(argv[1],"reference")==0;
  for(int size=0;size<3;size++)for(int clip=0;clip<2;clip++)for(int kind=0;kind<3;kind++){
   int width=(int[]){96,1932,3864}[size],height=(int[]){80,1144,2288}[size];
   double us=(old?reference_bench:candidate_bench)(width,height,repeats,kind,clip);
   printf("BENCH %s %dx%d clip=48x48 replay=%d kind=%s n=%d us_per_op=%.3f\n",old?"reference":"candidate",width,height,clip,(char*[]){"fill","stroke-outline","glyph-outline"}[kind],repeats,us);
  }return 0;
 }
 const int dims[][2]={{1,1},{17,13},{32,24},{71,57},{129,81},{1932,1144}};
 unsigned cases=0;
 for(int size=0;size<6;size++){int w=dims[size][0],h=dims[size][1];size_t n=(size_t)w*h*16;void*a=malloc(n),*b=malloc(n);assert(a&&b);
  unsigned trials=size==5?12:180;
  for(unsigned trial=0;trial<trials;trial++){
   size_t na=candidate_render(trial,w,h,a),nb=reference_render(trial,w,h,b);assert(na==n&&nb==n);
   if(memcmp(a,b,n)){fprintf(stderr,"FAIL size=%dx%d trial=%u\n",w,h,trial);for(size_t i=0;i<n;i++)if(((unsigned char*)a)[i]!=((unsigned char*)b)[i]){fprintf(stderr,"first differing byte=%zu\n",i);break;}return 1;}cases++;
  }free(a);free(b);
 }printf("PASS %u old/new full bitmap byte comparisons, seed=c11f2026\n",cases);return 0;
}
'''
for scalar in ['float', 'double']:
    objects = []
    flags = ['-std=c11', '-D_POSIX_C_SOURCE=200809L', '-O2', '-g', '-Wall', '-Wextra', '-Werror',
             '-Wno-sign-compare', '-Wno-unused-function', '-Wno-missing-field-initializers', '-Wno-misleading-indentation']
    if not a.no_sanitize:
        flags += ['-fsanitize=address,undefined,float-cast-overflow', '-fno-omit-frame-pointer']
    for label, selected in [('candidate', a.source or root / 'Onyx2D/O2Context_builtin.m'), ('reference', a.reference)]:
        ns = {'__file__': str(generator_path), 'selected': str(selected.resolve())}
        exec(compile(generator, str(generator_path), 'exec'), ns)
        src = ns['src'].split('int main(int argc,char**argv)', 1)[0]
        signature = 'static void O2Image_read_argb32f(O2Surface *s,int x,int y,O2argb32f *out,int n){'
        assert signature in src
        src = src.replace(signature, 'static size_t pixelReads;\n'+signature+'pixelReads+=n;') + extra
        # The two translation units retain separate private adapter state.
        names = ['O2RasterizerSetViewport', 'O2RasterizerClear', 'O2DContextAddEdge',
                 'O2RasterizerSetShouldAntialias', 'O2DContextFillEdgesOnSurface',
                 'original_fixture_main', 'O2PathIsRect', 'O2PointApplyAffineTransform']
        defines = ''.join('#define '+name+' '+label+'_'+name+'\n' for name in names)
        src = defines + src.replace('typedef double O2Float;', 'typedef '+scalar+' O2Float;')
        src = '#define MATRIX '+label+'_matrix\n' + src
        src = '#define PATHRENDER '+label+'_path_render\n' + ('#define EXPECT_PATH_BOUNDED\n' if label == 'candidate' else '') + src
        path = a.out / (label+'-'+scalar+'.c')
        path.write_text(src)
        obj = path.with_suffix('.o')
        subprocess.run(['cc', *flags, '-DLABEL=\"'+label+'\"', *(['-DEXPECT_BOUNDED'] if label == 'candidate' else []), '-DRENDER='+label+'_render', '-DBENCH='+label+'_bench', '-c', str(path), '-o', str(obj)], check=True)
        objects.append(str(obj))
    path = a.out / ('main-'+scalar+'.c')
    path.write_text(main)
    binary = a.out / scalar
    subprocess.run(['cc', *flags, str(path), *objects, '-lm', '-o', str(binary)], check=True)
    print(binary, flush=True)
