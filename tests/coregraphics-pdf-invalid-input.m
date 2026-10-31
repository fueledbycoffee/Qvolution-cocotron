#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>
#ifdef NDEBUG
#error Assertions required
#endif
int main(void) {
    @autoreleasepool {
        setbuf(stdout,NULL);
        const char *cases[]={
            "not-a-pdf\n%%EOF\n",
            "%PDF-1.4\nbroken\nstartxref\n9\n%%EOF\n",
            "%PDF-1.4\nxref\n0 1\n0000000000 65535 f \ntrailer\n>>\nstartxref\n9\n%%EOF\n",
        };
        for(unsigned i=0;i<sizeof(cases)/sizeof(cases[0]);++i) {
            printf("INVALID PDF case%u\n",i);
            CFDataRef bytes=CFDataCreate(NULL,(const UInt8*)cases[i],strlen(cases[i]));
            CGDataProviderRef provider=CGDataProviderCreateWithCFData(bytes);
            CGPDFDocumentRef document=CGPDFDocumentCreateWithProvider(provider);
            CGDataProviderRelease(provider);CFRelease(bytes);
            assert(document==NULL); // An exception is an actual test failure.
        }
        puts("PASS: invalid PDF creation returns NULL without exceptions");
    }
    return 0;
}
