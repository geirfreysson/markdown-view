/* Include the small app controller so this tests the actual Edit/split/refresh flow. */
#define main mdv_app_main
#import "../src/macos.m"
#undef main
#import <assert.h>
#import <unistd.h>
#import <sys/resource.h>

@interface MdvTerminalController (Testing)
- (void)watchDocument;
@end
static void pump(double seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}
static BOOL await(BOOL (^condition)(void)) {
    NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:10];
    while(!condition() && limit.timeIntervalSinceNow>0) pump(0.02);
    return condition();
}
static void verifyReaderLayout(Viewer *viewer) {
    [viewer.window.contentView layoutSubtreeIfNeeded]; [viewer.split adjustSubviews];
    NSView *bar=viewer.search.superview;
    assert(fabs(bar.frame.size.height-32)<1);
    assert(fabs(NSMaxY(bar.frame)-(viewer.window.contentView.bounds.size.height-12))<1);
    NSScrollView *scroll=viewer.text.enclosingScrollView;
    assert(viewer.split.subviews.count==1);
    assert(NSEqualRects(scroll.frame,viewer.split.bounds));
    assert(viewer.split.bounds.size.height>viewer.window.contentView.bounds.size.height-60);
}
static void type(MdvTerminalController *terminal, NSString *text) {
    [(id<NSTextInputClient>)terminal.view insertText:text replacementRange:NSMakeRange(NSNotFound,0)];
}
static NSArray<NSString *> *prepare(NSString *agent, NSString *path, NSURL *document, BOOL enabled, NSString **failure) {
    __block BOOL done=NO; __block NSArray *arguments=nil; __block NSString *error=nil;
    mdv_prepare_agent(agent,path,document,NSProcessInfo.processInfo.environment,enabled,^(NSArray *args,NSString *message) {
        arguments=args; error=message; done=YES;
    });
    assert(await(^BOOL { return done; }));
    if(failure) *failure=error; else assert(!error);
    return arguments;
}
static void verifyDocumentContext(NSURL *document) {
    assert(mdv_document_context_enabled());
    NSString *context=mdv_document_instructions(document);
    assert([context containsString:@"already established conversation target take precedence"]);
    assert([context containsString:@"Wait for the user's request"]);
    NSString *fixture=[[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:@"tests/fake_agent.sh"];
    for(NSString *agent in @[@"claude",@"codex"]) {
        NSArray *arguments=prepare(agent,fixture,document,YES,NULL);
        assert(arguments.count==2);
        if([agent isEqualToString:@"claude"]) {
            assert([arguments[0] isEqualToString:@"--append-system-prompt"]);
            assert([arguments[1] isEqualToString:context]);
        } else {
            assert([arguments[0] isEqualToString:@"-c"]);
            NSString *json=[arguments[1] substringFromIndex:[@"developer_instructions=" length]];
            NSString *merged=[NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingFragmentsAllowed error:nil];
            assert([merged hasPrefix:@"Existing instructions: keep quotes \"and\" Unicode ü.\nSecond line.\n\n"]);
            assert([merged hasSuffix:context]);
        }
        assert(prepare(agent,@"/does/not/exist",document,NO,NULL).count==0);
        // Verify the full command reaches the executable as separate argv values,
        // including shell-sensitive characters in filenames and instructions.
        NSString *capture=[document.path stringByAppendingString:[@".args-" stringByAppendingString:agent]];
        NSMutableDictionary *env=[NSProcessInfo.processInfo.environment mutableCopy]; env[@"MDV_TEST_ARGUMENTS"]=capture;
        NSMutableString *command=[NSMutableString stringWithFormat:@"exec %@",mdv_shell_quote(fixture)];
        for(NSString *argument in arguments) [command appendFormat:@" %@",mdv_shell_quote(argument)];
        MdvTerminalController *terminal=[MdvTerminalController new];
        assert([terminal startCommand:command directory:document.URLByDeletingLastPathComponent environment:env]);
        assert(await(^BOOL { return [NSData dataWithContentsOfFile:capture].length>0; }));
        NSData *raw=[NSData dataWithContentsOfFile:capture];
        NSString *captured=[[NSString alloc] initWithData:raw encoding:NSUTF8StringEncoding];
        NSMutableArray *received=[[captured componentsSeparatedByString:@"\0"] mutableCopy];
        [received removeLastObject]; assert([received isEqual:arguments]);
        [terminal stop];
    }
    NSString *error=nil;
    assert(!prepare(@"codex",@"/bin/false",document,YES,&error)); assert(error.length);
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"mdv terminal ' ü " stringByAppendingString:NSUUID.UUID.UUIDString]];
        assert([[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil]);
        NSURL *url=[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"test ' ü.md"]];
        assert([@"# Before\n\nMarkdown test\n" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil]);
        // Override preferences in memory: do not change the user's agent settings.
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{@"TerminalAgent":@"codex",@"TerminalExecutable.codex":@"/bin/sh",@"TerminalDocumentContext":@NO} forName:NSArgumentDomain];
        Viewer *viewer=[Viewer new]; [viewer.window setFrameAutosaveName:@""];
        [viewer.window setContentSize:NSMakeSize(900,1000)];
        [viewer showWindow:nil]; [viewer loadURL:url];
        assert(await(^BOOL { return viewer.hasDocument; }));
        verifyReaderLayout(viewer);
        double readerMemory=physicalMemoryMiB();
        [viewer edit:nil];
        assert(await(^BOOL { return viewer.terminal.running; }));
        assert(!viewer.terminal.usesDocumentContext);
        assert([viewer.terminalDocument.stringValue containsString:url.lastPathComponent]);
        assert([viewer.terminalDocument.stringValue containsString:@"context off"]);
        assert(viewer.terminalVisible && viewer.split.subviews.count==2);
        assert(fabs(viewer.terminalPanel.frame.size.height/viewer.split.bounds.size.height-0.4)<0.03);
        type(viewer.terminal,@"printf '\\033[32mMDV_READY\\033[0m\\n'; pwd > mdv-cwd; stty size > mdv-size-before\n");
        assert(await(^BOOL { return [[viewer.terminal screenText] containsString:@"MDV_READY"]; }));
        NSString *cwdPath=[directory stringByAppendingPathComponent:@"mdv-cwd"];
        BOOL wroteCWD=await(^BOOL { return [NSString stringWithContentsOfFile:cwdPath encoding:NSUTF8StringEncoding error:nil].length>0; });
        if(!wroteCWD) fprintf(stderr,"Terminal screen: %s\nStatus: %s\n",viewer.terminal.screenText.UTF8String,viewer.terminal.status.UTF8String);
        assert(wroteCWD);
        NSString *cwd=[[NSString stringWithContentsOfFile:cwdPath encoding:NSUTF8StringEncoding error:nil] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        assert([cwd.stringByResolvingSymlinksInPath isEqualToString:directory.stringByResolvingSymlinksInPath]);
        pump(0.3);
        [viewer.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES]; pump(0.2); [viewer.window displayIfNeeded];
        NSView *snapshot=viewer.window.contentView;
        NSBitmapImageRep *bitmap=[snapshot bitmapImageRepForCachingDisplayInRect:snapshot.bounds];
        [snapshot cacheDisplayInRect:snapshot.bounds toBitmapImageRep:bitmap];
        [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"build/terminal-preview.png" atomically:YES];
        printf("Footprint: reader %.2f MiB; terminal + shell %.2f MiB (app physical footprint only).\n",readerMemory,physicalMemoryMiB());
        struct rusage cpuBefore,cpuAfter; getrusage(RUSAGE_SELF,&cpuBefore); pump(2); getrusage(RUSAGE_SELF,&cpuAfter);
        double idleCPU=(cpuAfter.ru_utime.tv_sec-cpuBefore.ru_utime.tv_sec)+(cpuAfter.ru_utime.tv_usec-cpuBefore.ru_utime.tv_usec)/1e6+
            (cpuAfter.ru_stime.tv_sec-cpuBefore.ru_stime.tv_sec)+(cpuAfter.ru_stime.tv_usec-cpuBefore.ru_stime.tv_usec)/1e6;
        printf("Terminal idle CPU over two seconds: %.2f%% of one core.\n",idleCPU/2*100);
        NSPasteboard *clipboard=NSPasteboard.generalPasteboard;
        NSMutableArray *savedClipboard=[NSMutableArray new];
        for(NSPasteboardItem *original in clipboard.pasteboardItems) {
            NSPasteboardItem *saved=[NSPasteboardItem new];
            for(NSPasteboardType format in original.types) {
                NSData *data=[original dataForType:format]; if(data) [saved setData:data forType:format];
            }
            [savedClipboard addObject:saved];
        }
        [clipboard clearContents]; [clipboard setString:@"printf MDV_PASTED > mdv-paste" forType:NSPasteboardTypeString];
        assert([viewer.terminal.view tryToPerform:@selector(paste:) with:nil]);
        NSEvent *enter=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:viewer.window.windowNumber context:nil characters:@"\r" charactersIgnoringModifiers:@"\r" isARepeat:NO keyCode:36];
        [viewer.terminal.view keyDown:enter];
        NSString *pastePath=[directory stringByAppendingPathComponent:@"mdv-paste"];
        BOOL pasted=await(^BOOL { return [[NSString stringWithContentsOfFile:pastePath encoding:NSUTF8StringEncoding error:nil] isEqualToString:@"MDV_PASTED"]; });
        [viewer.terminal.view tryToPerform:@selector(selectAll:) with:nil];
        [viewer.terminal.view tryToPerform:@selector(copy:) with:nil];
        BOOL copied=[[clipboard stringForType:NSPasteboardTypeString] containsString:@"MDV_READY"];
        [clipboard clearContents]; if(savedClipboard.count) [clipboard writeObjects:savedClipboard];
        assert(pasted && copied);
        // Resizing must update the PTY, and hiding must preserve the same process.
        [viewer.split setPosition:viewer.split.bounds.size.height*0.5 ofDividerAtIndex:0];
        [viewer.window.contentView layoutSubtreeIfNeeded]; pump(0.3);
        type(viewer.terminal,@"stty size > mdv-size-after\n");
        NSString *sizeAfter=[directory stringByAppendingPathComponent:@"mdv-size-after"];
        assert(await(^BOOL { return [NSString stringWithContentsOfFile:sizeAfter encoding:NSUTF8StringEncoding error:nil].length>0; }));
        NSString *beforeSize=[NSString stringWithContentsOfFile:[directory stringByAppendingPathComponent:@"mdv-size-before"] encoding:NSUTF8StringEncoding error:nil];
        NSString *afterSize=[NSString stringWithContentsOfFile:sizeAfter encoding:NSUTF8StringEncoding error:nil];
        if([beforeSize isEqualToString:afterSize]) fprintf(stderr,"Resize dimensions unchanged: %s; frame %s\n",beforeSize.UTF8String,NSStringFromRect(viewer.terminal.view.frame).UTF8String);
        assert(beforeSize.length && afterSize.length && ![beforeSize isEqualToString:afterSize]);
        type(viewer.terminal,@"echo $$ > mdv-test.pid\n");
        NSString *pidPath=[directory stringByAppendingPathComponent:@"mdv-test.pid"];
        BOOL wrotePID=await(^BOOL { return [NSString stringWithContentsOfFile:pidPath encoding:NSUTF8StringEncoding error:nil].intValue>0; });
        if(!wrotePID) fprintf(stderr,"Terminal screen: %s\nStatus: %s\n",viewer.terminal.screenText.UTF8String,viewer.terminal.status.UTF8String);
        assert(wrotePID);
        pid_t pid=[[NSString stringWithContentsOfFile:pidPath encoding:NSUTF8StringEncoding error:nil] intValue];
        assert(pid>0 && kill(pid,0)==0);
        for(int i=0;i<3;i++) {
            [viewer hideTerminal:nil]; assert(viewer.terminal.running && viewer.split.subviews.count==1);
            verifyReaderLayout(viewer);
            [viewer.window setContentSize:NSMakeSize(900,i%2?700:1000)];
            verifyReaderLayout(viewer);
            [viewer edit:nil]; assert(viewer.terminal.running && kill(pid,0)==0);
        }
        type(viewer.terminal,@"sleep 60 & echo $! > mdv-child.pid\n");
        NSString *childPath=[directory stringByAppendingPathComponent:@"mdv-child.pid"];
        assert(await(^BOOL { return [NSString stringWithContentsOfFile:childPath encoding:NSUTF8StringEncoding error:nil].intValue>0; }));
        pid_t child=[[NSString stringWithContentsOfFile:childPath encoding:NSUTF8StringEncoding error:nil] intValue];
        assert(child>0 && kill(child,0)==0);
        NSURL *secondURL=[url.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"second.md"];
        assert([@"# Second document\n" writeToURL:secondURL atomically:YES encoding:NSUTF8StringEncoding error:nil]);
        Viewer *second=[Viewer new]; [second showWindow:nil]; [second loadURL:secondURL];
        assert(await(^BOOL { return second.hasDocument; })); [second edit:nil];
        assert(await(^BOOL { return second.terminal.running; }));
        assert(second.terminal!=viewer.terminal);
        type(second.terminal,@"echo $$ > mdv-second.pid\n");
        NSString *secondPath=[directory stringByAppendingPathComponent:@"mdv-second.pid"];
        assert(await(^BOOL { return [NSString stringWithContentsOfFile:secondPath encoding:NSUTF8StringEncoding error:nil].intValue>0; }));
        pid_t secondPID=[[NSString stringWithContentsOfFile:secondPath encoding:NSUTF8StringEncoding error:nil] intValue];
        assert(secondPID!=pid); [second stopTerminal:nil]; [second.window close];
        assert(await(^BOOL { return kill(secondPID,0)!=0; })); assert(kill(pid,0)==0);
        [viewer toggleSource:nil];
        NSUInteger refreshes=viewer.liveRefresh;
        assert([@"# After\n\nAtomic replacement\n" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil]);
        assert(await(^BOOL { return viewer.liveRefresh>refreshes && [viewer.text.string containsString:@"# After"]; }));
        assert(viewer.showsSource && kill(pid,0)==0);
        // A temporary unreadable save must preserve the current preview.
        NSData *invalid=[NSData dataWithBytes:"\xff" length:1]; [invalid writeToURL:url atomically:YES];
        assert(await(^BOOL { return viewer.refreshError!=nil; }));
        assert([viewer.text.string containsString:@"# After"]);
        [viewer hideTerminal:nil];
        assert([@"# Hidden save\n" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil]);
        assert(await(^BOOL { return [viewer.text.string containsString:@"# Hidden save"]; }));
        assert(!viewer.refreshError);
        [viewer edit:nil];
        [viewer zoomIn:nil]; pump(0.2); assert(kill(pid,0)==0);
        [viewer stopTerminal:nil]; assert(!viewer.terminal.running && !viewer.terminal.hasSession);
        assert(await(^BOOL { return kill(pid,0)!=0 && kill(child,0)!=0; }));
        // Natural exit retains output and allows a fresh session.
        assert([viewer.terminal startCommand:@"exec /bin/echo MDV_EXIT" directory:url.URLByDeletingLastPathComponent environment:NSProcessInfo.processInfo.environment]);
        assert(await(^BOOL { return !viewer.terminal.running; }));
        assert([[viewer.terminal screenText] containsString:@"MDV_EXIT"]);
        [viewer stopTerminal:nil];
        __block BOOL resolved=NO;
        mdv_resolve_agent(@"codex",@"/does/not/exist",^(NSString *path,NSDictionary *env,NSString *error) {
            assert(!path && error.length && [env[@"PATH"] length]); resolved=YES;
        });
        assert(await(^BOOL { return resolved; }));
        if(argc>1 && !strcmp(argv[1],"--agents")) for(NSString *agent in @[@"claude",@"codex"]) {
            __block BOOL done=NO;
            __block NSString *program=nil; __block NSDictionary *environment=nil;
            mdv_resolve_agent(agent,nil,^(NSString *path,NSDictionary *env,NSString *error) {
                assert(!error); program=path; environment=env; done=YES;
            });
            assert(await(^BOOL { return done; }));
            NSArray *arguments=prepare(agent,program,url,YES,NULL);
            NSMutableString *command=[NSMutableString stringWithFormat:@"exec %@",mdv_shell_quote(program)];
            for(NSString *argument in arguments) [command appendFormat:@" %@",mdv_shell_quote(argument)];
            assert([viewer.terminal startCommand:command directory:url.URLByDeletingLastPathComponent environment:environment]);
            assert(await(^BOOL { return viewer.terminal.screenText.length>80; }));
            pump(1); assert(viewer.terminal.running);
            printf("Installed %s interactive CLI launched in embedded terminal (no task submitted).\n",agent.UTF8String);
            [viewer stopTerminal:nil];
        }
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{@"TerminalDocumentContext":@YES} forName:NSArgumentDomain];
        verifyDocumentContext(url);
        NSString *fixture=[[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:@"tests/fake_agent.sh"];
        NSString *capture=[directory stringByAppendingPathComponent:@"mdv-captured.args"];
        for(NSString *agent in @[@"claude",@"codex"]) {
            [[NSFileManager defaultManager] removeItemAtPath:capture error:nil];
            [NSUserDefaults.standardUserDefaults setVolatileDomain:@{@"TerminalAgent":agent,[@"TerminalExecutable." stringByAppendingString:agent]:fixture,@"TerminalDocumentContext":@YES} forName:NSArgumentDomain];
            [viewer edit:nil]; assert(await(^BOOL { return viewer.terminal.running; }));
            assert(viewer.terminal.usesDocumentContext);
            assert([viewer.terminalDocument.stringValue isEqualToString:[@"Editing: " stringByAppendingString:url.lastPathComponent]]);
            assert(await(^BOOL { return [NSData dataWithContentsOfFile:capture].length>0; }));
            NSString *args=[[NSString alloc] initWithData:[NSData dataWithContentsOfFile:capture] encoding:NSUTF8StringEncoding];
            assert([args containsString:@"Wait for the user's request"]);
            [viewer hideTerminal:nil]; [viewer edit:nil]; assert(viewer.terminal.usesDocumentContext);
            [viewer stopTerminal:nil];
        }
        [viewer.window close];
        [[NSFileManager defaultManager] removeItemAtPath:directory error:nil];
        puts("Terminal checks passed: document context, preserved Codex instructions, agent launch, cwd, input, resize, hide/show, independent windows, live saves, invalid saves, source mode, process cleanup, exit, and missing executable.");
    }
    return 0;
}
