#include <gtk/gtk.h>
#include <glib/gstdio.h>
#include "render.h"
#define MAX_FILE_SIZE (128ULL*1024*1024)
typedef struct {
    GtkApplication *app;
    GtkWidget *window, *view, *search;
    GtkTextBuffer *buffer;
    GHashTable *tags;
    char *path, *base;
    int font_size;
} Viewer;

static void show_file(GtkApplication *app, const char *path);
static void error_dialog(Viewer *v, const char *message) {
    GtkWidget *dialog=gtk_message_dialog_new(GTK_WINDOW(v->window),GTK_DIALOG_MODAL|GTK_DIALOG_DESTROY_WITH_PARENT,GTK_MESSAGE_ERROR,GTK_BUTTONS_CLOSE,"Unable to open Markdown file");
    gtk_message_dialog_format_secondary_text(GTK_MESSAGE_DIALOG(dialog),"%s",message);
    g_signal_connect_swapped(dialog,"response",G_CALLBACK(gtk_widget_destroy),dialog);
    gtk_widget_show(dialog);
}
static char *resolve_link(Viewer *v, const char *target) {
    if(!target || !*target) return NULL;
    if(g_str_has_prefix(target,"www.")) return g_strconcat("https://",target,NULL);
    return g_uri_resolve_relative(v->base,target,G_URI_FLAGS_PARSE_RELAXED,NULL);
}
static int native_sink(const char *text, size_t length, const MdvStyle *style, void *context) {
    Viewer *v=context; GtkTextIter start,end;
    gtk_text_buffer_get_end_iter(v->buffer,&end);
    int offset=gtk_text_iter_get_offset(&end);
    char *uri=style->link?resolve_link(v,style->link):NULL;
    if((style->flags&MDV_IMAGE) && uri && g_str_has_prefix(uri,"file:")) {
        char *path=g_filename_from_uri(uri,NULL,NULL);
        GdkPixbuf *image=path?gdk_pixbuf_new_from_file_at_scale(path,640,480,TRUE,NULL):NULL;
        g_free(path);
        if(image) { gtk_text_buffer_insert_pixbuf(v->buffer,&end,image); g_object_unref(image); g_free(uri); return 0; }
    }
    if(style->flags&MDV_IMAGE) gtk_text_buffer_insert(v->buffer,&end,"[Image: ",-1);
    gtk_text_buffer_insert(v->buffer,&end,text,(gint)length);
    if(style->flags&MDV_IMAGE) gtk_text_buffer_insert(v->buffer,&end,"]",1);
    gtk_text_buffer_get_iter_at_offset(v->buffer,&start,offset);
    char key[96]; g_snprintf(key,sizeof key,"%u:%u:%u",style->flags,style->heading,style->indent);
    GtkTextTag *tag=g_hash_table_lookup(v->tags,key);
    if(!tag) {
        tag=gtk_text_buffer_create_tag(v->buffer,NULL,"left-margin",(gint)(style->indent*22),"pixels-inside-wrap",4,NULL);
        double factors[]={1,2.0,1.6,1.3,1.15,1.05,1};
        double size=v->font_size*(style->heading?factors[MIN(style->heading,6)]:1);
        if(style->flags&(MDV_CODE|MDV_TABLE)) g_object_set(tag,"family","monospace","size-points",size*0.9,NULL);
        else g_object_set(tag,"size-points",size,NULL);
        if(style->heading || style->flags&MDV_BOLD) g_object_set(tag,"weight",PANGO_WEIGHT_BOLD,NULL);
        if(style->flags&MDV_ITALIC) g_object_set(tag,"style",PANGO_STYLE_ITALIC,NULL);
        if(style->flags&MDV_STRIKE) g_object_set(tag,"strikethrough",TRUE,NULL);
        if(style->flags&MDV_QUOTE) g_object_set(tag,"style",PANGO_STYLE_ITALIC,NULL);
        if(style->flags&MDV_CODE) { GdkRGBA color={0.5,0.5,0.5,0.12}; g_object_set(tag,"background-rgba",&color,NULL); }
        if(style->flags&MDV_TABLE) {
            PangoTabArray *tabs=pango_tab_array_new(32,TRUE);
            for(int i=0;i<32;i++) pango_tab_array_set_tab(tabs,i,PANGO_TAB_LEFT,(i+1)*v->font_size*12);
            g_object_set(tag,"tabs",tabs,NULL); pango_tab_array_free(tabs);
        }
        g_hash_table_insert(v->tags,g_strdup(key),tag);
    }
    gtk_text_buffer_apply_tag(v->buffer,tag,&start,&end);
    if(uri) {
        GtkTextTag *link=gtk_text_buffer_create_tag(v->buffer,NULL,"underline",PANGO_UNDERLINE_SINGLE,NULL);
        g_object_set_data_full(G_OBJECT(link),"mdv-uri",uri,g_free);
        gtk_text_buffer_apply_tag(v->buffer,link,&start,&end);
    }
    return 0;
}
static void load_file(Viewer *v, const char *path) {
    GStatBuf statbuf;
    if(g_stat(path,&statbuf)!=0) { error_dialog(v,"The file could not be read."); return; }
    if(!S_ISREG(statbuf.st_mode)) { error_dialog(v,"Please open a regular text file."); return; }
    if((guint64)statbuf.st_size>MAX_FILE_SIZE) { error_dialog(v,"This file exceeds the 128 MB document limit."); return; }
    char *source=NULL; gsize length=0; GError *error=NULL;
    if(!g_file_get_contents(path,&source,&length,&error)) { error_dialog(v,error->message); g_error_free(error); return; }
    if(!g_utf8_validate(source,(gssize)length,NULL)) { error_dialog(v,"This file is not UTF-8 text."); g_free(source); return; }
    /* Render into a fresh buffer: a failed parse keeps the previous document. */
    GtkTextBuffer *old_buffer=v->buffer; GHashTable *old_tags=v->tags; char *old_base=v->base;
    v->buffer=gtk_text_buffer_new(NULL); v->tags=g_hash_table_new_full(g_str_hash,g_str_equal,g_free,NULL);
    v->base=g_filename_to_uri(path,NULL,NULL);
    const char *text=source; gsize size=length;
    if(size>=3 && !memcmp(text,"\xef\xbb\xbf",3)) { text+=3; size-=3; }
    int result=mdv_render(text,size,native_sink,v); g_free(source);
    if(result) {
        g_object_unref(v->buffer); g_hash_table_destroy(v->tags); g_free(v->base);
        v->buffer=old_buffer; v->tags=old_tags; v->base=old_base;
        error_dialog(v,"Could not render this document (excessive nesting)."); return;
    }
    gtk_text_view_set_buffer(GTK_TEXT_VIEW(v->view),v->buffer);
    g_object_unref(old_buffer); g_hash_table_destroy(old_tags); g_free(old_base);
    char *new_path=g_strdup(path); g_free(v->path); v->path=new_path;
    char *basename=g_path_get_basename(path), *title=g_strconcat(basename," — Markdown View",NULL);
    gtk_window_set_title(GTK_WINDOW(v->window),title); g_free(title); g_free(basename);
}
static void reload(GtkWidget *widget, gpointer context) { (void)widget; Viewer *v=context; if(v->path) load_file(v,v->path); }
static void zoom(Viewer *v, int delta) { v->font_size=CLAMP(v->font_size+delta,10,32); reload(NULL,v); }
static void zoom_in(GtkWidget *widget, gpointer context) { (void)widget; zoom(context,2); }
static void zoom_out(GtkWidget *widget, gpointer context) { (void)widget; zoom(context,-2); }
static void find(Viewer *v, gboolean backward) {
    const char *query=gtk_entry_get_text(GTK_ENTRY(v->search)); if(!*query) return;
    GtkTextIter start,end,from;
    if(gtk_text_buffer_get_selection_bounds(v->buffer,&start,&end)) from=backward?start:end;
    else gtk_text_buffer_get_iter_at_mark(v->buffer,&from,gtk_text_buffer_get_insert(v->buffer));
    GtkTextSearchFlags flags=GTK_TEXT_SEARCH_TEXT_ONLY|GTK_TEXT_SEARCH_CASE_INSENSITIVE;
    gboolean found=backward?gtk_text_iter_backward_search(&from,query,flags,&start,&end,NULL):gtk_text_iter_forward_search(&from,query,flags,&start,&end,NULL);
    if(!found) {
        if(backward) gtk_text_buffer_get_end_iter(v->buffer,&from); else gtk_text_buffer_get_start_iter(v->buffer,&from);
        found=backward?gtk_text_iter_backward_search(&from,query,flags,&start,&end,NULL):gtk_text_iter_forward_search(&from,query,flags,&start,&end,NULL);
    }
    if(found) { gtk_text_buffer_select_range(v->buffer,&start,&end); gtk_text_view_scroll_to_iter(GTK_TEXT_VIEW(v->view),&start,0.15,FALSE,0,0); }
    else gtk_widget_error_bell(v->search);
}
static void find_next(GtkWidget *widget, gpointer context) { (void)widget; find(context,FALSE); }
static void chooser_response(GtkNativeDialog *dialog, gint response, gpointer context) {
    Viewer *v=g_object_get_data(G_OBJECT(context),"viewer");
    if(response==GTK_RESPONSE_ACCEPT) {
        char *path=gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dialog)); show_file(v->app,path); g_free(path);
    }
    g_object_unref(dialog);
}
static void open_file(GtkWidget *widget, gpointer context) {
    (void)widget; Viewer *v=context;
    GtkFileChooserNative *dialog=gtk_file_chooser_native_new("Open Markdown file",GTK_WINDOW(v->window),GTK_FILE_CHOOSER_ACTION_OPEN,"Open","Cancel");
    GtkFileFilter *filter=gtk_file_filter_new(); gtk_file_filter_set_name(filter,"Markdown and text");
    gtk_file_filter_add_pattern(filter,"*.md"); gtk_file_filter_add_pattern(filter,"*.markdown"); gtk_file_filter_add_pattern(filter,"*.mdown"); gtk_file_filter_add_pattern(filter,"*.mkd"); gtk_file_filter_add_pattern(filter,"*.txt");
    gtk_file_chooser_add_filter(GTK_FILE_CHOOSER(dialog),filter);
    filter=gtk_file_filter_new(); gtk_file_filter_set_name(filter,"All files"); gtk_file_filter_add_pattern(filter,"*"); gtk_file_chooser_add_filter(GTK_FILE_CHOOSER(dialog),filter);
    g_signal_connect_object(dialog,"response",G_CALLBACK(chooser_response),v->window,0); gtk_native_dialog_show(GTK_NATIVE_DIALOG(dialog));
}
static gboolean key_press(GtkWidget *widget, GdkEventKey *event, gpointer context) {
    (void)widget; Viewer *v=context; if(!(event->state&GDK_CONTROL_MASK)) return FALSE;
    switch(event->keyval) {
    case GDK_KEY_o: open_file(NULL,v); return TRUE;
    case GDK_KEY_r: reload(NULL,v); return TRUE;
    case GDK_KEY_f: gtk_widget_grab_focus(v->search); gtk_editable_select_region(GTK_EDITABLE(v->search),0,-1); return TRUE;
    case GDK_KEY_g: case GDK_KEY_G: find(v,(event->state&GDK_SHIFT_MASK)!=0); return TRUE;
    case GDK_KEY_plus: case GDK_KEY_equal: case GDK_KEY_KP_Add: zoom(v,2); return TRUE;
    case GDK_KEY_minus: case GDK_KEY_KP_Subtract: zoom(v,-2); return TRUE;
    case GDK_KEY_0: v->font_size=16; reload(NULL,v); return TRUE;
    case GDK_KEY_w: gtk_widget_destroy(v->window); return TRUE;
    case GDK_KEY_q: g_application_quit(G_APPLICATION(v->app)); return TRUE;
    default: return FALSE;
    }
}
static void link_clicked(GtkWidget *widget, GdkEvent *event, gpointer context) {
    Viewer *v=context;
    if(event->type!=GDK_BUTTON_RELEASE || event->button.button!=1) return;
    GtkTextIter start,end;
    if(gtk_text_buffer_get_selection_bounds(v->buffer,&start,&end)) return;
    gint x,y; gtk_text_view_window_to_buffer_coords(GTK_TEXT_VIEW(widget),GTK_TEXT_WINDOW_WIDGET,(gint)event->button.x,(gint)event->button.y,&x,&y);
    GtkTextIter iter; gtk_text_view_get_iter_at_location(GTK_TEXT_VIEW(widget),&iter,x,y);
    GSList *tags=gtk_text_iter_get_tags(&iter);
    for(GSList *p=tags;p;p=p->next) {
        const char *uri=g_object_get_data(G_OBJECT(p->data),"mdv-uri"); if(!uri) continue;
        char *scheme=g_uri_parse_scheme(uri);
        if(scheme && !strcmp(scheme,"file")) {
            char *path=g_filename_from_uri(uri,NULL,NULL);
            if(path && (g_str_has_suffix(path,".md") || g_str_has_suffix(path,".markdown") || g_str_has_suffix(path,".mdown") || g_str_has_suffix(path,".mkd"))) show_file(v->app,path);
            else gtk_show_uri_on_window(GTK_WINDOW(v->window),uri,GDK_CURRENT_TIME,NULL);
            g_free(path);
        } else if(scheme && (!strcmp(scheme,"http") || !strcmp(scheme,"https") || !strcmp(scheme,"mailto"))) gtk_show_uri_on_window(GTK_WINDOW(v->window),uri,GDK_CURRENT_TIME,NULL);
        g_free(scheme); break;
    }
    g_slist_free(tags);
}
static void destroy_viewer(gpointer context) {
    Viewer *v=context; g_object_unref(v->buffer); g_hash_table_destroy(v->tags); g_free(v->path); g_free(v->base); g_free(v);
}
static Viewer *new_viewer(GtkApplication *app) {
    Viewer *v=g_new0(Viewer,1); v->app=app; v->font_size=16;
    v->window=gtk_application_window_new(app); gtk_window_set_title(GTK_WINDOW(v->window),"Markdown View"); gtk_window_set_default_size(GTK_WINDOW(v->window),860,680);
    g_object_set_data_full(G_OBJECT(v->window),"viewer",v,destroy_viewer);
    GtkWidget *box=gtk_box_new(GTK_ORIENTATION_VERTICAL,0), *bar=gtk_box_new(GTK_ORIENTATION_HORIZONTAL,8);
    gtk_container_add(GTK_CONTAINER(v->window),box); gtk_container_set_border_width(GTK_CONTAINER(bar),12);
    const char *labels[]={"Open…","Reload","A−","A+"}; GCallback actions[]={G_CALLBACK(open_file),G_CALLBACK(reload),G_CALLBACK(zoom_out),G_CALLBACK(zoom_in)};
    for(int i=0;i<4;i++) { GtkWidget *button=gtk_button_new_with_label(labels[i]); g_signal_connect(button,"clicked",actions[i],v); gtk_box_pack_start(GTK_BOX(bar),button,FALSE,FALSE,0); }
    v->search=gtk_search_entry_new(); gtk_entry_set_placeholder_text(GTK_ENTRY(v->search),"Find in document"); g_signal_connect(v->search,"activate",G_CALLBACK(find_next),v); gtk_box_pack_end(GTK_BOX(bar),v->search,TRUE,TRUE,0);
    gtk_box_pack_start(GTK_BOX(box),bar,FALSE,FALSE,0);
    GtkWidget *scroll=gtk_scrolled_window_new(NULL,NULL); gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll),GTK_POLICY_AUTOMATIC,GTK_POLICY_AUTOMATIC);
    v->view=gtk_text_view_new(); gtk_text_view_set_editable(GTK_TEXT_VIEW(v->view),FALSE); gtk_text_view_set_cursor_visible(GTK_TEXT_VIEW(v->view),FALSE); gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(v->view),GTK_WRAP_WORD_CHAR);
    gtk_text_view_set_left_margin(GTK_TEXT_VIEW(v->view),36); gtk_text_view_set_right_margin(GTK_TEXT_VIEW(v->view),36); gtk_text_view_set_top_margin(GTK_TEXT_VIEW(v->view),28); gtk_text_view_set_bottom_margin(GTK_TEXT_VIEW(v->view),28);
    v->buffer=gtk_text_view_get_buffer(GTK_TEXT_VIEW(v->view)); g_object_ref(v->buffer); v->tags=g_hash_table_new_full(g_str_hash,g_str_equal,g_free,NULL);
    gtk_text_buffer_set_text(v->buffer,"Markdown View\n\nOpen a Markdown file to start reading.\n\nCtrl+O  Open     Ctrl+F  Find     Ctrl+Plus / Ctrl+Minus  Zoom     Ctrl+R  Reload",-1);
    gtk_container_add(GTK_CONTAINER(scroll),v->view); gtk_box_pack_start(GTK_BOX(box),scroll,TRUE,TRUE,0);
    g_signal_connect(v->window,"key-press-event",G_CALLBACK(key_press),v); g_signal_connect(v->view,"event-after",G_CALLBACK(link_clicked),v);
    gtk_widget_show_all(v->window); return v;
}
static void show_file(GtkApplication *app, const char *path) {
    if(!path) return;
    char *canonical=g_canonicalize_filename(path,NULL); Viewer *target=NULL;
    for(GList *p=gtk_application_get_windows(app);p;p=p->next) {
        Viewer *v=g_object_get_data(G_OBJECT(p->data),"viewer");
        if(v->path && !strcmp(v->path,canonical)) { gtk_window_present(GTK_WINDOW(v->window)); g_free(canonical); return; }
        if(!v->path) target=v;
    }
    if(!target) target=new_viewer(app);
    load_file(target,canonical); gtk_window_present(GTK_WINDOW(target->window)); g_free(canonical);
}
static void activate(GtkApplication *app, gpointer context) {
    (void)context; GList *windows=gtk_application_get_windows(app);
    if(windows) gtk_window_present(GTK_WINDOW(windows->data)); else new_viewer(app);
}
static void open_documents(GtkApplication *app, GFile **files, gint count, const gchar *hint, gpointer context) {
    (void)hint; (void)context;
    for(int i=0;i<count;i++) { char *path=g_file_get_path(files[i]); show_file(app,path); g_free(path); }
}
int main(int argc, char **argv) {
    if(argc==3 && !strcmp(argv[1],"--smoke-test")) {
        gtk_init(NULL,NULL);
        GtkApplication *test_app=gtk_application_new("io.github.markdownview.test",G_APPLICATION_NON_UNIQUE);
        g_application_register(G_APPLICATION(test_app),NULL,NULL);
        Viewer *v=new_viewer(test_app); char *path=g_canonicalize_filename(argv[2],NULL);
        load_file(v,path); g_free(path);
        if(!v->path || gtk_text_view_get_editable(GTK_TEXT_VIEW(v->view)) || !gtk_text_buffer_get_char_count(v->buffer)) return 1;
        gtk_entry_set_text(GTK_ENTRY(v->search),"Markdown"); find(v,FALSE);
        GtkTextIter start,end;
        if(!gtk_text_buffer_get_selection_bounds(v->buffer,&start,&end)) return 2;
        while(gtk_events_pending()) gtk_main_iteration();
        g_print("Native window, read-only text buffer, layout, and search smoke test passed.\n");
        gtk_widget_destroy(v->window); g_object_unref(test_app); return 0;
    }
    GtkApplication *app=gtk_application_new("io.github.markdownview.viewer",G_APPLICATION_HANDLES_OPEN);
    g_signal_connect(app,"activate",G_CALLBACK(activate),NULL); g_signal_connect(app,"open",G_CALLBACK(open_documents),NULL);
    int result=g_application_run(G_APPLICATION(app),argc,argv); g_object_unref(app); return result;
}
