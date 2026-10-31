#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Onyx2D/O2PDFDocument.h>
#import <Onyx2D/O2PDFDictionary.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>
#ifdef NDEBUG
#error Assertions required
#endif
static void checkPDF(NSString *path,unsigned expected) {
    printf("PARSE %s\n",[[path lastPathComponent] UTF8String]);
    NSData *data=[NSData dataWithContentsOfFile:path];assert(data);
    CGDataProviderRef provider=CGDataProviderCreateWithCFData((CFDataRef)data);
    CGPDFDocumentRef document=CGPDFDocumentCreateWithProvider(provider);
    CGDataProviderRelease(provider);
    if(!expected) { assert(!document);return; }
    assert(document && CGPDFDocumentGetNumberOfPages(document)==1);
    CGPDFPageRef page=CGPDFDocumentGetPage(document,1);assert(page);
    NSString *name=[path lastPathComponent];
    if([name hasPrefix:@"eof-"]) {
        O2PDFDictionary *catalog=[(O2PDFDocument *)document catalog];
        O2PDFObject *probe;assert([catalog getObjectForKey:"Probe" value:&probe]);
        if([name isEqualToString:@"eof-integer.pdf"])assert([probe objectType]==kO2PDFObjectTypeInteger);
        if([name isEqualToString:@"eof-real.pdf"])assert([probe objectType]==kO2PDFObjectTypeReal);
        if([name isEqualToString:@"eof-name.pdf"])assert([probe objectType]==kO2PDFObjectTypeName);
        if([name isEqualToString:@"eof-boolean.pdf"])assert([probe objectType]==kO2PDFObjectTypeBoolean);
        if([name isEqualToString:@"eof-null.pdf"])assert([probe objectType]==kO2PDFObjectTypeNull);
    }
    assert(CGRectEqualToRect(CGPDFPageGetBoxRect(page,kCGPDFMediaBox),CGRectMake(0,0,32,32)));
    unsigned char pixels[32*32*4];memset(pixels,0,sizeof(pixels));
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(pixels,32,32,8,128,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);assert(context);
    CGContextSetRGBFillColor(context,1,1,1,1);CGContextFillRect(context,CGRectMake(0,0,32,32));
    CGContextDrawPDFPage(context,page);CGContextFlush(context);
    unsigned char *p=pixels+(16*32+16)*4;
    printf("PIXEL %u %u %u %u\n",p[0],p[1],p[2],p[3]);
    assert(p[3]>=250);
    if(expected==1)assert(p[0]>=250 && p[1]<=5 && p[2]<=5);
    if(expected==2)assert(p[0]<=5 && p[1]>=250 && p[2]<=5);
    if(expected==3)assert(p[0]>=250 && p[1]>=250 && p[2]>=250);
    CGContextRelease(context);CGPDFDocumentRelease(document);
}
int main(int argc,char **argv) {
    @autoreleasepool {
        setbuf(stdout,NULL);assert(argc==2);
        NSString *directory=[NSString stringWithUTF8String:argv[1]];
        NSArray *red=@[@"flate.pdf",@"raw.pdf",@"object-stream.pdf",@"default-width.pdf",@"index.pdf",@"png-up.pdf",@"png-all.pdf",@"compact-header.pdf",@"eof-integer.pdf",@"eof-real.pdf",@"eof-name.pdf",@"eof-boolean.pdf",@"eof-null.pdf"];
        for(NSString *name in red)checkPDF([directory stringByAppendingPathComponent:name],1);
        checkPDF([directory stringByAppendingPathComponent:@"incremental.pdf"],2);
        checkPDF([directory stringByAppendingPathComponent:@"hybrid.pdf"],2);
        checkPDF([directory stringByAppendingPathComponent:@"free-newest.pdf"],3);
        for(NSString *name in @[@"truncated.pdf",@"bad-width.pdf",@"bad-index.pdf",@"prev-cycle.pdf",@"bad-object-self-ref.pdf",@"bad-object-mutual-ref.pdf",@"bad-object-first.pdf",@"bad-object-count.pdf",@"bad-object-index.pdf",@"bad-map-key.pdf"])
            checkPDF([directory stringByAppendingPathComponent:name],0);
        puts("PASS: xref streams/object streams parse and render actual page pixels");
    }
    return 0;
}
