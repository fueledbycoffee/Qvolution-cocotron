#import <Foundation/Foundation.h>
#import <Onyx2D/O2PDFFilter.h>
#import <Onyx2D/O2PDFDictionary.h>
#include <assert.h>
#include <stdio.h>
#ifdef NDEBUG
#error Assertions required
#endif
int main(int argc,char **argv) {
    @autoreleasepool {
        setbuf(stdout,NULL);assert(argc==2);
        NSString *directory=[NSString stringWithUTF8String:argv[1]];
        NSData *json=[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@"predictors.json"]];
        NSArray *vectors=[NSJSONSerialization JSONObjectWithData:json options:0 error:NULL];assert(vectors);
        for(NSDictionary *v in vectors) {
            NSString *name=[v objectForKey:@"name"];
            NSData *input=[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:[name stringByAppendingString:@".flate"]]];
            NSData *expected=[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:[name stringByAppendingString:@".raw"]]];
            BOOL invalid=[[v objectForKey:@"invalid"] boolValue];
            assert(input && (invalid || expected));
            O2PDFDictionary *parameters=[O2PDFDictionary pdfDictionary];
            const char *keys[]={"Predictor","Colors","BitsPerComponent","Columns"};
            NSArray *jsonKeys=@[@"predictor",@"colors",@"bits",@"columns"];
            for(unsigned i=0;i<4;++i)[parameters setIntegerForKey:keys[i] value:[[v objectForKey:[jsonKeys objectAtIndex:i]] integerValue]];
            size_t rowBytes=0;
            NSData *actual=[O2PDFFilter decodeWithName:"FlateDecode" data:input parameters:parameters bytesPerRow:&rowBytes];
            printf("PREDICTOR %s\n",[name UTF8String]);
            if(invalid) { assert(actual==nil);continue; }
            assert([actual isEqualToData:expected]);
            NSUInteger expectedRow=([[v objectForKey:@"colors"] unsignedIntegerValue]*[[v objectForKey:@"bits"] unsignedIntegerValue]*[[v objectForKey:@"columns"] unsignedIntegerValue]+7)/8;
            assert(rowBytes==expectedRow);
        }
        puts("PASS: PDF PNG and TIFF prediction preserves actual bytes");
    }
    return 0;
}
