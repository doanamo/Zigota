const c = @import("c.zig");
const std = @import("std");
const builtin = @import("builtin");
const memory = @import("memory.zig");
const glfw = @import("glfw.zig");
const vulkan = @import("vulkan.zig");

const allocator: std.mem.Allocator = memory.MimallocAllocator;
const log_scoped = std.log.scoped(.Main);

fn formatWindowTitle(buffer: []u8, title: []const u8, time_delta: f32) ![:0]u8 {
    return try std.fmt.bufPrintZ(buffer, "{s} - {s} - FPS: {} ({d:.2}ms)", .{
        title,
        @tagName(builtin.mode),
        if (time_delta != 0) @floatToInt(u32, @round(1.0 / time_delta)) else 0,
        time_delta * std.time.ms_per_s,
    });
}

pub fn main() !void {
    log_scoped.info("Starting application...", .{});
    log_scoped.debug("Debug logging enabled", .{});

    // Initialize memory allocator
    try memory.init();
    defer memory.deinit();

    // Initialize GLFW
    try glfw.init();
    defer glfw.deinit();

    // Create window
    var window_title_buffer = try allocator.alloc(u8, 256);
    defer allocator.free(window_title_buffer);

    const window_title = "Game";
    var window_config = glfw.WindowConfig{
        .title = try formatWindowTitle(window_title_buffer, window_title, 0.0),
        .width = 1024,
        .height = 576,
        .resizable = true,
        .visible = false,
    };

    var window = try glfw.Window.init(&window_config);
    defer window.deinit();

    // Initialize Vulkan
    try vulkan.init(window, allocator);
    defer vulkan.deinit();

    // Main loop
    var frame_timer = try std.time.Timer.start();
    var frame_time_previous_ns = frame_timer.read();
    var frame_time_delta: f32 = 0.0;
    var fps_stat_refresh: f32 = 0.0;

    window.show();
    while (!window.shouldClose()) {
        fps_stat_refresh += frame_time_delta;
        if (fps_stat_refresh >= 1.0) {
            window.setTitle(try formatWindowTitle(window_title_buffer, window_title, frame_time_delta));
            fps_stat_refresh = 0.0;
        }

        glfw.pollEvents();
        try vulkan.render();

        const time_current_ns = frame_timer.read();
        const time_elapsed_ns = @intToFloat(f64, time_current_ns - frame_time_previous_ns);
        frame_time_delta = @floatCast(f32, time_elapsed_ns / @intToFloat(f64, std.time.ns_per_s));
        frame_time_previous_ns = time_current_ns;
    }

    log_scoped.info("Exiting application...", .{});
}
