#import <Cocoa/Cocoa.h>
#import <CoreServices/CoreServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

int main(int argc, const char **argv) {
    @autoreleasepool {
        if(argc!=3 || (strcmp(argv[1],"--install") && strcmp(argv[1],"--check"))) {
            fprintf(stderr,"Usage: mdv-integrate --install APP | --check MARKDOWN_FILE\n"); return 1;
        }
        NSString *bundleID=@"io.github.markdownview.viewer";
        NSURL *url=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]];
        if(!strcmp(argv[1],"--check")) {
            NSURL *handler=[[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:url];
            NSString *identifier=handler?[NSBundle bundleWithURL:handler].bundleIdentifier:nil;
            printf("Default opener: %s\n",handler.path.UTF8String?:"(none)");
            return [identifier isEqual:bundleID]?0:2;
        }
        OSStatus status=LSRegisterURL((__bridge CFURLRef)url,true);
        if(status!=noErr) { fprintf(stderr,"App registration failed: %d\n",(int)status); return 3; }
        NSMutableSet<NSString *> *types=[NSMutableSet setWithObject:@"net.daringfireball.markdown"];
        for(NSString *extension in @[@"md",@"markdown",@"mdown",@"mkd"]) {
            NSString *identifier=[UTType typeWithFilenameExtension:extension].identifier;
            /* Never associate generic text/data types with the Markdown viewer. */
            if(identifier && ![identifier hasPrefix:@"public."]) [types addObject:identifier];
        }
        NSString *folder=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Markdown View"];
        [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *backup=[folder stringByAppendingPathComponent:@"previous-defaults.json"];
        if(![[NSFileManager defaultManager] fileExistsAtPath:backup]) {
            NSMutableDictionary *previous=[NSMutableDictionary new];
            for(NSString *type in types) {
                NSString *old=CFBridgingRelease(LSCopyDefaultRoleHandlerForContentType((__bridge CFStringRef)type,kLSRolesAll));
                if(old) previous[type]=old;
            }
            [[NSJSONSerialization dataWithJSONObject:previous options:NSJSONWritingPrettyPrinted error:nil] writeToFile:backup atomically:YES];
        }
        BOOL ok=YES;
        for(NSString *type in types) {
            status=LSSetDefaultRoleHandlerForContentType((__bridge CFStringRef)type,kLSRolesAll,(__bridge CFStringRef)bundleID);
            printf("%s: %s (status %d)\n",type.UTF8String,bundleID.UTF8String,(int)status);
            if(status!=noErr) ok=NO;
        }
        return ok?0:4;
    }
}
