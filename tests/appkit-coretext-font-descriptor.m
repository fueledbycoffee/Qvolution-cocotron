// Reuse exactly the standalone contract after AppKit registers its concrete class.
#define main standaloneDescriptorMain
#include "coretext-font-descriptor.m"
#undef main
#include <dlfcn.h>
int main(int argc,const char **argv) {
 NSAutoreleasePool *pool=[NSAutoreleasePool new];
 void *appkit=dlopen("/System/Library/Frameworks/AppKit.framework/AppKit",RTLD_LAZY|RTLD_LOCAL);
 CHECK(appkit&&NSClassFromString(@"NSFont")!=Nil,"actual AppKit class registers before first font");
 CTFontRef control=CTFontCreateWithName(CFSTR("DejaVuSans"),12,NULL);
 CHECK(control&&[(id)control isKindOfClass:NSClassFromString(@"NSFont")],"CoreText constructs actual NSFont bridge");
 CFRelease(control);
 int result=standaloneDescriptorMain(argc,argv);
 [pool drain];
 // Keep the framework loaded: its concrete class remains registered in CoreText.
 return result;
}
