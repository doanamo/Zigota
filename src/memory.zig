const c = @import("c.zig");
const std = @import("std");

// TODO Add mimalloc asserts on shutdown errors (leaks, corruptions, etc.)

pub const default_allocator = MimallocAllocator;

pub fn setup() void {
    if (std.debug.runtime_safety) {
        c.mi_option_set(c.mi_option_show_stats, 1);
        c.mi_option_set(c.mi_option_verbose, 1);
    }
}

pub const MimallocAllocator = std.mem.Allocator{
    .ptr = undefined,
    .vtable = &std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .free = free,
    },
};

pub fn calculateAlignmentFromLog2(log2_align: u8) usize {
    return @as(usize, 1) << @intCast(std.mem.Allocator.Log2Align, log2_align);
}

fn alloc(
    ctx: *anyopaque,
    len: usize,
    log2_align: u8,
    return_address: usize,
) ?[*]u8 {
    _ = ctx;
    _ = return_address;

    std.debug.assert(len > 0);
    const alignment = calculateAlignmentFromLog2(log2_align);
    const ptr = c.mi_malloc_aligned(len, alignment);
    return @ptrCast([*]u8, ptr);
}

fn resize(
    ptr: *anyopaque,
    buf: []u8,
    log2_align: u8,
    new_len: usize,
    ret_addr: usize,
) bool {
    _ = ret_addr;
    _ = log2_align;
    _ = ptr;

    if (new_len <= buf.len) {
        return true;
    }

    const full_len = c.mi_usable_size(buf.ptr);
    if (new_len <= full_len) {
        return true;
    }

    return false;
}

fn free(ptr: *anyopaque, buf: []u8, log2_align: u8, ret_addr: usize) void {
    _ = ptr;
    _ = ret_addr;

    const alignment = calculateAlignmentFromLog2(log2_align);
    c.mi_free_size_aligned(buf.ptr, buf.len, alignment);
}
