const std = @import("std");
const c = @import("../c.zig");
const memory = @import("memory.zig");
const utility = @import("utility.zig");
const log = std.log.scoped(.Vulkan);
const check = utility.vulkanCheckResult;
const checkSpv = utility.spvReflectCheckResult;

const Device = @import("device.zig").Device;

pub const ShaderStage = enum(c.VkShaderStageFlagBits) {
    Vertex = c.VK_SHADER_STAGE_VERTEX_BIT,
    Fragment = c.VK_SHADER_STAGE_FRAGMENT_BIT,
};

pub const ShaderModule = struct {
    const ByteCode = []align(@alignOf(u32)) u8;

    handle: c.VkShaderModule = null,
    reflect: c.SpvReflectShaderModule = std.mem.zeroes(c.SpvReflectShaderModule),
    byte_code: ByteCode = &.{},
    device: *Device = undefined,

    pub fn loadFromFile(device: *Device, path: []const u8) !ShaderModule {
        const byte_code = std.fs.cwd().readFileAllocOptions(
            memory.frame_allocator,
            path,
            utility.megabytes(1),
            null,
            @alignOf(u32),
            null,
        ) catch |err| {
            log.err("Failed to load shader byte code from \"{s}\" file: {}", .{ path, err });
            return error.FailedToLoadShaderByteCodeFromFile;
        };
        defer memory.frame_allocator.free(byte_code);

        var shader_module = ShaderModule.init(device, byte_code) catch |err| {
            log.err("Failed to create shader module from \"{s}\" file: {}", .{ path, err });
            return error.FailedToCreateShaderModuleFromFile;
        };

        log.info("Loaded shader module from \"{s}\" file", .{path});
        return shader_module;
    }

    pub fn init(device: *Device, byte_code: ByteCode) !ShaderModule {
        var self = ShaderModule{};
        errdefer self.deinit();

        self.device = device;

        self.createShaderModule(byte_code) catch |err| {
            log.err("Failed to create shader module: {}", .{err});
            return error.FailedToCreateShaderModule;
        };

        self.createReflection(byte_code) catch |err| {
            log.err("Failed to create shader module reflection: {}", .{err});
            return error.FailedToCreateShaderModuleReflection;
        };

        return self;
    }

    pub fn deinit(self: *ShaderModule) void {
        self.destroyReflection();
        self.destroyShaderModule();
        self.* = undefined;
    }

    fn createShaderModule(self: *ShaderModule, byte_code: ByteCode) !void {
        const create_info = &c.VkShaderModuleCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .codeSize = byte_code.len,
            .pCode = std.mem.bytesAsSlice(u32, byte_code).ptr,
        };

        try check(c.vkCreateShaderModule.?(self.device.handle, create_info, memory.vulkan_allocator, &self.handle));
    }

    fn destroyShaderModule(self: *ShaderModule) void {
        if (self.handle != null) {
            c.vkDestroyShaderModule.?(self.device.handle, self.handle, memory.vulkan_allocator);
        }
    }

    fn createReflection(self: *ShaderModule, byte_code: ByteCode) !void {
        self.byte_code = try memory.default_allocator.alignedAlloc(u8, @alignOf(u32), byte_code.len);
        @memcpy(self.byte_code, byte_code);

        try checkSpv(c.spvReflectCreateShaderModule2(c.SPV_REFLECT_MODULE_FLAG_NO_COPY, self.byte_code.len, self.byte_code.ptr, &self.reflect));
    }

    fn destroyReflection(self: *ShaderModule) void {
        c.spvReflectDestroyShaderModule(&self.reflect);

        if (self.byte_code.len != 0) {
            memory.default_allocator.free(self.byte_code);
        }
    }
};
