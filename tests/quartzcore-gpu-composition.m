#define GL_GLEXT_PROTOTYPES 1
#import <AppKit/AppKit.h>
#import <CoreGraphics/CGSubWindow.h>
#import <CoreGraphics/CGWindowPrivate.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/CGLInternal.h>
#import <OpenGL/glext.h>
#import <QuartzCore/QuartzCore.h>
#import "../QuartzCore/CALayerInternal.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { SceneWidth=96, SceneHeight=64, ImageWidth=16, ImageHeight=12, ImageStride=80 };
static void checkComposition(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr,"FAIL: %s\n",message); exit(1); }
}

// Independent scene description: premultiplied source-over in bottom-left
// coordinates. This does not read uploaded image bytes or CARenderer state.
static void sourceColor(int x, int y, int version, double result[4]) {
    static const double colors[4][4]={{1,0,0,1},{0,1,0,0.5},{0,0,1,0.75},{1,1,0,0.25}};
    int quadrant=(y>=ImageHeight/2 ? 2:0)+(x>=ImageWidth/2 ? 1:0);
    if (version) quadrant^=1;
    for (int channel=0;channel<3;channel++) result[channel]=colors[quadrant][channel]*colors[quadrant][3];
    result[3]=colors[quadrant][3];
}
static void expectedPixel(double x, double y, int phase, unsigned char result[4]) {
    double color[4]={32.0/255,32.0/255,32.0/255,1};
    int positions[2][2]={{8,8},{phase ? 30:16,phase ? 20:12}};
    for (int layer=0;layer<2;layer++) {
        int sx=(int)floor(x-positions[layer][0]), sy=(int)floor(y-positions[layer][1]);
        if (sx<0 || sy<0 || sx>=ImageWidth || sy>=ImageHeight) continue;
        double source[4]; sourceColor(sx,sy,layer==0 ? phase:0,source);
        double opacity=layer ? 0.5:1;
        for (int c=0;c<4;c++) color[c]=source[c]*opacity+color[c]*(1-source[3]*opacity);
    }
    for (int c=0;c<4;c++) result[c]=(unsigned char)lround(color[c]*255);
}

// Exercise real CPU CoreGraphics rasterization into deliberately padded rows.
static CGImageRef rasterImage(int version, BOOL corrupt) {
    size_t stride=version ? 77:ImageStride;
    unsigned char *bytes=malloc(stride*ImageHeight);
    checkComposition(bytes!=NULL,"raster allocation"); memset(bytes,0xA5,stride*ImageHeight);
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(bytes,ImageWidth,ImageHeight,8,stride,space,
            kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space); checkComposition(context!=NULL,"CPU bitmap context");
    CGContextClearRect(context,CGRectMake(0,0,ImageWidth,ImageHeight));
    // Different expression from the oracle: four explicit fills, not a readback
    // of the resulting bitmap used as the expected image.
    const CGFloat fills[4][4]={{1,0,0,1},{0,1,0,0.5},{0,0,1,0.75},{1,1,0,0.25}};
    for (int row=0;row<2;row++) for (int column=0;column<2;column++) {
        int index=row*2+(version ? 1-column:column);
        CGContextSetRGBFillColor(context,fills[index][0],fills[index][1],fills[index][2],fills[index][3]);
        CGContextFillRect(context,CGRectMake(column*8,row*6,8,6));
    }
    if (corrupt) bytes[2]^=0xFF;
    CGImageRef image=CGBitmapContextCreateImage(context);
    checkComposition(image!=NULL && CGImageGetBytesPerRow(image)==stride,"padded CPU image stride preserved");
    CGContextRelease(context); free(bytes);
    return image;
}
static CALayer *imageLayer(CGImageRef image, int x, int y, double opacity, GLuint texture) {
    CALayer *layer=[CALayer layer];
    layer.anchorPoint=CGPointZero; layer.position=CGPointMake(x,y);
    layer.bounds=CGRectMake(0,0,ImageWidth,ImageHeight); layer.opacity=opacity;
    layer.contents=(id)image; layer.minificationFilter=kCAFilterNearest; layer.magnificationFilter=kCAFilterNearest;
    [layer _setTextureId:[NSNumber numberWithUnsignedInt:texture]];
    return layer;
}
static void renderAndCheck(CARenderer *renderer, int width, int height, int phase, const char *label) {
    glViewport(0,0,width,height);
    glMatrixMode(GL_PROJECTION); glLoadIdentity(); glOrtho(0,SceneWidth,0,SceneHeight,-1,1);
    GLuint unpackBuffer=0;
    if (phase) {
        glGenBuffers(1,&unpackBuffer); glBindBuffer(GL_PIXEL_UNPACK_BUFFER,unpackBuffer);
        glBufferData(GL_PIXEL_UNPACK_BUFFER,256,NULL,GL_STREAM_DRAW);
        glPixelStorei(GL_UNPACK_ALIGNMENT,8); glPixelStorei(GL_UNPACK_ROW_LENGTH,3);
        glPixelStorei(GL_UNPACK_SKIP_ROWS,1); glPixelStorei(GL_UNPACK_SKIP_PIXELS,1);
        glPixelStorei(GL_UNPACK_SWAP_BYTES,GL_TRUE);
    }
    [renderer render]; glFinish();
    if (phase) {
        GLint value;
        glGetIntegerv(GL_UNPACK_ALIGNMENT,&value); checkComposition(value==8,"unpack alignment restored");
        glGetIntegerv(GL_UNPACK_ROW_LENGTH,&value); checkComposition(value==3,"unpack row length restored");
        glGetIntegerv(GL_UNPACK_SKIP_ROWS,&value); checkComposition(value==1,"unpack row skip restored");
        glGetIntegerv(GL_UNPACK_SKIP_PIXELS,&value); checkComposition(value==1,"unpack pixel skip restored");
        glGetIntegerv(GL_UNPACK_SWAP_BYTES,&value); checkComposition(value==GL_TRUE,"unpack byte swap restored");
        glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING,&value); checkComposition(value==(GLint)unpackBuffer,"unpack buffer restored");
    }
    unsigned char *pixels=malloc((size_t)width*height*4); checkComposition(pixels!=NULL,"readback allocation");
    glPixelStorei(GL_PACK_ALIGNMENT,1); glReadPixels(0,0,width,height,GL_RGBA,GL_UNSIGNED_BYTE,pixels);
    checkComposition(glGetError()==GL_NO_ERROR,"real CARenderer composition GL status");
    unsigned mismatches=0;
    for (int y=0;y<height;y++) for (int x=0;x<width;x++) {
        unsigned char expected[4]; expectedPixel((x+0.5)*SceneWidth/width,(y+0.5)*SceneHeight/height,phase,expected);
        unsigned char *actual=pixels+((size_t)y*width+x)*4;
        BOOL wrong=NO; for (int c=0;c<4;c++) if(abs(actual[c]-expected[c])>2) wrong=YES;
        if (wrong && mismatches++==0) fprintf(stderr,"%s pixel(%d,%d) got=%u,%u,%u,%u expected=%u,%u,%u,%u\n",
                label,x,y,actual[0],actual[1],actual[2],actual[3],expected[0],expected[1],expected[2],expected[3]);
    }
    free(pixels); printf("%s phase=%d size=%dx%d mismatched_pixels=%u\n",label,phase,width,height,mismatches);
    checkComposition(mismatches==0,"independent CPU source-over oracle");
    glPixelStorei(GL_UNPACK_ALIGNMENT,4); glPixelStorei(GL_UNPACK_ROW_LENGTH,0);
    glPixelStorei(GL_UNPACK_SKIP_ROWS,0); glPixelStorei(GL_UNPACK_SKIP_PIXELS,0);
    glPixelStorei(GL_UNPACK_SWAP_BYTES,GL_FALSE); glBindBuffer(GL_PIXEL_UNPACK_BUFFER,0);
    if (unpackBuffer) glDeleteBuffers(1,&unpackBuffer);
}
@interface CompositionStopper : NSObject @end
@implementation CompositionStopper
- (void)windowWillClose:(NSNotification *)notification { [self fire:nil]; }
- (void)fire:(NSTimer *)timer {
    [NSApp stop:nil];
    [NSApp postEvent:[NSEvent otherEventWithType:NSApplicationDefined location:NSZeroPoint modifierFlags:0
            timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0] atStart:YES];
}
@end
@interface NSObject (CompositionNative)
- (BOOL)isMapped;
- (BOOL)isInvalidated;
- (CGSize)drawablePixelSize;
@end
@interface NSWindow (CompositionNative)
- (CGWindow *)platformWindow;
- (CGSubWindow *)_createSubWindowWithFrame:(CGRect)frame;
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        setbuf(stdout,NULL);
        BOOL corrupt=NO, present=NO, hold=NO;
        for (int i=1;i<argc;i++) {
            if (!strcmp(argv[i],"--negative-control")) corrupt=YES;
            else if (!strcmp(argv[i],"--present")) present=YES;
            else if (!strcmp(argv[i],"--hold")) { present=YES; hold=YES; }
            else checkComposition(NO,"unknown argument");
        }
        [NSApplication sharedApplication];
        CGLPixelFormatAttribute attributes[]={kCGLPFAAccelerated,0};
        CGLPixelFormatObj format=NULL; CGLContextObj context=NULL; GLint count=0;
        checkComposition(CGLChoosePixelFormat(attributes,&format,&count)==kCGLNoError && format && count,"pixel format");
        checkComposition(CGLCreateContext(format,NULL,&context)==kCGLNoError && context,"CGL composition context");
        checkComposition(CGLSetCurrentContext(context)==kCGLNoError,"make composition context current");
        const char *renderer=(const char *)glGetString(GL_RENDERER), *vendor=(const char *)glGetString(GL_VENDOR);
        const char *version=(const char *)glGetString(GL_VERSION);
        checkComposition(renderer && vendor && version,"renderer identity");
        printf("renderer=%s\nvendor=%s\nversion=%s\n",renderer,vendor,version);
        checkComposition(strtod(version,NULL)>=3,"probe requires desktop GL 3 framebuffer bindings");
        NSString *identity=[NSString stringWithUTF8String:renderer];
        for (NSString *software in @[@"llvmpipe",@"softpipe",@"swrast",@"swiftshader",@"software"])
            checkComposition([identity rangeOfString:software options:NSCaseInsensitiveSearch].location==NSNotFound,"software renderer rejected");
        GLuint fbo=0, target=0, textures[2];
        glGenTextures(2,textures); glGenTextures(1,&target); glBindTexture(GL_TEXTURE_2D,target);
        glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,SceneWidth,SceneHeight,0,GL_RGBA,GL_UNSIGNED_BYTE,NULL);
        glGenFramebuffers(1,&fbo); glBindFramebuffer(GL_FRAMEBUFFER,fbo);
        glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,target,0);
        checkComposition(glCheckFramebufferStatus(GL_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE,"composition framebuffer");
        CALayer *root=[CALayer layer]; root.anchorPoint=CGPointZero;
        root.bounds=CGRectMake(0,0,SceneWidth,SceneHeight);
        CGColorRef background=CGColorCreateGenericRGB(32.0/255,32.0/255,32.0/255,1);
        root.backgroundColor=background; CGColorRelease(background);
        CGImageRef first=rasterImage(0,corrupt), second=rasterImage(0,NO);
        CALayer *a=imageLayer(first,8,8,1,textures[0]), *b=imageLayer(second,16,12,0.5,textures[1]);
        [root addSublayer:a]; [root addSublayer:b]; CGImageRelease(first); CGImageRelease(second);
        CARenderer *composition=[CARenderer rendererWithCGLContext:context options:nil];
        composition.layer=root; composition.bounds=root.bounds;
        renderAndCheck(composition,SceneWidth,SceneHeight,0,"offscreen");
        CGImageRef changed=rasterImage(1,NO); a.contents=(id)changed; CGImageRelease(changed);
        b.position=CGPointMake(30,20);
        renderAndCheck(composition,SceneWidth,SceneHeight,1,"updated");
        NSWindow *window=nil; CGSubWindow *child=nil; CGLWindowRef drawable=NULL;
        if (present) {
            window=[[NSWindow alloc] initWithContentRect:NSMakeRect(100,100,320,200)
                    styleMask:NSTitledWindowMask|NSClosableWindowMask backing:NSBackingStoreBuffered defer:NO];
            [window setReleasedWhenClosed:NO]; [window setTitle:@"Qvolution CPU raster / GPU composition"];
            [window makeKeyAndOrderFront:nil];
            checkComposition([NSStringFromClass([[window platformWindow] class]) isEqualToString:@"WaylandWindow"],"native Wayland backend required");
            CompositionStopper *stopper=[[[CompositionStopper alloc] init] autorelease];
            [NSTimer scheduledTimerWithTimeInterval:0.5 target:stopper selector:@selector(fire:) userInfo:nil repeats:NO];
            [NSApp run]; checkComposition([(id)[window platformWindow] isMapped],"native parent mapped");
            [[NSNotificationCenter defaultCenter] addObserver:stopper selector:@selector(windowWillClose:)
                    name:NSWindowWillCloseNotification object:window];
            child=[[window _createSubWindowWithFrame:CGRectMake(16,16,SceneWidth,SceneHeight)] retain];
            checkComposition(child && [child nativeWindow],"native EGL child");
            drawable=CGLGetWindowForContext(context,[child nativeWindow]); checkComposition(drawable!=NULL,"native EGL drawable");
            checkComposition(CGLContextMakeCurrentAndAttachToWindow(context,drawable)==kCGLNoError,"attach actual native drawable");
            GLint state;
            glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING,&state);checkComposition(state==(GLint)fbo,"first native attach preserves draw FBO");
            glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&state);checkComposition(state==(GLint)fbo,"first native attach preserves read FBO");
            glGetIntegerv(GL_DRAW_BUFFER,&state);checkComposition(state==GL_COLOR_ATTACHMENT0,"first native attach preserves FBO draw selection");
            glGetIntegerv(GL_READ_BUFFER,&state);checkComposition(state==GL_COLOR_ATTACHMENT0,"first native attach preserves FBO read selection");
            glBindFramebuffer(GL_FRAMEBUFFER,0);
            glGetIntegerv(GL_DRAW_BUFFER,&state);checkComposition(state==GL_BACK,"first native default draw buffer initialized");
            glGetIntegerv(GL_READ_BUFFER,&state);checkComposition(state==GL_BACK,"first native default read buffer initialized");
            CGSize pixels=[(id)child drawablePixelSize]; checkComposition(pixels.width>0 && pixels.height>0,"native drawable size");
            renderAndCheck(composition,pixels.width,pixels.height,1,"native-preswap");
            glDrawBuffer(GL_NONE);glReadBuffer(GL_NONE);
            checkComposition(CGLContextMakeCurrentAndAttachToWindow(context,drawable)==kCGLNoError,"repeat native attach");
            glGetIntegerv(GL_DRAW_BUFFER,&state);checkComposition(state==GL_NONE,"repeat native attach preserves explicit draw NONE");
            glGetIntegerv(GL_READ_BUFFER,&state);checkComposition(state==GL_NONE,"repeat native attach preserves explicit read NONE");
            glBindFramebuffer(GL_DRAW_FRAMEBUFFER,fbo);
            checkComposition(CGLContextMakeCurrentAndAttachToWindow(context,drawable)==kCGLNoError,"repeat native attach with separate FBOs");
            glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING,&state);checkComposition(state==(GLint)fbo,"repeat attach preserves nondefault draw FBO");
            glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&state);checkComposition(state==0,"repeat attach preserves independent read FBO");
            glGetIntegerv(GL_DRAW_BUFFER,&state);checkComposition(state==GL_COLOR_ATTACHMENT0,"repeat attach preserves FBO draw selection");
            glGetIntegerv(GL_READ_BUFFER,&state);checkComposition(state==GL_NONE,"repeat attach preserves independent read selection");
            glBindFramebuffer(GL_FRAMEBUFFER,0);glDrawBuffer(GL_BACK);glReadBuffer(GL_BACK);
            renderAndCheck(composition,pixels.width,pixels.height,1,"native-after-rebind");
            checkComposition(CGLFlushDrawable(context)==kCGLNoError,"native EGL swap"); [child flush];
            puts("PASS: native EGL child swap and parent commit submitted; compositor-visible acceptance separate");
            if (hold) [NSApp run];
            [[NSNotificationCenter defaultCenter] removeObserver:stopper];
        }
        glDeleteFramebuffers(1,&fbo); glDeleteTextures(1,&target); glDeleteTextures(2,textures);
        CGLSetCurrentContext(NULL); if (drawable) CGLDestroyWindow(drawable);
        [child hide]; [child release]; [window orderOut:nil]; [window release];
        CGLDestroyContext(context); CGLDestroyPixelFormat(format);
        puts("PASS: CPU-raster layers, real GPU composition, stride/orientation/alpha/update oracle");
    }
    return 0;
}
