const std = @import("std");
const c = @import("../cimport/c.zig");
const log = std.log.scoped(.GLFW);

const Window = @import("window.zig").Window;

pub const Input = struct {
    const PressStates = enum {
        Released,
        Pressed,
        Repeat,
    };

    keyboard: struct {
        keys: [c.GLFW_KEY_LAST]PressStates = .{.Released} ** c.GLFW_KEY_LAST,

        pub fn isPressed(self: *@This(), key: c_int) bool {
            std.debug.assert(key >= 0 and key < c.GLFW_KEY_LAST);
            switch (self.keys[@intCast(key)]) {
                .Pressed, .Repeat => return true,
                .Released => return false,
            }
        }

        pub fn isReleased(self: *@This(), key: c_int) bool {
            std.debug.assert(key >= 0 and key < c.GLFW_KEY_LAST);
            switch (self.keys[@intCast(key)]) {
                .Pressed, .Repeat => return false,
                .Released => return true,
            }
        }
    } = .{},

    pub fn init(self: *Input, window: *Window) !void {
        log.info("Initializing input...", .{});
        errdefer self.deinit();

        window.key_callback = .{
            .userdata = @ptrCast(self),
            .function = keyCallback,
        };
    }

    pub fn deinit(self: *Input) void {
        self.* = .{};
    }

    fn keyCallback(userdata: ?*anyopaque, key: c_int, scan_code: c_int, action: c_int, mods: c_int) void {
        var self = @as(?*Input, @ptrCast(userdata)) orelse unreachable;

        std.debug.assert(key >= 0 and key < c.GLFW_KEY_LAST);
        self.keyboard.keys[@intCast(key)] = switch (action) {
            c.GLFW_RELEASE => .Released,
            c.GLFW_PRESS => .Pressed,
            c.GLFW_REPEAT => .Repeat,
            else => unreachable,
        };

        _ = mods;
        _ = scan_code;
    }
};
