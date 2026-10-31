#import <Foundation/Foundation.h>
#import <Onyx2D/O2PDFScanner.h>
#import <Onyx2D/O2PDFDictionary.h>
#include <stdio.h>
#include <string.h>
#define CHECK(c) do { if (!(c)) { fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#c); return 1; } } while (0)
int main(void) {
    puts("ENTER empty-name scanner"); fflush(stdout);
    NSAutoreleasePool *pool=[NSAutoreleasePool new];
    const char *tokens[]={"/ ","/]","/", "/abc", "/#20 "};
    const char *expected[]={"","","","abc"," "};
    for (unsigned i=0;i<5;i++) {
        O2PDFObject *obj=nil; O2PDFInteger end=0; const char *name=NULL;
        CHECK(O2PDFScanObject(tokens[i],strlen(tokens[i]),0,&end,&obj));
        CHECK([obj checkForType:kO2PDFObjectTypeName value:&name] && !strcmp(name,expected[i]));
        CHECK(end==(i==3?4:(i==4?4:1)));
    }
    const char *source="<< / /Value /Name / /Escaped /A#20B >> ";
    O2PDFObject *obj=nil; O2PDFInteger end=0; O2PDFDictionary *dict=nil; const char *name=NULL;
    CHECK(O2PDFParseObject(source,strlen(source),0,&end,&obj,nil));
    CHECK([obj checkForType:kO2PDFObjectTypeDictionary value:&dict]);
    CHECK([dict getNameForKey:"" value:&name] && !strcmp(name,"Value"));
    CHECK([dict getNameForKey:"Name" value:&name] && !strcmp(name,""));
    CHECK([dict getNameForKey:"Escaped" value:&name] && !strcmp(name,"A B"));
    const char *invalid[]={"/# ","/#0 ","/#GG ","/#00 ","/#", "/#0"};
    for (unsigned i=0;i<6;i++) CHECK(!O2PDFScanObject(invalid[i],strlen(invalid[i]),0,&end,&obj));
    puts("PASS empty-name scanner and dictionary"); [pool drain]; return 0;
}
