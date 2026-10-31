#import <Foundation/Foundation.h>
#import <AppKit/NSFontDescriptor.h>
#include <math.h>
#include <stdio.h>
static unsigned failures;
static void expectWeight(BOOL condition,const char *message){printf("%s: %s\n",condition?"PASS":"FAIL",message);if(!condition)failures++;}
int main(void){
 setbuf(stdout,NULL);puts("ENTER: original normalized font weight data");NSAutoreleasePool *pool=[NSAutoreleasePool new];
 const NSFontWeight weights[]={NSFontWeightUltraLight,NSFontWeightThin,NSFontWeightLight,NSFontWeightRegular,NSFontWeightMedium,NSFontWeightSemibold,NSFontWeightBold,NSFontWeightHeavy,NSFontWeightBlack};
 const char *names[]={"ultraLight","thin","light","regular","medium","semibold","bold","heavy","black"};
 for(unsigned i=0;i<9;i++){
  printf("MEASURE: %s=%.12g\n",names[i],(double)weights[i]);
  expectWeight(isfinite(weights[i])&&weights[i]>=-1&&weights[i]<=1,"exported weight is finite normalized CGFloat");
  if(i)expectWeight(weights[i]>weights[i-1],"named weight ordering is strictly increasing");
  if(i<3)expectWeight(weights[i]<0,"light and thin named weights are negative");
  else if(i==3)expectWeight(weights[i]==0,"regular is zero");
  else expectWeight(weights[i]>0,"heavier named weights are positive");
 }
 [pool drain];printf("RESULT: %u failures\n",failures);return failures?1:0;
}
