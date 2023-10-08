const std = @import("std");
const log = std.log.scoped(.Scene);

const Transform = @import("transform.zig").Transform;

pub const Node = struct {
    transform: Transform = .{},

    parent: ?*Node = null,
    first_child: ?*Node = null,
    next_sibling: ?*Node = null,
};
