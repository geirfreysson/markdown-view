#import "native.h"
#include "render.h"

typedef struct {
    __unsafe_unretained NSMutableAttributedString *output;
    __unsafe_unretained NSURL *base;
    __unsafe_unretained NSMutableDictionary *cache;
    CGFloat size;
} NativeRender;

static NSURL *resolveURL(NSString *target, NSURL *base) {
    if (!target.length) return nil;
    if ([target hasPrefix:@"www."]) target=[@"https://" stringByAppendingString:target];
    NSURL *url=[NSURL URLWithString:target relativeToURL:base];
    if(!url) url=[NSURL fileURLWithPath:target relativeToURL:[base URLByDeletingLastPathComponent]];
    return url.absoluteURL;
}
static int nativeSink(const char *bytes, size_t length, const MdvStyle *style, void *context) {
    @autoreleasepool {
        NativeRender *r=context;
        NSString *text=[[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding];
        if(!text) return -1;
        NSNumber *key=@((uint64_t)style->flags | ((uint64_t)style->heading<<16) | ((uint64_t)style->indent<<24));
        NSMutableDictionary *attributes=r->cache[key];
        if(!attributes) {
            CGFloat size=r->size;
            if(style->heading) { const double factors[]={1,2.0,1.6,1.3,1.15,1.05,1.0}; size*=factors[MIN(style->heading,6)]; }
            BOOL mono=style->flags&(MDV_CODE|MDV_TABLE);
            NSFont *font=mono?[NSFont monospacedSystemFontOfSize:size*0.9 weight:NSFontWeightRegular]:[NSFont systemFontOfSize:size];
            NSFontTraitMask traits=0;
            if(style->flags&MDV_BOLD || style->heading) traits|=NSBoldFontMask;
            if(style->flags&MDV_ITALIC) traits|=NSItalicFontMask;
            if(traits) {
                NSFontSymbolicTraits symbolic=0;
                if(traits&NSBoldFontMask) symbolic|=NSFontBoldTrait;
                if(traits&NSItalicFontMask) symbolic|=NSFontItalicTrait;
                font=[NSFont fontWithDescriptor:[font.fontDescriptor fontDescriptorWithSymbolicTraits:symbolic] size:size*(mono?0.9:1)]?:font;
            }
            NSMutableParagraphStyle *paragraph=[NSMutableParagraphStyle new];
            paragraph.lineSpacing=mono?2:4;
            paragraph.headIndent=style->indent*22; paragraph.firstLineHeadIndent=paragraph.headIndent;
            paragraph.defaultTabInterval=size*12;
            paragraph.tabStops=@[];
            if(style->flags&MDV_CODE_BLOCK) { paragraph.headIndent+=12; paragraph.firstLineHeadIndent+=12; }
            attributes=[@{NSFontAttributeName:font, NSForegroundColorAttributeName:NSColor.textColor, NSParagraphStyleAttributeName:paragraph} mutableCopy];
            if(style->flags&MDV_QUOTE) attributes[NSForegroundColorAttributeName]=NSColor.secondaryLabelColor;
            if(style->flags&MDV_CODE) attributes[NSBackgroundColorAttributeName]=NSColor.quaternaryLabelColor;
            if(style->flags&MDV_STRIKE) attributes[NSStrikethroughStyleAttributeName]=@(NSUnderlineStyleSingle);
            r->cache[key]=attributes;
        }
        if(style->link) {
            attributes=[attributes mutableCopy];
            NSString *target=[NSString stringWithUTF8String:style->link];
            NSURL *url=resolveURL(target,r->base);
            if(style->flags&MDV_IMAGE) {
                /* Local files only: no network requests or background fetches. */
                if(url.isFileURL) {
                    NSImage *image=[[NSImage alloc] initWithContentsOfURL:url];
                    if(image && image.size.width>0 && image.size.height>0) {
                        CGFloat ratio=MIN(1,MIN(640/image.size.width,480/image.size.height));
                        NSTextAttachment *attachment=[NSTextAttachment new];
                        attachment.image=image;
                        attachment.bounds=NSMakeRect(0,0,image.size.width*ratio,image.size.height*ratio);
                        [r->output appendAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
                        return 0;
                    }
                }
                text=[NSString stringWithFormat:@"[Image: %@]",text];
            }
            if(url) attributes[NSLinkAttributeName]=url;
        }
        [r->output appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:attributes]];
    } return 0;
}
NSAttributedString *mdv_render_data(NSData *data, NSURL *url, CGFloat size, NSError **error) {
    NSString *validated=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if(!validated) { if(error) *error=[NSError errorWithDomain:@"MarkdownView" code:1 userInfo:@{NSLocalizedDescriptionKey:@"This file is not UTF-8 text."}]; return nil; }
    NSMutableAttributedString *result=[NSMutableAttributedString new];
    NSMutableDictionary *cache=[NSMutableDictionary new];
    NativeRender renderer={result,url,cache,size};
    const char *source=data.bytes; size_t length=data.length;
    if(length>=3 && !memcmp(source,"\xef\xbb\xbf",3)) { source+=3; length-=3; }
    if(mdv_render(source?source:"",length,nativeSink,&renderer)) {
        if(error) *error=[NSError errorWithDomain:@"MarkdownView" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Could not render this document (invalid text or excessive nesting)."}];
        return nil;
    }
    return result;
}
