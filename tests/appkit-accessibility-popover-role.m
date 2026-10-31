#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>
#define CHECK(c,m) do{if(!(c)){fprintf(stderr,"FAIL: %s\n",m);return 1;}}while(0)
int main(void){
 NSAutoreleasePool *pool=[NSAutoreleasePool new];
 void *library=dlopen("/System/Library/Frameworks/AppKit.framework/AppKit",RTLD_LAZY|RTLD_LOCAL);
 CHECK(library,"actual AppKit framework loads");
 NSString *const *language=dlsym(library,"NSAccessibilityLanguageAttribute");
 NSString *const *toggle=dlsym(library,"NSAccessibilitySwitchSubrole");
 CHECK(language&&toggle&&[*language isKindOfClass:[NSString class]]&&[*toggle isKindOfClass:[NSString class]],"existing accessibility data controls");
 CHECK([*language isEqual:@"AXLanguage"]&&[*toggle isEqual:@"AXSwitch"],"existing independently mapped values preserved");
 NSString *const *role=dlsym(library,"NSAccessibilityPopoverRole");
 CHECK(role&&*role,"observed public popover role data export exists");
 CHECK([*role isKindOfClass:[NSString class]]&&[*role isEqual:@"AXPopover"],"primary API-client popover wire spelling");
 CHECK(![*role isEqual:*language]&&! [*role isEqual:*toggle],"role stays distinct from attribute and subrole");
 NSAutoreleasePool *creation=[NSAutoreleasePool new];
 NSDictionary *metadata=[[NSDictionary alloc] initWithObjectsAndKeys:*role,@"role",nil];
 NSMutableString *local=[[*role mutableCopy] autorelease];[local appendString:@".fixture"];
 CHECK([*role isEqual:@"AXPopover"]&&! [local isEqual:*role],"local value mutation does not change immutable export");
 CHECK(dlsym(library,"QvolutionAbsentPopoverRole")==NULL,"missing role negative control");
 [creation drain];CHECK([[metadata objectForKey:@"role"] isEqual:@"AXPopover"],"owned generic role metadata survives pool");
 [metadata release];[pool drain];dlclose(library);
 puts("PASS: actual popover role NSString data and ownership; no accessibility-tree qualification");return 0;
}
