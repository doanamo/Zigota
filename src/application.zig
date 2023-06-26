const std = @import("std");
const log = std.log.scoped(.Application);

pub const Application = struct {
    pub fn init() !Application {
        log.info("Initializing...", .{});

        var self = Application{};
        errdefer self.deinit();

        return self;
    }

    pub fn deinit(self: *Application) void {
        log.info("Deinitializing...", .{});
        _ = self;
    }

    pub fn onResize(self: *Application, width: u32, height: u32) void {
        _ = self;
        _ = height;
        _ = width;
    }

    pub fn onUpdate(self: *Application, time_delta: f32) void {
        _ = self;
        _ = time_delta;
    }

    pub fn onRender(self: *Application, time_alpha: f32) void {
        _ = self;
        _ = time_alpha;
    }
};
