// Adapted public Scrubber model/image/render contract after image codec integration.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>
#define CHECK(c,m) do{if(!(c)){fprintf(stderr,"FAIL %s\n",m);return 1;}}while(0)
@protocol QVAttributes <NSObject,NSCopying>
+(id)layoutAttributesForItemAtIndex:(NSInteger)index;
@property NSInteger itemIndex;
@property NSRect frame;
@property CGFloat alpha;
@end
@protocol QVArranged <NSObject>
@property(getter=isSelected) BOOL selected;
@property(getter=isHighlighted) BOOL highlighted;
-(void)applyLayoutAttributes:(id<QVAttributes>)attributes;
@end
@protocol QVImageItem <QVArranged>
@property(copy) NSImage *image;
@property(readonly,strong) NSImageView *imageView;
@property NSImageAlignment imageAlignment;
@end
static NSImage *originalImage(void){
 NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:8 pixelsHigh:4 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:32 bitsPerPixel:32];
 if(!rep)return nil;unsigned char *bytes=[rep bitmapData];for(int y=0;y<4;y++)for(int x=0;x<8;x++){unsigned char *p=bytes+y*32+x*4;p[0]=x<3?255:0;p[1]=x>=3&&y<2?255:0;p[2]=x>=3&&y>=2?255:0;p[3]=255;}
 NSImage *image=[[NSImage alloc]initWithSize:NSMakeSize(8,4)];[image addRepresentation:rep];[rep release];return image;
}
static unsigned raster(NSImageView *view,unsigned char *bytes){
 memset(bytes,0,80*60*4);CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();CGContextRef context=CGBitmapContextCreate(bytes,80,60,8,80*4,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);if(!context){CGColorSpaceRelease(space);return 0;}
 [NSGraphicsContext saveGraphicsState];@try{[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithGraphicsPort:context flipped:NO]];[view drawRect:[view bounds]];}@finally{[NSGraphicsContext restoreGraphicsState];CGContextRelease(context);CGColorSpaceRelease(space);}unsigned visible=0;for(int i=0;i<80*60;i++)if(bytes[i*4+3])visible++;return visible;
}
static int attributes(void){
 Class<QVAttributes> cls=(Class<QVAttributes>)NSClassFromString(@"NSScrubberLayoutAttributes");CHECK(cls,"real layout attributes class exists");CHECK([(id)cls respondsToSelector:@selector(layoutAttributesForItemAtIndex:)],"public indexed factory exists");
 id<QVAttributes> value=[cls layoutAttributesForItemAtIndex:7];CHECK(value&&[value itemIndex]==7,"factory preserves actual item index");[value setFrame:NSMakeRect(3,4,80,60)];[value setAlpha:0.35];id<QVAttributes> copy=[value copy];CHECK(copy&&copy!=value&&NSEqualRects([copy frame],[value frame])&&[copy alpha]==(CGFloat)0.35&&[copy itemIndex]==7,"independent layout data copy");[value setItemIndex:9];[value setFrame:NSMakeRect(0,0,4,4)];[value setAlpha:1];CHECK([copy itemIndex]==7&&NSEqualRects([copy frame],NSMakeRect(3,4,80,60))&&[copy alpha]==(CGFloat)0.35,"copy survives original mutation");[copy release];return 0;
}
static int base(void){
 Class cls=NSClassFromString(@"NSScrubberItemView");CHECK(cls&&[cls isSubclassOfClass:[NSView class]],"existing actual item view hierarchy control");NSView<QVArranged> *view=[[(id)cls alloc]initWithFrame:NSMakeRect(0,0,20,20)];CHECK(view,"actual item frame constructor");
 CHECK([view respondsToSelector:@selector(isSelected)]&&[view respondsToSelector:@selector(setSelected:)]&&[view respondsToSelector:@selector(isHighlighted)]&&[view respondsToSelector:@selector(setHighlighted:)],"genuine selection/highlight methods, not forwarding signatures");
 [view setNeedsDisplay:NO];[view setSelected:YES];CHECK([view isSelected]&&[view needsDisplay],"selected state stores and invalidates");[view setNeedsDisplay:NO];[view setHighlighted:YES];CHECK([view isHighlighted]&&[view isSelected]&&[view needsDisplay],"independent highlighted state stores and invalidates");[view setSelected:NO];CHECK(![view isSelected]&&[view isHighlighted],"selection and highlight remain independent");
 Class<QVAttributes> attrs=(Class<QVAttributes>)NSClassFromString(@"NSScrubberLayoutAttributes");CHECK(attrs,"real layout attributes prerequisite");id<QVAttributes> a=[attrs layoutAttributesForItemAtIndex:2];[a setFrame:NSMakeRect(6,7,80,60)];[a setAlpha:0.35];[view applyLayoutAttributes:a];CHECK(NSEqualRects([view frame],[a frame])&&[view alphaValue]==(CGFloat)0.35,"public attributes apply frame and alpha model");[view setSelected:YES];
 NSData *archive=[NSKeyedArchiver archivedDataWithRootObject:view];NSView<QVArranged> *decoded=[NSKeyedUnarchiver unarchiveObjectWithData:archive];CHECK(decoded&&[decoded isSelected]&&[decoded isHighlighted]&&NSEqualRects([decoded frame],[view frame]),"own base keyed state/frame roundtrip");[view release];return 0;
}
static int image(void){
 Class cls=NSClassFromString(@"NSScrubberImageItemView");CHECK(cls,"public concrete image item class exists");NSView<QVImageItem> *item=[[(id)cls alloc]initWithFrame:NSMakeRect(0,0,80,60)];CHECK(item&&[item isKindOfClass:NSClassFromString(@"NSScrubberItemView")],"image item actual base hierarchy");CHECK([item respondsToSelector:@selector(imageView)]&&[item respondsToSelector:@selector(setImage:)],"real image getter/setter methods");NSImageView *child=[item imageView];CHECK(child&&[child isKindOfClass:[NSImageView class]]&&[child superview]==item&&NSEqualRects([child frame],[item bounds]),"actual owned image subview fills bounds");
 NSImage *source=originalImage();CHECK(source,"own bitmap image control");[item setImage:source];[source setSize:NSMakeSize(16,4)];[source release];CHECK([item image]&&NSEqualSizes([[item image]size],NSMakeSize(8,4))&&[child image]==[item image],"copied image survives original size mutation/release and backs actual child");
 [item setFrameSize:NSMakeSize(100,40)];CHECK(NSEqualRects([child frame],[item bounds]),"actual image child follows resize");[item setFrameSize:NSMakeSize(80,60)];
 unsigned char top[80*60*4],bottom[80*60*4];[item setImageAlignment:NSImageAlignTop];CHECK([item imageAlignment]==NSImageAlignTop&&[child imageAlignment]==NSImageAlignTop,"alignment forwards to actual child");CHECK(raster(child,top)>100,"actual NSImageView renders original pixels");[item setImageAlignment:NSImageAlignBottom];CHECK(raster(child,bottom)>100&&memcmp(top,bottom,sizeof top),"alignment changes actual image raster placement");
 NSData *populatedArchive=[NSKeyedArchiver archivedDataWithRootObject:item];NSView<QVImageItem> *populatedCopy=[NSKeyedUnarchiver unarchiveObjectWithData:populatedArchive];CHECK(populatedCopy&&[populatedCopy image]&&NSEqualSizes([[populatedCopy image]size],NSMakeSize(8,4)),"populated keyed coding preserves image size");unsigned char copied[80*60*4];CHECK(raster([populatedCopy imageView],copied)>100&&!memcmp(bottom,copied,sizeof bottom),"populated keyed coding preserves rendered content and alignment");
 CHECK(NSEqualSizes([[item image]size],NSMakeSize(8,4)),"coding preserves live image");
 [item setImage:nil];CHECK(![item image]&&![child image],"cleared content stays absent");[item setSelected:YES];[item setHighlighted:YES];
 NSData *archive=[NSKeyedArchiver archivedDataWithRootObject:item];NSView<QVImageItem> *decoded=[NSKeyedUnarchiver unarchiveObjectWithData:archive];CHECK(decoded&&[decoded imageView]&&[[decoded imageView]superview]==decoded&&[decoded isSelected]&&[decoded isHighlighted]&&! [decoded image],"own empty image child/state roundtrip");unsigned children=0;for(NSView *v in [decoded subviews])if([v isKindOfClass:[NSImageView class]])children++;CHECK(children==1&&[decoded imageAlignment]==NSImageAlignBottom&&NSEqualRects([[decoded imageView]frame],[decoded bounds]),"decoded owned child is unique with actual alignment/layout");
 [item release];NSView<QVImageItem> *fresh=[[(id)cls alloc]initWithFrame:NSMakeRect(0,0,12,12)];NSImageView *retained=[[fresh imageView]retain];[fresh release];CHECK([retained superview]==nil,"item release detaches independently retained child without cycle");[retained release];return 0;
}
static int populatedCoding(void){
 Class cls=NSClassFromString(@"NSScrubberImageItemView");CHECK(cls,"concrete image item prerequisite");NSView<QVImageItem> *item=[[(id)cls alloc]initWithFrame:NSMakeRect(0,0,80,60)];NSImage *source=originalImage();[item setImage:source];[source release];
 @try{NSData *data=[NSKeyedArchiver archivedDataWithRootObject:item];NSView<QVImageItem>*copy=[NSKeyedUnarchiver unarchiveObjectWithData:data];CHECK(copy&&[copy image]&&NSEqualSizes([[copy image]size],NSMakeSize(8,4)),"populated item preserves actual image");unsigned char pixels[80*60*4];CHECK(raster([copy imageView],pixels)>100,"populated roundtrip retains actual pixels");[item release];return 0;}@catch(NSException *e){fprintf(stderr,"FAIL populated image coding prerequisite %s\n",[[e name]UTF8String]);[item release];return 1;}
}
static int objectValueCoding(void){
 Class cls=NSClassFromString(@"NSScrubberImageItemView");CHECK(cls,"concrete image item prerequisite");NSView<QVImageItem> *item=[[(id)cls alloc]initWithFrame:NSMakeRect(0,0,80,60)];NSImage *source=originalImage();CHECK(item&&source,"image item and source");[[item imageView] setObjectValue:source];[source release];CHECK(![item image]&&[[[item imageView] objectValue] isKindOfClass:[NSImage class]],"direct object value stored separately from image");unsigned char before[80*60*4],after[80*60*4];CHECK(raster([item imageView],before)>100,"object value renders before coding");NSData *data=[NSKeyedArchiver archivedDataWithRootObject:item];NSView<QVImageItem> *copy=[NSKeyedUnarchiver unarchiveObjectWithData:data];CHECK(copy&&! [copy image]&&[[[copy imageView] objectValue] isKindOfClass:[NSImage class]]&&NSEqualSizes([[[copy imageView] objectValue] size],NSMakeSize(8,4)),"direct image object value survives keyed coding");CHECK(raster([copy imageView],after)>100&&!memcmp(before,after,sizeof before),"direct object value preserves rendered pixels");[item release];return 0;
}
static int codingControl(BOOL image){
 @try {
  NSView *view=image?[[NSImageView alloc]initWithFrame:NSMakeRect(2,3,80,60)]:[[NSView alloc]initWithFrame:NSMakeRect(2,3,80,60)];
  if(image){NSImage *source=originalImage();[(NSImageView*)view setImage:source];[source release];}
  NSData *data=[NSKeyedArchiver archivedDataWithRootObject:view];id copy=[NSKeyedUnarchiver unarchiveObjectWithData:data];CHECK(copy&&NSEqualRects([copy frame],[view frame]),"existing own keyed view geometry control");
  if(image)CHECK([copy image]&&NSEqualSizes([[copy image]size],NSMakeSize(8,4)),"existing image-content keyed control");[view release];return 0;
 } @catch(NSException *e){fprintf(stderr,"FAIL existing coding control exception %s\n",[[e name]UTF8String]);return 1;}
}
int main(int argc,char**argv){@autoreleasepool{
 [NSApplication sharedApplication];CHECK([NSImageView isSubclassOfClass:[NSView class]],"existing concrete image view positive class control");const char *mode=argc>1?argv[1]:"image";int result;
 if(!strcmp(mode,"attributes"))result=attributes();else if(!strcmp(mode,"base"))result=base();else if(!strcmp(mode,"image"))result=image();else if(!strcmp(mode,"image-populated-coding"))result=populatedCoding();else if(!strcmp(mode,"object-value-coding"))result=objectValueCoding();else if(!strcmp(mode,"coding-control"))result=codingControl(NO);else if(!strcmp(mode,"coding-image-control"))result=codingControl(YES);else if(!strcmp(mode,"render-control")){NSImage *source=originalImage();CHECK(source,"original bitmap");NSImageView *view=[[NSImageView alloc]initWithFrame:NSMakeRect(0,0,80,60)];[view setImage:source];[view setImageScaling:NSImageScaleProportionallyUpOrDown];unsigned char pixels[80*60*4];CHECK(raster(view,pixels)>100,"existing NSImageView actual raster positive control");[view release];[source release];result=0;}else{fputs("FAIL unknown mode\n",stderr);return 2;}
 if(!result)puts("PASS original Scrubber public model/image/CPU-raster mode; no full scrubber or compositor qualification");return result;
}}
