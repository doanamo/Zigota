const std = @import("std");
const c = @import("../c.zig");
const utility = @import("utility.zig");
const memory = @import("memory.zig");
const log = utility.log_scoped;

const Device = @import("device.zig").Device;

pub const ShaderModule = struct {
    const ByteCode = []align(@alignOf(u32)) u8;

    handle: c.VkShaderModule = null,
    device: *Device = undefined,

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

        var shader_module: ShaderModule = .{};
        try shader_module.init(device, byte_code);
        return shader_module;
    }

    pub fn init(self: *ShaderModule, device: *Device, bytes: ByteCode) !void {
        self.device = device;
        errdefer self.deinit();

        self.createShaderModule(bytes) catch {
            log.err("Failed to create shader module", .{});
            return error.FailedToCreateShaderModule;
        };
    }

    pub fn deinit(self: *ShaderModule) void {
        self.destroyShaderModule();
        self.* = undefined;
    }

    fn createShaderModule(self: *ShaderModule, bytes: ByteCode) !void {
        log.info("Creating shader module...", .{});

        const create_info = &c.VkShaderModuleCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .codeSize = bytes.len,
            .pCode = std.mem.bytesAsSlice(u32, bytes).ptr,
        };

        try utility.checkResult(c.vkCreateShaderModule.?(self.device.handle, create_info, memory.allocation_callbacks, &self.handle));
    }

    fn destroyShaderModule(self: *ShaderModule) void {
        if (self.handle != null) {
            c.vkDestroyShaderModule.?(self.device.handle, self.handle, memory.allocation_callbacks);
        }
    }
};
