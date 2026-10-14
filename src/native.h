#import <Cocoa/Cocoa.h>
NSAttributedString *mdv_render_data(NSData *data, NSURL *url, CGFloat size, NSError **error);
NSTextView *mdv_text_view(NSRect frame);
void mdv_update_reading_layout(NSTextView *view);
