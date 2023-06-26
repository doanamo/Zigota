#pragma once

#include <stdint.h>

void* (*vmaAlignedMalloc)(size_t size, size_t alignment);
void (*vmaFree)(void* ptr);

#include <VmaUsage.h>
