const c = @import("c.zig");
const std = @import("std");

pub var frame_arena_allocator: std.heap.ArenaAllocator = undefined;
pub var frame_allocator: std.mem.Allocator = undefined;
pub var default_allocator: std.mem.Allocator = undefined;

pub fn init() !void {
    if (std.debug.runtime_safety) {
        c.mi_option_enable(c.mi_option_show_errors);
        c.mi_option_enable(c.mi_option_show_stats);
        c.mi_option_enable(c.mi_option_verbose);
    }

    frame_arena_allocator = std.heap.ArenaAllocator.init(MimallocAllocator);
    frame_allocator = frame_arena_allocator.allocator();
    default_allocator = MimallocAllocator;
}

pub fn deinit() void {
    frame_arena_allocator.deinit();
    frame_arena_allocator = undefined;
    frame_allocator = undefined;
    default_allocator = undefined;
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
    return @as(usize, 1) << @as(std.mem.Allocator.Log2Align, @intCast(log2_align));
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
    return @ptrCast(ptr);
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
