const std = @import("std");
const c = @import("../c.zig");
const memory = @import("memory.zig");
const utility = @import("utility.zig");
const log = std.log.scoped(.Vulkan);
const check = utility.vulkanCheckResult;

const Vulkan = @import("../vulkan.zig").Vulkan;
const Device = @import("device.zig").Device;
const Buffer = @import("buffer.zig").Buffer;
const DescriptorPool = @import("descriptor_pool.zig").DescriptorPool;

pub const Bindless = struct {
    pub const IdentifierType = u32;

    pub const descriptor_count = std.math.maxInt(u16);
    pub const invalid_id = std.math.maxInt(u16);

    const uniform_buffer_binding = 0;

    vulkan: *Vulkan = undefined,
    descriptor_pool: DescriptorPool = .{},
    descriptor_set_layout: c.VkDescriptorSetLayout = null,
    descriptor_set: c.VkDescriptorSet = null,
    pipeline_layout: c.VkPipelineLayout = null,

    uniform_buffers_next_id: u32 = 0,
    uniform_buffers_free_ids: std.fifo.LinearFifo(u32, .Dynamic) = undefined,

    uniform_buffer_infos: std.ArrayListUnmanaged(c.VkDescriptorBufferInfo) = .{},
    descriptor_set_writes: std.ArrayListUnmanaged(c.VkWriteDescriptorSet) = .{},

    pub fn init(self: *Bindless, vulkan: *Vulkan) !void {
        log.info("Initializing bindless...", .{});
        errdefer self.deinit();

        self.vulkan = vulkan;
        self.uniform_buffers_free_ids = @TypeOf(self.uniform_buffers_free_ids).init(memory.default_allocator);

        self.createDescriptorPool() catch |err| {
            log.err("Failed to create descriptor pool: {}", .{err});
            return error.FailedToCreateDescriptorPool;
        };

        self.createDescriptorSetLayout() catch |err| {
            log.err("Failed to create descriptor set layout: {}", .{err});
            return error.FailedToCreateDescriptorSetLayout;
        };

        self.allocateDescriptorSet() catch |err| {
            log.err("Failed to allocate descriptor set: {}", .{err});
            return error.FailedToAllocateDescriptorSet;
        };

        self.createPipelineLayout() catch |err| {
            log.err("Failed to create pipeline layout: {}", .{err});
            return error.FailedToCreatePipelineLayout;
        };
    }

    pub fn deinit(self: *Bindless) void {
        // Allocated descriptor set is freed when the descriptor pool is destroyed.
        self.uniform_buffer_infos.deinit(memory.default_allocator);
        self.descriptor_set_writes.deinit(memory.default_allocator);
        self.uniform_buffers_free_ids.deinit();
        self.destroyPipelineLayout();
        self.destroyDescriptorSetLayout();
        self.destroyDescriptorPool();
        self.* = .{};
    }

    fn createDescriptorPool(self: *Bindless) !void {
        try self.descriptor_pool.init(self.vulkan, .{
            .max_set_count = 1,
            .pool_sizes = &[_]c.VkDescriptorPoolSize{
                .{
                    .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                    .descriptorCount = descriptor_count,
                },
            },
            .flags = c.VK_DESCRIPTOR_POOL_CREATE_UPDATE_AFTER_BIND_BIT,
        });
    }

    fn destroyDescriptorPool(self: *Bindless) void {
        self.descriptor_pool.deinit();
    }

    fn createDescriptorSetLayout(self: *Bindless) !void {
        const layout_bindings = [_]c.VkDescriptorSetLayoutBinding{
            .{
                .binding = uniform_buffer_binding,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .descriptorCount = descriptor_count,
                .stageFlags = c.VK_SHADER_STAGE_ALL,
                .pImmutableSamplers = null,
            },
        };

        const binding_flags = [_]c.VkDescriptorBindingFlags{
            c.VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT | c.VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT,
        };

        const layout_binding_flags_create_info = c.VkDescriptorSetLayoutBindingFlagsCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
            .pNext = null,
            .bindingCount = @intCast(binding_flags.len),
            .pBindingFlags = &binding_flags,
        };

        const layout_create_info = c.VkDescriptorSetLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .pNext = &layout_binding_flags_create_info,
            .flags = c.VK_DESCRIPTOR_SET_LAYOUT_CREATE_UPDATE_AFTER_BIND_POOL_BIT,
            .bindingCount = @intCast(layout_bindings.len),
            .pBindings = &layout_bindings,
        };

        try check(c.vkCreateDescriptorSetLayout.?(self.vulkan.device.handle, &layout_create_info, memory.vulkan_allocator, &self.descriptor_set_layout));
    }

    fn destroyDescriptorSetLayout(self: *Bindless) void {
        if (self.descriptor_set_layout != null) {
            c.vkDestroyDescriptorSetLayout.?(self.vulkan.device.handle, self.descriptor_set_layout, memory.vulkan_allocator);
        }
    }

    fn allocateDescriptorSet(self: *Bindless) !void {
        const allocate_info = c.VkDescriptorSetAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .pNext = null,
            .descriptorPool = self.descriptor_pool.handle,
            .descriptorSetCount = 1,
            .pSetLayouts = &self.descriptor_set_layout,
        };

        try check(c.vkAllocateDescriptorSets.?(self.vulkan.device.handle, &allocate_info, &self.descriptor_set));
    }

    fn createPipelineLayout(self: *Bindless) !void {
        const pipeline_layout_create_info = c.VkPipelineLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .setLayoutCount = 1,
            .pSetLayouts = &self.descriptor_set_layout,
            .pushConstantRangeCount = 1,
            .pPushConstantRanges = &c.VkPushConstantRange{
                .stageFlags = c.VK_SHADER_STAGE_ALL,
                .offset = 0,
                .size = 128, // Guaranteed minimum size by specification.
            },
        };

        try check(c.vkCreatePipelineLayout.?(self.vulkan.device.handle, &pipeline_layout_create_info, memory.vulkan_allocator, &self.pipeline_layout));
    }

    fn destroyPipelineLayout(self: *Bindless) void {
        if (self.pipeline_layout != null) {
            c.vkDestroyPipelineLayout.?(self.vulkan.device.handle, self.pipeline_layout, memory.vulkan_allocator);
        }
    }

    pub fn registerResource(self: *Bindless, resource: anytype) !IdentifierType {
        const bindless_id = switch (@TypeOf(resource)) {
            *Buffer => blk: {
                if (resource.usage_flags & c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT != 0) {
                    break :blk self.registerUniformBuffer(resource);
                } else {
                    log.err("Bindless resource not supported for this buffer usage", .{});
                    return error.UnsupportedBindlessBufferUsage;
                }
            },
            else => @compileError("Unsupported resource typer, found '" ++ @typeName(@TypeOf(resource)) ++ "'"),
        };

        std.debug.assert(bindless_id != Bindless.invalid_id);
        return bindless_id;
    }

    pub fn unregisterResource(self: *Bindless, resource: anytype, bindless_id: IdentifierType) void {
        std.debug.assert(bindless_id < invalid_id);

        switch (@TypeOf(resource)) {
            *Buffer => {
                if (resource.usage_flags & c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT != 0) {
                    self.unregisterUniformBuffer(bindless_id);
                } else {
                    unreachable;
                }
            },
            else => @compileError("Unsupported resource typer, found '" ++ @typeName(@TypeOf(resource)) ++ "'"),
        }
    }

    fn registerUniformBuffer(self: *Bindless, uniform_buffer: *Buffer) IdentifierType {
        std.debug.assert(uniform_buffer.handle != null);
        std.debug.assert(uniform_buffer.usage_flags & c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT != 0);

        var bindless_id: u32 = undefined;
        if (self.uniform_buffers_free_ids.count > 0) {
            bindless_id = self.uniform_buffers_free_ids.readItem().?;
        } else {
            bindless_id = self.uniform_buffers_next_id;
            self.uniform_buffers_next_id += 1;
        }

        std.debug.assert(bindless_id < invalid_id);

        var uniform_buffer_info = self.uniform_buffer_infos.addOne(memory.default_allocator) catch unreachable;
        var write_descriptor_set = self.descriptor_set_writes.addOne(memory.default_allocator) catch unreachable;

        uniform_buffer_info.* = c.VkDescriptorBufferInfo{
            .buffer = uniform_buffer.handle,
            .offset = 0,
            .range = c.VK_WHOLE_SIZE,
        };

        write_descriptor_set.* = c.VkWriteDescriptorSet{
            .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .pNext = null,
            .dstSet = self.descriptor_set,
            .dstBinding = uniform_buffer_binding,
            .dstArrayElement = bindless_id,
            .descriptorCount = 1,
            .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .pImageInfo = null,
            .pBufferInfo = uniform_buffer_info,
            .pTexelBufferView = null,
        };

        return bindless_id;
    }

    fn unregisterUniformBuffer(self: *Bindless, bindless_id: IdentifierType) void {
        std.debug.assert(bindless_id < self.uniform_buffers_next_id);
        self.uniform_buffers_free_ids.writeItem(bindless_id) catch unreachable;
    }

    pub fn updateDescriptorSet(self: *Bindless) void {
        if (self.descriptor_set_writes.items.len > 0) {
            c.vkUpdateDescriptorSets.?(self.vulkan.device.handle, @intCast(self.descriptor_set_writes.items.len), self.descriptor_set_writes.items.ptr, 0, null);
        }

        self.uniform_buffer_infos.clearRetainingCapacity();
        self.descriptor_set_writes.clearRetainingCapacity();
    }
};
