const std = @import("std");
const memory = @import("../memory.zig");
const utility = @import("../utility.zig");
const log = std.log.scoped(.Game);

const Input = @import("../glfw/input.zig").Input;

pub const Game = struct {
    input: *Input = undefined,

    pub fn init(self: *Game, input: *Input) !void {
        log.info("Initializing game...", .{});
        errdefer self.deinit();

        self.input = input;
    }

    pub fn deinit(self: *Game) void {
        log.info("Deinitializing game...", .{});
        self.* = .{};
    }

    pub fn update(self: *Game, time_delta: f32) void {
        _ = self;
        _ = time_delta;
    }
};
