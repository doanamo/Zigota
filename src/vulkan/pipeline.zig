const std = @import("std");
const c = @import("../c.zig");
const memory = @import("memory.zig");
const utility = @import("utility.zig");
const vertex_attributes = @import("vertex_attributes.zig");

const Device = @import("device.zig").Device;
const ShaderStage = @import("shader_module.zig").ShaderStage;
const ShaderModule = @import("shader_module.zig").ShaderModule;
const VertexAttribute = vertex_attributes.VertexAttribute;

const log = std.log.scoped(.Vulkan);
const check = utility.vulkanCheckResult;

pub const PipelineBuilder = struct {
    const ShaderStages = std.ArrayListUnmanaged(struct {
        stage: ShaderStage,
        module: ShaderModule,
    });

    device: *Device,

    shader_stages: ShaderStages,
    vertex_binding_descriptions: std.ArrayListUnmanaged(c.VkVertexInputBindingDescription) = .{},
    vertex_attribute_descriptions: std.ArrayListUnmanaged(c.VkVertexInputAttributeDescription) = .{},
    color_attachment_format: c.VkFormat = c.VK_FORMAT_UNDEFINED,
    depth_attachment_format: c.VkFormat = c.VK_FORMAT_UNDEFINED,
    stencil_attachment_format: c.VkFormat = c.VK_FORMAT_UNDEFINED,
    pipeline_layout: c.VkPipelineLayout = null,

    pub fn init(device: *Device) !PipelineBuilder {
        return PipelineBuilder{
            .device = device,
            .shader_stages = try ShaderStages.initCapacity(memory.frame_allocator, @typeInfo(ShaderStage).Enum.fields.len),
        };
    }

    pub fn deinit(self: *PipelineBuilder) void {
        for (self.shader_stages.items) |*shader_stage| {
            shader_stage.module.deinit();
        }
        self.shader_stages.deinit(memory.frame_allocator);

        self.vertex_binding_descriptions.deinit(memory.frame_allocator);
        self.vertex_attribute_descriptions.deinit(memory.frame_allocator);
    }

    pub fn loadShaderModule(self: *PipelineBuilder, shader_stage: ShaderStage, path: []const u8) !void {
        var shader_module = try ShaderModule.loadFromFile(self.device, path);
        errdefer shader_module.deinit();

        try self.shader_stages.append(memory.default_allocator, .{
            .stage = shader_stage,
            .module = shader_module,
        });
    }

    pub fn addVertexAttribute(self: *PipelineBuilder, attribute: VertexAttribute, instanced: bool) !void {
        const binding_description = c.VkVertexInputBindingDescription{
            .binding = @intCast(self.vertex_binding_descriptions.items.len),
            .stride = vertex_attributes.getVertexAttributeSize(attribute),
            .inputRate = if (!instanced) c.VK_VERTEX_INPUT_RATE_VERTEX else c.VK_VERTEX_INPUT_RATE_INSTANCE,
        };
        try self.vertex_binding_descriptions.append(memory.frame_allocator, binding_description);

        const attribute_description = c.VkVertexInputAttributeDescription{
            .location = @intCast(self.vertex_attribute_descriptions.items.len),
            .binding = binding_description.binding,
            .format = vertex_attributes.getVertexAttributeFormat(attribute),
            .offset = 0,
        };
        try self.vertex_attribute_descriptions.append(memory.frame_allocator, attribute_description);
    }

    pub fn setColorAttachmentFormat(self: *PipelineBuilder, format: c.VkFormat) void {
        self.color_attachment_format = format;
    }

    pub fn setDepthAttachmentFormat(self: *PipelineBuilder, format: c.VkFormat) void {
        self.depth_attachment_format = format;
    }

    pub fn setStencilAttachmentFormat(self: *PipelineBuilder, format: c.VkFormat) void {
        self.stencil_attachment_format = format;
    }

    pub fn setPipelineLayout(self: *PipelineBuilder, pipeline_layout: c.VkPipelineLayout) void {
        self.pipeline_layout = pipeline_layout;
    }

    pub fn build(self: *PipelineBuilder) !Pipeline {
        log.info("Creating pipeline...", .{});

        var shader_stage_create_infos = try memory.default_allocator.alloc(c.VkPipelineShaderStageCreateInfo, self.shader_stages.items.len);
        defer memory.default_allocator.free(shader_stage_create_infos);

        for (self.shader_stages.items, 0..) |shader_stage, i| {
            shader_stage_create_infos[i] = .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .stage = @intFromEnum(shader_stage.stage),
                .module = shader_stage.module.handle,
                .pName = "main",
                .pSpecializationInfo = null,
            };
        }

        const input_assembly_state_create_info = c.VkPipelineInputAssemblyStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            .primitiveRestartEnable = c.VK_FALSE,
        };

        const vertex_input_state_create_info = c.VkPipelineVertexInputStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .vertexBindingDescriptionCount = @intCast(self.vertex_binding_descriptions.items.len),
            .pVertexBindingDescriptions = self.vertex_binding_descriptions.items.ptr,
            .vertexAttributeDescriptionCount = @intCast(self.vertex_attribute_descriptions.items.len),
            .pVertexAttributeDescriptions = self.vertex_attribute_descriptions.items.ptr,
        };

        const dynamic_states = &[_]c.VkDynamicState{
            c.VK_DYNAMIC_STATE_VIEWPORT,
            c.VK_DYNAMIC_STATE_SCISSOR,
        };

        const dynamic_state_create_info = c.VkPipelineDynamicStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .dynamicStateCount = dynamic_states.len,
            .pDynamicStates = dynamic_states.ptr,
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
            .pColorAttachmentFormats = &self.color_attachment_format,
            .depthAttachmentFormat = self.depth_attachment_format,
            .stencilAttachmentFormat = self.stencil_attachment_format,
        };

        const pipeline_create_info = c.VkGraphicsPipelineCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .pNext = &pipeline_rendering_create_info,
            .flags = 0,
            .stageCount = @intCast(shader_stage_create_infos.len),
            .pStages = shader_stage_create_infos.ptr,
            .pVertexInputState = &vertex_input_state_create_info,
            .pInputAssemblyState = &input_assembly_state_create_info,
            .pTessellationState = null,
            .pViewportState = &viewport_state_create_info,
            .pRasterizationState = &rasterization_state_create_info,
            .pMultisampleState = &multisample_state_create_info,
            .pDepthStencilState = null,
            .pColorBlendState = &color_blend_state_create_info,
            .pDynamicState = &dynamic_state_create_info,
            .layout = self.pipeline_layout,
            .renderPass = null,
            .subpass = 0,
            .basePipelineHandle = null,
            .basePipelineIndex = 0,
        };

        var pipeline: c.VkPipeline = undefined;
        try check(c.vkCreateGraphicsPipelines.?(self.device.handle, null, 1, &pipeline_create_info, memory.vulkan_allocator, &pipeline));

        return .{
            .handle = pipeline,
            .device = self.device.handle,
        };
    }
};

pub const Pipeline = struct {
    handle: c.VkPipeline = null,
    device: c.VkDevice = undefined,

    pub fn deinit(self: *Pipeline) void {
        if (self.handle != null) {
            c.vkDestroyPipeline.?(self.device, self.handle, memory.vulkan_allocator);
        }
    }
};
