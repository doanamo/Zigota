const c = @import("c.zig");
const std = @import("std");
const glfw = @import("glfw.zig");
const utility = @import("vulkan/utility.zig");
const memory = @import("vulkan/memory.zig");
const log = utility.log_scoped;

const Instance = @import("vulkan/instance.zig").Instance;
const PhysicalDevice = @import("vulkan/physical_device.zig").PhysicalDevice;
const Surface = @import("vulkan/surface.zig").Surface;
const Device = @import("vulkan/device.zig").Device;
const Swapchain = @import("vulkan/swapchain.zig").Swapchain;
const CommandPool = @import("vulkan/command_pool.zig").CommandPool;
const CommandBuffer = @import("vulkan/command_buffer.zig").CommandBuffer;
const ShaderModule = @import("vulkan/shader_module.zig").ShaderModule;

var allocator: std.mem.Allocator = undefined;

var instance: Instance = .{};
var physical_device: PhysicalDevice = .{};
var surface: Surface = .{};
var device: Device = .{};
var swapchain: Swapchain = .{};

var command_pools: std.ArrayListUnmanaged(CommandPool) = .{};
var command_buffers: std.ArrayListUnmanaged(CommandBuffer) = .{};
var render_pass: c.VkRenderPass = null;
var framebuffers: std.ArrayListUnmanaged(c.VkFramebuffer) = .{};
var pipeline_layout: c.VkPipelineLayout = null;
var pipeline_graphics: c.VkPipeline = null;

pub fn init(window: *glfw.Window, allocator_: std.mem.Allocator) !void {
    log.info("Initializing...", .{});
    errdefer deinit();

    allocator = allocator_;
    instance = try Instance.init(allocator);
    physical_device = try PhysicalDevice.init(&instance, allocator);
    surface = try Surface.init(window, &instance, &physical_device);
    device = try Device.init(&physical_device, &surface, allocator);
    swapchain = try Swapchain.init(window, &surface, &device, allocator);

    createCommandPools() catch {
        log.err("Failed to create command pools", .{});
        return error.FailedToCreateCommandPools;
    };

    createCommandBuffers() catch {
        log.err("Failed to create command buffers", .{});
        return error.FailedToCreateCommandBuffers;
    };

    createRenderPass() catch {
        log.err("Failed to create render pass", .{});
        return error.FailedToCreateRenderPass;
    };

    createFramebuffers() catch {
        log.err("Failed to create framebuffers", .{});
        return error.FailedToCreateFramebuffers;
    };

    createGraphicsPipeline() catch {
        log.err("Failed to create graphics pipeline", .{});
        return error.FailedToCreateGraphicsPipeline;
    };

    try Instance.printVersion();
}

pub fn deinit() void {
    log.info("Deinitializing...", .{});

    device.waitIdle();

    destroyGraphicsPipeline();
    destroyFramebuffers();
    destroyRenderPass();
    destroyCommandBuffers();
    destroyCommandPools();

    swapchain.deinit();
    device.deinit();
    surface.deinit();
    physical_device.deinit();
    instance.deinit();
}

pub fn recreateSwapchain() !void {
    device.waitIdle();
    destroyFramebuffers();

    try swapchain.recreate();
    try createFramebuffers();
}

fn createCommandPools() !void {
    log.info("Creating command pools...", .{});

    try command_pools.ensureTotalCapacityPrecise(allocator, swapchain.max_inflight_frames);
    for (0..swapchain.max_inflight_frames) |_| {
        try command_pools.append(allocator, try CommandPool.init(&device));
    }
}

fn destroyCommandPools() void {
    for (command_pools.items) |*command_pool| {
        command_pool.deinit();
    }

    command_pools.deinit(allocator);
}

fn createCommandBuffers() !void {
    log.info("Creating command buffers...", .{});

    try command_buffers.ensureTotalCapacityPrecise(allocator, swapchain.max_inflight_frames);
    for (0..swapchain.max_inflight_frames) |i| {
        try command_buffers.append(allocator, try CommandBuffer.init(&device, &command_pools.items[i], c.VK_COMMAND_BUFFER_LEVEL_PRIMARY));
    }
}

fn destroyCommandBuffers() void {
    for (command_buffers.items, 0..) |*command_buffer, i| {
        command_buffer.deinit(&device, &command_pools.items[i]);
    }

    command_buffers.deinit(allocator);
}

fn createRenderPass() !void {
    log.info("Creating render pass...", .{});

    const color_attachment_description = &c.VkAttachmentDescription{
        .flags = 0,
        .format = swapchain.image_format,
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

    try utility.checkResult(c.vkCreateRenderPass.?(device.handle, create_info, memory.vulkan_allocator, &render_pass));
}

fn destroyRenderPass() void {
    if (render_pass != null) {
        c.vkDestroyRenderPass.?(device.handle, render_pass, memory.vulkan_allocator);
    }
}

fn createFramebuffers() !void {
    log.info("Creating framebuffers...", .{});
    errdefer destroyFramebuffers();

    try framebuffers.ensureTotalCapacityPrecise(allocator, swapchain.image_views.items.len);
    for (swapchain.image_views.items) |image_view| {
        const attachments = [_]c.VkImageView{
            image_view,
        };

        const create_info = &c.VkFramebufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .renderPass = render_pass,
            .attachmentCount = attachments.len,
            .pAttachments = &attachments[0],
            .width = swapchain.extent.width,
            .height = swapchain.extent.height,
            .layers = 1,
        };

        var framebuffer: c.VkFramebuffer = undefined;
        try utility.checkResult(c.vkCreateFramebuffer.?(device.handle, create_info, memory.vulkan_allocator, &framebuffer));
        try framebuffers.append(allocator, framebuffer);
    }
}

fn destroyFramebuffers() void {
    for (framebuffers.items) |framebuffer| {
        c.vkDestroyFramebuffer.?(device.handle, framebuffer, memory.vulkan_allocator);
    }

    framebuffers.deinit(allocator);
    framebuffers = .{};
}

fn createGraphicsPipeline() !void {
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

    try utility.checkResult(c.vkCreatePipelineLayout.?(device.handle, &pipeline_layout_create_info, memory.vulkan_allocator, &pipeline_layout));

    var vertex_shader_module = try ShaderModule.loadFromFile(&device, "data/shaders/simple.vert.spv", allocator);
    defer vertex_shader_module.deinit(&device);

    var fragment_shader_module = try ShaderModule.loadFromFile(&device, "data/shaders/simple.frag.spv", allocator);
    defer fragment_shader_module.deinit(&device);

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
        .vertexBindingDescriptionCount = 0,
        .pVertexBindingDescriptions = null,
        .vertexAttributeDescriptionCount = 0,
        .pVertexAttributeDescriptions = null,
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
        .layout = pipeline_layout,
        .renderPass = render_pass,
        .subpass = 0,
        .basePipelineHandle = null,
        .basePipelineIndex = 0,
    };

    try utility.checkResult(c.vkCreateGraphicsPipelines.?(device.handle, null, 1, graphics_pipeline_create_info, memory.vulkan_allocator, &pipeline_graphics));
}

fn destroyGraphicsPipeline() void {
    if (pipeline_graphics != null) {
        c.vkDestroyPipeline.?(device.handle, pipeline_graphics, memory.vulkan_allocator);
    }

    if (pipeline_layout != null) {
        c.vkDestroyPipelineLayout.?(device.handle, pipeline_layout, memory.vulkan_allocator);
    }
}

fn recordCommandBuffer(command_buffer: CommandBuffer, image_index: u32) !void {
    var command_buffer_begin_info = c.VkCommandBufferBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .pNext = null,
        .flags = 0,
        .pInheritanceInfo = null,
    };

    try utility.checkResult(c.vkBeginCommandBuffer.?(command_buffer.handle, &command_buffer_begin_info));

    var render_pass_begin_info = &c.VkRenderPassBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .pNext = null,
        .renderPass = render_pass,
        .framebuffer = framebuffers.items[image_index],
        .renderArea = c.VkRect2D{
            .offset = c.VkOffset2D{
                .x = 0,
                .y = 0,
            },
            .extent = swapchain.extent,
        },
        .clearValueCount = 1,
        .pClearValues = &c.VkClearValue{
            .color = c.VkClearColorValue{
                .float32 = [_]f32{ 0.0, 0.0, 0.0, 1.0 },
            },
        },
    };

    c.vkCmdBeginRenderPass.?(command_buffer.handle, render_pass_begin_info, c.VK_SUBPASS_CONTENTS_INLINE);
    c.vkCmdBindPipeline.?(command_buffer.handle, c.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline_graphics);

    const viewport = &c.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @intToFloat(f32, swapchain.extent.width),
        .height = @intToFloat(f32, swapchain.extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };

    c.vkCmdSetViewport.?(command_buffer.handle, 0, 1, viewport);

    const scissors = &c.VkRect2D{
        .offset = c.VkOffset2D{
            .x = 0,
            .y = 0,
        },
        .extent = swapchain.extent,
    };

    c.vkCmdSetScissor.?(command_buffer.handle, 0, 1, scissors);

    c.vkCmdDraw.?(command_buffer.handle, 3, 1, 0, 0);
    c.vkCmdEndRenderPass.?(command_buffer.handle);

    try utility.checkResult(c.vkEndCommandBuffer.?(command_buffer.handle));
}

pub fn render() !void {
    const image_next = swapchain.acquireNextImage() catch |err| {
        if (err == error.SwapchainOutOfDate) {
            try recreateSwapchain();
            return;
        } else {
            return err;
        }
    };

    const frame_index = swapchain.frame_index;
    var command_pool = command_pools.items[frame_index];
    try command_pool.reset();

    var command_buffer = command_buffers.items[frame_index];
    try recordCommandBuffer(command_buffer, image_next.index);

    const submit_wait_semaphores = [_]c.VkSemaphore{
        image_next.available_semaphore,
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

    const submit_info = &c.VkSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .pNext = null,
        .waitSemaphoreCount = submit_wait_semaphores.len,
        .pWaitSemaphores = &submit_wait_semaphores,
        .pWaitDstStageMask = &submit_wait_stages,
        .commandBufferCount = submit_command_buffers.len,
        .pCommandBuffers = &submit_command_buffers,
        .signalSemaphoreCount = submit_signal_semaphores.len,
        .pSignalSemaphores = &submit_signal_semaphores,
    };

    try device.submit(1, submit_info, image_next.inflight_fence);

    const present_info = &c.VkPresentInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .pNext = null,
        .waitSemaphoreCount = submit_signal_semaphores.len,
        .pWaitSemaphores = &submit_signal_semaphores,
        .swapchainCount = 1,
        .pSwapchains = &swapchain.handle,
        .pImageIndices = &image_next.index,
        .pResults = null,
    };

    swapchain.present(present_info) catch |err| {
        if (err == error.SwapchainOutOfDate or err == error.SwapchainSuboptimal) {
            try recreateSwapchain();
            return;
        }
        return err;
    };
}
