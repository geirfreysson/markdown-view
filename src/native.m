#import "native.h"
#include "render.h"

@interface MdvCell : NSObject
@property NSMutableAttributedString *text;
@property unsigned row, column, alignment;
@property BOOL header;
@end
@implementation MdvCell
@end
@interface NativeRender : NSObject
@property NSMutableAttributedString *output;
@property NSURL *base;
@property NSMutableDictionary *cache;
@property CGFloat size;
@property NSMutableArray<MdvCell *> *cells;
@property MdvCell *cell;
@property unsigned columns;
@end
@implementation NativeRender
@end
static NSURL *resolveURL(NSString *target, NSURL *base) {
    if (!target.length) return nil;
    if ([target hasPrefix:@"www."]) target=[@"https://" stringByAppendingString:target];
    NSURL *url=[NSURL URLWithString:target relativeToURL:base];
    if(!url) url=[NSURL fileURLWithPath:target relativeToURL:[base URLByDeletingLastPathComponent]];
    return url.absoluteURL;
}
static NSDictionary *attributes(NativeRender *r, const MdvStyle *style) {
    NSNumber *key=@((uint64_t)style->flags | ((uint64_t)style->heading<<16) | ((uint64_t)style->indent<<24));
    NSDictionary *cached=r.cache[key]; if(cached) return cached;
    CGFloat size=r.size;
    if(style->heading) { const double factors[]={1,1.75,1.4,1.2,1.1,1.0,1.0}; size*=factors[MIN(style->heading,6)]; }
    BOOL mono=style->flags&MDV_CODE;
    NSFontWeight weight=style->heading?NSFontWeightSemibold:((style->flags&MDV_BOLD)?NSFontWeightSemibold:NSFontWeightRegular);
    NSFont *font=mono?[NSFont monospacedSystemFontOfSize:size*0.9 weight:weight]:[NSFont systemFontOfSize:size weight:weight];
    if(style->flags&MDV_ITALIC) font=[NSFont fontWithDescriptor:[font.fontDescriptor fontDescriptorWithSymbolicTraits:font.fontDescriptor.symbolicTraits|NSFontItalicTrait] size:font.pointSize]?:font;
    NSMutableParagraphStyle *p=[NSMutableParagraphStyle new];
    p.lineSpacing=mono?3:5;
    p.paragraphSpacing=style->indent?5:10;
    p.headIndent=style->indent*20; p.firstLineHeadIndent=p.headIndent;
    p.tailIndent=760; p.tabStops=@[];
    if(style->heading) { p.paragraphSpacingBefore=style->heading==1?0:16; p.paragraphSpacing=8; }
    if(style->flags&MDV_CODE_BLOCK) { p.headIndent+=12; p.firstLineHeadIndent+=12; p.paragraphSpacing=0; }
    NSMutableDictionary *a=[@{NSFontAttributeName:font,NSForegroundColorAttributeName:NSColor.textColor,NSParagraphStyleAttributeName:p} mutableCopy];
    if(style->flags&MDV_CODE) a[NSBackgroundColorAttributeName]=[NSColor.quaternaryLabelColor colorWithAlphaComponent:0.1];
    if(style->flags&MDV_STRIKE) a[NSStrikethroughStyleAttributeName]=@(NSUnderlineStyleSingle);
    if(style->flags&MDV_QUOTE && !(style->flags&MDV_TABLE)) {
        a[NSForegroundColorAttributeName]=NSColor.secondaryLabelColor;
        NSTextBlock *quote=[NSTextBlock new];
        [quote setContentWidth:100 type:NSTextBlockPercentageValueType];
        [quote setWidth:12 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockPadding];
        [quote setWidth:3 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockBorder edge:NSMinXEdge];
        [quote setBorderColor:[NSColor.controlAccentColor colorWithAlphaComponent:0.5] forEdge:NSMinXEdge];
        p.textBlocks=@[quote]; p.headIndent=0; p.firstLineHeadIndent=0;
    }
    r.cache[key]=a; return a;
}
static void finishTable(NativeRender *r) {
    if(!r.columns) return;
    NSMutableArray<NSNumber *> *widths=[NSMutableArray new];
    for(unsigned col=0;col<r.columns;col++) [widths addObject:@(48)];
    for(MdvCell *cell in r.cells) {
        CGFloat measured=[cell.text size].width;
        widths[cell.column]=@(MAX(widths[cell.column].doubleValue,MIN(280,measured+24)));
    }
    CGFloat sum=0,minimum=0;
    for(NSNumber *width in widths) { sum+=width.doubleValue; minimum+=MIN(width.doubleValue,120); }
    NSTextTable *table=[NSTextTable new]; table.numberOfColumns=r.columns;
    table.layoutAlgorithm=NSTextTableFixedLayoutAlgorithm; table.collapsesBorders=YES; table.hidesEmptyCells=NO;
    [table setContentWidth:100 type:NSTextBlockPercentageValueType];
    [table setValue:minimum type:NSTextBlockAbsoluteValueType forDimension:NSTextBlockMinimumWidth];
    for(MdvCell *cell in r.cells) {
        NSTextTableBlock *block=[[NSTextTableBlock alloc] initWithTable:table startingRow:cell.row rowSpan:1 startingColumn:cell.column columnSpan:1];
        [block setContentWidth:widths[cell.column].doubleValue/sum*100 type:NSTextBlockPercentageValueType];
        [block setWidth:10 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockPadding];
        [block setWidth:0.5 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockBorder edge:NSMaxYEdge];
        [block setBorderColor:NSColor.separatorColor]; block.verticalAlignment=NSTextBlockTopAlignment;
        if(cell.header) block.backgroundColor=[NSColor.quaternaryLabelColor colorWithAlphaComponent:0.1];
        NSMutableParagraphStyle *paragraph=[NSMutableParagraphStyle new];
        paragraph.textBlocks=@[block]; paragraph.lineSpacing=4;
        paragraph.alignment=cell.alignment==2?NSTextAlignmentCenter:cell.alignment==3?NSTextAlignmentRight:NSTextAlignmentLeft;
        NSDictionary *base=@{NSFontAttributeName:[NSFont systemFontOfSize:r.size weight:cell.header?NSFontWeightSemibold:NSFontWeightRegular],NSForegroundColorAttributeName:NSColor.textColor,NSParagraphStyleAttributeName:paragraph};
        [cell.text appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:base]];
        [cell.text addAttribute:NSParagraphStyleAttributeName value:paragraph range:NSMakeRange(0,cell.text.length)];
        [r.output appendAttributedString:cell.text];
    }
    NSMutableParagraphStyle *space=[NSMutableParagraphStyle new]; space.paragraphSpacing=6;
    [r.output appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:6],NSParagraphStyleAttributeName:space}]];
    r.cell=nil; r.cells=nil;
}
static int nativeSink(const char *bytes, size_t length, const MdvStyle *style, void *context) {
    @autoreleasepool {
        NativeRender *r=(__bridge NativeRender *)context;
        if(style->event==MDV_TABLE_BEGIN) { r.cells=[NSMutableArray new]; r.columns=style->table_columns; return 0; }
        if(style->event==MDV_CELL_BEGIN) {
            MdvCell *cell=[MdvCell new]; cell.text=[NSMutableAttributedString new];
            cell.row=style->table_row; cell.column=style->table_column; cell.header=style->table_header; cell.alignment=style->table_alignment;
            [r.cells addObject:cell]; r.cell=cell; return 0;
        }
        if(style->event==MDV_CELL_END) { r.cell=nil; return 0; }
        if(style->event==MDV_TABLE_END) { finishTable(r); return 0; }
        if(r.cells && !r.cell) return 0; /* TSV separators are replaced by native cells. */
        NSString *text=[[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding]; if(!text) return -1;
        NSMutableDictionary *a=[attributes(r,style) mutableCopy];
        NSMutableAttributedString *output=r.cell?r.cell.text:r.output;
        if(style->link) {
            NSURL *url=resolveURL([NSString stringWithUTF8String:style->link],r.base);
            if(style->flags&MDV_IMAGE) {
                if(url.isFileURL) {
                    NSImage *image=[[NSImage alloc] initWithContentsOfURL:url];
                    if(image && image.size.width>0 && image.size.height>0) {
                        CGFloat ratio=MIN(1,MIN((r.cell?180:640)/image.size.width,480/image.size.height));
                        NSTextAttachment *attachment=[NSTextAttachment new]; attachment.image=image;
                        attachment.bounds=NSMakeRect(0,0,image.size.width*ratio,image.size.height*ratio);
                        [output appendAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]]; return 0;
                    }
                }
                text=[NSString stringWithFormat:@"[Image: %@]",text];
            }
            if(url) a[NSLinkAttributeName]=url;
        }
        [output appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:a]];
    } return 0;
}
NSAttributedString *mdv_render_data(NSData *data, NSURL *url, CGFloat size, NSError **error) {
    if(![[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]) { if(error) *error=[NSError errorWithDomain:@"MarkdownView" code:1 userInfo:@{NSLocalizedDescriptionKey:@"This file is not UTF-8 text."}]; return nil; }
    NativeRender *r=[NativeRender new]; r.output=[NSMutableAttributedString new]; r.cache=[NSMutableDictionary new]; r.base=url; r.size=size;
    const char *source=data.bytes; size_t length=data.length;
    if(length>=3 && !memcmp(source,"\xef\xbb\xbf",3)) { source+=3; length-=3; }
    if(mdv_render(source?source:"",length,nativeSink,(__bridge void *)r)) {
        if(error) *error=[NSError errorWithDomain:@"MarkdownView" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Could not render this document (invalid text or excessive nesting)."}]; return nil;
    }
    return r.output;
}

@interface MdvTextView : NSTextView
@property CGFloat minimumReadingWidth;
@end
@implementation MdvTextView
- (void)setFrameSize:(NSSize)size {
    NSScrollView *scroll=self.enclosingScrollView;
    if(scroll) {
        CGFloat available=scroll.contentSize.width;
        size.width=MAX(available,self.minimumReadingWidth+72);
        CGFloat column=MAX(760,self.minimumReadingWidth);
        self.textContainerInset=NSMakeSize(MAX(32,(size.width-column)/2),28);
    }
    [super setFrameSize:size];
}
@end
NSTextView *mdv_text_view(NSRect frame) {
    MdvTextView *view=[[MdvTextView alloc] initWithFrame:frame];
    view.editable=NO; view.selectable=YES; view.richText=YES;
    view.verticallyResizable=YES; view.horizontallyResizable=NO; view.autoresizingMask=NSViewWidthSizable;
    view.textContainerInset=NSMakeSize(32,28); view.textContainer.widthTracksTextView=YES;
    view.textContainer.containerSize=NSMakeSize(frame.size.width,CGFLOAT_MAX);
    return view;
}
void mdv_update_reading_layout(NSTextView *view) {
    __block CGFloat minimum=0;
    [view.textStorage enumerateAttribute:NSParagraphStyleAttributeName inRange:NSMakeRange(0,view.string.length) options:0 usingBlock:^(NSParagraphStyle *paragraph, NSRange range, BOOL *stop) {
        (void)range; (void)stop;
        for(NSTextBlock *block in paragraph.textBlocks) if([block isKindOfClass:NSTextTableBlock.class]) minimum=MAX(minimum,[((NSTextTableBlock *)block).table valueForDimension:NSTextBlockMinimumWidth]);
    }];
    ((MdvTextView *)view).minimumReadingWidth=minimum;
    [view setFrameSize:view.frame.size];
}
