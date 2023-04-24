#define STB_IMAGE_IMPLEMENTATION

#include <stddef.h>
extern void *zig_malloc(size_t size);
extern void* zig_realloc(void* ptr, size_t size);
extern void zig_free(void* p);
int abs(int x) {
    return x >= 0 ? x : -x; 
}

#include "stb_image.h"

