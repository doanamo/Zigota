pub usingnamespace @import("../common/memory.zig");

const std = @import("std");
const c = @import("../c/c.zig");

pub const vulkan_allocator = &c.VkAllocationCallbacks{
    .pUserData = null,
    .pfnAllocation = &vulkanAlloc,
    .pfnReallocation = &vulkanRealloc,
    .pfnFree = &vulkanFree,
    .pfnInternalAllocation = null,
    .pfnInternalFree = null,
};

fn vulkanAlloc(
    user_data: ?*anyopaque,
    size: usize,
    alignment: usize,
    allocation_scope: c.VkSystemAllocationScope,
) callconv(.C) ?*anyopaque {
    _ = allocation_scope;
    _ = user_data;
    return c.mi_malloc_aligned(size, alignment);
}

fn vulkanRealloc(
    user_data: ?*anyopaque,
    old_allocation: ?*anyopaque,
    size: usize,
    alignment: usize,
    allocation_scope: c.VkSystemAllocationScope,
) callconv(.C) ?*anyopaque {
    _ = allocation_scope;
    _ = user_data;
    return c.mi_realloc_aligned(old_allocation, size, alignment);
}

fn vulkanFree(user_data: ?*anyopaque, allocation: ?*anyopaque) callconv(.C) void {
    _ = user_data;
    c.mi_free(allocation);
}
