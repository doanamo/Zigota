const std = @import("std");
const c = @import("../c.zig");

//var allocator_callbacks: c.GLFWallocator = undefined; // TODO Waiting for GLFW 3.4.0

fn allocateCallback(size: usize, user: ?*anyopaque) callconv(.C) ?*anyopaque {
    _ = user;
    return c.mi_malloc(size);
}

fn reallocateCallback(block: ?*anyopaque, size: usize, user: ?*anyopaque) callconv(.C) ?*anyopaque {
    _ = user;
    return c.mi_realloc(block, size);
}

fn freeCallback(block: ?*anyopaque, user: ?*anyopaque) callconv(.C) void {
    _ = user;
    c.mi_free(block);
}
