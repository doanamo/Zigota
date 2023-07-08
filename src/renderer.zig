const std = @import("std");
const c = @import("c.zig");
const log = std.log.scoped(.Renderer);
const utility = @import("vulkan/utility.zig");
const memory = @import("vulkan/memory.zig");

const Window = @import("glfw/window.zig").Window;
const Vulkan = @import("vulkan.zig").Vulkan;
const CommandPool = @import("vulkan/command_pool.zig").CommandPool;
const CommandBuffer = @import("vulkan/command_buffer.zig").CommandBuffer;
const ColorVertex = @import("vulkan/vertex.zig").ColorVertex;
const Buffer = @import("vulkan/buffer.zig").Buffer;
const ShaderModule = @import("vulkan/shader_module.zig").ShaderModule;

pub const Renderer = struct {
    allocator: std.mem.Allocator = undefined,

    vulkan: Vulkan = .{},
    command_pools: std.ArrayListUnmanaged(CommandPool) = .{},
    command_buffers: std.ArrayListUnmanaged(CommandBuffer) = .{},
    render_pass: c.VkRenderPass = null,
    framebuffers: std.ArrayListUnmanaged(c.VkFramebuffer) = .{},
    vertex_buffer: Buffer = .{},
    pipeline_layout: c.VkPipelineLayout = null,
    pipeline_graphics: c.VkPipeline = null,

    pub fn init(self: *Renderer, window: *Window, allocator: std.mem.Allocator) !void {
        log.info("Initializing...", .{});
        self.allocator = allocator;
        errdefer self.deinit();

        self.vulkan.init(window, allocator) catch {
            log.err("Failed to initialize Vulkan", .{});
            return error.FailedToInitializeVulkan;
        };

        self.createCommandPools() catch {
            log.err("Failed to create command pools", .{});
            return error.FailedToCreateCommandPools;
        };

        self.createCommandBuffers() catch {
            log.err("Failed to create command buffers", .{});
            return error.FailedToCreateCommandBuffers;
        };

        // TODO: Use dynamic rendering to get rid of render passes and framebuffers
        self.createRenderPass() catch {
            log.err("Failed to create render pass", .{});
            return error.FailedToCreateRenderPass;
        };

        self.createFramebuffers() catch {
            log.err("Failed to create framebuffers", .{});
            return error.FailedToCreateFramebuffers;
        };

        self.createBuffers() catch {
            log.err("Failed to create vertex buffer", .{});
            return error.FailedToCreateVertexBuffer;
        };

        self.createGraphicsPipeline() catch {
            log.err("Failed to create graphics pipeline", .{});
            return error.FailedToCreateGraphicsPipeline;
        };
    }

    pub fn deinit(self: *Renderer) void {
        log.info("Deinitializing...", .{});

        self.vulkan.device.waitIdle();

        self.destroyGraphicsPipeline();
        self.destroyBuffers();
        self.destroyFramebuffers();
        self.destroyRenderPass();
        self.destroyCommandBuffers();
        self.destroyCommandPools();

        self.vulkan.deinit();
    }

    pub fn recreateSwapchain(self: *Renderer) !void {
        self.vulkan.device.waitIdle();

        self.destroyFramebuffers();
        try self.vulkan.recreateSwapchain();
        try self.createFramebuffers();
    }

    fn createCommandPools(self: *Renderer) !void {
        log.info("Creating command pools...", .{});

        try self.command_pools.ensureTotalCapacityPrecise(self.allocator, self.vulkan.swapchain.max_inflight_frames);
        for (0..self.vulkan.swapchain.max_inflight_frames) |_| {
            try self.command_pools.addOneAssumeCapacity().init(&self.vulkan.device, &.{ .queue = .Graphics });
        }
    }

    fn destroyCommandPools(self: *Renderer) void {
        for (self.command_pools.items) |*command_pool| {
            command_pool.deinit();
        }

        self.command_pools.deinit(self.allocator);
    }

    fn createCommandBuffers(self: *Renderer) !void {
        log.info("Creating command buffers...", .{});

        try self.command_buffers.ensureTotalCapacityPrecise(self.allocator, self.vulkan.swapchain.max_inflight_frames);
        for (0..self.vulkan.swapchain.max_inflight_frames) |i| {
            try self.command_buffers.addOneAssumeCapacity().init(
                &self.vulkan.device,
                &self.command_pools.items[i],
                c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            );
        }
    }

    fn destroyCommandBuffers(self: *Renderer) void {
        for (self.command_buffers.items, 0..) |*command_buffer, i| {
            command_buffer.deinit(&self.vulkan.device, &self.command_pools.items[i]);
        }

        self.command_buffers.deinit(self.allocator);
    }

    fn createRenderPass(self: *Renderer) !void {
        log.info("Creating render pass...", .{});

        const color_attachment_description = &c.VkAttachmentDescription{
            .flags = 0,
            .format = self.vulkan.swapchain.image_format,
            .samples = c.VK_SAMPLE_COUNT_1_BIT,
            .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
            .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        };

        const color_attachment_reference = &c.VkAttachmentReference{
            .attachment = 0,
            .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        };

        const subpass_description = &c.VkSubpassDescription{
            .flags = 0,
            .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            .inputAttachmentCount = 0,
            .pInputAttachments = null,
            .colorAttachmentCount = 1,
            .pColorAttachments = color_attachment_reference,
            .pResolveAttachments = null,
            .pDepthStencilAttachment = null,
            .preserveAttachmentCount = 0,
            .pPreserveAttachments = null,
        };

        const subpass_dependency = &c.VkSubpassDependency{
            .srcSubpass = c.VK_SUBPASS_EXTERNAL,
            .dstSubpass = 0,
            .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .srcAccessMask = 0,
            .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
            .dependencyFlags = 0,
        };

        const create_info = &c.VkRenderPassCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .attachmentCount = 1,
            .pAttachments = color_attachment_description,
            .subpassCount = 1,
            .pSubpasses = subpass_description,
            .dependencyCount = 1,
            .pDependencies = subpass_dependency,
        };

        try utility.checkResult(c.vkCreateRenderPass.?(self.vulkan.device.handle, create_info, memory.allocation_callbacks, &self.render_pass));
    }

    fn destroyRenderPass(self: *Renderer) void {
        if (self.render_pass != null) {
            c.vkDestroyRenderPass.?(self.vulkan.device.handle, self.render_pass, memory.allocation_callbacks);
        }
    }

    fn createFramebuffers(self: *Renderer) !void {
        log.info("Creating framebuffers...", .{});
        errdefer self.destroyFramebuffers();

        try self.framebuffers.ensureTotalCapacityPrecise(self.allocator, self.vulkan.swapchain.image_views.items.len);
        for (self.vulkan.swapchain.image_views.items) |image_view| {
            const attachments = [_]c.VkImageView{
                image_view,
            };

            const create_info = &c.VkFramebufferCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .renderPass = self.render_pass,
                .attachmentCount = attachments.len,
                .pAttachments = &attachments[0],
                .width = self.vulkan.swapchain.extent.width,
                .height = self.vulkan.swapchain.extent.height,
                .layers = 1,
            };

            var framebuffer: c.VkFramebuffer = undefined;
            try utility.checkResult(c.vkCreateFramebuffer.?(self.vulkan.device.handle, create_info, memory.allocation_callbacks, &framebuffer));
            try self.framebuffers.append(self.allocator, framebuffer);
        }
    }

    fn destroyFramebuffers(self: *Renderer) void {
        for (self.framebuffers.items) |framebuffer| {
            c.vkDestroyFramebuffer.?(self.vulkan.device.handle, framebuffer, memory.allocation_callbacks);
        }

        self.framebuffers.deinit(self.allocator);
        self.framebuffers = .{};
    }

    fn createBuffers(self: *Renderer) !void {
        log.info("Creating buffers...", .{});

        const vertices = [3]ColorVertex{
            ColorVertex{
                .position = [3]f32{ 0.0, -0.5, 0.0 },
                .color = [4]f32{ 1.0, 0.0, 0.0, 1.0 },
            },
            ColorVertex{
                .position = [3]f32{ 0.5, 0.5, 0.0 },
                .color = [4]f32{ 0.0, 1.0, 0.0, 1.0 },
            },
            ColorVertex{
                .position = [3]f32{ -0.5, 0.5, 0.0 },
                .color = [4]f32{ 0.0, 0.0, 1.0, 1.0 },
            },
        };

        try self.vertex_buffer.init(&self.vulkan.vma, &.{
            .size_bytes = @sizeOf(ColorVertex) * vertices.len,
            .usage_flags = c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        });

        try self.vulkan.transfer.upload(&self.vertex_buffer, 0, std.mem.sliceAsBytes(&vertices));
    }

    fn destroyBuffers(self: *Renderer) void {
        self.vertex_buffer.deinit(&self.vulkan.vma);
    }

    fn createGraphicsPipeline(self: *Renderer) !void {
        log.info("Creating graphics pipeline...", .{});

        const pipeline_layout_create_info = c.VkPipelineLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .setLayoutCount = 0,
            .pSetLayouts = null,
            .pushConstantRangeCount = 0,
            .pPushConstantRanges = null,
        };

        try utility.checkResult(c.vkCreatePipelineLayout.?(self.vulkan.device.handle, &pipeline_layout_create_info, memory.allocation_callbacks, &self.pipeline_layout));

        var vertex_shader_module = try ShaderModule.loadFromFile(&self.vulkan.device, "data/shaders/simple.vert.spv", self.allocator);
        defer vertex_shader_module.deinit();

        var fragment_shader_module = try ShaderModule.loadFromFile(&self.vulkan.device, "data/shaders/simple.frag.spv", self.allocator);
        defer fragment_shader_module.deinit();

        const vertex_shader_stage_info = c.VkPipelineShaderStageCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
            .module = vertex_shader_module.handle,
            .pName = "main",
            .pSpecializationInfo = null,
        };

        const fragment_shader_stage_info = c.VkPipelineShaderStageCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = fragment_shader_module.handle,
            .pName = "main",
            .pSpecializationInfo = null,
        };

        const shader_stages = &[_]c.VkPipelineShaderStageCreateInfo{
            vertex_shader_stage_info,
            fragment_shader_stage_info,
        };

        const dynamic_states = &[_]c.VkDynamicState{
            c.VK_DYNAMIC_STATE_VIEWPORT,
            c.VK_DYNAMIC_STATE_SCISSOR,
        };

        const dynamic_state_create_info = &c.VkPipelineDynamicStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .dynamicStateCount = dynamic_states.len,
            .pDynamicStates = dynamic_states,
        };

        const vertex_input_state_create_info = &c.VkPipelineVertexInputStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .vertexBindingDescriptionCount = 1,
            .pVertexBindingDescriptions = &ColorVertex.binding_description,
            .vertexAttributeDescriptionCount = ColorVertex.attribute_descriptions.len,
            .pVertexAttributeDescriptions = &ColorVertex.attribute_descriptions[0],
        };

        const input_assembly_state_create_info = &c.VkPipelineInputAssemblyStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            .primitiveRestartEnable = c.VK_FALSE,
        };

        const viewport_state_create_info = &c.VkPipelineViewportStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .viewportCount = 1,
            .pViewports = null,
            .scissorCount = 1,
            .pScissors = null,
        };

        const rasterization_state_create_info = &c.VkPipelineRasterizationStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .depthClampEnable = c.VK_FALSE,
            .rasterizerDiscardEnable = c.VK_FALSE,
            .polygonMode = c.VK_POLYGON_MODE_FILL,
            .cullMode = c.VK_CULL_MODE_BACK_BIT,
            .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
            .depthBiasEnable = c.VK_FALSE,
            .depthBiasConstantFactor = 0.0,
            .depthBiasClamp = 0.0,
            .depthBiasSlopeFactor = 0.0,
            .lineWidth = 1.0,
        };

        const multisample_state_create_info = &c.VkPipelineMultisampleStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
            .sampleShadingEnable = c.VK_FALSE,
            .minSampleShading = 1.0,
            .pSampleMask = null,
            .alphaToCoverageEnable = c.VK_FALSE,
            .alphaToOneEnable = c.VK_FALSE,
        };

        const color_blend_attachment_state = &c.VkPipelineColorBlendAttachmentState{
            .blendEnable = c.VK_FALSE,
            .srcColorBlendFactor = c.VK_BLEND_FACTOR_ONE,
            .dstColorBlendFactor = c.VK_BLEND_FACTOR_ZERO,
            .colorBlendOp = c.VK_BLEND_OP_ADD,
            .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
            .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
            .alphaBlendOp = c.VK_BLEND_OP_ADD,
            .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
        };

        const color_blend_state_create_info = &c.VkPipelineColorBlendStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .logicOpEnable = c.VK_FALSE,
            .logicOp = c.VK_LOGIC_OP_COPY,
            .attachmentCount = 1,
            .pAttachments = color_blend_attachment_state,
            .blendConstants = [_]f32{ 0.0, 0.0, 0.0, 0.0 },
        };

        const graphics_pipeline_create_info = &c.VkGraphicsPipelineCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stageCount = shader_stages.len,
            .pStages = shader_stages,
            .pVertexInputState = vertex_input_state_create_info,
            .pInputAssemblyState = input_assembly_state_create_info,
            .pTessellationState = null,
            .pViewportState = viewport_state_create_info,
            .pRasterizationState = rasterization_state_create_info,
            .pMultisampleState = multisample_state_create_info,
            .pDepthStencilState = null,
            .pColorBlendState = color_blend_state_create_info,
            .pDynamicState = dynamic_state_create_info,
            .layout = self.pipeline_layout,
            .renderPass = self.render_pass,
            .subpass = 0,
            .basePipelineHandle = null,
            .basePipelineIndex = 0,
        };

        try utility.checkResult(c.vkCreateGraphicsPipelines.?(self.vulkan.device.handle, null, 1, graphics_pipeline_create_info, memory.allocation_callbacks, &self.pipeline_graphics));
    }

    fn destroyGraphicsPipeline(self: *Renderer) void {
        if (self.pipeline_graphics != null) {
            c.vkDestroyPipeline.?(self.vulkan.device.handle, self.pipeline_graphics, memory.allocation_callbacks);
        }

        if (self.pipeline_layout != null) {
            c.vkDestroyPipelineLayout.?(self.vulkan.device.handle, self.pipeline_layout, memory.allocation_callbacks);
        }
    }

    pub fn recordCommandBuffer(self: *Renderer, command_buffer: CommandBuffer, image_index: u32) !void {
        var command_buffer_begin_info = c.VkCommandBufferBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .pNext = null,
            .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            .pInheritanceInfo = null,
        };

        try utility.checkResult(c.vkBeginCommandBuffer.?(command_buffer.handle, &command_buffer_begin_info));

        self.vulkan.transfer.recordOwnershipTransfersToGraphicsQueue(command_buffer);

        var render_pass_begin_info = &c.VkRenderPassBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .pNext = null,
            .renderPass = self.render_pass,
            .framebuffer = self.framebuffers.items[image_index],
            .renderArea = c.VkRect2D{
                .offset = c.VkOffset2D{
                    .x = 0,
                    .y = 0,
                },
                .extent = self.vulkan.swapchain.extent,
            },
            .clearValueCount = 1,
            .pClearValues = &c.VkClearValue{
                .color = c.VkClearColorValue{
                    .float32 = [_]f32{ 0.0, 0.0, 0.0, 1.0 },
                },
            },
        };

        c.vkCmdBeginRenderPass.?(command_buffer.handle, render_pass_begin_info, c.VK_SUBPASS_CONTENTS_INLINE);
        c.vkCmdBindPipeline.?(command_buffer.handle, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline_graphics);

        const viewport = &c.VkViewport{
            .x = 0.0,
            .y = 0.0,
            .width = @intToFloat(f32, self.vulkan.swapchain.extent.width),
            .height = @intToFloat(f32, self.vulkan.swapchain.extent.height),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };

        c.vkCmdSetViewport.?(command_buffer.handle, 0, 1, viewport);

        const scissors = &c.VkRect2D{
            .offset = c.VkOffset2D{
                .x = 0,
                .y = 0,
            },
            .extent = self.vulkan.swapchain.extent,
        };

        c.vkCmdSetScissor.?(command_buffer.handle, 0, 1, scissors);

        const vertex_buffers = &[_]c.VkBuffer{
            self.vertex_buffer.handle,
        };

        const vertex_offsets = &[_]c.VkDeviceSize{
            0,
        };

        c.vkCmdBindVertexBuffers.?(command_buffer.handle, 0, 1, vertex_buffers, vertex_offsets);
        c.vkCmdDraw.?(command_buffer.handle, 3, 1, 0, 0);

        c.vkCmdEndRenderPass.?(command_buffer.handle);
        try utility.checkResult(c.vkEndCommandBuffer.?(command_buffer.handle));
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

        var command_buffer = self.command_buffers.items[frame_index];
        try self.recordCommandBuffer(command_buffer, image_next.index);

        const submit_wait_semaphores = [_]c.VkSemaphore{
            self.vulkan.transfer.finished_semaphore,
            image_next.available_semaphore,
        };

        const submit_wait_sempahore_values = [_]u64{
            self.vulkan.transfer.finished_semaphore_index,
            0,
        };

        const submit_wait_stages = [_]c.VkPipelineStageFlags{
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

        try self.vulkan.device.submit(.Graphics, 1, &submit_info, image_next.inflight_fence);

        const present_info = &c.VkPresentInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .pNext = null,
            .waitSemaphoreCount = submit_signal_semaphores.len,
            .pWaitSemaphores = &submit_signal_semaphores,
            .swapchainCount = 1,
            .pSwapchains = &self.vulkan.swapchain.handle,
            .pImageIndices = &image_next.index,
            .pResults = null,
        };

        self.vulkan.swapchain.present(present_info) catch |err| {
            if (err == error.SwapchainOutOfDate or err == error.SwapchainSuboptimal) {
                try self.recreateSwapchain();
                return;
            }
            return err;
        };
    }
};
