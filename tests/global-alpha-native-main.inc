static unsigned checks, failures;
static void check_at(bool ok,const char *path,int line){checks++;if(!ok){failures++;if(failures<12)fprintf(stderr,"FAIL %s (probe line %d)\n",path,line);}}
#define check(ok,path) check_at(ok,path,__LINE__)
/* Expected alpha for a stored value: the documented range is [0,1]; out of range is GUESS-grade. */
static double clamped(double a){return a!=a?0:a<0?0:a>1?1:a;}
static bool is_image(O2Paint *p){return [p isKindOfClass:[O2Paint_image class]];}
static void reset_image_alpha(O2Paint *p){
#if IMAGE_HAS_ALPHA
 if(is_image(p))((O2Paint_image *)p)->_alpha=1;
#endif
}
static O2Paint *install(O2Context_builtin *c,O2Paint *p,double a){
 O2GStateSetAlpha(&c->state,a);reset_image_alpha(p);image_call_site(c,p);
 O2ContextSetupPaintAndBlendMode(c,p,kO2BlendModeNormal);return c->_paint;
}
/* Post-switch selection of the 8u/float blend routines for each surface/clip environment. */
static void post_switch(O2Paint *p,double alpha,const char *path){
 double ea=clamped(alpha);
 O2Surface rw={1},ro={0};Stack *stack=[Stack alloc];
 for(int env=0;env<6;env++){
  O2Context_builtin c={0};c._surface=&rw;
  if(env==1)c._clipContext=(id)(uintptr_t)1;
  if(env==2)c.viewport=1;
  if(env==3)c._surface=&ro;
  if(env==4){stack->top=&ro;c._layerStack=stack;}
  if(env==5){stack->top=&rw;c._layerStack=stack;c._surface=&ro;}
  install(&c,p,alpha);
  bool opaque=p->isOpaque&&ea==1;
  bool fast=(env==0||env==5)&&p->_paint_largb8u_PRE!=NULL;
  if(fast){
   void *cov=opaque?(void *)O2RasterizeWriteCoverageSpan8888_Copy:(void *)O2RasterizeWriteCoverageSpan8888_Normal;
   check(c._writeCoverageFunction==cov&&c._blendFunction==NULL,path);
  }else{
   void *blend=opaque?(void *)O2BlendSpanCopy_ffff:(void *)O2BlendSpanNormal_ffff;
   check(c._blendFunction==blend&&c._writeCoverageFunction==(void *)O2RasterizeWriteCoverageSpanffff&&c._blend_argb8u_PRE==NULL&&c._writeCoverage_argb8u_PRE==NULL,path);
  }
  check(c._blend_argb32f_PRE==(opaque?(void *)O2BlendSpanCopy_ffff:(void *)O2BlendSpanNormal_ffff),path);
  O2ContextSetPaint(&c,NULL);
 }
 [stack release];
}
static void differential(O2Paint *p,const char *path,bool glyph){
 unsigned prior=failures;
 O2Context_builtin c={0};c._surface=&(O2Surface){1};
 double alphas[]={0,.125,.35,.5,.9995,1,2,-1,NAN};
 for(unsigned a=0;a<sizeof(alphas)/sizeof(*alphas);a++){
  double ea=clamped(alphas[a]);
  O2Paint *q=install(&c,p,alphas[a]);if(glyph)q=ft_paint(&c,p);
  check(c.state._alpha==ea,path);
  check(ea!=1||q==p,path);
  post_switch(p,alphas[a],path);
  for(int x=-3;x<24;x++)for(int len=1;len<=17;len+=4){
   O2argb32f before[20],after[20];memset(before,0x5a,sizeof(before));memset(after,0x5a,sizeof(after));
   reset_image_alpha(p);
   int n=O2PaintReadSpan_largb32f_PRE(p,x,1,before,len);
   image_call_site(&c,p);
   int m=O2PaintReadSpan_largb32f_PRE(q,x,1,after,len);
   check(n==m,path);
   if(n>0)for(int i=0;i<n;i++){
    /* Independent of the wrapper: scale each premultiplied channel in double and compare to a float ulp. */
    for(int ch=0;ch<4;ch++){
     const float *bc=(const float *)&before[i]+ch,*vc=(const float *)&after[i]+ch;
     check(fabs((double)*vc-(double)*bc*ea)<=1e-6,path);
    }
    check(after[i].r<=after[i].a+1e-6&&after[i].g<=after[i].a+1e-6&&after[i].b<=after[i].a+1e-6,path);
   }
   check(!memcmp(before+abs(n),after+abs(n),(20-abs(n))*sizeof(*before)),path);
   if(p->_paint_largb8u_PRE){
    O2argb8u b[20],v[20];memset(b,0x5a,sizeof(b));memset(v,0x5a,sizeof(v));
    reset_image_alpha(p);
    n=O2PaintReadSpan_argb8u_PRE(p,x,1,b,len);
    image_call_site(&c,p);
    m=O2PaintReadSpan_argb8u_PRE(q,x,1,v,len);check(n==m,path);
    if(n>0)for(int i=0;i<n;i++){
     /* Nearest byte to the exact product: any rounding convention is within half a step. */
     check(fabs(v[i].b-b[i].b*ea)<=.5+1e-6&&fabs(v[i].g-b[i].g*ea)<=.5+1e-6&&fabs(v[i].r-b[i].r*ea)<=.5+1e-6&&fabs(v[i].a-b[i].a*ea)<=.5+1e-6,path);
    }
    check(!memcmp(b+abs(n),v+abs(n),(20-abs(n))*sizeof(*b)),path);
   }
  }
 }
 O2ContextSetPaint(&c,NULL);printf("CHECKED %s failures=%u\n",path,failures-prior);
}
int main(void){
 O2Paint *rgb=[[O2Paint_color alloc] initWithRed:.8 green:.4 blue:.2 alpha:.7 surfaceToPaintTransform:O2AffineTransformIdentity];
 O2Paint *gray=[[O2Paint_color alloc] initWithGray:.6 alpha:1 surfaceToPaintTransform:O2AffineTransformIdentity];
 differential(rgb,"rgb-fill",false);differential(gray,"gray-fill",false);
 differential(rgb,"stroke",false);differential(rgb,"glyph",true);
 O2Image image={0},mask={1};O2Paint_pattern *pat=[O2Paint_pattern alloc];O2PaintInitWithTransform(pat,O2AffineTransformIdentity);
 pat->_image=&image;pat->_paint_largb8u_PRE=o2pattern_largb8u_PRE;pat->_paint_largb32f_PRE=o2pattern_largb32f_PRE;
 differential(pat,"pattern-fill-and-stroke",false);[pat release];
 O2Paint_image *im=[O2Paint_image alloc];O2PaintInitWithTransform(im,O2AffineTransformIdentity);im->_image=&image;
 reset_image_alpha(im);
 O2PaintReadSpan_argb8u_PRE_function bytes[]={O2PaintReadIntegerTranslateSpan_largb8u_PRE,O2PaintReadResampledNoneSpan_largb8u_PRE,O2PaintReadResampledLowSpan_largb8u_PRE,O2PaintReadResampledLowSpanFloatTranslate_largb8u_PRE};
 for(int mode=0;mode<4;mode++)for(int masked=0;masked<2;masked++){
  im->_mask=masked?&mask:NULL;im->_paint_largb8u_PRE=bytes[mode];im->_paint_largb32f_PRE=mode==1?O2PaintReadResampledNoneSpan_largb32f_PRE:O2PaintReadResampledLowSpan_largb32f_PRE;
  differential(im,masked?"masked-image-and-layer":"image-and-layer",false);
 }
 im->_paint_largb8u_PRE=NULL;differential(im,"float-only-image",false);
 [im release];
 GradientStop stops[3];for(int i=0;i<3;i++){stops[i].offset=i*.5;stops[i].color32f=O2argb32fInit(.1+i*.2,.25,.125,.6+i*.2);stops[i].color8u=O2argb8uFromO2argb32f(stops[i].color32f);}
 O2Paint_axialGradient *ax=[O2Paint_axialGradient alloc];O2PaintInitWithTransform(ax,O2AffineTransformIdentity);
 ax->_startPoint=(O2Point){0,0};ax->_endPoint=(O2Point){12,0};ax->_u=(O2Point){12,0};ax->_oou=1./144;ax->_rho=.05;ax->_colorStops=stops;ax->_numberOfColorStops=3;ax->_paint_largb8u_PRE=linear_span_largb8u_PRE;ax->_paint_largb32f_PRE=linear_span_largb32f_PRE;
 differential(ax,"axial-shading-skip-spans",false);[ax release];
 O2Paint_radialGradient *ra=[O2Paint_radialGradient alloc];O2PaintInitWithTransform(ra,O2AffineTransformIdentity);
 ra->_startPoint=(O2Point){4,2};ra->_endPoint=(O2Point){8,2};ra->_startRadius=1;ra->_endRadius=10;ra->_colorStops=stops;ra->_numberOfColorStops=3;ra->_paint_largb8u_PRE=radial_span_largb8u_PRE;ra->_paint_largb32f_PRE=radial_span_largb32f_PRE;
 differential(ra,"radial-shading-skip-spans",false);[ra release];
 // Alpha 1 keeps the exact constant-colour and opacity identity used by fast paths.
 O2Context_builtin c={0};c._surface=&(O2Surface){1};O2Paint *q=install(&c,gray,1);O2argb32f value;
 check(q==gray&&O2PaintGetConstantColor(q,&value)&&c._blend_argb32f_PRE==(void *)O2BlendSpanCopy_ffff,"constant-fast-path-alpha-one");
 q=install(&c,gray,.5);check(q!=gray&&!O2PaintGetConstantColor(q,&value)&&c._blend_argb32f_PRE==(void *)O2BlendSpanNormal_ffff,"fractional-alpha-not-opaque-copy");
 // Repeated installation must neither stack adapters nor mutate the source paint.
 for(int i=0;i<100;i++){q=install(&c,gray,.5);O2argb32f out;O2PaintReadSpan_largb32f_PRE(q,0,0,&out,1);check(out.a==.5,"repeated-install");}
#if HAS_PAINT_ALPHA
 // The paint wrapper clamps by itself, so a caller that bypasses the state setter is safe.
 double wild[]={2,-1,NAN,INFINITY,-INFINITY};
 for(unsigned i=0;i<sizeof(wild)/sizeof(*wild);i++){
  O2Paint *w=O2PaintCreateWithAlpha(rgb,wild[i]);O2argb32f base,out;
  O2PaintReadSpan_largb32f_PRE(rgb,0,0,&base,1);O2PaintReadSpan_largb32f_PRE(w,0,0,&out,1);
  check(isfinite(out.a)&&fabs((double)out.a-(double)base.a*clamped(wild[i]))<=1e-6,"wrapper-clamp");
  check(clamped(wild[i])!=1||w==rgb,"wrapper-clamp-identity");
  O2PaintRelease(w);
 }
#endif
 O2ContextSetPaint(&c,NULL);[rgb release];[gray release];check(alive==0,"paint-ownership");
 printf("RESULT native-global-alpha checks=%u failures=%u alive=%d\n",checks,failures,alive);return failures!=0;
}
