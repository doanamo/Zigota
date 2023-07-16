const std = @import("std");
const builtin = @import("builtin");
const c = @import("c.zig");
const memory = @import("memory.zig");
const glfw = @import("glfw.zig");

const Config = @import("config.zig").Config;
const Application = @import("application.zig").Application;

pub var config = Config{};
pub const project_name = "Zigota";
pub const project_version = std.SemanticVersion{
    .major = 0,
    .minor = 1,
    .patch = 0,
};

const log = std.log.scoped(.Main);

pub fn main() !void {
    log.info("Starting {s} {}...", .{ project_name, project_version });
    log.debug("Debug logging enabled", .{});

    // Setup memory
    memory.setupMimalloc();

    // Load config
    try config.init();

    // Initialize GLFW
    try glfw.init();
    defer glfw.deinit();

    // Create application
    var application = Application{};
    try application.init();
    defer application.deinit();

    // Main loop
    log.info("Starting main loop...", .{});
    application.window.show();

    var timer = try std.time.Timer.start();
    while (!application.window.shouldClose()) {
        glfw.pollEvents();

        const time_delta: f32 = @floatCast(@as(f64, @floatFromInt(timer.lap())) / @as(f64, @floatFromInt(std.time.ns_per_s)));

        try application.update(time_delta);
        try application.render();
    }

    log.info("Exiting application...", .{});
}
