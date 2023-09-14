const std = @import("std");
const builtin = @import("builtin");
const c = @import("cimport/c.zig");
const memory = @import("common/memory.zig");
const log = std.log.scoped(.Main);

const glfw = @import("glfw/glfw.zig");
const Config = @import("config.zig").Config;
const Application = @import("application.zig").Application;

pub var config = Config{};
pub const project_name = "Zigota";
pub const project_version = std.SemanticVersion{
    .major = 0,
    .minor = 1,
    .patch = 0,
};

pub fn main() !void {
    log.info("Starting {s} {}...", .{ project_name, project_version });
    log.debug("Debug logging enabled", .{});

    // Core memory
    try memory.init();
    defer memory.deinit();

    // Initialize GLFW
    try glfw.init();
    defer glfw.deinit();

    // Load config
    try config.load();

    // Create application
    var application = Application{};
    defer application.deinit();
    try application.init();

    // Main loop
    log.info("Starting main loop...", .{});
    application.window.show();

    var timer = try std.time.Timer.start();
    while (!application.window.shouldClose()) {
        glfw.pollEvents();

        const time_delta: f32 = @floatCast(@as(f64, @floatFromInt(timer.lap())) / @as(f64, @floatFromInt(std.time.ns_per_s)));

        try application.update(time_delta);
        try application.render();

        _ = memory.frame_arena_allocator.reset(.retain_capacity);
    }

    // Exit
    log.info("Exiting application...", .{});
}

test "main" {
    _ = @import("common/common.zig");
}
