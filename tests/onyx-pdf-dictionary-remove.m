#import <Foundation/Foundation.h>
#import <Onyx2D/O2PDFDictionary.h>
#include <stdio.h>
#define CHECK(c) do {if(!(c)){fprintf(stderr,"FAIL dictionary removal line %d: %s\n",__LINE__,#c);return 1;}}while(0)
int main(void) {
    NSAutoreleasePool *pool=[NSAutoreleasePool new];
    O2PDFDictionary *dictionary=[O2PDFDictionary pdfDictionary];
    [dictionary setIntegerForKey:"Keep" value:27];
    [dictionary setIntegerForKey:"Remove" value:91];
    BOOL available=YES;
    @try { [dictionary removeObjectForKey:"Remove"]; [dictionary removeObjectForKey:"Missing"]; }
    @catch (NSException *exception) { available=NO; }
    CHECK(available);
    O2PDFObject *object=nil;O2PDFInteger number=0;
    CHECK(![dictionary objectForKeyNoParsing:"Remove"] && ![dictionary getObjectForKey:"Remove" value:&object]);
    CHECK([dictionary getIntegerForKey:"Keep" value:&number] && number==27);
    [dictionary setIntegerForKey:"Remove" value:19]; [dictionary removeObjectForKey:"Remove"];
    CHECK(![dictionary objectForKeyNoParsing:"Remove"]);
    puts("PASS physical PDF dictionary key removal and missing-key no-op");
    [pool drain];return 0;
}
