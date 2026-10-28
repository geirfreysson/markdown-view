#import <Cocoa/Cocoa.h>

/* Ghostty is private to the implementation; the renderer and Quick Look do not link it. */
@interface MdvTerminalController : NSViewController
@property (nonatomic,copy) void (^documentChanged)(void);
@property (nonatomic,copy) void (^sessionChanged)(void);
@property (nonatomic,readonly) BOOL running;
@property (nonatomic,readonly) BOOL hasSession;
@property (nonatomic,readonly) NSString *status;
@property (nonatomic,readonly) BOOL usesDocumentContext;
- (void)startForDocument:(NSURL *)url;
- (void)stop;
- (void)setTerminalVisible:(BOOL)visible;
- (void)focusTerminal;
/* Used by native integration tests; never starts an AI task. */
- (BOOL)startCommand:(NSString *)command directory:(NSURL *)directory environment:(NSDictionary *)environment;
- (NSString *)screenText;
@end

BOOL mdv_terminal_settings(NSWindow *parent, BOOL firstUse);
NSString *mdv_shell_quote(NSString *value);
void mdv_resolve_agent(NSString *agent, NSString *override, void (^completion)(NSString *,NSDictionary *,NSString *));

BOOL mdv_document_context_enabled(void);
NSString *mdv_document_instructions(NSURL *url);
void mdv_prepare_agent(NSString *agent, NSString *executablePath, NSURL *url, NSDictionary *environment, BOOL contextEnabled, void (^completion)(NSArray<NSString *> *,NSString *));
