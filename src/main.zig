const c = @import("c.zig");
const std = @import("std");
const builtin = @import("builtin");
const memory = @import("memory.zig");
const glfw = @import("glfw.zig");
const vulkan = @import("vulkan.zig");

const allocator: std.mem.Allocator = memory.MimallocAllocator;
const log_scoped = std.log.scoped(.Main);

fn formatWindowTitle(buffer: []u8, title: []const u8, fps_count: f32, frame_time: f32) ![:0]u8 {
    return try std.fmt.bufPrintZ(buffer, "{s} - {s} - FPS: {d:.0} ({d:.2}ms)", .{
        title,
        @tagName(builtin.mode),
        fps_count,
        frame_time * std.time.ms_per_s,
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

    const window_title = "Zigota";
    var window_config = glfw.WindowConfig{
        .title = try formatWindowTitle(window_title_buffer, window_title, 0.0, 0.0),
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
    var timer = try std.time.Timer.start();
    var time_previous_ns = timer.read();
    var time_current_ns = time_previous_ns;

    var fps_count: u32 = 0;
    var fps_time: f32 = 0.0;

    window.show();
    while (!window.shouldClose()) {
        const time_elapsed_ns = @intToFloat(f64, time_current_ns - time_previous_ns);
        const time_delta = @floatCast(f32, time_elapsed_ns / @intToFloat(f64, std.time.ns_per_s));

        fps_time += time_delta;
        if (fps_time >= 1.0) {
            const fps_count_avg = @intToFloat(f32, fps_count) / fps_time;
            const frame_time_avg = fps_time / @intToFloat(f32, fps_count);
            window.setTitle(try formatWindowTitle(
                window_title_buffer,
                window_title,
                fps_count_avg,
                frame_time_avg,
            ));
            fps_count = 0;
            fps_time = 0.0;
        }

        glfw.pollEvents();
        try vulkan.render();

        time_previous_ns = time_current_ns;
        time_current_ns = timer.read();
        fps_count += 1;
    }

    log_scoped.info("Exiting application...", .{});
}
