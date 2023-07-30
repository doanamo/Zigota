pub usingnamespace @import("../utility.zig");

const std = @import("std");
const c = @import("../c.zig");

pub fn vulkanCheckResult(result: c.VkResult) !void {
    switch (result) {
        c.VK_SUCCESS => return,
        else => {
            if (std.debug.runtime_safety) {
                @breakpoint();
            }
            return error.VulkanError;
        },
    }
}

pub fn spvReflectCheckResult(result: c.SpvReflectResult) !void {
    switch (result) {
        c.SPV_REFLECT_RESULT_SUCCESS => return,
        else => {
            if (std.debug.runtime_safety) {
                @breakpoint();
            }
            return error.SpvReflectError;
        },
    }
}
