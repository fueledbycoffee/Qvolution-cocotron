// Original events exercise the actual own Wayland backend without fake proxies.
#import <AppKit/AppKit.h>
#import <AppKit/NSDisplay.h>
#import <objc/runtime.h>
#import "../AppKit/Wayland.backend/WaylandProtocol.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-util.h>
#define CHECK(x) do{if(!(x)){fprintf(stderr,"FAIL line%d: %s\n",__LINE__,#x);exit(1);}}while(0)
@interface NSObject (OwnScreenMetadata)
- (NSString *)localizedName;
- (void)outputEvent:(uint32_t)opcode output:(id)output arguments:(union wl_argument *)args;
- (void)logicalOutputEvent:(uint32_t)opcode output:(id)output arguments:(union wl_argument *)args;
- (void)invalidateScreens;
- (NSArray *)screens;
@end
static void scalar(id obj,const char *name,uint32_t value) {
    Ivar field=class_getInstanceVariable([obj class],name);CHECK(field!=NULL);
    memcpy((unsigned char *)obj+ivar_getOffset(field),&value,sizeof(value));
}
static void geometry(id display,id output,const char *make,const char *model) {
    union wl_argument a[8]={0};a[5].s=make;a[6].s=model;
    [display outputEvent:WP_OUTPUT_EV_GEOMETRY output:output arguments:a];
}
static void done(id display,id output) {
    union wl_argument a[1]={0};[display outputEvent:WP_OUTPUT_EV_DONE output:output arguments:a];
}
static void text(id display,id output,uint32_t kind,const char *value) {
    union wl_argument a[1]={{.s=value}};[display logicalOutputEvent:kind output:output arguments:a];
}
static void logicalDone(id display,id output) {
    union wl_argument a[1]={0};[display logicalOutputEvent:WP_LOGICAL_OUTPUT_EV_DONE output:output arguments:a];
}
static NSString *name(id display) {return [[[display screens] objectAtIndex:0] localizedName];}
int main(void) {
    NSScreen *retainedScreen=nil;NSString *retainedName=nil;
    @autoreleasepool {
        [NSApplication sharedApplication];CHECK([[NSApp windows] count]==0);
        id display=[NSDisplay currentDisplay];CHECK([NSStringFromClass([display class]) isEqualToString:@"WaylandDisplay"]);
        CHECK([NSScreen instancesRespondToSelector:@selector(localizedName)]);
        Ivar outputsField=class_getInstanceVariable([display class],"_outputs");CHECK(outputsField!=NULL);
        NSMutableArray *outputs=object_getIvar(display,outputsField);NSArray *saved=[outputs copy];
        Class outputClass=NSClassFromString(@"WaylandOutput");CHECK(outputClass!=Nil);
        id output=[outputClass new];
        Ivar modesField=class_getInstanceVariable(outputClass,"_pendingModes");CHECK(modesField!=NULL);
        object_setIvar(output,modesField,[NSMutableArray new]);
        scalar(output,"_version",2);scalar(output,"_logicalVersion",0);
        [outputs removeAllObjects];[outputs addObject:output];[display invalidateScreens];
        @try {
            CHECK([name(display) isEqualToString:@"Display 1"]);
            union wl_argument scale[1]={{.i=1}};[display outputEvent:WP_OUTPUT_EV_SCALE output:output arguments:scale];
            union wl_argument mode[4]={{.u=WP_OUTPUT_MODE_CURRENT},{.i=100},{.i=50},{.i=60000}};
            [display outputEvent:WP_OUTPUT_EV_MODE output:output arguments:mode];
            char make[]="Acme",model[]="Panel";geometry(display,output,make,model);
            make[0]='X';model[0]='Y';
            CHECK([name(display) isEqualToString:@"Display 1"]);done(display,output);
            CHECK([name(display) isEqualToString:@"Acme Panel"]);
            NSArray *snapshot=[[display screens] retain];retainedScreen=[[snapshot objectAtIndex:0] retain];
            retainedName=[[retainedScreen localizedName] copy];
            geometry(display,output,"Other","Panel2");
            CHECK([display screens]==snapshot);CHECK([name(display) isEqualToString:@"Acme Panel"]);
            done(display,output);CHECK([name(display) isEqualToString:@"Other Panel2"]);
            CHECK([[retainedScreen localizedName] isEqualToString:@"Acme Panel"]);[snapshot release];
            scalar(output,"_logicalVersion",2);
            char description[]="Desk Display";
            text(display,output,WP_LOGICAL_OUTPUT_EV_DESCRIPTION,description);description[0]='Z';
            CHECK([name(display) isEqualToString:@"Other Panel2"]);
            logicalDone(display,output);CHECK([name(display) isEqualToString:@"Desk Display"]);
            scalar(output,"_logicalVersion",3);
            text(display,output,WP_LOGICAL_OUTPUT_EV_DESCRIPTION,"Updated Display");
            logicalDone(display,output);CHECK([name(display) isEqualToString:@"Desk Display"]);
            done(display,output);CHECK([name(display) isEqualToString:@"Updated Display"]);
            text(display,output,WP_LOGICAL_OUTPUT_EV_DESCRIPTION,"");
            text(display,output,WP_LOGICAL_OUTPUT_EV_NAME,"Virtual-1");
            geometry(display,output,"","");done(display,output);
            CHECK([name(display) isEqualToString:@"Virtual-1"]);
            text(display,output,WP_LOGICAL_OUTPUT_EV_NAME,NULL);done(display,output);
            CHECK([name(display) isEqualToString:@"Display 1"]);
            const char invalid[]={ (char)0xff,0 };
            geometry(display,output,invalid,invalid);
            text(display,output,WP_LOGICAL_OUTPUT_EV_DESCRIPTION,invalid);
            text(display,output,WP_LOGICAL_OUTPUT_EV_NAME,invalid);done(display,output);
            CHECK([name(display) isEqualToString:@"Display 1"]);
            geometry(display,output," Atelier "," Écran ");done(display,output);
            CHECK([name(display) isEqualToString:@"Atelier Écran"]);
            scalar(output,"_version",1);scalar(output,"_logicalVersion",0);
            geometry(display,output,NULL,"Legacy"); // Corev1 publishes immediately.
            CHECK([name(display) isEqualToString:@"Legacy"]);
            [outputs removeObject:output];[display invalidateScreens];
            CHECK([name(display) isEqualToString:@"Display 1"]);
            CHECK([[retainedScreen localizedName] isEqualToString:@"Acme Panel"]);
        } @finally {
            [outputs setArray:saved];[display invalidateScreens];[saved release];[output release];
        }
    }
    CHECK([[retainedScreen localizedName] isEqualToString:retainedName]);
    [retainedScreen release];[retainedName release];
    puts("PASS: actual output metadata batching, copied wire strings, Unicode/fallback and independent retained screen/name lifetime");return 0;
}
