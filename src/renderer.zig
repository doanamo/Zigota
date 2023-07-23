const std = @import("std");
const c = @import("c.zig");
const math = @import("math.zig");
const memory = @import("vulkan/memory.zig");
const utility = @import("vulkan/utility.zig");
const vertex_attributes = @import("vulkan/vertex_attributes.zig");
const log = std.log.scoped(.Renderer);
const check = utility.vulkanCheckResult;

const Window = @import("glfw/window.zig").Window;
const Vulkan = @import("vulkan.zig").Vulkan;
const CommandPool = @import("vulkan/command_pool.zig").CommandPool;
const CommandBuffer = @import("vulkan/command_buffer.zig").CommandBuffer;
const Buffer = @import("vulkan/buffer.zig").Buffer;
const DescriptorPool = @import("vulkan/descriptor_pool.zig").DescriptorPool;
const ShaderModule = @import("vulkan/shader_module.zig").ShaderModule;
const PipelineBuilder = @import("vulkan/pipeline.zig").PipelineBuilder;
const Pipeline = @import("vulkan/pipeline.zig").Pipeline;
const VertexTransformUniform = @import("renderer/uniform_types.zig").VertexTransformUniform;
const Mesh = @import("renderer/mesh.zig").Mesh;

pub const Renderer = struct {
    vulkan: Vulkan = .{},

    command_pools: std.ArrayListUnmanaged(CommandPool) = .{},
    command_buffers: std.ArrayListUnmanaged(CommandBuffer) = .{},
    uniform_buffers: std.ArrayListUnmanaged(Buffer) = .{},
    mesh: Mesh = .{},
    layout_descriptor_set: c.VkDescriptorSetLayout = null,
    layout_pipeline: c.VkPipelineLayout = null,
    descriptor_pool: DescriptorPool = .{},
    descriptor_sets: std.ArrayListUnmanaged(c.VkDescriptorSet) = .{},
    pipeline: Pipeline = .{},

    time: f32 = 0.0,

    pub fn init(self: *Renderer, window: *Window) !void {
        log.info("Initializing...", .{});
        errdefer self.deinit();

        self.vulkan.init(window) catch {
            log.err("Failed to initialize Vulkan", .{});
            return error.FailedToInitializeVulkan;
        };

        self.createCommandBuffers() catch {
            log.err("Failed to create command buffers", .{});
            return error.FailedToCreateCommandBuffers;
        };

        self.createBuffers() catch {
            log.err("Failed to create buffers", .{});
            return error.FailedToCreateBuffers;
        };

        self.createMesh() catch {
            log.err("Failed to create mesh", .{});
            return error.FailedToCreateMesh;
        };

        self.createLayouts() catch {
            log.err("Failed to create layouts", .{});
            return error.FailedToCreateLayouts;
        };

        self.createDescriptors() catch {
            log.err("Failed to create descriptors", .{});
            return error.FailedToCreateDescriptors;
        };

        self.createPipeline() catch {
            log.err("Failed to create pipeline", .{});
            return error.FailedToCreatePipeline;
        };
    }

    pub fn deinit(self: *Renderer) void {
        log.info("Deinitializing...", .{});

        self.vulkan.device.waitIdle();
        self.destroyPipeline();
        self.destroyDescriptors();
        self.destroyLayouts();
        self.destroyMesh();
        self.destroyBuffers();
        self.destroyCommandBuffers();
        self.vulkan.deinit();
    }

    pub fn recreateSwapchain(self: *Renderer) !void {
        self.vulkan.device.waitIdle();
        try self.vulkan.recreateSwapchain();
    }

    fn createCommandBuffers(self: *Renderer) !void {
        log.info("Creating command buffers...", .{});

        try self.command_pools.ensureTotalCapacityPrecise(memory.default_allocator, self.vulkan.swapchain.max_inflight_frames);
        for (0..self.vulkan.swapchain.max_inflight_frames) |_| {
            var command_pool = CommandPool{};
            try command_pool.init(&self.vulkan.device, .{
                .queue = .Graphics,
                .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            });
            self.command_pools.appendAssumeCapacity(command_pool);
        }

        try self.command_buffers.ensureTotalCapacityPrecise(memory.default_allocator, self.vulkan.swapchain.max_inflight_frames);
        for (self.command_pools.items) |*command_pool| {
            var command_buffer = try command_pool.createBuffer(c.VK_COMMAND_BUFFER_LEVEL_PRIMARY);
            self.command_buffers.appendAssumeCapacity(command_buffer);
        }
    }

    fn destroyCommandBuffers(self: *Renderer) void {
        for (self.command_buffers.items, 0..) |*command_buffer, i| {
            command_buffer.deinit(&self.vulkan.device, &self.command_pools.items[i]);
        }

        for (self.command_pools.items) |*command_pool| {
            command_pool.deinit();
        }

        self.command_buffers.deinit(memory.default_allocator);
        self.command_pools.deinit(memory.default_allocator);
    }

    fn createBuffers(self: *Renderer) !void {
        log.info("Creating buffers...", .{});

        try self.uniform_buffers.ensureTotalCapacityPrecise(memory.default_allocator, self.vulkan.swapchain.max_inflight_frames);
        for (0..self.vulkan.swapchain.max_inflight_frames) |_| {
            var uniform_buffer = Buffer{};
            try uniform_buffer.init(&self.vulkan.vma, .{
                .size = @sizeOf(VertexTransformUniform),
                .usage_flags = c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                .memory_flags = c.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT | c.VMA_ALLOCATION_CREATE_MAPPED_BIT,
            });
            self.uniform_buffers.appendAssumeCapacity(uniform_buffer);
        }
    }

    fn destroyBuffers(self: *Renderer) void {
        for (self.uniform_buffers.items) |*uniform_buffer| {
            uniform_buffer.deinit();
        }
        self.uniform_buffers.deinit(memory.default_allocator);
    }

    fn createMesh(self: *Renderer) !void {
        log.info("Creating mesh...", .{});

        self.mesh.loadFromFile(&self.vulkan, "data/meshes/cube.bin") catch |err| {
            log.err("Failed to load mesh ({})", .{err});
            return error.FailedToLoadMesh;
        };
    }

    fn destroyMesh(self: *Renderer) void {
        self.mesh.deinit();
    }

    fn createLayouts(self: *Renderer) !void {
        log.info("Creating layouts...", .{});

        const descriptor_set_layout_binding = c.VkDescriptorSetLayoutBinding{
            .binding = 0,
            .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = 1,
            .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
            .pImmutableSamplers = null,
        };

        const descriptor_set_layout_create_info = c.VkDescriptorSetLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .bindingCount = 1,
            .pBindings = &descriptor_set_layout_binding,
        };

        try check(c.vkCreateDescriptorSetLayout.?(self.vulkan.device.handle, &descriptor_set_layout_create_info, memory.vulkan_allocator, &self.layout_descriptor_set));

        const pipeline_layout_create_info = c.VkPipelineLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .setLayoutCount = 1,
            .pSetLayouts = &self.layout_descriptor_set,
            .pushConstantRangeCount = 0,
            .pPushConstantRanges = null,
        };

        try check(c.vkCreatePipelineLayout.?(self.vulkan.device.handle, &pipeline_layout_create_info, memory.vulkan_allocator, &self.layout_pipeline));
    }

    fn destroyLayouts(self: *Renderer) void {
        if (self.layout_descriptor_set != null) {
            c.vkDestroyDescriptorSetLayout.?(self.vulkan.device.handle, self.layout_descriptor_set, memory.vulkan_allocator);
        }

        if (self.layout_pipeline != null) {
            c.vkDestroyPipelineLayout.?(self.vulkan.device.handle, self.layout_pipeline, memory.vulkan_allocator);
        }
    }

    fn createDescriptors(self: *Renderer) !void {
        log.info("Creating descriptors...", .{});

        try self.descriptor_pool.init(&self.vulkan.device, .{
            .max_set_count = self.vulkan.swapchain.max_inflight_frames,
            .uniform_buffer_count = self.vulkan.swapchain.max_inflight_frames,
        });

        try self.descriptor_sets.ensureTotalCapacityPrecise(memory.default_allocator, self.vulkan.swapchain.max_inflight_frames);
        for (0..self.vulkan.swapchain.max_inflight_frames) |i| {
            const set_allocate_info = c.VkDescriptorSetAllocateInfo{
                .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
                .pNext = null,
                .descriptorPool = self.descriptor_pool.handle,
                .descriptorSetCount = 1,
                .pSetLayouts = &self.layout_descriptor_set,
            };

            var descriptor_set: c.VkDescriptorSet = undefined;
            try check(c.vkAllocateDescriptorSets.?(self.vulkan.device.handle, &set_allocate_info, &descriptor_set));
            self.descriptor_sets.appendAssumeCapacity(descriptor_set);

            const buffer_info = c.VkDescriptorBufferInfo{
                .buffer = self.uniform_buffers.items[i].handle,
                .offset = 0,
                .range = @sizeOf(VertexTransformUniform),
            };

            const write_set = c.VkWriteDescriptorSet{
                .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .pNext = null,
                .dstSet = descriptor_set,
                .dstBinding = 0,
                .dstArrayElement = 0,
                .descriptorCount = 1,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .pImageInfo = null,
                .pBufferInfo = &buffer_info,
                .pTexelBufferView = null,
            };

            c.vkUpdateDescriptorSets.?(self.vulkan.device.handle, 1, &write_set, 0, null);
        }
    }

    fn destroyDescriptors(self: *Renderer) void {
        // Descriptors sets will be deallocated automatically when the descriptor pool is destroyed
        self.descriptor_sets.deinit(memory.default_allocator);
        self.descriptor_pool.deinit();
    }

    fn createPipeline(self: *Renderer) !void {
        log.info("Creating pipeline...", .{});

        var builder = try PipelineBuilder.init(&self.vulkan.device);
        defer builder.deinit();

        try builder.loadShaderModule(.Vertex, "data/shaders/simple.vert.spv");
        try builder.loadShaderModule(.Fragment, "data/shaders/simple.frag.spv");

        try builder.addVertexAttribute(.Position, false);
        try builder.addVertexAttribute(.Normal, false);
        try builder.addVertexAttribute(.Color, false);

        builder.setDepthTest(true);
        builder.setDepthWrite(true);
        builder.setColorAttachmentFormat(self.vulkan.swapchain.image_format);
        builder.setDepthAttachmentFormat(self.vulkan.swapchain.depth_stencil_image_format);
        builder.setStencilAttachmentFormat(self.vulkan.swapchain.depth_stencil_image_format);
        builder.setPipelineLayout(self.layout_pipeline);

        self.pipeline = try builder.build();
    }

    fn destroyPipeline(self: *Renderer) void {
        self.pipeline.deinit();
    }

    fn updateUniformBuffer(self: *Renderer, uniform_buffer: *Buffer) !void {
        const window = self.vulkan.swapchain.window;
        const width: f32 = @floatFromInt(window.width);
        const height: f32 = @floatFromInt(window.height);

        const camera_position = math.Vec3{ 0.0, 0.0, -3.0 };

        const uniform_object = VertexTransformUniform{
            .model = math.rotation(math.Vec3{
                math.radians(30.0) * self.time,
                0.0,
                math.radians(30.0) * self.time,
            }),
            .view = math.translation(camera_position * math.splat3(-1.0)),
            .projection = math.perspectiveFov(math.radians(90.0), width / height, 0.0001, 1000.0),
        };

        try uniform_buffer.upload(std.mem.asBytes(&uniform_object), 0);
        try uniform_buffer.flush(0, c.VK_WHOLE_SIZE);
    }

    fn recordCommandBuffer(self: *Renderer, command_buffer: *CommandBuffer, frame_index: u32, image_index: u32) !void {
        var command_buffer_begin_info = c.VkCommandBufferBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .pNext = null,
            .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            .pInheritanceInfo = null,
        };

        try check(c.vkBeginCommandBuffer.?(command_buffer.handle, &command_buffer_begin_info));
        self.vulkan.transfer.recordOwnershipTransfers(command_buffer);
        self.vulkan.swapchain.recordLayoutTransitions(command_buffer, image_index);

        const color_attachment_info = c.VkRenderingAttachmentInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
            .pNext = null,
            .imageView = self.vulkan.swapchain.image_views.items[image_index],
            .imageLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            .resolveMode = c.VK_RESOLVE_MODE_NONE,
            .resolveImageView = null,
            .resolveImageLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
            .clearValue = c.VkClearValue{
                .color = c.VkClearColorValue{
                    .float32 = [_]f32{ 0.0, 0.0, 0.0, 1.0 },
                },
            },
        };

        const depth_stencil_attachment_info = c.VkRenderingAttachmentInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
            .pNext = null,
            .imageView = self.vulkan.swapchain.depth_stencil_image_view,
            .imageLayout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
            .resolveMode = c.VK_RESOLVE_MODE_NONE,
            .resolveImageView = null,
            .resolveImageLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
            .clearValue = c.VkClearValue{
                .depthStencil = c.VkClearDepthStencilValue{
                    .depth = 1.0,
                    .stencil = 0,
                },
            },
        };

        const rendering_info = c.VkRenderingInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDERING_INFO,
            .pNext = null,
            .flags = 0,
            .renderArea = c.VkRect2D{
                .offset = c.VkOffset2D{
                    .x = 0,
                    .y = 0,
                },
                .extent = self.vulkan.swapchain.extent,
            },
            .layerCount = 1,
            .viewMask = 0,
            .colorAttachmentCount = 1,
            .pColorAttachments = &color_attachment_info,
            .pDepthAttachment = &depth_stencil_attachment_info,
            .pStencilAttachment = &depth_stencil_attachment_info,
        };

        c.vkCmdBeginRendering.?(command_buffer.handle, &rendering_info);
        c.vkCmdBindPipeline.?(command_buffer.handle, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline.handle);

        c.vkCmdBindDescriptorSets.?(command_buffer.handle, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.layout_pipeline, 0, 1, &self.descriptor_sets.items[frame_index], 0, null);

        c.vkCmdSetViewport.?(command_buffer.handle, 0, 1, &c.VkViewport{
            .x = 0.0,
            .y = 0.0,
            .width = @floatFromInt(self.vulkan.swapchain.extent.width),
            .height = @floatFromInt(self.vulkan.swapchain.extent.height),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        });

        c.vkCmdSetScissor.?(command_buffer.handle, 0, 1, &c.VkRect2D{
            .offset = c.VkOffset2D{
                .x = 0,
                .y = 0,
            },
            .extent = self.vulkan.swapchain.extent,
        });

        var vertex_buffers = [_]c.VkBuffer{undefined} ** vertex_attributes.max_attributes;
        try self.mesh.fillVertexBufferHandles(&vertex_buffers);

        var vertex_offsets = [_]c.VkDeviceSize{undefined} ** vertex_attributes.max_attributes;
        try self.mesh.fillVertexBufferOffsets(&vertex_offsets);

        c.vkCmdBindVertexBuffers.?(command_buffer.handle, 0, self.mesh.getVertexAttributeCount(), &vertex_buffers, &vertex_offsets);
        c.vkCmdBindIndexBuffer.?(command_buffer.handle, self.mesh.index_buffer.handle, 0, self.mesh.getIndexFormat());
        c.vkCmdDrawIndexed.?(command_buffer.handle, self.mesh.getIndexCount(), 1, 0, 0, 0);

        c.vkCmdEndRendering.?(command_buffer.handle);
        try check(c.vkEndCommandBuffer.?(command_buffer.handle));
    }

    pub fn update(self: *Renderer, time_delta: f32) !void {
        self.time += time_delta;
    }

    pub fn render(self: *Renderer) !void {
        try self.vulkan.transfer.submit();

        const image_next = self.vulkan.swapchain.acquireNextImage() catch |err| {
            if (err == error.SwapchainOutOfDate) {
                try self.recreateSwapchain();
                return;
            } else {
                return err;
            }
        };

        const frame_index = self.vulkan.swapchain.frame_index;
        var command_pool = self.command_pools.items[frame_index];
        try command_pool.reset();

        var uniform_buffer = &self.uniform_buffers.items[frame_index];
        try self.updateUniformBuffer(uniform_buffer);

        var command_buffer = &self.command_buffers.items[frame_index];
        try self.recordCommandBuffer(command_buffer, frame_index, image_next.index);

        const submit_wait_semaphores = [_]c.VkSemaphore{
            self.vulkan.transfer.finished_semaphore,
            image_next.available_semaphore,
        };

        const submit_wait_sempahore_values = [_]u64{
            self.vulkan.transfer.finished_semaphore_index,
            0,
        };

        const submit_wait_stages = [_]c.VkPipelineStageFlags{
            c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
            c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        };

        const submit_command_buffers = [_]c.VkCommandBuffer{
            command_buffer.handle,
        };

        const submit_signal_semaphores = [_]c.VkSemaphore{
            image_next.finished_semaphore,
        };

        const timeline_semaphore_submit_info = c.VkTimelineSemaphoreSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO,
            .pNext = null,
            .waitSemaphoreValueCount = submit_wait_sempahore_values.len,
            .pWaitSemaphoreValues = &submit_wait_sempahore_values,
            .signalSemaphoreValueCount = 0,
            .pSignalSemaphoreValues = null,
        };

        const submit_info = c.VkSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .pNext = &timeline_semaphore_submit_info,
            .waitSemaphoreCount = submit_wait_semaphores.len,
            .pWaitSemaphores = &submit_wait_semaphores,
            .pWaitDstStageMask = &submit_wait_stages,
            .commandBufferCount = submit_command_buffers.len,
            .pCommandBuffers = &submit_command_buffers,
            .signalSemaphoreCount = submit_signal_semaphores.len,
            .pSignalSemaphores = &submit_signal_semaphores,
        };

        try self.vulkan.device.submit(.{
            .queue_type = .Graphics,
            .submit_count = 1,
            .submit_info = &submit_info,
            .fence = image_next.inflight_fence,
        });

        const present_info = c.VkPresentInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .pNext = null,
            .waitSemaphoreCount = submit_signal_semaphores.len,
            .pWaitSemaphores = &submit_signal_semaphores,
            .swapchainCount = 1,
            .pSwapchains = &self.vulkan.swapchain.handle,
            .pImageIndices = &image_next.index,
            .pResults = null,
        };

        self.vulkan.swapchain.present(&present_info) catch |err| {
            if (err == error.SwapchainOutOfDate or err == error.SwapchainSuboptimal) {
                try self.recreateSwapchain();
                return;
            }
            return err;
        };
    }
};
