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
    };

    vulkan: Vulkan = .{},
    pipeline: Pipeline = .{},
    frames: std.ArrayListUnmanaged(Frame) = .{},

    mesh: Mesh = .{},
    time: f32 = 0.0,

    pub fn init(self: *Renderer, window: *Window) !void {
        log.info("Initializing...", .{});
        errdefer self.deinit();

        self.vulkan.init(window) catch |err| {
            log.err("Failed to initialize Vulkan: {}", .{err});
            return error.FailedToInitializeVulkan;
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
    }

    pub fn deinit(self: *Renderer) void {
        log.info("Deinitializing...", .{});

        self.vulkan.device.waitIdle();
        self.destroyAssets();
        self.destroyFrames();
        self.destroyPipeline();
        self.vulkan.deinit();
        self.* = .{};
    }

    pub fn recreateSwapchain(self: *Renderer) !void {
        try self.vulkan.recreateSwapchain();
    }

    fn createPipeline(self: *Renderer) !void {
        log.info("Creating pipeline...", .{});

        var builder = PipelineBuilder{};
        try builder.init(&self.vulkan);
        defer builder.deinit();

        try builder.loadShaderModule(.Vertex, "data/shaders/simple.vert.spv");
        try builder.loadShaderModule(.Fragment, "data/shaders/simple.frag.spv");

        try builder.addVertexAttribute(.Position, false);
        try builder.addVertexAttribute(.Normal, false);
        try builder.addVertexAttribute(.Color, false);

        builder.setSwapchainAttachmentFormats(&self.vulkan.swapchain);

        self.pipeline = try builder.build();
    }

    fn destroyPipeline(self: *Renderer) void {
        self.pipeline.deinit();
    }

    fn createFrames(self: *Renderer) !void {
        log.info("Creating frames...", .{});

        try self.frames.ensureTotalCapacityPrecise(memory.default_allocator, self.vulkan.swapchain.max_inflight_frames);
        for (0..self.vulkan.swapchain.max_inflight_frames) |_| {
            var command_pool = CommandPool{};
            try command_pool.init(&self.vulkan, .{
                .queue = .Graphics,
                .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            });
            errdefer command_pool.deinit();

            var command_buffer = CommandBuffer{};
            try command_buffer.init(&self.vulkan, .{
                .command_pool = &command_pool,
                .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            });
            errdefer command_buffer.deinit();

            var uniform_buffer = Buffer{};
            try uniform_buffer.init(&self.vulkan, .{
                .size = @sizeOf(VertexTransformUniform),
                .usage_flags = c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                .memory_flags = c.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT | c.VMA_ALLOCATION_CREATE_MAPPED_BIT,
                .bindless = true,
            });
            errdefer uniform_buffer.deinit();

            try self.frames.append(memory.default_allocator, .{
                .command_pool = command_pool,
                .command_buffer = command_buffer,
                .uniform_buffer = uniform_buffer,
            });
        }
    }

    fn destroyFrames(self: *Renderer) void {
        for (self.frames.items) |*frame| {
            frame.uniform_buffer.deinit();
            frame.command_buffer.deinit();
            frame.command_pool.deinit();
        }

        self.frames.deinit(memory.default_allocator);
    }

    fn createAssets(self: *Renderer) !void {
        log.info("Creating mesh...", .{});

        self.mesh.init(&self.vulkan, "data/meshes/monkey.bin") catch |err| {
            log.err("Failed to load mesh ({})", .{err});
            return error.FailedToLoadMesh;
        };
    }

    fn destroyAssets(self: *Renderer) void {
        self.mesh.deinit();
    }

    fn updateUniformBuffer(self: *Renderer, uniform_buffer: *Buffer) !void {
        const window: *Window = self.vulkan.window;
        const width: f32 = @floatFromInt(window.width);
        const height: f32 = @floatFromInt(window.height);

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

    fn recordCommandBuffer(self: *Renderer, frame: *Frame, image_index: u32) !void {
        try frame.command_pool.reset();
        var command_buffer = &frame.command_buffer;
        var uniform_buffer = &frame.uniform_buffer;

        try check(c.vkBeginCommandBuffer.?(command_buffer.handle, &c.VkCommandBufferBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .pNext = null,
            .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            .pInheritanceInfo = null,
        }));

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

        c.vkCmdBindDescriptorSets.?(command_buffer.handle, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.vulkan.bindless.pipeline_layout, 0, 1, &self.vulkan.bindless.descriptor_set, 0, null);

        const push_constants = .{
            .uniform_buffer_id = uniform_buffer.bindless_id,
        };

        c.vkCmdPushConstants.?(command_buffer.handle, self.vulkan.bindless.pipeline_layout, c.VK_SHADER_STAGE_ALL, 0, @sizeOf(@TypeOf(push_constants)), &push_constants);

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
        try self.vulkan.transfer.submit();
        self.vulkan.bindless.updateDescriptorSet();

        const image_next = self.vulkan.swapchain.acquireNextImage() catch |err| {
            if (err == error.SwapchainOutOfDate) {
                try self.recreateSwapchain();
                return;
            }
            return err;
        };

        const frame_index = self.vulkan.swapchain.frame_index;
        var frame = &self.frames.items[frame_index];

        try self.updateUniformBuffer(&frame.uniform_buffer);
        try self.recordCommandBuffer(frame, image_next.index);

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
