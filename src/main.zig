const c = @import("c.zig");
const std = @import("std");
const builtin = @import("builtin");
const memory = @import("memory.zig");
const glfw = @import("glfw.zig");
const vulkan = @import("vulkan.zig");

var allocator: std.mem.Allocator = memory.MimallocAllocator;

const log_level: std.log.Level = if (std.builtin.mode == .Debug) .debug else .info;
const log_scoped = std.log.scoped(.Main);

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

    const window_title = try std.fmt.bufPrintZ(window_title_buffer, "Game - {s}", .{@tagName(builtin.mode)});
    var window_config = glfw.WindowConfig{
        .title = window_title,
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
    window.show();

    while (!window.shouldClose()) {
        glfw.pollEvents();
        try vulkan.render();
    }

    log_scoped.info("Exiting application...", .{});
}
