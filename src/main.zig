const std = @import("std");
const builtin = @import("builtin");
const c = @import("c.zig");
const memory = @import("memory.zig");
const glfw = @import("glfw.zig");

const Application = @import("application.zig").Application;

pub const project_name = "Zigota";
pub const project_version = .{
    .major = 0,
    .minor = 1,
    .patch = 0,
};

const allocator = memory.default_allocator;
const log = std.log.scoped(.Main);

pub fn main() !void {
    log.info("Starting {s} {}.{}.{}...", .{
        project_name,
        project_version.major,
        project_version.minor,
        project_version.patch,
    });
    log.debug("Debug logging enabled", .{});

    // TODO Add simple config loaded from json file

    // Setup memory
    memory.setupMimalloc();

    // Initialize GLFW
    try glfw.init();
    defer glfw.deinit();

    // Create application
    var application = Application{};
    try application.init(allocator);
    defer application.deinit();

    // Main loop
    log.info("Starting main loop...", .{});

    var timer = try std.time.Timer.start();
    var time_previous_ns = timer.read();
    var time_current_ns = time_previous_ns;

    application.window.show();
    while (!application.window.shouldClose()) {
        glfw.pollEvents();

        // TODO Encapsulate into timer class
        const time_delta = @floatCast(f32, @intToFloat(f64, time_current_ns - time_previous_ns) / @intToFloat(f64, std.time.ns_per_s));

        try application.update(time_delta);
        try application.render(1.0);

        time_previous_ns = time_current_ns;
        time_current_ns = timer.read();
    }

    log.info("Exiting application...", .{});
}
