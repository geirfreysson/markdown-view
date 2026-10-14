#import "native.h"
#include <assert.h>
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication]; NSError *error=nil;
        NSURL *url=[NSURL fileURLWithPath:@"tests/tables.md"];
        NSAttributedString *document=mdv_render_data([NSData dataWithContentsOfURL:url],url,15,&error);
        assert(document && !error);
        NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,860,680)];
        NSTextView *view=mdv_text_view(scroll.bounds); scroll.documentView=view;
        [view.textStorage setAttributedString:document]; mdv_update_reading_layout(view);
        [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
        __block NSUInteger count=0, tables=0; __block NSTextTable *previous=nil;
        __block CGFloat previousX=-1, wrappedHeight=0, nextRowY=0, rowBottom=0;
        [document enumerateAttribute:NSParagraphStyleAttributeName inRange:NSMakeRange(0,document.length) options:0 usingBlock:^(NSParagraphStyle *p, NSRange range, BOOL *stop) {
            (void)stop;
            for(NSTextBlock *block in p.textBlocks) {
                if(![block isKindOfClass:NSTextTableBlock.class]) continue;
                NSTextTableBlock *cell=(NSTextTableBlock *)block; count++;
                if(cell.table!=previous) { previous=cell.table; tables++; }
                assert(cell.table.numberOfColumns==6 || cell.table.numberOfColumns==2);
                assert(cell.columnSpan==1 && cell.rowSpan==1);
                assert([cell widthForLayer:NSTextBlockPadding edge:NSMinXEdge]>=8);
                NSRange glyphs=[view.layoutManager glyphRangeForCharacterRange:range actualCharacterRange:NULL];
                NSRect rect=[view.layoutManager boundingRectForGlyphRange:glyphs inTextContainer:view.textContainer];
                if(cell.table.numberOfColumns==6 && cell.startingRow==0) {
                    assert(rect.origin.x>previousX); previousX=rect.origin.x;
                }
                if(cell.table.numberOfColumns==6 && cell.startingRow==1) rowBottom=MAX(rowBottom,NSMaxY(rect));
                if(cell.table.numberOfColumns==6 && cell.startingRow==1 && cell.startingColumn==5) wrappedHeight=rect.size.height;
                if(cell.table.numberOfColumns==6 && cell.startingRow==2 && cell.startingColumn==0) nextRowY=rect.origin.y;
            }
        }];
        assert(count==30 && tables==2); assert(wrappedHeight>35 && nextRowY>=rowBottom);
        assert([document.string containsString:@"rotation schedule"]);
        __block BOOL link=NO, code=NO;
        [document enumerateAttributesInRange:NSMakeRange(0,document.length) options:0 usingBlock:^(NSDictionary *a,NSRange range,BOOL *stop) {
            (void)range; (void)stop;
            if(a[NSLinkAttributeName]) link=YES;
            if([a[NSFontAttributeName] isKindOfClass:NSFont.class] && [(NSFont *)a[NSFontAttributeName] isFixedPitch]) code=YES;
        }];
        assert(link && code);
        [scroll setFrameSize:NSMakeSize(480,680)]; mdv_update_reading_layout(view);
        [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
        assert(view.frame.size.width>=scroll.contentSize.width);
        puts("Native table tests passed: cells, multiple tables, column positions, wrapping, row heights, inline styles, links, and narrow layout.");
    } return 0;
}
