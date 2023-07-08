const std = @import("std");
const c = @import("../c.zig");
const memory = @import("memory.zig");
const utility = @import("utility.zig");
const log = utility.log_scoped;

const Device = @import("device.zig").Device;
const VmaAllocator = @import("vma.zig").VmaAllocator;
const CommandPool = @import("command_pool.zig").CommandPool;
const CommandBuffer = @import("command_buffer.zig").CommandBuffer;
const Buffer = @import("buffer.zig").Buffer;

pub const Transfer = struct {
    const staging_size = utility.kilobytes(64);

    const BufferCopyCommand = struct {
        buffer: c.VkBuffer = undefined,
        buffer_offset: usize = 0,
        staging_offset: usize = 0,
        size: c.VkDeviceSize = 0,
    };

    device: *Device = undefined,
    vma: *VmaAllocator = undefined,
    allocator: std.mem.Allocator = undefined,

    command_pool: CommandPool = .{},
    command_buffer: CommandBuffer = .{},
    staging_buffer: Buffer = .{},
    staging_offset: usize = 0,
    buffer_copy_commands: std.ArrayListUnmanaged(BufferCopyCommand) = .{},
    buffer_ownership_transfers_source: std.ArrayListUnmanaged(c.VkBufferMemoryBarrier2) = .{},
    buffer_ownership_transfers_target: std.ArrayListUnmanaged(c.VkBufferMemoryBarrier2) = .{},
    finished_semaphore: c.VkSemaphore = null,
    finished_semaphore_index: u64 = 0,

    pub fn init(self: *Transfer, device: *Device, vma: *VmaAllocator, allocator: std.mem.Allocator) !void {
        log.info("Initializing transfer...", .{});
        self.device = device;
        self.vma = vma;
        self.allocator = allocator;
        errdefer self.deinit();

        self.createCommandPool() catch {
            log.err("Failed to create transfer command pool", .{});
            return error.FailedToCreateCommandPool;
        };

        self.createStagingBuffer() catch {
            log.err("Failed to create transfer staging buffer", .{});
            return error.FailedToCreateStagingBuffers;
        };

        self.createSynchronization() catch {
            log.err("Failed to create transfer synchronization", .{});
            return error.FailedToCreateSynchronization;
        };
    }

    pub fn deinit(self: *Transfer) void {
        self.destroySynchronization();
        self.destroyStagingBuffer();
        self.destroyCommandPool();
        self.* = undefined;
    }

    fn createCommandPool(self: *Transfer) !void {
        log.info("Creating transfer command pool", .{});

        try self.command_pool.init(self.device, &.{
            .queue = .Transfer,
            .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        });

        try self.command_buffer.init(
            self.device,
            &self.command_pool,
            c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        );
    }

    fn destroyCommandPool(self: *Transfer) void {
        self.command_buffer.deinit(self.device, &self.command_pool);
        self.command_pool.deinit();
    }

    fn createStagingBuffer(self: *Transfer) !void {
        log.info("Creating transfer staging buffer...", .{});

        try self.staging_buffer.init(self.vma, &.{
            .size_bytes = staging_size,
            .usage_flags = c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            .memory_flags = c.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT | c.VMA_ALLOCATION_CREATE_MAPPED_BIT,
        });
    }

    fn destroyStagingBuffer(self: *Transfer) void {
        self.buffer_copy_commands.deinit(self.allocator);
        self.buffer_ownership_transfers_source.deinit(self.allocator);
        self.buffer_ownership_transfers_target.deinit(self.allocator);
        self.staging_buffer.deinit(self.vma);
    }

    fn createSynchronization(self: *Transfer) !void {
        log.info("Creating transfer synchronization...", .{});

        const semaphore_type_create_info = c.VkSemaphoreTypeCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO,
            .pNext = null,
            .semaphoreType = c.VK_SEMAPHORE_TYPE_TIMELINE,
            .initialValue = self.finished_semaphore_index,
        };

        const semaphore_create_info = c.VkSemaphoreCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
            .pNext = @ptrCast(&semaphore_type_create_info),
            .flags = 0,
        };

        try utility.checkResult(c.vkCreateSemaphore.?(self.device.handle, &semaphore_create_info, memory.allocation_callbacks, &self.finished_semaphore));
    }

    fn destroySynchronization(self: *Transfer) void {
        if (self.finished_semaphore != null) {
            c.vkDestroySemaphore.?(self.device.handle, self.finished_semaphore, memory.allocation_callbacks);
        }
    }

    pub fn upload(self: *Transfer, buffer: *Buffer, buffer_offset: usize, data: []const u8) !void {
        std.debug.assert(data.len != 0);

        var data_offset: usize = 0;
        while (true) {
            const staging_remaining_size = staging_size - self.staging_offset;
            if (staging_remaining_size == 0) {
                // Staging buffer is already full and needs to be copied to GPU
                // Submit queued buffer copies before we can stage more data
                try self.submit();

                // Wait for transfer to complete before we start modifying the staging buffer
                // Consider multiple inflight transfers to avoid stalling the pipeline
                try self.wait();

                self.staging_offset = 0;
                continue;
            }

            const data_remaining_size = data.len - data_offset;
            if (data_remaining_size == 0)
                break;

            const data_upload_size = @min(data_remaining_size, staging_remaining_size);
            try self.staging_buffer.upload(self.vma, u8, data[data_offset .. data_offset + data_upload_size], self.staging_offset);

            try self.buffer_copy_commands.append(self.allocator, BufferCopyCommand{
                .buffer = buffer.handle,
                .buffer_offset = buffer_offset + data_offset,
                .staging_offset = self.staging_offset,
                .size = data_upload_size,
            });

            data_offset += data_upload_size;
            self.staging_offset += data_upload_size;
        }

        try self.buffer_ownership_transfers_source.append(self.allocator, c.VkBufferMemoryBarrier2{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER_2,
            .pNext = null,
            .srcStageMask = c.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
            .srcAccessMask = c.VK_ACCESS_2_MEMORY_WRITE_BIT,
            .dstStageMask = 0,
            .dstAccessMask = 0,
            .srcQueueFamilyIndex = self.device.getQueue(.Transfer).index,
            .dstQueueFamilyIndex = self.device.getQueue(.Graphics).index,
            .buffer = buffer.handle,
            .offset = 0,
            .size = c.VK_WHOLE_SIZE,
        });

        try self.buffer_ownership_transfers_target.append(self.allocator, c.VkBufferMemoryBarrier2{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER_2,
            .pNext = null,
            .srcStageMask = 0,
            .srcAccessMask = 0,
            .dstStageMask = c.VK_PIPELINE_STAGE_2_VERTEX_ATTRIBUTE_INPUT_BIT,
            .dstAccessMask = c.VK_ACCESS_2_MEMORY_READ_BIT,
            .srcQueueFamilyIndex = self.device.getQueue(.Transfer).index,
            .dstQueueFamilyIndex = self.device.getQueue(.Graphics).index,
            .buffer = buffer.handle,
            .offset = 0,
            .size = c.VK_WHOLE_SIZE,
        });
    }

    pub fn submit(self: *Transfer) !void {
        if (self.buffer_copy_commands.items.len == 0 and self.buffer_ownership_transfers_source.items.len == 0)
            return;

        try self.wait();
        try self.staging_buffer.flush(self.vma, 0, c.VK_WHOLE_SIZE);
        try self.command_pool.reset();

        try utility.checkResult(c.vkBeginCommandBuffer.?(self.command_buffer.handle, &c.VkCommandBufferBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .pNext = null,
            .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            .pInheritanceInfo = null,
        }));

        for (self.buffer_copy_commands.items) |command| {
            c.vkCmdCopyBuffer.?(self.command_buffer.handle, self.staging_buffer.handle, command.buffer, 1, &c.VkBufferCopy{
                .srcOffset = command.staging_offset,
                .dstOffset = command.buffer_offset,
                .size = command.size,
            });
        }
        self.buffer_copy_commands.clearRetainingCapacity();

        if (self.buffer_ownership_transfers_source.items.len != 0) {
            const dependency_info = c.VkDependencyInfo{
                .sType = c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
                .pNext = null,
                .dependencyFlags = 0,
                .memoryBarrierCount = 0,
                .pMemoryBarriers = null,
                .bufferMemoryBarrierCount = @intCast(self.buffer_ownership_transfers_source.items.len),
                .pBufferMemoryBarriers = self.buffer_ownership_transfers_source.items.ptr,
                .imageMemoryBarrierCount = 0,
                .pImageMemoryBarriers = null,
            };

            c.vkCmdPipelineBarrier2.?(self.command_buffer.handle, &dependency_info);
            self.buffer_ownership_transfers_source.clearRetainingCapacity();
        }

        try utility.checkResult(c.vkEndCommandBuffer.?(self.command_buffer.handle));

        const timeline_semaphore_submit_info = c.VkTimelineSemaphoreSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO,
            .pNext = null,
            .waitSemaphoreValueCount = 1,
            .pWaitSemaphoreValues = &[1]u64{self.finished_semaphore_index},
            .signalSemaphoreValueCount = 1,
            .pSignalSemaphoreValues = &[1]u64{self.finished_semaphore_index + 1},
        };

        const submit_info = c.VkSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .pNext = @ptrCast(&timeline_semaphore_submit_info),
            .waitSemaphoreCount = 0,
            .pWaitSemaphores = null,
            .pWaitDstStageMask = null,
            .commandBufferCount = 1,
            .pCommandBuffers = &self.command_buffer.handle,
            .signalSemaphoreCount = 1,
            .pSignalSemaphores = &self.finished_semaphore,
        };

        self.finished_semaphore_index += 1;
        try self.device.submit(.Transfer, 1, &submit_info, null);
    }

    pub fn wait(self: *Transfer) !void {
        const semaphore_wait_info = c.VkSemaphoreWaitInfo{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO,
            .pNext = null,
            .flags = 0,
            .semaphoreCount = 1,
            .pSemaphores = &self.finished_semaphore,
            .pValues = &self.finished_semaphore_index,
        };

        try utility.checkResult(c.vkWaitSemaphores.?(self.device.handle, &semaphore_wait_info, std.math.maxInt(u64)));
    }

    pub fn recordOwnershipTransfersToGraphicsQueue(self: *Transfer, command_buffer: CommandBuffer) void {
        if (self.buffer_ownership_transfers_target.items.len == 0)
            return;

        const dependency_info = c.VkDependencyInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
            .pNext = null,
            .dependencyFlags = 0,
            .memoryBarrierCount = 0,
            .pMemoryBarriers = null,
            .bufferMemoryBarrierCount = @intCast(self.buffer_ownership_transfers_target.items.len),
            .pBufferMemoryBarriers = self.buffer_ownership_transfers_target.items.ptr,
            .imageMemoryBarrierCount = 0,
            .pImageMemoryBarriers = null,
        };

        c.vkCmdPipelineBarrier2.?(command_buffer.handle, &dependency_info);
        self.buffer_ownership_transfers_target.clearRetainingCapacity();
    }
};