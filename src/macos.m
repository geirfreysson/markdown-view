#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <mach/mach.h>
#import "native.h"

static CFAbsoluteTime launchStart;
static BOOL profileLaunch;
static double physicalMemoryMiB(void) {
    task_vm_info_data_t info={0}; mach_msg_type_number_t count=TASK_VM_INFO_COUNT;
    if(task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&info,&count)!=KERN_SUCCESS) return 0;
    return info.phys_footprint/1048576.0;
}

@class AppDelegate;
@interface Viewer : NSWindowController <NSWindowDelegate,NSTextViewDelegate>
@property NSTextView *text;
@property NSSearchField *search;
@property NSURL *url;
@property CGFloat fontSize;
@property NSUInteger generation;
@property BOOL hasDocument;
@property BOOL showsSource;
@property NSButton *viewButton;
@property NSString *source;
@property NSAttributedString *rendered;
- (void)displayDocument;
- (void)toggleSource:(id)sender;
- (void)loadURL:(NSURL *)url;
- (void)open:(id)sender;
- (void)reload:(id)sender;
- (void)zoomIn:(id)sender;
- (void)zoomOut:(id)sender;
- (void)actualSize:(id)sender;
- (void)find:(id)sender;
- (void)findNext:(id)sender;
- (void)findPrevious:(id)sender;
@end
@interface AppDelegate : NSObject <NSApplicationDelegate>
@property NSMutableArray<Viewer *> *viewers;
- (void)open:(id)sender;
- (void)showURL:(NSURL *)url;
@end
@implementation Viewer
- (instancetype)init {
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,860,680) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    if((self=[super initWithWindow:window])) {
        _fontSize=15; window.title=@"Markdown View"; window.delegate=self;
        window.minSize=NSMakeSize(400,280); window.releasedWhenClosed=NO;
        NSView *root=window.contentView;
        NSStackView *bar=[NSStackView new]; bar.orientation=NSUserInterfaceLayoutOrientationHorizontal; bar.spacing=8;
        NSArray *labels=@[@"Open…",@"Reload",@"A−",@"A+"];
        NSArray *actions=@[NSStringFromSelector(@selector(open:)),NSStringFromSelector(@selector(reload:)),NSStringFromSelector(@selector(zoomOut:)),NSStringFromSelector(@selector(zoomIn:))];
        for(NSUInteger i=0;i<labels.count;i++) { NSButton *b=[NSButton buttonWithTitle:labels[i] target:self action:NSSelectorFromString(actions[i])]; [bar addArrangedSubview:b]; }
        _viewButton=[NSButton buttonWithTitle:@"Show Markdown" target:self action:@selector(toggleSource:)];
        _viewButton.enabled=NO; [bar addArrangedSubview:_viewButton];
        _search=[NSSearchField new]; _search.placeholderString=@"Find in document"; _search.target=self; _search.action=@selector(findNext:);
        _search.sendsWholeSearchString=YES; _search.sendsSearchStringImmediately=NO; [bar addArrangedSubview:_search];
        [_search.widthAnchor constraintGreaterThanOrEqualToConstant:160].active=YES;
        NSScrollView *scroll=[NSScrollView new]; scroll.hasVerticalScroller=YES; scroll.hasHorizontalScroller=YES; scroll.autohidesScrollers=YES;
        _text=mdv_text_view(NSMakeRect(0,0,800,600));
        _text.editable=NO; _text.selectable=YES; _text.richText=YES; _text.importsGraphics=NO; _text.usesFindBar=NO; _text.delegate=self;
        _text.verticallyResizable=YES; _text.horizontallyResizable=NO; _text.autoresizingMask=NSViewWidthSizable;
        _text.textContainerInset=NSMakeSize(36,28);
        _text.textContainer.widthTracksTextView=YES;
        _text.textContainer.containerSize=NSMakeSize(800,CGFLOAT_MAX);
        scroll.documentView=_text;
        bar.translatesAutoresizingMaskIntoConstraints=NO; scroll.translatesAutoresizingMaskIntoConstraints=NO;
        [root addSubview:bar]; [root addSubview:scroll];
        [NSLayoutConstraint activateConstraints:@[
            [bar.topAnchor constraintEqualToAnchor:root.topAnchor constant:12], [bar.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:16], [bar.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-16],
            [scroll.topAnchor constraintEqualToAnchor:bar.bottomAnchor constant:12], [scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor], [scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor], [scroll.bottomAnchor constraintEqualToAnchor:root.bottomAnchor]]];
        _text.string=@"Markdown View\n\nOpen a Markdown file to start reading.\n\n⌘O  Open     ⌘F  Find     ⌘+ / ⌘−  Zoom     ⌘R  Reload";
        _text.font=[NSFont systemFontOfSize:16]; _text.textColor=NSColor.secondaryLabelColor;
        [window center]; [window setFrameAutosaveName:@"ViewerWindow"];
    } return self;
}
- (void)loadURL:(NSURL *)url {
    NSUInteger generation=++self.generation;
    CGFloat size=self.fontSize;
    NSURL *previousURL=self.url; NSString *previousTitle=self.window.title;
    self.window.title=[url.lastPathComponent stringByAppendingString:@" — Markdown View"];
    self.window.representedURL=url;
    self.url=url;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        @autoreleasepool {
            NSError *error=nil;
            NSNumber *fileSize=nil; [url getResourceValue:&fileSize forKey:NSURLFileSizeKey error:&error];
            NSData *data=nil;
            if(fileSize.unsignedLongLongValue>128ULL*1024*1024) error=[NSError errorWithDomain:@"MarkdownView" code:3 userInfo:@{NSLocalizedDescriptionKey:@"This file exceeds the 128 MB document limit."}];
            else data=[NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&error];
            NSAttributedString *rendered=data?mdv_render_data(data,url,size,&error):nil;
            NSString *source=rendered?[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]:nil;
            if([source hasPrefix:@"\uFEFF"]) source=[source substringFromIndex:1];
            dispatch_async(dispatch_get_main_queue(),^{
                if(generation!=self.generation) return;
                if(!rendered) {
                    self.url=previousURL; self.window.representedURL=previousURL; self.window.title=previousTitle;
                    NSAlert *alert=[NSAlert new]; alert.messageText=@"Unable to open Markdown file"; alert.informativeText=error.localizedDescription?:@"The file could not be read.";
                    [alert beginSheetModalForWindow:self.window completionHandler:nil]; return;
                }
                self.source=source; self.rendered=rendered;
                self.hasDocument=YES; self.viewButton.enabled=YES;
                [self displayDocument];
                if(profileLaunch) {
                    [self.text.layoutManager ensureLayoutForTextContainer:self.text.textContainer];
                    [self.window displayIfNeeded];
                    fprintf(stderr,"First document displayed: %.2f ms since main(); physical footprint: %.2f MiB\n",(CFAbsoluteTimeGetCurrent()-launchStart)*1000,physicalMemoryMiB());
                    profileLaunch=NO;
                }
            });
        }
    });
}
- (void)displayDocument {
    NSRange selection=self.text.selectedRange;
    NSAttributedString *content=self.rendered;
    if(self.showsSource) content=[[NSAttributedString alloc] initWithString:self.source attributes:@{
        NSFontAttributeName:[NSFont monospacedSystemFontOfSize:self.fontSize weight:NSFontWeightRegular],
        NSForegroundColorAttributeName:NSColor.labelColor}];
    [self.text.textStorage setAttributedString:content];
    mdv_update_reading_layout(self.text);
    if(NSMaxRange(selection)<=self.text.string.length) self.text.selectedRange=selection;
    self.viewButton.title=self.showsSource?@"Show Rendered":@"Show Markdown";
}
- (void)toggleSource:(id)sender {
    (void)sender; if(!self.hasDocument) return;
    self.showsSource=!self.showsSource; [self displayDocument];
    self.text.selectedRange=NSMakeRange(0,0); [self.text scrollRangeToVisible:NSMakeRange(0,0)];
}
- (void)open:(id)sender { [(AppDelegate *)NSApp.delegate open:sender]; }
- (void)reload:(id)sender { if(self.url) [self loadURL:self.url]; }
- (void)zoomIn:(id)sender { self.fontSize=MIN(32,self.fontSize+2); [self reload:sender]; }
- (void)zoomOut:(id)sender { self.fontSize=MAX(10,self.fontSize-2); [self reload:sender]; }
- (void)actualSize:(id)sender { self.fontSize=15; [self reload:sender]; }
- (void)find:(id)sender { [self.window makeFirstResponder:self.search]; [self.search selectText:sender]; }
- (void)findDirection:(BOOL)backward {
    NSString *query=self.search.stringValue; if(!query.length) return;
    NSString *text=self.text.string; NSRange selected=self.text.selectedRange;
    NSUInteger start=MIN(NSMaxRange(selected),text.length);
    NSRange range=backward?NSMakeRange(0,MIN(selected.location,text.length)):NSMakeRange(start,text.length-start);
    NSStringCompareOptions options=NSCaseInsensitiveSearch|(backward?NSBackwardsSearch:0);
    NSRange match=[text rangeOfString:query options:options range:range];
    if(match.location==NSNotFound) match=[text rangeOfString:query options:options];
    if(match.location!=NSNotFound) { self.text.selectedRange=match; [self.text scrollRangeToVisible:match]; } else NSBeep();
}
- (void)findNext:(id)sender { [self findDirection:NO]; }
- (void)findPrevious:(id)sender { [self findDirection:YES]; }
- (BOOL)textView:(NSTextView *)view clickedOnLink:(id)link atIndex:(NSUInteger)index {
    (void)view; (void)index;
    NSURL *url=[link isKindOfClass:NSURL.class]?link:[NSURL URLWithString:link];
    if(url.isFileURL && [@[@"md",@"markdown",@"mdown",@"mkd"] containsObject:url.pathExtension.lowercaseString]) [(AppDelegate *)NSApp.delegate showURL:url];
    else if([@[@"https",@"http",@"mailto",@"file"] containsObject:url.scheme.lowercaseString]) [[NSWorkspace sharedWorkspace] openURL:url];
    return YES;
}
- (void)windowWillClose:(NSNotification *)notification { (void)notification; ++self.generation; [((AppDelegate *)NSApp.delegate).viewers removeObject:self]; }
@end

static void menuItem(NSMenu *menu, NSString *title, SEL action, NSString *key, NSEventModifierFlags modifiers) {
    NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key]; item.keyEquivalentModifierMask=modifiers; [menu addItem:item];
}
@implementation AppDelegate
- (instancetype)init { if((self=[super init])) _viewers=[NSMutableArray new]; return self; }
- (void)applicationWillFinishLaunching:(NSNotification *)note {
    (void)note; NSMenu *main=[NSMenu new]; NSApp.mainMenu=main;
    NSMenu *app=[NSMenu new], *file=[NSMenu new], *edit=[NSMenu new], *view=[NSMenu new], *window=[NSMenu new];
    NSArray *titles=@[@"Markdown View",@"File",@"Edit",@"View",@"Window"]; NSArray *menus=@[app,file,edit,view,window];
    for(NSUInteger i=0;i<titles.count;i++) { NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:titles[i] action:nil keyEquivalent:@""]; item.submenu=menus[i]; [main addItem:item]; }
    NSEventModifierFlags cmd=NSEventModifierFlagCommand;
    menuItem(app,@"About Markdown View",@selector(orderFrontStandardAboutPanel:),@"",cmd);
    [app addItem:NSMenuItem.separatorItem]; menuItem(app,@"Hide Markdown View",@selector(hide:),@"h",cmd); menuItem(app,@"Quit Markdown View",@selector(terminate:),@"q",cmd);
    menuItem(file,@"Open…",@selector(open:),@"o",cmd); menuItem(file,@"Reload",@selector(reload:),@"r",cmd); menuItem(file,@"Close",@selector(performClose:),@"w",cmd);
    menuItem(edit,@"Copy",@selector(copy:),@"c",cmd); menuItem(edit,@"Select All",@selector(selectAll:),@"a",cmd);
    menuItem(edit,@"Find…",@selector(find:),@"f",cmd); menuItem(edit,@"Find Next",@selector(findNext:),@"g",cmd); menuItem(edit,@"Find Previous",@selector(findPrevious:),@"g",cmd|NSEventModifierFlagShift);
    menuItem(view,@"Zoom In",@selector(zoomIn:),@"=",cmd); menuItem(view,@"Zoom Out",@selector(zoomOut:),@"-",cmd); menuItem(view,@"Actual Size",@selector(actualSize:),@"0",cmd);
    menuItem(window,@"Minimize",@selector(performMiniaturize:),@"m",cmd); menuItem(window,@"Zoom",@selector(performZoom:),@"",cmd); NSApp.windowsMenu=window;
}
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    (void)note;
    for(NSString *arg in NSProcessInfo.processInfo.arguments) {
        if([arg isEqual:NSProcessInfo.processInfo.arguments.firstObject] || [arg hasPrefix:@"-"]) continue;
        NSURL *url=[NSURL fileURLWithPath:arg]; if([[NSFileManager defaultManager] fileExistsAtPath:url.path]) [self showURL:url];
    }
    if(!self.viewers.count) { Viewer *viewer=[Viewer new]; [self.viewers addObject:viewer]; [viewer showWindow:nil]; }
    [NSApp activateIgnoringOtherApps:YES];
}
- (void)showURL:(NSURL *)url {
    for(Viewer *v in self.viewers) if([v.url isEqual:url]) { [v showWindow:nil]; return; }
    Viewer *viewer=nil;
    for(Viewer *v in self.viewers) if(!v.url) { viewer=v; break; }
    if(!viewer) { viewer=[Viewer new]; [self.viewers addObject:viewer]; }
    [viewer loadURL:url]; [viewer showWindow:nil];
}
- (void)open:(id)sender {
    (void)sender; NSOpenPanel *panel=[NSOpenPanel openPanel]; panel.allowsMultipleSelection=YES;
    panel.allowedContentTypes=@[[UTType typeWithFilenameExtension:@"md"], [UTType typeWithFilenameExtension:@"markdown"],UTTypePlainText]; panel.allowsOtherFileTypes=YES;
    if([panel runModal]==NSModalResponseOK) for(NSURL *url in panel.URLs) [self showURL:url];
}
- (BOOL)application:(NSApplication *)app openFile:(NSString *)filename { (void)app; [self showURL:[NSURL fileURLWithPath:filename]]; return YES; }
- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)visible { (void)app; if(!visible) { Viewer *v=[Viewer new]; [self.viewers addObject:v]; [v showWindow:nil]; } return YES; }
@end
int main(int argc, const char **argv) {
    @autoreleasepool {
        launchStart=CFAbsoluteTimeGetCurrent();
        for(int i=1;i<argc;i++) if(!strcmp(argv[i],"--profile")) profileLaunch=YES;
        [NSApplication sharedApplication];
        if(argc==3 && (!strcmp(argv[1],"--smoke-test") || !strcmp(argv[1],"--benchmark") || !strcmp(argv[1],"--screenshot"))) {
            CFAbsoluteTime start=CFAbsoluteTimeGetCurrent();
            NSURL *url=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]]; NSError *error=nil;
            NSData *data=[NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&error];
            NSAttributedString *result=data?mdv_render_data(data,url,15,&error):nil;
            if(!result) { fprintf(stderr,"%s\n",error.localizedDescription.UTF8String); return 1; }
            struct mach_task_basic_info info; mach_msg_type_number_t count=MACH_TASK_BASIC_INFO_COUNT;
            task_info(mach_task_self(),MACH_TASK_BASIC_INFO,(task_info_t)&info,&count);
            printf("Rendered %lu bytes → %lu characters in %.2f ms; RSS %.2f MiB; physical footprint %.2f MiB\n",(unsigned long)data.length,(unsigned long)result.length,(CFAbsoluteTimeGetCurrent()-start)*1000,info.resident_size/1048576.0,physicalMemoryMiB());
            if(!strcmp(argv[1],"--smoke-test") || !strcmp(argv[1],"--screenshot")) {
                Viewer *v=[Viewer new]; v.source=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if([v.source hasPrefix:@"\uFEFF"]) v.source=[v.source substringFromIndex:1];
                v.rendered=result; v.hasDocument=YES; v.viewButton.enabled=YES;
                [v displayDocument]; [v.window.contentView layoutSubtreeIfNeeded];
                if(!strcmp(argv[1],"--smoke-test")) {
                    NSAttributedString *before=[v.text.textStorage copy];
                    [v.viewButton performClick:nil];
                    if(!v.showsSource || ![v.text.string isEqualToString:v.source] || v.text.editable) return 3;
                    if(![[v.text.textStorage attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] isEqual:[NSFont monospacedSystemFontOfSize:15 weight:NSFontWeightRegular]]) return 4;
                    v.search.stringValue=@"Markdown"; [v findNext:nil];
                    if(!v.text.selectedRange.length) return 5;
                    [v.viewButton performClick:nil];
                    if(v.showsSource || ![v.text.textStorage isEqualToAttributedString:before]) return 6;
                    [v.viewButton performClick:nil];
                    v.url=url;
                    [v zoomIn:nil];
                    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
                    while(v.rendered==result && deadline.timeIntervalSinceNow>0)
                        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
                    if(v.rendered==result || !v.showsSource || ![v.text.string isEqualToString:v.source]) return 7;
                    if(![[v.text.textStorage attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] isEqual:[NSFont monospacedSystemFontOfSize:17 weight:NSFontWeightRegular]]) return 8;
                    [v.viewButton performClick:nil];
                    if(![v.text.string isEqualToString:result.string]) return 9;
                    [v findNext:nil];
                }
                if(!strcmp(argv[1],"--screenshot")) {
                    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
                    v.window.title=@"Markdown View";
                    [v.window makeKeyAndOrderFront:nil];
                    [NSApp activateIgnoringOtherApps:YES];
                    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
                    [v.window displayIfNeeded];
                }
                NSView *snapshotView=!strcmp(argv[1],"--screenshot")?v.text.enclosingScrollView:v.window.contentView;
                NSBitmapImageRep *bitmap=[snapshotView bitmapImageRepForCachingDisplayInRect:snapshotView.bounds];
                [snapshotView cacheDisplayInRect:snapshotView.bounds toBitmapImageRep:bitmap];
                [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"build/preview.png" atomically:YES];
                if(v.text.editable || !v.text.selectable || !v.text.string.length || (!strcmp(argv[1],"--smoke-test") && !v.text.selectedRange.length)) return 2;
                printf("Native window, source toggle, zoom/reload, read-only text storage, layout, and search smoke test passed.\n");
            }
            return 0;
        }
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        AppDelegate *delegate=[AppDelegate new]; NSApp.delegate=delegate; [NSApp run];
    } return 0;
}
