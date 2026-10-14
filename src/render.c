#include "render.h"
#include "md4c.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdint.h>
#include <limits.h>
#include "entities.h"
#define DEPTH 256

typedef struct { MdvStyle style; unsigned number; int ordered; MD_BLOCKTYPE type; } Block;
typedef struct {
    MdvSink sink; void *context; MdvStyle style;
    Block blocks[DEPTH]; unsigned depth;
    MdvStyle spans[DEPTH]; unsigned span_depth;
    unsigned trailing, column, image_depth;
    char *alt; size_t alt_size; char *image;
} Render;
static int emit(Render *r, const char *s, size_t n) {
    if (!n) return 0;
    for (size_t i=0;i<n;i++) r->trailing = s[i]=='\n' ? r->trailing+1 : 0;
    return r->sink(s,n,&r->style,r->context);
}
static int gap(Render *r, unsigned count) {
    while (r->trailing<count) { if(emit(r,"\n",1)) return -1; }
    return 0;
}
static char *attribute(MD_ATTRIBUTE a) {
    char *s=malloc((size_t)a.size+1); if(s) { memcpy(s,a.text,a.size); s[a.size]=0; } return s;
}
static int enter_block(MD_BLOCKTYPE type, void *detail, void *ctx) {
    Render *r=ctx; if(r->depth==DEPTH) return -1;
    r->blocks[r->depth++]=(Block){r->style,0,0,type};
    switch(type) {
    case MD_BLOCK_H: if(gap(r,2)) return -1; r->style.heading=((MD_BLOCK_H_DETAIL*)detail)->level; break;
    case MD_BLOCK_P: if(r->depth<2 || r->blocks[r->depth-2].type!=MD_BLOCK_LI) { if(gap(r,r->style.indent?1:2)) return -1; } break;
    case MD_BLOCK_QUOTE: r->style.flags|=MDV_QUOTE; r->style.indent++; break;
    case MD_BLOCK_CODE: if(gap(r,2)) return -1; r->style.flags|=MDV_CODE|MDV_CODE_BLOCK; break;
    case MD_BLOCK_UL: case MD_BLOCK_OL:
        if(gap(r,r->style.indent?1:2)) return -1;
        r->style.indent++;
        r->blocks[r->depth-1].ordered=type==MD_BLOCK_OL;
        r->blocks[r->depth-1].number=type==MD_BLOCK_OL?((MD_BLOCK_OL_DETAIL*)detail)->start:0;
        break;
    case MD_BLOCK_LI: {
        if(gap(r,1)) return -1;
        /* A list item can contain a paragraph. Keep its marker on that line. */
        MD_BLOCK_LI_DETAIL *li=detail; char marker[48];
        Block *list=r->depth>=2?&r->blocks[r->depth-2]:NULL;
        if(li->is_task) snprintf(marker,sizeof marker,"%s  ",li->task_mark==' '?"☐":"☑");
        else if(list && list->ordered) snprintf(marker,sizeof marker,"%u.  ",list->number++);
        else snprintf(marker,sizeof marker,"•  ");
        return emit(r,marker,strlen(marker));
    }
    case MD_BLOCK_HR: if(gap(r,2)) return -1; return emit(r,"────────────────────────\n",strlen("────────────────────────\n"));
    case MD_BLOCK_TABLE: if(gap(r,2)) return -1; r->style.flags|=MDV_TABLE; break;
    case MD_BLOCK_TR: r->column=0; if(gap(r,1)) return -1; break;
    case MD_BLOCK_TH: r->style.flags|=MDV_BOLD; /* fall through */
    case MD_BLOCK_TD: if(r->column++ && emit(r,"\t",1)) return -1; break;
    default: break;
    } return 0;
}
static int leave_block(MD_BLOCKTYPE type, void *detail, void *ctx) {
    (void)detail; Render *r=ctx; int result=0;
    if(type==MD_BLOCK_H || type==MD_BLOCK_CODE || type==MD_BLOCK_P || type==MD_BLOCK_TABLE || type==MD_BLOCK_UL || type==MD_BLOCK_OL) result=gap(r,type==MD_BLOCK_P && r->style.indent?1:2);
    else if(type==MD_BLOCK_LI || type==MD_BLOCK_TR) result=gap(r,1);
    r->style=r->blocks[--r->depth].style; return result;
}
static int enter_span(MD_SPANTYPE type, void *detail, void *ctx) {
    Render *r=ctx; if(r->span_depth==DEPTH) return -1;
    r->spans[r->span_depth++]=r->style;
    switch(type) {
    case MD_SPAN_EM: r->style.flags|=MDV_ITALIC; break;
    case MD_SPAN_STRONG: r->style.flags|=MDV_BOLD; break;
    case MD_SPAN_CODE: r->style.flags|=MDV_CODE; break;
    case MD_SPAN_DEL: r->style.flags|=MDV_STRIKE; break;
    case MD_SPAN_A:
        r->style.link=attribute(((MD_SPAN_A_DETAIL*)detail)->href);
        if(!r->style.link) return -1; break;
    case MD_SPAN_IMG:
        if(!r->image_depth) { r->image=attribute(((MD_SPAN_IMG_DETAIL*)detail)->src); if(!r->image) return -1; }
        r->image_depth++; break;
    default: break;
    } return 0;
}
static int leave_span(MD_SPANTYPE type, void *detail, void *ctx) {
    (void)detail; Render *r=ctx; int result=0;
    if(type==MD_SPAN_A) free((void*)r->style.link);
    if(type==MD_SPAN_IMG && --r->image_depth==0) {
        MdvStyle saved=r->style; r->style.flags|=MDV_IMAGE; r->style.link=r->image;
        result=emit(r,r->alt_size?r->alt:"[image]",r->alt_size?r->alt_size:7);
        r->style=saved; free(r->image); r->image=NULL; free(r->alt); r->alt=NULL; r->alt_size=0;
    }
    r->style=r->spans[--r->span_depth]; return result;
}
static int output(Render *r, const char *s, size_t n) {
    if(r->image_depth) {
        char *p=realloc(r->alt,r->alt_size+n+1); if(!p) return -1;
        r->alt=p; memcpy(p+r->alt_size,s,n); r->alt_size+=n; p[r->alt_size]=0; return 0;
    } return emit(r,s,n);
}
static int text(MD_TEXTTYPE type, const MD_CHAR *s, MD_SIZE n, void *ctx) {
    Render *r=ctx;
    if(type==MD_TEXT_SOFTBR) return output(r," ",1);
    if(type==MD_TEXT_BR) return output(r,"\n",1);
    if(type==MD_TEXT_NULLCHAR) return output(r,"�",3);
    if(type==MD_TEXT_ENTITY) {
        if(n>3 && s[1]=='#') {
            char number[32]; size_t count=n-3; if(count>=sizeof number) return output(r,"�",3);
            memcpy(number,s+2,count); number[count]=0;
            char *end; unsigned long cp;
            if(number[0]=='x'||number[0]=='X') cp=strtoul(number+1,&end,16); else cp=strtoul(number,&end,10);
            if(*end || !cp || cp>0x10ffff || (cp>=0xd800 && cp<=0xdfff)) cp=0xfffd;
            char utf[4]; size_t len;
            if(cp<0x80) { utf[0]=(char)cp; len=1; }
            else if(cp<0x800) { utf[0]=0xc0|(cp>>6); utf[1]=0x80|(cp&63); len=2; }
            else if(cp<0x10000) { utf[0]=0xe0|(cp>>12); utf[1]=0x80|((cp>>6)&63); utf[2]=0x80|(cp&63); len=3; }
            else { utf[0]=0xf0|(cp>>18); utf[1]=0x80|((cp>>12)&63); utf[2]=0x80|((cp>>6)&63); utf[3]=0x80|(cp&63); len=4; }
            return output(r,utf,len);
        }
        const char *value=mdv_entity(s,n); if(value) return output(r,value,strlen(value));
    }
    return output(r,s,n);
}
int mdv_render(const char *source, size_t size, MdvSink sink, void *context) {
    if(size>UINT_MAX || !source || !sink) return -1;
    Render *r=calloc(1,sizeof *r); if(!r) return -1;
    r->sink=sink; r->context=context; r->trailing=2;
    MD_PARSER parser={0}; parser.flags=MD_DIALECT_GITHUB|MD_FLAG_NOHTML;
    parser.enter_block=enter_block; parser.leave_block=leave_block; parser.enter_span=enter_span; parser.leave_span=leave_span; parser.text=text;
    int result=md_parse(source,(MD_SIZE)size,&parser,r);
    /* Clean up active link allocations after an aborted callback. */
    while(r->span_depth) { MdvStyle previous=r->spans[--r->span_depth]; if(r->style.link!=previous.link) free((void*)r->style.link); r->style=previous; }
    free(r->image); free(r->alt); free(r); return result;
}
