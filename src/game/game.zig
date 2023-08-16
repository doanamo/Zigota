const std = @import("std");
const memory = @import("../memory.zig");
const utility = @import("../utility.zig");

pub const Game = struct {
    pub fn init(self: *Game) !void {
        _ = self;
    }

    pub fn deinit(self: *Game) void {
        _ = self;
    }

    pub fn update(self: *Game, time_delta: f32) void {
        _ = self;
        _ = time_delta;
    }
};
