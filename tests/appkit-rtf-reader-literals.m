// Original public RTF reader: lexical symbols, destination isolation and halfpoint size.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <math.h>
static unsigned failures;
static void expectReader(BOOL c,const char *m){printf("%s: %s\n",c?"PASS":"FAIL",m);failures+=!c;}
static NSAttributedString *readRTFOriginal(const char *rtf){return [[[NSAttributedString alloc]initWithRTF:[NSData dataWithBytes:rtf length:strlen(rtf)] documentAttributes:NULL]autorelease];}
int main(void){@autoreleasepool{
 setbuf(stdout,NULL);[NSApplication sharedApplication];
 NSAttributedString *s=readRTFOriginal("{\\rtf1\\ansi\\fs35 A\\{B\\}\\\\C}");
 expectReader(s!=nil,"actual public reader accepts bounded original RTF");
 expectReader([[s string]isEqualToString:@"A{B}\\C"],"escaped braces/backslash become literal text in order");
 NSFont *font=[s length]?[s attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL]:nil;
 expectReader(font&&fabs([font pointSize]-17.5)<.00001,"fs35 preserves fractional17.5point size");
 s=readRTFOriginal("{\\rtf1\\ansi x{y\\{z\\}}q{\\*\\unknown ignored\\{escaped\\}}end}");
 expectReader([[s string]isEqualToString:@"xy{z}qend"],"literal escapes preserve groups and ignored destination isolation");
 printf("RESULT %u failures\n",failures);return failures?1:0;
}}
