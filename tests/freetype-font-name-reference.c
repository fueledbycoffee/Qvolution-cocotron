#include <stdio.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_TYPE1_TABLES_H
int main(int argc,char **argv) {
 FT_Library lib;if(argc!=2||FT_Init_FreeType(&lib))return 2;FT_Face face;if(FT_New_Face(lib,argv[1],0,&face))return 3;
 PS_FontInfoRec info;const char *ps=FT_Get_Postscript_Name(face);int status=FT_Get_PS_Font_Info(face,&info);
 printf("PostScript=%s FontInfoStatus=%d Full=%s\n",ps?ps:"(absent)",status,status==0&&info.full_name?info.full_name:"(absent)");
 FT_Done_Face(face);FT_Done_FreeType(lib);return status!=0;
}
