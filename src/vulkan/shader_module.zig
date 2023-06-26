const std = @import("std");
const c = @import("../c.zig");
const glfw = @import("../glfw.zig");
const utility = @import("utility.zig");
const memory = @import("memory.zig");
const log = utility.log_scoped;

const Device = @import("device.zig").Device;

pub const ShaderModule = struct {
    const ByteCode = []align(@alignOf(u32)) u8;

    handle: c.VkShaderModule = null,

    pub fn loadFromFile(device: *Device, path: []const u8, allocator: std.mem.Allocator) !ShaderModule {
        log.info("Loading shader module from \"{s}\" file...", .{path});

        const byte_code = try std.fs.cwd().readFileAllocOptions(
            allocator,
            path,
            utility.megabytes(1),
            null,
            @alignOf(u32),
            null,
        );
        defer allocator.free(byte_code);

        return try init(device, byte_code);
    }

    pub fn init(device: *Device, bytes: ByteCode) !ShaderModule {
        var self = ShaderModule{};
        errdefer self.deinit(device);

        self.createShaderModule(device, bytes) catch {
            log.err("Failed to create shader module", .{});
            return error.FailedToCreateShaderModule;
        };

        return self;
    }

    pub fn deinit(self: *ShaderModule, device: *Device) void {
        self.destroyShaderModule(device);
        self.* = undefined;
    }

    fn createShaderModule(self: *ShaderModule, device: *Device, bytes: ByteCode) !void {
        log.info("Creatng shader module...", .{});

        const create_info = &c.VkShaderModuleCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .codeSize = bytes.len,
            .pCode = std.mem.bytesAsSlice(u32, bytes).ptr,
        };

        try utility.checkResult(c.vkCreateShaderModule.?(device.handle, create_info, memory.vulkan_allocator, &self.handle));
    }

    fn destroyShaderModule(self: *ShaderModule, device: *Device) void {
        if (self.handle != null) {
            c.vkDestroyShaderModule.?(device.handle, self.handle, memory.vulkan_allocator);
        }
    }
};
