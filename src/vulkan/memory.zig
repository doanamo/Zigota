pub usingnamespace @import("../memory.zig");

const std = @import("std");
const c = @import("../c.zig");

pub const allocation_callbacks = &c.VkAllocationCallbacks{
    .pUserData = null,
    .pfnAllocation = &vulkanAllocationCallback,
    .pfnReallocation = &vulkanReallocationCallback,
    .pfnFree = &vulkanFreeCallback,
    .pfnInternalAllocation = null,
    .pfnInternalFree = null,
};

fn vulkanAllocationCallback(
    user_data: ?*anyopaque,
    size: usize,
    alignment: usize,
    allocation_scope: c.VkSystemAllocationScope,
) callconv(.C) ?*anyopaque {
    _ = allocation_scope;
    _ = user_data;
    return c.mi_malloc_aligned(size, alignment);
}

fn vulkanReallocationCallback(
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

fn vulkanFreeCallback(user_data: ?*anyopaque, allocation: ?*anyopaque) callconv(.C) void {
    _ = user_data;
    c.mi_free(allocation);
}
