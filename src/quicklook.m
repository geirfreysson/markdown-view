#import <Cocoa/Cocoa.h>
#import <QuickLookUI/QuickLookUI.h>
#import "native.h"
#import <os/log.h>

@interface MarkdownPreviewController : NSViewController <QLPreviewingController>
@property NSTextView *text;
@end
@implementation MarkdownPreviewController
- (void)loadView {
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,820,640)];
    scroll.hasVerticalScroller=YES; scroll.autohidesScrollers=YES;
    self.text=[[NSTextView alloc] initWithFrame:scroll.bounds];
    self.text.editable=NO; self.text.selectable=YES; self.text.richText=YES;
    self.text.verticallyResizable=YES; self.text.horizontallyResizable=NO;
    self.text.autoresizingMask=NSViewWidthSizable;
    self.text.textContainerInset=NSMakeSize(32,24);
    self.text.textContainer.widthTracksTextView=YES;
    self.text.textContainer.containerSize=NSMakeSize(820,CGFLOAT_MAX);
    scroll.documentView=self.text; self.view=scroll;
    self.preferredContentSize=NSMakeSize(820,640);
}
- (void)preparePreviewOfFileAtURL:(NSURL *)url completionHandler:(void (^)(NSError *))handler {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        @autoreleasepool {
            NSError *error=nil; NSNumber *size=nil;
            [url getResourceValue:&size forKey:NSURLFileSizeKey error:&error];
            NSData *data=nil;
            if(size.unsignedLongLongValue>128ULL*1024*1024) error=[NSError errorWithDomain:@"MarkdownView" code:3 userInfo:@{NSLocalizedDescriptionKey:@"This file exceeds the 128 MB document limit."}];
            else data=[NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&error];
            NSAttributedString *rendered=data?mdv_render_data(data,url,16,&error):nil;
            dispatch_async(dispatch_get_main_queue(),^{
                if(rendered) { (void)self.view; [self.text.textStorage setAttributedString:rendered]; os_log(OS_LOG_DEFAULT,"Markdown preview ready (%lu characters)",(unsigned long)rendered.length); }
                else os_log_error(OS_LOG_DEFAULT,"Markdown preview failed: %{public}@",error.localizedDescription);
                handler(error);
            });
        }
    });
}
@end
#ifndef MDV_QUICKLOOK_TEST
extern int NSExtensionMain(int argc, const char **argv);
int main(int argc, const char **argv) { return NSExtensionMain(argc,argv); }
#else
int main(int argc, const char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        if(argc!=2) return 1;
        MarkdownPreviewController *controller=[MarkdownPreviewController new];
        __block BOOL completed=NO, passed=NO;
        NSURL *url=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        [controller preparePreviewOfFileAtURL:url completionHandler:^(NSError *error) {
            passed=!error && controller.text.string.length>0 && !controller.text.editable && controller.text.selectable;
            completed=YES;
        }];
        NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:10];
        while(!completed && deadline.timeIntervalSinceNow>0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        if(!passed) return 2;
        puts("Quick Look controller smoke test passed."); return 0;
    }
}
#endif
