#include "render.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { char text[32768]; size_t length; unsigned seen; unsigned heading; unsigned indent; int links,images; char target[256]; int abort_after,calls; } Result;
static int collect(const char *text, size_t length, const MdvStyle *style, void *context) {
    Result *r=context;
    if(r->abort_after && ++r->calls>=r->abort_after) return 1;
    assert(r->length+length<sizeof r->text);
    memcpy(r->text+r->length,text,length); r->length+=length; r->text[r->length]=0;
    r->seen|=style->flags; if(style->heading>r->heading) r->heading=style->heading;
    if(style->indent>r->indent) r->indent=style->indent;
    if(style->link) { r->links++; snprintf(r->target,sizeof r->target,"%s",style->link); }
    if(style->flags&MDV_IMAGE) r->images++;
    return 0;
}
static Result parse(const char *source) {
    Result r={0}; assert(mdv_render(source,strlen(source),collect,&r)==0); return r;
}
int main(void) {
    Result r=parse("# Heading\n\nA **bold and *italic*** ~~gone~~ `code` [link](https://example.com).\n");
    assert(r.heading==1); assert((r.seen&(MDV_BOLD|MDV_ITALIC|MDV_CODE|MDV_STRIKE))==(MDV_BOLD|MDV_ITALIC|MDV_CODE|MDV_STRIKE));
    assert(strstr(r.text,"A bold and italic gone code link.")); assert(!strcmp(r.target,"https://example.com"));
    r=parse("3. first\n4. second\n   - nested\n\n- [x] done\n- [ ] next\n");
    assert(strstr(r.text,"3.  first\n")); assert(strstr(r.text,"4.  second\n")); assert(strstr(r.text,"•  nested"));
    assert(strstr(r.text,"☑  done")); assert(strstr(r.text,"☐  next")); assert(r.indent>=2);
    r=parse("> quoted **text**\n\n```c\nint main() {\n  return 0;\n}\n```\n");
    assert(r.seen&MDV_QUOTE); assert(r.seen&MDV_CODE_BLOCK); assert(strstr(r.text,"int main() {\n  return 0;\n}"));
    r=parse("| Left | Right |\n| --- | ---: |\n| one | two |\n");
    assert(r.seen&MDV_TABLE); assert(strstr(r.text,"Left\tRight\n")); assert(strstr(r.text,"one\ttwo"));
    r=parse("&amp; &lt; &copy; &NotEqualTilde; &#65; &#x1F600; &#0;\n");
    assert(strstr(r.text,"& < © ≂̸ A 😀 �"));
    r=parse("![an **image**](picture.png)\n"); assert(r.images==1); assert(strstr(r.text,"an image")); assert(!strcmp(r.target,"picture.png"));
    r=parse("<script>alert('hi')</script>\n\n---\n"); assert(strstr(r.text,"<script>")); assert(strstr(r.text,"────"));
    r=parse("first\nsecond  \nthird\n"); assert(strstr(r.text,"first second\nthird"));
    r=parse(""); assert(r.length==0);
    char nul[]={'a',0,'b'}; memset(&r,0,sizeof r); assert(!mdv_render(nul,sizeof nul,collect,&r)); assert(strstr(r.text,"a�b"));
    const char *complex="[![**image**](local.png)](https://example.com) **[link](elsewhere.md)**";
    for(int i=1;i<20;i++) { memset(&r,0,sizeof r); r.abort_after=i; mdv_render(complex,strlen(complex),collect,&r); }
    char deep[1024]; memset(deep,'>',600); strcpy(deep+600," text"); memset(&r,0,sizeof r); assert(mdv_render(deep,strlen(deep),collect,&r)!=0);
    puts("Renderer tests passed: styles, nesting, lists, tasks, tables, entities, images, raw HTML, breaks, empty input, NUL, callback aborts, nesting limit.");
    return 0;
}
