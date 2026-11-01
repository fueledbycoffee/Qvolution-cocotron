/* Native adapters, randomized driver and measurement only. */
static unsigned rng=192711;
static unsigned randomBelow(unsigned n){rng=rng*1664525u+1013904223u;return (rng>>4)%n;}
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
static void initSurface(O2Surface*s,int w,int h,int format){
 memset(s,0,sizeof(*s));s->_colorSpace=1;s->_width=w;s->_height=h;s->_bytesPerRow=w*4+(w<=40?16:0);
 s->_pixelBytes=malloc(s->_bytesPerRow*h);assert(s->_pixelBytes);memset(s->_pixelBytes,0xa7,s->_bytesPerRow*h);
 s->_bitmapInfo=format?(kO2ImageAlphaPremultipliedFirst|kO2BitmapByteOrder32Little):(kO2ImageAlphaPremultipliedLast|kO2BitmapByteOrder32Big);
 s->_bitsPerComponent=8;s->_bitsPerPixel=32;s->_directLength=s->_bytesPerRow*h;s->_read_argb32f=O2ImageRead_ANY_to_argb8u_to_argb32f;
 s->_read_argb8u=format?O2ImageRead_BGRA8888_to_argb8u:O2ImageRead_RGBA8888_to_argb8u;
 s->_writeargb8u=format?O2SurfaceWrite_argb8u_to_BGRA8888:O2SurfaceWrite_argb8u_to_argb8u;
 s->_writeargb32f=format?O2SurfaceWrite_argb32f_to_argb8u_to_ANY:O2SurfaceWrite_argb32f_to_argb8u;
 for(int y=0;y<h;y++)for(int x=0;x<w;x++){uint8_t*p=s->_pixelBytes+y*s->_bytesPerRow+x*4;p[3]=randomBelow(256);for(int c=0;c<3;c++)p[c]=randomBelow(p[3]+1);}
}
static void initContext(O2Context_builtin*c,O2Surface*s){
 memset(c,0,sizeof(*c));c->_state=(O2GState){{1,0,0,1,0,0},{1,0,0,1,0,0},1,kO2BlendModeCopy};c->_surface=s;c->_edgeCapacity=256;c->_edges=calloc(256,sizeof(Edge*));c->_sortCache=calloc(129,sizeof(Edge*));
 c->_winding=calloc(s->_width*256+1,sizeof(int));c->_rowIncrease=calloc(s->_width*256+1,sizeof(int));c->_increase=malloc(s->_width*sizeof(int));for(size_t i=0;i<s->_width;i++)c->_increase[i]=INT_MAX;
 c->samplesX=calloc(256,sizeof(O2Float));O2RasterizerSetViewport(c,0,0,s->_width,s->_height);O2RasterizerSetShouldAntialias(c,YES,64);
}
static void disposeContext(O2Context_builtin*c){O2RasterizerClear(c);for(int i=0;i<c->_edgeAllocated;i++)free(c->_edges[i]);free(c->_edges);free(c->_sortCache);free(c->_winding);free(c->_rowIncrease);free(c->_increase);free(c->samplesX);}
static void general(O2Context_builtin*c,O2Paint*p,double x0,double y0,double x1,double y1,int normal,int floating,O2Surface*mask){
 c->_writeCoverageFunction=floating?(void(*)())O2RasterizeWriteCoverageSpanffff:normal?(void(*)())O2RasterizeWriteCoverageSpan8888_Normal:(void(*)())O2RasterizeWriteCoverageSpan8888_Copy;
 c->_blendFunction=normal?(void*)O2BlendSpanNormal_ffff:(void*)O2BlendSpanCopy_ffff;
 O2DContextAddEdge(c,(O2Point){x0,y0},(O2Point){x1,y0});O2DContextAddEdge(c,(O2Point){x1,y0},(O2Point){x1,y1});O2DContextAddEdge(c,(O2Point){x1,y1},(O2Point){x0,y1});O2DContextAddEdge(c,(O2Point){x0,y1},(O2Point){x0,y0});
 O2DContextFillEdgesOnSurface(c,c->_surface,mask,p,-1);O2RasterizerClear(c);
}
static void checkDamage(O2Surface *s, const uint8_t *before, int hit) {
 O2SurfaceDamage damage;
 assert(O2SurfaceTakeDamage(s,&damage));
 for(size_t y=0;y<s->_height;y++)for(size_t byte=0;byte<s->_bytesPerRow;byte++){
  if(s->_pixelBytes[y*s->_bytesPerRow+byte]==before[y*s->_bytesPerRow+byte])continue;
  int covered=0;
  for(int i=0;i<damage.count;i++){
   O2SurfaceDamageRect r=damage.rects[i];
   covered|=byte/4>=(size_t)r.x&&byte/4<(size_t)(r.x+r.width)&&y>=(size_t)r.y&&y<(size_t)(r.y+r.height);
  }
  if(!covered){fprintf(stderr,"UNCOVERED fast-path write x=%zu y=%zu byte=%zu\n",byte/4,y,byte);abort();}
 }
 if(!hit)assert(damage.count==0);
 assert(O2SurfaceTakeDamage(s,&damage)&&damage.count==0);
}
static int candidate(O2Context_builtin*c,O2Paint*p,double x0,double y0,double x1,double y1,int normal,int floating,int masked){
#if HAVE_FAST_PATHS
 c->_state._blendMode=normal?kO2BlendModeNormal:kO2BlendModeCopy;c->_viewportClip=floating;
 if(masked)return 0;
 if(p->image){O2AffineTransform transform={1,0,0,p->transform.d,x0,p->transform.d<0?y0+p->image->_height:y0};return tryFastImage(c,p->image,transform);}
 O2Path path={5,4,{0,1,1,1,4},{{x0,y0},{x1,y0},{x1,y1},{x0,y1}}};
 // The path is in base space. Exercise the fixed backing Y flip independently
 // of user translations; general() receives the resulting surface rectangle.
 if(c->_state._deviceSpaceTransform.d<0)for(int i=0;i<4;i++)path._points[i].y=c->_surface->_height-path._points[i].y;
 c->_path=&path;int result=tryFastSolidRect(c,p);c->_path=NULL;return result;
#else
 (void)c;(void)p;(void)x0;(void)y0;(void)x1;(void)y1;(void)normal;(void)floating;(void)masked;return 0;
#endif
}
#if HAVE_FAST_PATHS
static void fastDamageCases(void) {
 unsigned cases=0;
 for(int format=0;format<2;format++)for(int op=0;op<4;op++)for(int flip=0;flip<2;flip++)for(int empty=0;empty<2;empty++){
  O2Surface dst,img;initSurface(&dst,16,16,format);initSurface(&img,8,8,format);
  O2Context_builtin c;initContext(&c,&dst);O2RasterizerSetViewport(&c,3,4,6,5);
  O2SurfaceDamage recorded={0};dst._damage=&recorded;
  uint8_t before[1280];memcpy(before,dst._pixelBytes,sizeof(before));
  for(int y=0;y<8;y++)for(int x=0;x<8;x++)img._pixelBytes[y*img._bytesPerRow+x*4+3]=255;
  O2Paint p={op==1?O2argb32fInit(0,0,0,0):O2argb32fInit(.3,.7,.4,1),op>=2?&img:NULL,{1,0,0,flip?-1:1,0,0},0,{0}};
  p._argb8u_PRE=O2argb8uFromO2argb32f(p._argb32f_PRE);
  int x=empty?32:1,y=2;
  assert(candidate(&c,&p,x,y,x+8,y+8,op==3,0,0));
  O2SurfaceDamage damage=recorded;
  checkDamage(&dst,before,1);
  assert(damage.count==(empty?0:1));
  if(!empty){O2SurfaceDamageRect r=damage.rects[0];assert(r.x==3&&r.y==4&&r.width==6&&r.height==5);}
  disposeContext(&c);free(dst._pixelBytes);free(img._pixelBytes);cases++;
 }
 printf("PASS %u exact damage rectangles: fill, clear, copy/blend blit, formats, Y flips, viewport intersections, empty writes\n",cases);
}
static void exhaustiveBlend(void){
 _Alignas(uint32_t) O2argb8u source[256],destination[256],expected[256];
 unsigned char rawSource[1040],rawDest[1040],rawExpected[1040];
 O2FastPixelRect clip={0,0,256,1};
 for(int format=0;format<2;format++)for(int alpha=0;alpha<256;alpha++)for(int dest=0;dest<256;dest++){
  memset(rawSource,0x91,sizeof(rawSource));memset(rawDest,0x72,sizeof(rawDest));memcpy(rawExpected,rawDest,sizeof(rawDest));
  for(int x=0;x<256;x++){source[x]=(O2argb8u){.r=x,.g=255-x,.b=x^85,.a=alpha};destination[x]=(O2argb8u){.r=dest,.g=dest^170,.b=255-dest,.a=(dest+x)&255};expected[x]=destination[x];}
  O2Surface input={0},output={0},oracle={0};input._pixelBytes=rawSource+1;output._pixelBytes=rawDest+2;oracle._pixelBytes=rawExpected+2;
  input._bytesPerRow=output._bytesPerRow=oracle._bytesPerRow=1027;
  void(*writer)(O2Surface*,int,int,O2argb8u*,int)=format?O2SurfaceWrite_argb8u_to_BGRA8888:O2SurfaceWrite_argb8u_to_argb8u;
  writer(&input,0,0,source,256);writer(&output,0,0,destination,256);
  O2argb8u_sover_by_coverage(source,expected,256,256);writer(&oracle,0,0,expected,256);
  O2FastPixelBuffer sb={rawSource+1,256,1,1027,format?2:1},db={rawDest+2,256,1,1027,format?2:1};
  assert(O2FastBlitPixels(db,sb,clip,0,0,0,1,0,NULL));assert(!memcmp(rawDest,rawExpected,sizeof(rawDest)));
 }
 puts("PASS 33554432 exhaustive packed blend pixel comparisons, both formats, every alpha/source/destination byte, malformed premultiplication and unaligned storage");
}
#endif
static void equivalence(void){
 unsigned cases=0,hits=0;
 for(int format=0;format<2;format++)for(int floating=0;floating<2;floating++)for(int trial=0;trial<1800;trial++){
  O2Surface a,b,img,mask;initSurface(&a,40,32,format);initSurface(&b,40,32,format);initSurface(&img,16,12,format);initSurface(&mask,40,32,format);
  memcpy(b._pixelBytes,a._pixelBytes,a._bytesPerRow*a._height);O2Context_builtin ca,cb;initContext(&ca,&a);initContext(&cb,&b);
  int quality=(int[]){1,2,4,16,64,256}[(trial/6)%6];O2RasterizerSetShouldAntialias(&ca,quality!=1,quality);O2RasterizerSetShouldAntialias(&cb,quality!=1,quality);
  if((trial/6)%3){int x=randomBelow(12),y=randomBelow(10),w=randomBelow(29),h=randomBelow(23);O2RasterizerSetViewport(&ca,x,y,w,h);O2RasterizerSetViewport(&cb,x,y,w,h);}
  int op=trial%6,normal=op==0||op==3||op==5,masked=trial%19==0;
  double x=(int)randomBelow(56)-16,y=(int)randomBelow(44)-12,w=randomBelow(40),h=randomBelow(32);
  O2Paint p={O2argb32fInit(randomBelow(65536)/65535.,randomBelow(65536)/65535.,randomBelow(65536)/65535.,1),NULL,{1,0,0,1,0,0},(trial/12)%2,{0}};
  if(op==1)p._argb32f_PRE=O2argb32fInit(0,0,0,0);
  if(op==2)p._argb32f_PRE=O2argb32fMultiplyByFloat(p._argb32f_PRE,.3);
  if(op>=3){p.image=&img;w=16;h=12;p.transform=(O2AffineTransform){1,0,0,(trial/6)%2?-1:1,-x,(trial/6)%2?y+h:-y};if(op==5)for(int sy=0;sy<12;sy++)for(int sx=0;sx<16;sx++)img._pixelBytes[sy*img._bytesPerRow+sx*4+3]=255;}
  if(trial%11==0&&!p.image){x+=.25;y+=.5;}
  if(trial%17==0&&!p.image){x+=w;w=-w;}
  p._argb8u_PRE=O2argb8uFromO2argb32f(p._argb32f_PRE);
  ca._state._userSpaceTransform=(O2AffineTransform){1,0,0,1,(int)randomBelow(9)-4,(int)randomBelow(9)-4};
  ca._state._deviceSpaceTransform=ca._state._userSpaceTransform;
  if((trial/18)%2){ca._state._deviceSpaceTransform.d=-1;ca._state._deviceSpaceTransform.ty=32-ca._state._userSpaceTransform.ty;}
  O2SurfaceDamage recorded={0};a._damage=&recorded;
  int hit=candidate(&ca,&p,x,y,x+w,y+h,normal,floating,masked);hits+=hit;
  checkDamage(&a,b._pixelBytes,hit);
  if(!hit){assert(!memcmp(a._pixelBytes,b._pixelBytes,a._bytesPerRow*a._height));general(&ca,&p,x,y,x+w,y+h,normal,floating,masked?&mask:NULL);}
  general(&cb,&p,x,y,x+w,y+h,normal,floating,masked?&mask:NULL);
  if(memcmp(a._pixelBytes,b._pixelBytes,a._bytesPerRow*a._height)){fprintf(stderr,"DIFFERENCE format=%d float=%d trial=%d op=%d hit=%d rect=%g,%g,%g,%g\n",format,floating,trial,op,hit,x,y,w,h);abort();}
  disposeContext(&ca);disposeContext(&cb);free(a._pixelBytes);free(b._pixelBytes);free(img._pixelBytes);free(mask._pixelBytes);cases++;
 }
#if HAVE_FAST_PATHS
 assert(hits>2000);
 fastDamageCases();
 exhaustiveBlend();
 // Execute production eligibility guards, including mismatched reader metadata.
 O2Surface gs,gi;initSurface(&gs,16,16,0);initSurface(&gi,8,8,0);O2Context_builtin gc;initContext(&gc,&gs);
 uint8_t original[1280];assert(sizeof(original)==gs._bytesPerRow*gs._height);memcpy(original,gs._pixelBytes,sizeof(original));
 O2Path gp={5,4,{0,1,1,1,4},{{0,0},{8,0},{8,8},{0,8}}};gc._path=&gp;
 O2Paint solid={O2argb32fInit(.2,.8,.3,1),NULL,{1,0,0,1,0,0},0,{0}};
 O2GState initial=gc._state;O2Surface initialImage=gi;int initialSpace=gs._colorSpace;
 for(int bad=0;bad<20;bad++){
  gc._state=initial;gi=initialImage;gs._colorSpace=initialSpace;gc._layerStack=0;gc._clipContext=NULL;gc._clipSamples=NULL;gc._edgeCount=0;
  if(bad==0)gc._state._alpha=.5;if(bad==1)gc._state._blendMode=3;if(bad==2)gc._state._userSpaceTransform.tx=.5;
  if(bad==3)gc._state._userSpaceTransform.a=2;if(bad==4)gc._state._deviceSpaceTransform.c=.5;
  if(bad==5)gc._layerStack=1;if(bad==6)gc._clipContext=&gc;if(bad==7)gc._clipSamples=(uint32_t*)original;
  if(bad==8)gc._edgeCount=1;
  if(bad==19)gs._colorSpace=4;
  if(bad<9||bad==19){assert(!tryFastSolidRect(&gc,&solid));assert(!tryFastImage(&gc,&gi,(O2AffineTransform){1,0,0,1,0,0}));}
  else{if(bad==9)gi._decode=(void*)1;if(bad==10)gi._decoder=(void*)1;if(bad==11)gi._clampExternalPixels=YES;
   if(bad==12)gi._bitmapInfo=kO2ImageAlphaLast;if(bad==13)gi._bitsPerComponent=16;if(bad==14)gi._directLength=1;
   if(bad==15)gi._read_argb8u=O2ImageRead_BGRA8888_to_argb8u;if(bad==16)gi._mask=&gs;if(bad==17)gi._isMask=YES;
   assert(!tryFastImage(&gc,&gi,(O2AffineTransform){bad==18?2:1,0,0,1,0,0}));}
  assert(!memcmp(original,gs._pixelBytes,sizeof(original)));cases++;
 }
 gc._clipContext=NULL;gc._clipSamples=NULL;gc._edgeCount=0;disposeContext(&gc);free(gs._pixelBytes);free(gi._pixelBytes);
 // Every aliasing arrangement is refused before mutation, including shifted
 // views with independent pointers and strides. The old path retains ownership.
 uint8_t storage[512];memset(storage,0x39,sizeof(storage));uint8_t saved[512];memcpy(saved,storage,512);
 for(int shift=0;shift<64;shift++)for(int flip=0;flip<2;flip++)for(int normal=0;normal<2;normal++){
  O2FastPixelBuffer d={storage,8,8,32,1},s={storage+shift,8,8,32,1};O2FastPixelRect clip={0,0,8,8};assert(!O2FastBlitPixels(d,s,clip,0,0,flip,normal,0,NULL));assert(!memcmp(saved,storage,512));cases++;}
 // Fractional/nonfinite edges, unsupported formats, invalid strides and clips.
 for(int bad=0;bad<8;bad++){
  O2FastPixelBuffer d={storage,8,8,32,1};O2FastPixelRect clip={0,0,8,8};double x=0;
  if(bad==0)x=.5;if(bad==1)x=NAN;if(bad==2)x=INFINITY;if(bad==3)d.format=3;if(bad==4)d.stride=31;if(bad==5)clip.x=-1;if(bad==6)clip.width=9;if(bad==7)d.width=SIZE_MAX;
  assert(!O2FastFillPixels(d,clip,x,0,4,4,storage+500,NULL));assert(!memcmp(saved,storage,512));cases++;
 }
#endif
 printf("PASS %u byte-identical randomized cases; %u fast-path hits; damage covers every changed byte; pinned old sweep/spans/samplers/conversions; RGBA/BGRA, clips, alpha, edge alignment, subrects, overlaps\n",cases,hits);
}
static volatile unsigned checksum;
static void benchmark(void){
 for(int pipeline=0;pipeline<2;pipeline++)for(int op=0;op<3;op++){
  O2Surface s,img;initSurface(&s,op==1?512:1932,op==1?512:1144,1);initSurface(&img,512,512,1);O2Context_builtin c;initContext(&c,&s);O2RasterizerSetShouldAntialias(&c,YES,256);
  for(int y=0;y<512;y++)for(int x=0;x<512;x++)img._pixelBytes[y*img._bytesPerRow+x*4+3]=255;
  O2Paint p={op==2?O2argb32fInit(0,0,0,0):O2argb32fInit(.82,.3,.91,1),op==1?&img:NULL,{1,0,0,-1,0,512},1,{0}};
  p._argb8u_PRE=O2argb8uFromO2argb32f(p._argb32f_PRE);
  for(int old=1;old>=0;old--){double samples[7];for(int repeat=0;repeat<7;repeat++){double start=now();for(int n=0;n<3;n++){if(old||!candidate(&c,&p,0,0,s._width,s._height,0,pipeline,0))general(&c,&p,0,0,s._width,s._height,0,pipeline,NULL);checksum+=s._pixelBytes[repeat*4];}samples[repeat]=(now()-start)*1000/3;for(size_t k=0;k<s._bytesPerRow*s._height;k++)checksum+=s._pixelBytes[k];}
   for(int i=0;i<7;i++)for(int j=i+1;j<7;j++)if(samples[j]<samples[i]){double t=samples[i];samples[i]=samples[j];samples[j]=t;}
   printf("TIMING %s %s %s median_ms=%.6f min_ms=%.6f max_ms=%.6f\n",pipeline?"float":"byte",op==0?"fill-1932x1144":op==1?"blit-512x512":"clear-1932x1144",old?"old":"new",samples[3],samples[0],samples[6]);}
  disposeContext(&c);free(s._pixelBytes);free(img._pixelBytes);
 }
}
int main(int argc,char**argv){setbuf(stdout,NULL);if(argc>1&&!strcmp(argv[1],"--benchmark"))benchmark();else equivalence();return 0;}
