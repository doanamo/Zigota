#include <stdint.h>

extern "C" {
    void* (*vmaAlignedMalloc)(size_t size, size_t alignment) = nullptr;
    void (*vmaFree)(void* ptr) = nullptr;
}

#define VMA_SYSTEM_ALIGNED_MALLOC(size, alignment) vmaAlignedMalloc(size, alignment)
#define VMA_SYSTEM_FREE(ptr) vmaFree(ptr)

#define VMA_IMPLEMENTATION
#include <VmaUsage.h>
