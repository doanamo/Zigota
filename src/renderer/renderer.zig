const std = @import("std");
const c = @import("../c/c.zig");
const math = @import("../math.zig");
const memory = @import("../vulkan/memory.zig");
const utility = @import("../vulkan/utility.zig");
const log = std.log.scoped(.Renderer);
const check = utility.vulkanCheckResult;

const Window = @import("../glfw/window.zig").Window;
const Vulkan = @import("../vulkan/vulkan.zig").Vulkan;
const CommandPool = @import("../vulkan/command_pool.zig").CommandPool;
const CommandBuffer = @import("../vulkan/command_buffer.zig").CommandBuffer;
const Buffer = @import("../vulkan/buffer.zig").Buffer;
const DescriptorPool = @import("../vulkan/descriptor_pool.zig").DescriptorPool;
const ShaderModule = @import("../vulkan/shader_module.zig").ShaderModule;
const PipelineBuilder = @import("../vulkan/pipeline.zig").PipelineBuilder;
const Pipeline = @import("../vulkan/pipeline.zig").Pipeline;
const vertex_attributes = @import("../vulkan/vertex_attributes.zig");

const VertexTransformUniform = @import("uniform_types.zig").VertexTransformUniform;
const Camera = @import("camera.zig").Camera;
const Mesh = @import("mesh.zig").Mesh;

pub const Renderer = struct {
    const Frame = struct {
        command_pool: CommandPool = .{},
        command_buffer: CommandBuffer = .{},
        uniform_buffer: Buffer = .{},
    };

    vulkan: Vulkan = .{},
    pipeline: Pipeline = .{},
    frames: std.ArrayListUnmanaged(Frame) = .{},

    camera: Camera = .{},
    mesh: Mesh = .{},
    time: f32 = 0.0,

    pub fn init(self: *Renderer, window: *Window) !void {
        log.info("Initializing renderer...", .{});
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

        self.createScene() catch |err| {
            log.err("Failed to create scene: {}", .{err});
            return error.FailedToCreateScene;
        };
    }

    pub fn deinit(self: *Renderer) void {
        log.info("Deinitializing renderer...", .{});

        self.vulkan.device.waitIdle();
        self.destroyScene();
        self.destroyFrames();
        self.destroyPipeline();
        self.vulkan.deinit();
        self.* = .{};
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

    fn createScene(self: *Renderer) !void {
        log.info("Creating scene...", .{});

        const width: f32 = @floatFromInt(self.vulkan.window.width);
        const height: f32 = @floatFromInt(self.vulkan.window.height);

        self.camera.aspect_ratio = width / height;
        self.camera.position = math.Vec3{ 0.0, -1.0, 0.0 };

        self.mesh.init(&self.vulkan, "data/meshes/monkey.bin") catch |err| {
            log.err("Failed to load mesh ({})", .{err});
            return error.FailedToLoadMesh;
        };
    }

    fn destroyScene(self: *Renderer) void {
        self.mesh.deinit();
    }

    fn updateUniformBuffer(self: *Renderer, uniform_buffer: *Buffer) !void {
        const uniform_object = VertexTransformUniform{
            .model = math.mul(
                math.scaling(math.splat(math.Vec3, 0.5)),
                math.rotationZ(math.radians(30.0) * self.time),
            ),
            .view = self.camera.getView(),
            .projection = self.camera.getProjection(),
        };

        try uniform_buffer.upload(std.mem.asBytes(&uniform_object), 0);
        try uniform_buffer.flush(0, c.VK_WHOLE_SIZE);
    }

    fn recordCommandBuffer(self: *Renderer, frame: *Frame, image_index: u32) !void {
        try frame.command_pool.reset();

        var command_buffer = &frame.command_buffer;
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

        c.vkCmdBeginRendering.?(command_buffer.handle, &c.VkRenderingInfo{
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
        });

        c.vkCmdBindPipeline.?(command_buffer.handle, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline.handle);
        c.vkCmdBindDescriptorSets.?(command_buffer.handle, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.vulkan.bindless.pipeline_layout, 0, 1, &self.vulkan.bindless.descriptor_set, 0, null);

        const push_constants = .{
            .uniform_buffer_id = frame.uniform_buffer.bindless_id,
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

    pub fn handleResize(self: *Renderer) !void {
        const width: f32 = @floatFromInt(self.vulkan.window.width);
        const height: f32 = @floatFromInt(self.vulkan.window.height);

        if (width > 0 and height > 0) {
            self.camera.aspect_ratio = width / height;
            self.camera.recalculate_projection = true;

            try self.vulkan.recreateSwapchain();
        }
    }

    pub fn update(self: *Renderer, time_delta: f32) void {
        self.time += time_delta;
    }

    pub fn render(self: *Renderer) !void {
        const swapchain_image = try self.vulkan.beginFrame();

        std.debug.assert(swapchain_image.frame_index < self.frames.items.len);
        var frame = &self.frames.items[swapchain_image.frame_index];

        try self.updateUniformBuffer(&frame.uniform_buffer);
        try self.recordCommandBuffer(frame, swapchain_image.index);

        var command_buffers = [_]*const CommandBuffer{
            &frame.command_buffer,
        };

        try self.vulkan.endFrame(.{
            .swapchain_image = &swapchain_image,
            .command_buffers = &command_buffers,
        });
    }
};
