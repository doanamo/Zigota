const c = @import("c.zig");
const std = @import("std");

pub fn init() !void {
    if (std.debug.runtime_safety) {
        c.mi_option_set(c.mi_option_show_stats, 1);
        c.mi_option_set(c.mi_option_verbose, 1);
    }
}

pub fn deinit() void {}

pub const MimallocAllocator = std.mem.Allocator{
    .ptr = undefined,
    .vtable = &std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .free = free,
    },
};

fn alloc(
    _: *anyopaque,
    len: usize,
    ptr_align: u29,
    len_align: u29,
    return_address: usize,
) error{OutOfMemory}![]u8 {
    _ = return_address;

    std.debug.assert(len > 0);
    std.debug.assert(std.math.isPowerOfTwo(ptr_align));

    const ptr = @ptrCast([*]u8, c.mi_malloc_aligned(len, ptr_align) orelse return error.OutOfMemory);
    if (len_align == 0) {
        return ptr[0..len];
    }

    const full_len = c.mi_usable_size(ptr);
    return ptr[0..std.mem.alignBackwardAnyAlign(full_len, len_align)];
}

fn resize(
    ptr: *anyopaque,
    buf: []u8,
    buf_align: u29,
    new_len: usize,
    len_align: u29,
    ret_addr: usize,
) ?usize {
    _ = ret_addr;
    _ = buf_align;
    _ = ptr;

    if (new_len <= buf.len) {
        return std.mem.alignAllocLen(buf.len, new_len, len_align);
    }

    const full_len = c.mi_usable_size(buf.ptr);
    if (new_len <= full_len) {
        return std.mem.alignAllocLen(full_len, new_len, len_align);
    }

    return null;
}

fn free(ptr: *anyopaque, buf: []u8, buf_align: u29, ret_addr: usize) void {
    _ = ptr;
    _ = ret_addr;

    c.mi_free_size_aligned(buf.ptr, buf.len, buf_align);
}
