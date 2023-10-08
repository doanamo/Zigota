const std = @import("std");
const log = std.log.scoped(.Scene);

const HandleMap = @import("../common/handle_map.zig").HandleMap;
const Node = @import("node.zig").Node;

pub const Scene = struct {
    nodes: HandleMap(Node) = .{},

    pub fn init(self: *Scene) !void {
        log.info("Initializing scene...", .{});
        _ = self;
    }

    pub fn deinit(self: *Scene) void {
        log.info("Deinitializing scene...", .{});
        _ = self;
    }
};
