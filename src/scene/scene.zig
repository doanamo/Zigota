const std = @import("std");
const log = std.log.scoped(.Scene);

pub const Scene = struct {
    pub fn init(self: *Scene) !void {
        log.info("Initializing scene...", .{});
        _ = self;
    }

    pub fn deinit(self: *Scene) void {
        log.info("Deinitializing scene...", .{});
        _ = self;
    }
};
