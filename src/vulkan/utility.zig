pub usingnamespace @import("../utility.zig");
const std = @import("std");
const c = @import("../c.zig");

pub const log_scoped = std.log.scoped(.Vulkan);
pub var last_result = c.VK_SUCCESS;

pub fn checkResult(result: c.VkResult) !void {
    last_result = result;

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
