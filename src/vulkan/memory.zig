pub usingnamespace @import("../memory.zig");
const c = @import("../c.zig");

pub const vulkan_allocator = &c.VkAllocationCallbacks{
    .pUserData = null,
    .pfnAllocation = &allocationCallback,
    .pfnReallocation = &reallocationCallback,
    .pfnFree = &freeCallback,
    .pfnInternalAllocation = null,
    .pfnInternalFree = null,
};

fn allocationCallback(
    user_data: ?*anyopaque,
    size: usize,
    alignment: usize,
    allocation_scope: c.VkSystemAllocationScope,
) callconv(.C) ?*anyopaque {
    _ = allocation_scope;
    _ = user_data;
    return c.mi_malloc_aligned(size, alignment);
}

fn reallocationCallback(
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

fn freeCallback(user_data: ?*anyopaque, allocation: ?*anyopaque) callconv(.C) void {
    _ = user_data;
    c.mi_free(allocation);
}
