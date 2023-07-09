const std = @import("std");
const c = @import("c.zig");
const log = std.log.scoped(.Renderer);
const utility = @import("vulkan/utility.zig");
const memory = @import("vulkan/memory.zig");
const math = @import("math.zig");

const Window = @import("glfw/window.zig").Window;
const Vulkan = @import("vulkan.zig").Vulkan;
const CommandPool = @import("vulkan/command_pool.zig").CommandPool;
const CommandBuffer = @import("vulkan/command_buffer.zig").CommandBuffer;
const Buffer = @import("vulkan/buffer.zig").Buffer;
const DescriptorPool = @import("vulkan/descriptor_pool.zig").DescriptorPool;
const ShaderModule = @import("vulkan/shader_module.zig").ShaderModule;
const ColorVertex = @import("renderer/vertex_types.zig").ColorVertex;
const VertexTransformUniform = @import("renderer/uniform_types.zig").VertexTransformUniform;

pub const Renderer = struct {
    allocator: std.mem.Allocator = undefined,

    vulkan: Vulkan = .{},
    command_pools: std.ArrayListUnmanaged(CommandPool) = .{},
    command_buffers: std.ArrayListUnmanaged(CommandBuffer) = .{},
    uniform_buffers: std.ArrayListUnmanaged(Buffer) = .{},
    vertex_buffer: Buffer = .{},
    index_buffer: Buffer = .{},
    layout_descriptor_set: c.VkDescriptorSetLayout = null,
    layout_pipeline: c.VkPipelineLayout = null,
    descriptor_pool: DescriptorPool = .{},
    descriptor_sets: std.ArrayListUnmanaged(c.VkDescriptorSet) = .{},
    pipeline: c.VkPipeline = null,

    pub fn init(self: *Renderer, window: *Window, allocator: std.mem.Allocator) !void {
        log.info("Initializing...", .{});
        self.allocator = allocator;
        errdefer self.deinit();

        self.vulkan.init(window, allocator) catch {
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

        try self.command_pools.ensureTotalCapacityPrecise(self.allocator, self.vulkan.swapchain.max_inflight_frames);
        for (0..self.vulkan.swapchain.max_inflight_frames) |_| {
            var command_pool = self.command_pools.addOneAssumeCapacity();
            try command_pool.init(&self.vulkan.device, .{
                .queue = .Graphics,
                .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            });
        }

        try self.command_buffers.ensureTotalCapacityPrecise(self.allocator, self.vulkan.swapchain.max_inflight_frames);
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

        self.command_buffers.deinit(self.allocator);
        self.command_pools.deinit(self.allocator);
    }

    fn createBuffers(self: *Renderer) !void {
        log.info("Creating buffers...", .{});

        try self.uniform_buffers.ensureTotalCapacityPrecise(self.allocator, self.vulkan.swapchain.max_inflight_frames);
        for (0..self.vulkan.swapchain.max_inflight_frames) |_| {
            var uniform_buffer = self.uniform_buffers.addOneAssumeCapacity();
            try uniform_buffer.init(&self.vulkan.vma, &.{
                .size_bytes = @sizeOf(VertexTransformUniform),
                .usage_flags = c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                .memory_flags = c.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT | c.VMA_ALLOCATION_CREATE_MAPPED_BIT,
            });
        }

        const vertices = [_]ColorVertex{
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
            ColorVertex{
                .position = [3]f32{ 0.75, -0.5, 0.0 },
                .color = [4]f32{ 1.0, 1.0, 0.0, 1.0 },
            },
            ColorVertex{
                .position = [3]f32{ -0.75, -0.5, 0.0 },
                .color = [4]f32{ 1.0, 0.0, 1.0, 1.0 },
            },
        };

        const indices = [_]u16{ 0, 1, 2, 3, 1, 0, 4, 0, 2 };

        try self.vertex_buffer.init(&self.vulkan.vma, &.{
            .size_bytes = @sizeOf(ColorVertex) * vertices.len,
            .usage_flags = c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        });

        try self.index_buffer.init(&self.vulkan.vma, &.{
            .size_bytes = @sizeOf(u16) * indices.len,
            .usage_flags = c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
        });

        try self.vulkan.transfer.upload(&self.vertex_buffer, 0, std.mem.sliceAsBytes(&vertices));
        try self.vulkan.transfer.upload(&self.index_buffer, 0, std.mem.sliceAsBytes(&indices));
    }

    fn destroyBuffers(self: *Renderer) void {
        for (self.uniform_buffers.items) |*uniform_buffer| {
            uniform_buffer.deinit(&self.vulkan.vma);
        }
        self.uniform_buffers.deinit(self.allocator);

        self.vertex_buffer.deinit(&self.vulkan.vma);
        self.index_buffer.deinit(&self.vulkan.vma);
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

        try utility.checkResult(c.vkCreateDescriptorSetLayout.?(self.vulkan.device.handle, &descriptor_set_layout_create_info, memory.allocation_callbacks, &self.layout_descriptor_set));

        const pipeline_layout_create_info = c.VkPipelineLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .setLayoutCount = 1,
            .pSetLayouts = &self.layout_descriptor_set,
            .pushConstantRangeCount = 0,
            .pPushConstantRanges = null,
        };

        try utility.checkResult(c.vkCreatePipelineLayout.?(self.vulkan.device.handle, &pipeline_layout_create_info, memory.allocation_callbacks, &self.layout_pipeline));
    }

    fn destroyLayouts(self: *Renderer) void {
        if (self.layout_descriptor_set != null) {
            c.vkDestroyDescriptorSetLayout.?(self.vulkan.device.handle, self.layout_descriptor_set, memory.allocation_callbacks);
        }

        if (self.layout_pipeline != null) {
            c.vkDestroyPipelineLayout.?(self.vulkan.device.handle, self.layout_pipeline, memory.allocation_callbacks);
        }
    }

    fn createDescriptors(self: *Renderer) !void {
        log.info("Creating descriptors...", .{});

        try self.descriptor_pool.init(&self.vulkan.device, .{
            .max_set_count = self.vulkan.swapchain.max_inflight_frames,
            .uniform_buffer_count = self.vulkan.swapchain.max_inflight_frames,
        });

        try self.descriptor_sets.ensureTotalCapacityPrecise(self.allocator, self.vulkan.swapchain.max_inflight_frames);
        for (0..self.vulkan.swapchain.max_inflight_frames) |i| {
            const set_allocate_info = c.VkDescriptorSetAllocateInfo{
                .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
                .pNext = null,
                .descriptorPool = self.descriptor_pool.handle,
                .descriptorSetCount = 1,
                .pSetLayouts = &self.layout_descriptor_set,
            };

            var descriptor_set: c.VkDescriptorSet = undefined;
            try utility.checkResult(c.vkAllocateDescriptorSets.?(self.vulkan.device.handle, &set_allocate_info, &descriptor_set));
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
        self.descriptor_sets.deinit(self.allocator);
        self.descriptor_pool.deinit();
    }

    fn createPipeline(self: *Renderer) !void {
        log.info("Creating pipeline...", .{});

        var vertex_shader_module = try ShaderModule.loadFromFile(
            &self.vulkan.device,
            "data/shaders/simple.vert.spv",
            self.allocator,
        );
        defer vertex_shader_module.deinit();

        const vertex_shader_stage_info = c.VkPipelineShaderStageCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
            .module = vertex_shader_module.handle,
            .pName = "main",
            .pSpecializationInfo = null,
        };

        var fragment_shader_module = try ShaderModule.loadFromFile(
            &self.vulkan.device,
            "data/shaders/simple.frag.spv",
            self.allocator,
        );
        defer fragment_shader_module.deinit();

        const fragment_shader_stage_info = c.VkPipelineShaderStageCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = fragment_shader_module.handle,
            .pName = "main",
            .pSpecializationInfo = null,
        };

        const shader_stages = [_]c.VkPipelineShaderStageCreateInfo{
            vertex_shader_stage_info,
            fragment_shader_stage_info,
        };

        const dynamic_states = [_]c.VkDynamicState{
            c.VK_DYNAMIC_STATE_VIEWPORT,
            c.VK_DYNAMIC_STATE_SCISSOR,
        };

        const dynamic_state_create_info = c.VkPipelineDynamicStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .dynamicStateCount = dynamic_states.len,
            .pDynamicStates = &dynamic_states,
        };

        const vertex_input_state_create_info = c.VkPipelineVertexInputStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .vertexBindingDescriptionCount = 1,
            .pVertexBindingDescriptions = &ColorVertex.binding_description,
            .vertexAttributeDescriptionCount = ColorVertex.attribute_descriptions.len,
            .pVertexAttributeDescriptions = &ColorVertex.attribute_descriptions[0],
        };

        const input_assembly_state_create_info = c.VkPipelineInputAssemblyStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            .primitiveRestartEnable = c.VK_FALSE,
        };

        const viewport_state_create_info = c.VkPipelineViewportStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .viewportCount = 1,
            .pViewports = null,
            .scissorCount = 1,
            .pScissors = null,
        };

        const rasterization_state_create_info = c.VkPipelineRasterizationStateCreateInfo{
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

        const multisample_state_create_info = c.VkPipelineMultisampleStateCreateInfo{
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

        const color_blend_attachment_state = c.VkPipelineColorBlendAttachmentState{
            .blendEnable = c.VK_FALSE,
            .srcColorBlendFactor = c.VK_BLEND_FACTOR_ONE,
            .dstColorBlendFactor = c.VK_BLEND_FACTOR_ZERO,
            .colorBlendOp = c.VK_BLEND_OP_ADD,
            .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
            .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
            .alphaBlendOp = c.VK_BLEND_OP_ADD,
            .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
        };

        const color_blend_state_create_info = c.VkPipelineColorBlendStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .logicOpEnable = c.VK_FALSE,
            .logicOp = c.VK_LOGIC_OP_COPY,
            .attachmentCount = 1,
            .pAttachments = &color_blend_attachment_state,
            .blendConstants = [_]f32{ 0.0, 0.0, 0.0, 0.0 },
        };

        const pipeline_rendering_create_info = c.VkPipelineRenderingCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
            .pNext = null,
            .viewMask = 0,
            .colorAttachmentCount = 1,
            .pColorAttachmentFormats = &self.vulkan.swapchain.image_format,
            .depthAttachmentFormat = c.VK_FORMAT_UNDEFINED,
            .stencilAttachmentFormat = c.VK_FORMAT_UNDEFINED,
        };

        const graphics_pipeline_create_info = &c.VkGraphicsPipelineCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .pNext = &pipeline_rendering_create_info,
            .flags = 0,
            .stageCount = shader_stages.len,
            .pStages = &shader_stages,
            .pVertexInputState = &vertex_input_state_create_info,
            .pInputAssemblyState = &input_assembly_state_create_info,
            .pTessellationState = null,
            .pViewportState = &viewport_state_create_info,
            .pRasterizationState = &rasterization_state_create_info,
            .pMultisampleState = &multisample_state_create_info,
            .pDepthStencilState = null,
            .pColorBlendState = &color_blend_state_create_info,
            .pDynamicState = &dynamic_state_create_info,
            .layout = self.layout_pipeline,
            .renderPass = null,
            .subpass = 0,
            .basePipelineHandle = null,
            .basePipelineIndex = 0,
        };

        try utility.checkResult(c.vkCreateGraphicsPipelines.?(self.vulkan.device.handle, null, 1, graphics_pipeline_create_info, memory.allocation_callbacks, &self.pipeline));
    }

    fn destroyPipeline(self: *Renderer) void {
        if (self.pipeline != null) {
            c.vkDestroyPipeline.?(self.vulkan.device.handle, self.pipeline, memory.allocation_callbacks);
        }
    }

    fn updateUniformBuffer(self: *Renderer, uniform_buffer: *Buffer) !void {
        const uniform_object = VertexTransformUniform{
            .model = math.identity(),
            .view = math.identity(),
            .projection = math.identity(),
        };

        try uniform_buffer.upload(&self.vulkan.vma, std.mem.asBytes(&uniform_object), 0);
        try uniform_buffer.flush(&self.vulkan.vma, 0, c.VK_WHOLE_SIZE);
    }

    fn recordCommandBuffer(self: *Renderer, command_buffer: *CommandBuffer, frame_index: u32, image_index: u32) !void {
        var command_buffer_begin_info = c.VkCommandBufferBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .pNext = null,
            .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            .pInheritanceInfo = null,
        };

        try utility.checkResult(c.vkBeginCommandBuffer.?(command_buffer.handle, &command_buffer_begin_info));
        self.vulkan.transfer.recordOwnershipTransfersToGraphicsQueue(command_buffer);

        const color_attachment_layout_transition = c.VkImageMemoryBarrier2{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
            .pNext = null,
            .srcStageMask = c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
            .srcAccessMask = 0,
            .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
            .oldLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            .newLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .image = self.vulkan.swapchain.images.items[image_index],
            .subresourceRange = c.VkImageSubresourceRange{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };

        const color_present_layout_transition = c.VkImageMemoryBarrier2{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
            .pNext = null,
            .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .srcAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
            .dstStageMask = c.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
            .dstAccessMask = 0,
            .oldLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            .newLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
            .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .image = self.vulkan.swapchain.images.items[image_index],
            .subresourceRange = c.VkImageSubresourceRange{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };

        c.vkCmdPipelineBarrier2.?(command_buffer.handle, &c.VkDependencyInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
            .pNext = null,
            .dependencyFlags = 0,
            .memoryBarrierCount = 0,
            .pMemoryBarriers = null,
            .bufferMemoryBarrierCount = 0,
            .pBufferMemoryBarriers = null,
            .imageMemoryBarrierCount = 2,
            .pImageMemoryBarriers = &[_]c.VkImageMemoryBarrier2{
                color_attachment_layout_transition,
                color_present_layout_transition,
            },
        });

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
            .pDepthAttachment = null,
            .pStencilAttachment = null,
        };

        c.vkCmdBeginRendering.?(command_buffer.handle, &rendering_info);
        c.vkCmdBindPipeline.?(command_buffer.handle, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline);

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

        const vertex_buffers = &[_]c.VkBuffer{
            self.vertex_buffer.handle,
        };

        const vertex_offsets = &[_]c.VkDeviceSize{
            0,
        };

        c.vkCmdBindVertexBuffers.?(command_buffer.handle, 0, 1, vertex_buffers, vertex_offsets);
        c.vkCmdBindIndexBuffer.?(command_buffer.handle, self.index_buffer.handle, 0, c.VK_INDEX_TYPE_UINT16);
        c.vkCmdDrawIndexed.?(command_buffer.handle, @intCast(self.index_buffer.size_bytes / @sizeOf(u16)), 1, 0, 0, 0);

        c.vkCmdEndRendering.?(command_buffer.handle);

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
