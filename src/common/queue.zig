const std = @import("std");

pub fn Queue(comptime T: type) type {
    std.debug.assert(@sizeOf(T) != 0);

    return struct {
        const Self = @This();

        items: []T = &[_]T{},
        head: usize = 0,
        count: usize = 0,

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.items);
            self.* = undefined;
        }

        pub fn realign(self: *Self) void {
            if (self.head == 0)
                return;

            if (self.head + self.count <= self.items.len) {
                std.mem.copyForwards(
                    T,
                    self.items[0..self.count],
                    self.items[self.head..][0..self.count],
                );
                @memset(std.mem.sliceAsBytes(self.items[self.count..]), undefined);
            } else {
                // This is a simple way to realign queue items, but it's not the most efficient
                // See std.LinearFifo.realign() for better and more complicated implementation
                std.mem.rotate(T, self.items, self.head);
            }
            self.head = 0;
        }

        pub fn ensureUnusedCapacity(
            self: *Self,
            allocator: std.mem.Allocator,
            additional_capacity: usize,
        ) std.mem.Allocator.Error!void {
            if (additional_capacity <= self.getUnusedCapacity())
                return;

            try self.ensureTotalCapacity(allocator, self.count + additional_capacity);
        }

        pub fn ensureTotalCapacity(
            self: *Self,
            allocator: std.mem.Allocator,
            new_capacity: usize,
        ) std.mem.Allocator.Error!void {
            if (new_capacity <= self.getCapacity())
                return;

            var better_capacity = self.getCapacity();
            while (true) {
                better_capacity +|= better_capacity / 2 + 8;
                if (better_capacity >= new_capacity)
                    break;
            }

            return self.ensureTotalCapacityPrecise(allocator, better_capacity);
        }

        pub fn ensureTotalCapacityPrecise(
            self: *Self,
            allocator: std.mem.Allocator,
            new_capacity: usize,
        ) std.mem.Allocator.Error!void {
            if (new_capacity <= self.getCapacity())
                return;

            self.realign();
            self.items = try allocator.realloc(self.items, new_capacity);
        }

        pub fn push(
            self: *Self,
            allocator: std.mem.Allocator,
            value: T,
        ) std.mem.Allocator.Error!void {
            try self.ensureUnusedCapacity(allocator, 1);
            self.pushAssumeCapacity(value);
        }

        pub fn pushAssumeCapacity(self: *Self, value: T) void {
            std.debug.assert(self.count < self.items.len);
            const tail = (self.head + self.count) % self.items.len;
            self.items[tail] = value;
            self.count += 1;
        }

        pub fn pop(self: *Self) !T {
            if (self.count == 0)
                return error.EmptyQueue;

            const result = self.items[self.head];
            self.items[self.head] = undefined;
            self.head = (self.head + 1) % self.items.len;
            self.count -= 1;
            return result;
        }

        pub fn getSize(self: *const Self) usize {
            return self.count;
        }

        pub fn getCapacity(self: *const Self) usize {
            return self.items.len;
        }

        pub fn getUnusedCapacity(self: *const Self) usize {
            return self.items.len - self.count;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.count == 0;
        }
    };
}

test "common.queue" {
    var queue: Queue(u32) = .{};
    defer queue.deinit(std.testing.allocator);

    try queue.ensureTotalCapacityPrecise(std.testing.allocator, 4);
    try std.testing.expect(queue.getSize() == 0);
    try std.testing.expect(queue.getCapacity() == 4);
    try std.testing.expect(queue.getUnusedCapacity() == 4);

    try queue.push(std.testing.allocator, 1);
    try queue.push(std.testing.allocator, 2);
    try queue.push(std.testing.allocator, 3);
    try queue.push(std.testing.allocator, 4);
    try std.testing.expect(queue.getSize() == 4);

    try std.testing.expect(try queue.pop() == 1);
    try std.testing.expect(try queue.pop() == 2);
    try std.testing.expect(queue.getSize() == 2);

    queue.realign();
    try std.testing.expect(queue.items[0] == 3);
    try std.testing.expect(queue.items[1] == 4);
    try std.testing.expect(queue.getSize() == 2);

    try std.testing.expect(try queue.pop() == 3);
    try std.testing.expect(try queue.pop() == 4);
    try std.testing.expect(queue.getSize() == 0);

    try queue.push(std.testing.allocator, 5);
    try queue.push(std.testing.allocator, 6);
    try queue.push(std.testing.allocator, 7);
    try queue.push(std.testing.allocator, 8);
    try std.testing.expect(queue.getSize() == 4);

    try std.testing.expect(queue.items[0] == 7);
    try std.testing.expect(queue.items[1] == 8);
    try std.testing.expect(queue.items[2] == 5);
    try std.testing.expect(queue.items[3] == 6);

    queue.realign();
    try std.testing.expect(queue.items[0] == 5);
    try std.testing.expect(queue.items[1] == 6);
    try std.testing.expect(queue.items[2] == 7);
    try std.testing.expect(queue.items[3] == 8);
}

test "common.queue.capacity" {
    var queue: Queue(u32) = .{};
    defer queue.deinit(std.testing.allocator);

    try queue.ensureUnusedCapacity(std.testing.allocator, 3);
    try std.testing.expect(queue.getCapacity() == 8);

    try queue.ensureTotalCapacity(std.testing.allocator, 10);
    try std.testing.expect(queue.getCapacity() == 20);

    try queue.ensureTotalCapacityPrecise(std.testing.allocator, 24);
    try std.testing.expect(queue.getCapacity() == 24);
}
