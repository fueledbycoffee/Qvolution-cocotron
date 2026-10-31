#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>
int main(int argc, const char **argv) {
 @autoreleasepool {
  if (argc != 2) { fprintf(stderr,"usage: rgb24-png OUTPUT.png\n"); return 2; }
  NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:3 pixelsHigh:2 bitsPerSample:8 samplesPerPixel:3 hasAlpha:NO isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bitmapFormat:0 bytesPerRow:12 bitsPerPixel:24];
  if (!rep || ![rep bitmapData] || [rep bytesPerRow]!=12 || [rep bitsPerPixel]!=24) { fprintf(stderr,"FAIL RGB24 construction\n"); [rep release]; return 1; }
  const unsigned char rows[24]={255,0,0, 0,255,0, 0,0,255, 0xA5,0xA5,0xA5, 17,34,51, 128,64,32, 9,199,240, 0xA5,0xA5,0xA5};
  memcpy([rep bitmapData],rows,sizeof(rows));
  NSData *png=[rep representationUsingType:NSPNGFileType properties:@{}];
  BOOL ok=png && [png length]>20 && [png writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES];
  fprintf(stderr,"%s RGB24 public PNG generation, bytes=%lu\n",ok?"PASS":"FAIL",(unsigned long)[png length]);
  [rep release]; return ok?0:1;
 }
}
