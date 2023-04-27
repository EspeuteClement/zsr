#define DR_MP3_IMPLEMENTATION

#include <stddef.h>

extern void *zig_malloc(size_t size);
extern void* zig_realloc(void* ptr, size_t size);
extern void zig_free(void* p);

#include "dr_mp3.h"