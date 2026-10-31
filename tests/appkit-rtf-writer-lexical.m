// Original lexical writer workload; independent host format parser verifies output.
#import <AppKit/AppKit.h>
#include <stdio.h>
#define REQUIRE(c,m) do{if(!(c)){fprintf(stderr,"FAIL: %s\n",m);return 1;}}while(0)
int main(int argc,char **argv){@autoreleasepool{
 setbuf(stdout,NULL);REQUIRE(argc==2,"caller-owned fresh output directory required");[NSApplication sharedApplication];
 NSString *directory=[NSString stringWithUTF8String:argv[1]];BOOL isDirectory=NO;
 REQUIRE([[NSFileManager defaultManager]fileExistsAtPath:directory isDirectory:&isDirectory]&&isDirectory,"existing output directory");
 NSMutableString *text=[NSMutableString string];for(unsigned i=0;i<256;i++)[text appendString:@"0123456789abcdef"];
 [text appendString:@" {brace}\\slash é e\u0301 \U0001D538\n\tend\r"];
 NSAttributedString *source=[[[NSAttributedString alloc]initWithString:text attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:17.5]}]autorelease];
 NSRange ranges[]={NSMakeRange(0,[text length]),NSMakeRange(4096,[text length]-4096),NSMakeRange([text length],0)};
 NSString *names[]={@"full.rtf",@"slice.rtf",@"empty.rtf"};
 for(unsigned i=0;i<3;i++){
  NSString *path=[directory stringByAppendingPathComponent:names[i]];REQUIRE(![[NSFileManager defaultManager]fileExistsAtPath:path],"never overwrite existing output");
  NSData *data=[source dataFromRange:ranges[i] documentAttributes:@{NSDocumentTypeDocumentAttribute:NSRTFTextDocumentType} error:NULL];
  REQUIRE(data&&[data length]>0,"actual writer returns bytes");REQUIRE([data writeToFile:path atomically:YES],"save actual bytes");
  REQUIRE([[NSData dataWithContentsOfFile:path]isEqual:data],"reopen exact bytes");
 }
 REQUIRE([[source string]isEqual:text],"writer preserves input UTF16 text");puts("PASS: lexical writer fresh files ready for independent oracle");return 0;
}}
