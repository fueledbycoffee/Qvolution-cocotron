#import <Foundation/Foundation.h>
#import <Onyx2D/O2PDFScanner.h>
#import <Onyx2D/O2PDFDictionary.h>
#import <Onyx2D/O2PDFString.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#define CHECK(c) do {if(!(c)){fprintf(stderr,"FAIL scanner line %d: %s\n",__LINE__,#c);return 1;}}while(0)
int main(int argc,char **argv) {
    NSAutoreleasePool *pool=[NSAutoreleasePool new];
    CHECK(argc==2); O2PDFInteger end=0; O2PDFObject *object=nil;
    if (!strcmp(argv[1],"numbers")) {
        const char *tokens[]={"12.125 ","23.5 ","113.375 ","66.25 ","1000000000000000000000000000000.0 ","0.000000000000000000000000000001 ","-1.2345678901234567 ","+.125 ","-.125 "};
        double expected[]={12.125,23.5,113.375,66.25,1e30,1e-30,-1.2345678901234567,.125,-.125};
        for (unsigned i=0;i<sizeof(expected)/sizeof(expected[0]);i++) {
            CHECK(O2PDFScanObject(tokens[i],strlen(tokens[i]),0,&end,&object));
            O2PDFReal actual; CHECK([object checkForType:kO2PDFObjectTypeReal value:&actual]);
            if (i<4) CHECK(actual==expected[i]);
            else CHECK(fabs((actual-expected[i])/expected[i])<1e-15);
        }
        const char *max="9223372036854775807 ",*min="-9223372036854775808 "; O2PDFInteger integer;
        CHECK(O2PDFScanObject(max,strlen(max),0,&end,&object) && [object checkForType:kO2PDFObjectTypeInteger value:&integer] && integer==NSIntegerMax);
        CHECK(O2PDFScanObject(min,strlen(min),0,&end,&object) && [object checkForType:kO2PDFObjectTypeInteger value:&integer] && integer==NSIntegerMin);
        const char *overflow="9223372036854775808 "; CHECK(!O2PDFScanObject(overflow,strlen(overflow),0,&end,&object));
        const char *exponent="1e3 "; CHECK(!O2PDFScanObject(exponent,strlen(exponent),0,&end,&object));
    } else if (!strcmp(argv[1],"names")) {
        const char *token="<< /F#31 27 /Hash#23Key /A#20B >> ";
        CHECK(O2PDFParseObject(token,strlen(token),0,&end,&object,nil));
        O2PDFDictionary *dictionary=nil;O2PDFInteger number;const char *name=NULL;
        CHECK([object checkForType:kO2PDFObjectTypeDictionary value:&dictionary]);
        CHECK([dictionary getIntegerForKey:"F1" value:&number] && number==27);
        CHECK([dictionary getNameForKey:"Hash#Key" value:&name] && !strcmp(name,"A B"));
        const char *badNames[]={"/Bad#QZ ","/Bad#0 ","/Bad#00 "};
        for (unsigned i=0;i<3;i++) CHECK(!O2PDFScanObject(badNames[i],strlen(badNames[i]),0,&end,&object));
    } else if (!strcmp(argv[1],"hex")) {
        const char *tokens[]={"<> ","< \t\r\n> ","< 41 42 F > "};
        for (unsigned i=0;i<3;i++) {
            CHECK(O2PDFScanObject(tokens[i],strlen(tokens[i]),0,&end,&object));
            O2PDFString *string=nil;CHECK([object checkForType:kO2PDFObjectTypeString value:&string]);
            CHECK([string length]==(i==2?3:0));
            if (i==2) CHECK(!memcmp([string bytes],"AB\xf0",3));
        }
    } else CHECK(0);
    printf("PASS scanner %s\n",argv[1]);[pool drain];return 0;
}
