const c = @import("c.zig");
const std = @import("std");
const utility = @import("utility.zig");
const log = std.log.scoped(.GLFW);

pub const WindowConfig = @import("glfw/window.zig").WindowConfig;
pub const Window = @import("glfw/window.zig").Window;

pub fn init() !void {
    log.info("Initializing...", .{});
    errdefer deinit();

    // TODO Waiting for GLFW 3.4.0
    // allocator_callbacks = .{
    //     .allocate = &allocateCallback,
    //     .reallocate = &reallocateCallback,
    //     .free = &freeCallback,
    //     .user = null,
    // };
    // c.glfwInitAllocator(&allocator_callbacks);

    if (c.glfwInit() == c.GLFW_FALSE) {
        log.err("Failed to initialize library", .{});
        return error.FailedToInitializeGLFWLibrary;
    }

    _ = c.glfwSetErrorCallback(errorCallback);

    var glfwVersionMajor: c_int = undefined;
    var glfwVersionMinor: c_int = undefined;
    var glfwVersionPatch: c_int = undefined;
    c.glfwGetVersion(&glfwVersionMajor, &glfwVersionMinor, &glfwVersionPatch);
    log.info("Initialized version {}.{}.{}", .{
        glfwVersionMajor, glfwVersionMinor, glfwVersionPatch,
    });
}

pub fn deinit() void {
    log.info("Deinitializing...", .{});
    c.glfwTerminate();
}

pub fn pollEvents() void {
    c.glfwPollEvents();
}

fn errorCallback(error_code: c_int, description: [*c]const u8) callconv(.C) void {
    log.err("{s} (Code: {})", .{ description, error_code });
}
