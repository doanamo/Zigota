const std = @import("std");
const c = @import("../cimport/c.zig");
const log = std.log.scoped(.GLFW);

pub fn init() !void {
    log.info("Initializing...", .{});
    errdefer deinit();

    if (c.glfwInit() == c.GLFW_FALSE) {
        log.err("Failed to initialize GLFW library", .{});
        return error.FailedToInitializeGLFWLibrary;
    }

    _ = c.glfwSetErrorCallback(errorCallback);

    var glfwVersionMajor: c_int = undefined;
    var glfwVersionMinor: c_int = undefined;
    var glfwVersionPatch: c_int = undefined;
    c.glfwGetVersion(&glfwVersionMajor, &glfwVersionMinor, &glfwVersionPatch);
    log.info("Initialized GLFW version {}.{}.{}", .{
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
