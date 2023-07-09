pub usingnamespace @import("../utility.zig");

const std = @import("std");

pub const log_scoped = std.log.scoped(.GLFW);
