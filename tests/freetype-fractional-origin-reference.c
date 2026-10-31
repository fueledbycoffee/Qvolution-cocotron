#include <ft2build.h>
#include FT_FREETYPE_H
#include <math.h>
#include <stdio.h>
#include <string.h>
static double centroid(FT_Face face,FT_UInt glyph,double origin,double *coverage) {
 FT_Vector phase={(FT_Pos)llround((origin-floor(origin))*64),0};FT_Set_Transform(face,NULL,&phase);
 if(FT_Load_Glyph(face,glyph,FT_LOAD_DEFAULT)||FT_Render_Glyph(face->glyph,FT_RENDER_MODE_NORMAL))return NAN;
 FT_Bitmap *bitmap=&face->glyph->bitmap;double total=0,sum=0;
 for(unsigned y=0;y<bitmap->rows;y++)for(unsigned x=0;x<bitmap->width;x++) {
  unsigned alpha=bitmap->buffer[y*bitmap->pitch+x];total+=alpha;sum+=alpha*(floor(origin)+face->glyph->bitmap_left+x+0.5);
 }
 *coverage=total;return sum/total;
}
int main(int argc,char **argv) {
 FT_Library library;FT_Face face;if(argc!=2||FT_Init_FreeType(&library)||FT_New_Face(library,argv[1],0,&face))return 2;
 if(!FT_Get_Postscript_Name(face)||strcmp(FT_Get_Postscript_Name(face),"DejaVuSans"))return 2;
 FT_UInt glyph=FT_Get_Char_Index(face,'f');int failures=0;
 for(int scale=1;scale<=2;scale++) {
  FT_Set_Char_Size(face,0,28*scale*64,72,72);double weight,base=centroid(face,glyph,10*scale,&weight);
  double shifts[]={.25,.5,1};for(int i=0;i<3;i++) {double movedWeight;double result=centroid(face,glyph,(10+shifts[i])*scale,&movedWeight);double expected=shifts[i]*scale;int pass=fabs(result-base-expected)<=.15;failures+=!pass;
   printf("%s scale=%d phase=%.2f dx=%.6f expected=%.3f coverage_ratio=%.6f\n",pass?"PASS":"FAIL",scale,shifts[i],result-base,expected,movedWeight/weight);
  }
 }
 FT_Done_Face(face);FT_Done_FreeType(library);return failures!=0;
}
