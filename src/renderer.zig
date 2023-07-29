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
    const Frame = struct {
        command_pool: CommandPool = .{},
        command_buffer: CommandBuffer = .{},
        uniform_buffer: Buffer = .{},
        descriptor_set: c.VkDescriptorSet = null,
    };

    vulkan: Vulkan = .{},

    descriptor_pool: DescriptorPool = .{},
    descriptor_set_layout: c.VkDescriptorSetLayout = null,
    pipeline_layout: c.VkPipelineLayout = null,
    pipeline: Pipeline = .{},
    frames: std.ArrayListUnmanaged(Frame) = .{},

    mesh: Mesh = .{},
    time: f32 = 0.0,

    pub fn init(window: *Window) !Renderer {
        log.info("Initializing...", .{});

        var self = Renderer{};
        errdefer self.deinit();

        self.vulkan = Vulkan.init(window) catch |err| {
            log.err("Failed to initialize Vulkan: {}", .{err});
            return error.FailedToInitializeVulkan;
        };

        self.createDescriptors() catch |err| {
            log.err("Failed to create descriptors: {}", .{err});
            return error.FailedToCreateDescriptors;
        };

        self.createLayouts() catch |err| {
            log.err("Failed to create layouts: {}", .{err});
            return error.FailedToCreateLayouts;
        };

        self.createPipeline() catch |err| {
            log.err("Failed to create pipeline: {}", .{err});
            return error.FailedToCreatePipeline;
        };

        self.createFrames() catch |err| {
            log.err("Failed to create frames: {}", .{err});
            return error.FailedToCreateFrames;
        };

        self.createAssets() catch |err| {
            log.err("Failed to create mesh: {}", .{err});
            return error.FailedToCreateMesh;
        };

        return self;
    }

    pub fn deinit(self: *Renderer) void {
        log.info("Deinitializing...", .{});

        self.vulkan.waitIdle();
        self.destroyAssets();
        self.destroyFrames();
        self.destroyPipeline();
        self.destroyLayouts();
        self.destroyDescriptors();
        self.vulkan.deinit();
    }

    pub fn recreateSwapchain(self: *Renderer) !void {
        try self.vulkan.recreateSwapchain();
    }

    fn createDescriptors(self: *Renderer) !void {
        log.info("Creating descriptors...", .{});

        var swapchain = &self.vulkan.heap.?.swapchain;
        var device = &self.vulkan.heap.?.device;

        self.descriptor_pool = try DescriptorPool.init(device, .{
            .max_set_count = swapchain.max_inflight_frames,
            .uniform_buffer_count = swapchain.max_inflight_frames,
        });
    }

    fn destroyDescriptors(self: *Renderer) void {
        self.descriptor_pool.deinit();
    }

    fn createLayouts(self: *Renderer) !void {
        log.info("Create layouts...", .{});

        var device = &self.vulkan.heap.?.device;

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

        try check(c.vkCreateDescriptorSetLayout.?(device.handle, &descriptor_set_layout_create_info, memory.vulkan_allocator, &self.descriptor_set_layout));

        const pipeline_layout_create_info = c.VkPipelineLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .setLayoutCount = 1,
            .pSetLayouts = &self.descriptor_set_layout,
            .pushConstantRangeCount = 0,
            .pPushConstantRanges = null,
        };

        try check(c.vkCreatePipelineLayout.?(device.handle, &pipeline_layout_create_info, memory.vulkan_allocator, &self.pipeline_layout));
    }

    fn destroyLayouts(self: *Renderer) void {
        if (self.pipeline_layout != null) {
            c.vkDestroyPipelineLayout.?(self.vulkan.heap.?.device.handle, self.pipeline_layout, memory.vulkan_allocator);
        }

        if (self.descriptor_set_layout != null) {
            c.vkDestroyDescriptorSetLayout.?(self.vulkan.heap.?.device.handle, self.descriptor_set_layout, memory.vulkan_allocator);
        }
    }

    fn createPipeline(self: *Renderer) !void {
        log.info("Creating pipeline...", .{});

        const device = &self.vulkan.heap.?.device;
        const swapchain = &self.vulkan.heap.?.swapchain;

        var builder = try PipelineBuilder.init(device);
        defer builder.deinit();

        try builder.loadShaderModule(.Vertex, "data/shaders/simple.vert.spv");
        try builder.loadShaderModule(.Fragment, "data/shaders/simple.frag.spv");

        try builder.addVertexAttribute(.Position, false);
        try builder.addVertexAttribute(.Normal, false);
        try builder.addVertexAttribute(.Color, false);

        builder.setDepthTest(true);
        builder.setDepthWrite(true);
        builder.setColorAttachmentFormat(swapchain.image_format);
        builder.setDepthAttachmentFormat(swapchain.depth_stencil_image_format);
        builder.setStencilAttachmentFormat(swapchain.depth_stencil_image_format);
        builder.setPipelineLayout(self.pipeline_layout);

        self.pipeline = try builder.build();
    }

    fn destroyPipeline(self: *Renderer) void {
        self.pipeline.deinit();
    }

    fn createFrames(self: *Renderer) !void {
        log.info("Creating frames...", .{});

        var device = &self.vulkan.heap.?.device;
        var swapchain = &self.vulkan.heap.?.swapchain;
        var vma = &self.vulkan.heap.?.vma;

        try self.frames.ensureTotalCapacityPrecise(memory.default_allocator, swapchain.max_inflight_frames);
        for (0..swapchain.max_inflight_frames) |_| {
            var command_pool = try CommandPool.init(device, .{
                .queue = .Graphics,
                .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            });

            var command_buffer = try command_pool.createBuffer(c.VK_COMMAND_BUFFER_LEVEL_PRIMARY);

            var uniform_buffer = try Buffer.init(vma, .{
                .size = @sizeOf(VertexTransformUniform),
                .usage_flags = c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                .memory_flags = c.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT | c.VMA_ALLOCATION_CREATE_MAPPED_BIT,
            });

            const descriptor_set_allocate_info = c.VkDescriptorSetAllocateInfo{
                .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
                .pNext = null,
                .descriptorPool = self.descriptor_pool.handle,
                .descriptorSetCount = 1,
                .pSetLayouts = &self.descriptor_set_layout,
            };

            var descriptor_set: c.VkDescriptorSet = undefined;
            try check(c.vkAllocateDescriptorSets.?(device.handle, &descriptor_set_allocate_info, &descriptor_set));

            const uniform_buffer_info = c.VkDescriptorBufferInfo{
                .buffer = uniform_buffer.handle,
                .offset = 0,
                .range = @sizeOf(VertexTransformUniform),
            };

            const write_descriptor_set = c.VkWriteDescriptorSet{
                .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .pNext = null,
                .dstSet = descriptor_set,
                .dstBinding = 0,
                .dstArrayElement = 0,
                .descriptorCount = 1,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .pImageInfo = null,
                .pBufferInfo = &uniform_buffer_info,
                .pTexelBufferView = null,
            };

            c.vkUpdateDescriptorSets.?(device.handle, 1, &write_descriptor_set, 0, null);

            try self.frames.append(memory.default_allocator, .{
                .command_pool = command_pool,
                .command_buffer = command_buffer,
                .uniform_buffer = uniform_buffer,
                .descriptor_set = descriptor_set,
            });
        }
    }

    fn destroyFrames(self: *Renderer) void {
        for (self.frames.items) |*frame| {
            // Descriptor sets are cleaned up automatically.
            frame.uniform_buffer.deinit();
            frame.command_buffer.deinit(&self.vulkan.heap.?.device, &frame.command_pool);
            frame.command_pool.deinit();
        }

        self.frames.deinit(memory.default_allocator);
    }

    fn createAssets(self: *Renderer) !void {
        log.info("Creating mesh...", .{});

        self.mesh = Mesh.init(&self.vulkan.heap.?.transfer, "data/meshes/monkey.bin") catch |err| {
            log.err("Failed to load mesh ({})", .{err});
            return error.FailedToLoadMesh;
        };
    }

    fn destroyAssets(self: *Renderer) void {
        self.mesh.deinit();
    }

    fn updateUniformBuffer(self: *Renderer, uniform_buffer: *Buffer) !void {
        const window = self.vulkan.heap.?.swapchain.window;
        const width: f32 = @floatFromInt(window.getWidth());
        const height: f32 = @floatFromInt(window.getHeight());

        const camera_position = math.Vec3{ 0.0, -1.0, 0.5 };
        const camera_target = math.Vec3{ 0.0, 0.0, 0.0 };
        const camera_up = math.Vec3{ 0.0, 0.0, 1.0 };

        const uniform_object = VertexTransformUniform{
            .model = math.mul(
                math.scaling(math.splat(math.Vec3, 0.5)),
                math.rotation(math.Vec3{ 0.0, 0.0, math.radians(30.0) * self.time }),
            ),
            .view = math.lookAt(camera_position, camera_target, camera_up),
            .projection = math.perspectiveFov(math.radians(70.0), width / height, 0.01, 1000.0),
        };

        try uniform_buffer.upload(std.mem.asBytes(&uniform_object), 0);
        try uniform_buffer.flush(0, c.VK_WHOLE_SIZE);
    }

    fn recordCommandBuffer(self: *Renderer, command_buffer: *CommandBuffer, descriptor_set: c.VkDescriptorSet, image_index: u32) !void {
        const transfer = &self.vulkan.heap.?.transfer;
        const swapchain = &self.vulkan.heap.?.swapchain;

        try check(c.vkBeginCommandBuffer.?(command_buffer.handle, &c.VkCommandBufferBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .pNext = null,
            .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            .pInheritanceInfo = null,
        }));

        transfer.recordOwnershipTransfers(command_buffer);
        swapchain.recordLayoutTransitions(command_buffer, image_index);

        const color_attachment_info = c.VkRenderingAttachmentInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
            .pNext = null,
            .imageView = swapchain.image_views.items[image_index],
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
            .imageView = swapchain.depth_stencil_image_view,
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
                .extent = swapchain.extent,
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
        c.vkCmdBindDescriptorSets.?(command_buffer.handle, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline_layout, 0, 1, &descriptor_set, 0, null);

        c.vkCmdSetViewport.?(command_buffer.handle, 0, 1, &c.VkViewport{
            .x = 0.0,
            .y = 0.0,
            .width = @floatFromInt(swapchain.extent.width),
            .height = @floatFromInt(swapchain.extent.height),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        });

        c.vkCmdSetScissor.?(command_buffer.handle, 0, 1, &c.VkRect2D{
            .offset = c.VkOffset2D{
                .x = 0,
                .y = 0,
            },
            .extent = swapchain.extent,
        });

        var vertex_buffers = [_]c.VkBuffer{undefined} ** vertex_attributes.max_attributes;
        self.mesh.fillVertexBufferHandles(&vertex_buffers);

        var vertex_offsets = [_]c.VkDeviceSize{undefined} ** vertex_attributes.max_attributes;
        self.mesh.fillVertexBufferOffsets(&vertex_offsets);

        c.vkCmdBindVertexBuffers.?(command_buffer.handle, 0, self.mesh.getAttributeCount(), &vertex_buffers, &vertex_offsets);
        c.vkCmdBindIndexBuffer.?(command_buffer.handle, self.mesh.index_buffer.handle, 0, self.mesh.getIndexFormat());
        c.vkCmdDrawIndexed.?(command_buffer.handle, self.mesh.getIndexCount(), 1, 0, 0, 0);

        c.vkCmdEndRendering.?(command_buffer.handle);
        try check(c.vkEndCommandBuffer.?(command_buffer.handle));
    }

    pub fn update(self: *Renderer, time_delta: f32) !void {
        self.time += time_delta;
    }

    pub fn render(self: *Renderer) !void {
        var transfer = &self.vulkan.heap.?.transfer;
        var swapchain = &self.vulkan.heap.?.swapchain;
        var device = &self.vulkan.heap.?.device;

        try transfer.submit();

        const image_next = swapchain.acquireNextImage() catch |err| {
            if (err == error.SwapchainOutOfDate) {
                try self.recreateSwapchain();
                return;
            }
            return err;
        };

        const frame_index = swapchain.frame_index;
        var frame = &self.frames.items[frame_index];

        try frame.command_pool.reset();
        try self.updateUniformBuffer(&frame.uniform_buffer);
        try self.recordCommandBuffer(&frame.command_buffer, frame.descriptor_set, image_next.index);

        const submit_wait_semaphores = [_]c.VkSemaphore{
            transfer.finished_semaphore,
            image_next.available_semaphore,
        };

        const submit_wait_sempahore_values = [_]u64{
            transfer.finished_semaphore_index,
            0,
        };

        const submit_wait_stages = [_]c.VkPipelineStageFlags{
            c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
            c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        };

        const submit_command_buffers = [_]c.VkCommandBuffer{
            frame.command_buffer.handle,
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

        try device.submit(.{
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
            .pSwapchains = &swapchain.handle,
            .pImageIndices = &image_next.index,
            .pResults = null,
        };

        swapchain.present(&present_info) catch |err| {
            if (err == error.SwapchainOutOfDate or err == error.SwapchainSuboptimal) {
                try self.recreateSwapchain();
                return;
            }
            return err;
        };
    }
};
