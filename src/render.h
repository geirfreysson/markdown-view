#ifndef MDV_RENDER_H
#define MDV_RENDER_H
#include <stddef.h>
enum { MDV_BOLD=1, MDV_ITALIC=2, MDV_CODE=4, MDV_STRIKE=8, MDV_QUOTE=16, MDV_IMAGE=32, MDV_TABLE=64, MDV_CODE_BLOCK=128 };
typedef struct { unsigned flags, heading, indent; const char *link; } MdvStyle;
/* Text and link pointers are valid only for the duration of the callback. */
typedef int (*MdvSink)(const char *, size_t, const MdvStyle *, void *);
int mdv_render(const char *text, size_t size, MdvSink sink, void *context);
#endif
