#define DR_WAV_IMPLEMENTATION

#include <stddef.h>
extern void *zig_malloc(size_t size);
extern void* zig_realloc(void* ptr, size_t size);
extern void zig_free(void* p);

#include "dr_wav.h"