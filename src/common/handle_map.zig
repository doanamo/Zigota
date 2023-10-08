const std = @import("std");
const Queue = @import("queue.zig").Queue;
const log = std.log.scoped(.HandleMap);

pub fn HandleMap(comptime T: type) type {
    return struct {
        const Self = @This();
        const Handle = struct {
            identifier: u32,
            version: u32,
        };

        // Number of free handles to maintain at all times so rapid creations and
        // destructions do not exhaust pool of available handles too quickly.
        const FreePoolRotation = 128;

        free: Queue(u32) = .{},
        versions: std.ArrayListUnmanaged(u32) = .{},
        indices: std.ArrayListUnmanaged(u32) = .{},
        storage: std.ArrayListUnmanaged(T) = .{},

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.free.deinit(allocator);
            self.versions.deinit(allocator);
            self.indices.deinit(allocator);
            self.storage.deinit(allocator);
            self.* = undefined;
        }

        pub fn create(self: *Self, allocator: std.mem.Allocator, item: T) !Handle {
            const handle: Handle = try self.allocateHandle(allocator);
            self.storage.items[self.indices.items[handle.identifier]] = item;
            return handle;
        }

        pub fn destroy(self: *Self, handle: Handle) void {
            if (handle.identifier >= self.versions.items.len or
                handle.version != self.versions.items[handle.identifier])
            {
                log.warn("Attempted to destroy invalid handle {}:{}", .{
                    handle.identifier,
                    handle.version,
                });
                return;
            }

            self.storage.items[self.indices.items[handle.identifier]] = undefined;
            self.versions.items[handle.identifier] +%= 1; // Allow overflow to zero
            if (self.versions.items[handle.identifier] != 0) {
                self.free.push(handle.identifier);
            } else {
                log.warn("Handle {}:{} has been retired due to version overflow", .{
                    handle.identifier,
                    handle.version,
                });
            }
        }

        fn allocateHandle(self: *Self, allocator: std.mem.Allocator) !Handle {
            std.debug.assert(FreePoolRotation >= 1);

            var free_handles_needed = @max(FreePoolRotation - self.free.getSize(), 0);
            if (free_handles_needed > 0) {
                try self.free.ensureUnusedCapacity(allocator, free_handles_needed);
                try self.versions.ensureUnusedCapacity(allocator, free_handles_needed);
                try self.indices.ensureUnusedCapacity(allocator, free_handles_needed);
                try self.storage.ensureUnusedCapacity(allocator, free_handles_needed);

                for (0..free_handles_needed) |_| {
                    self.free.pushAssumeCapacity(@intCast(self.versions.items.len));
                    self.versions.appendAssumeCapacity(1);
                    self.indices.appendAssumeCapacity(@intCast(self.storage.items.len));
                    self.storage.appendAssumeCapacity(undefined);
                }
            }

            const identifier = try self.free.pop();
            std.debug.assert(identifier < self.versions.items.len);
            std.debug.assert(identifier < self.indices.items.len);
            std.debug.assert(identifier < self.storage.items.len);

            const version = self.versions.items[identifier];
            std.debug.assert(version > 0); // Zero is reserved for version overflow

            return Handle{
                .identifier = identifier,
                .version = version,
            };
        }

        pub fn get(self: *Self, handle: Handle) !*T {
            if (handle.identifier >= self.versions.items.len or
                handle.version != self.versions.items[handle.identifier])
            {
                return error.InvalidHandle;
            }

            std.debug.assert(handle.identifier < self.indices.items.len);
            return &self.storage.items[self.indices.items[handle.identifier]];
        }
    };
}

test "common.handle" {
    var handle_map: HandleMap(u64) = .{};
    defer handle_map.deinit(std.testing.allocator);

    const handle1 = try handle_map.create(std.testing.allocator, 1);
    const handle2 = try handle_map.create(std.testing.allocator, 2);
    const handle3 = try handle_map.create(std.testing.allocator, 3);

    try std.testing.expect((try handle_map.get(handle1)).* == 1);
    try std.testing.expect((try handle_map.get(handle2)).* == 2);
    try std.testing.expect((try handle_map.get(handle3)).* == 3);

    const handle_invalid = HandleMap(u64).Handle{
        .identifier = 0,
        .version = 0,
    };

    try std.testing.expect(handle_map.get(handle_invalid) == error.InvalidHandle);
}
