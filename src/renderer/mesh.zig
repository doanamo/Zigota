const std = @import("std");
const c = @import("../c.zig");
const memory = @import("../memory.zig");
const utility = @import("../utility.zig");
const vertex_attributes = @import("../vulkan/vertex_attributes.zig");
const log = std.log.scoped(.Renderer);

const Vulkan = @import("../vulkan.zig").Vulkan;
const Buffer = @import("../vulkan/buffer.zig").Buffer;
const VertexAttributeType = vertex_attributes.VertexAttributeType;
const VertexAttributeFlags = vertex_attributes.VertexAttributeFlags;

pub const Mesh = struct {
    const FileHeader = extern struct {
        const expected_magic = 0xB2E2AA2A; // 30-01-1991 46
        const expected_version = 1;

        magic: u32,
        version: u32,

        pub fn isValid(self: FileHeader) bool {
            comptime std.debug.assert(@sizeOf(FileHeader) == 8);
            return self.magic == expected_magic and self.version == expected_version;
        }
    };

    const VerticesHeader = extern struct {
        attribute_types: VertexAttributeFlags,
        vertex_count: u32,

        pub fn isValid(self: VerticesHeader) bool {
            comptime std.debug.assert(@sizeOf(VerticesHeader) == 8);
            return self.attribute_types.isValid() and self.vertex_count > 0;
        }
    };

    const IndicesHeader = extern struct {
        index_type_bytes: u32,
        index_count: u32,

        pub fn isValid(self: IndicesHeader) bool {
            comptime std.debug.assert(@sizeOf(IndicesHeader) == 8);
            return (self.index_type_bytes == 2 or self.index_type_bytes == 4) and self.index_count > 0;
        }
    };

    attribute_offsets: std.ArrayListUnmanaged(usize) = .{},
    vertex_buffer: Buffer = .{},
    index_buffer: Buffer = .{},
    index_type_bytes: u8 = undefined,

    pub fn loadFromFile(self: *Mesh, vulkan: *Vulkan, path: []const u8) !void {
        log.info("Loading mesh from \"{s}\" file...", .{path});
        errdefer self.deinit();

        var file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
        defer file.close();

        var buffered = std.io.bufferedReader(file.reader());
        var reader = buffered.reader();

        const file_header = try reader.readStruct(FileHeader);
        if (!file_header.isValid()) {
            log.debug("{}", .{file_header});
            return error.InvalidFileHeader;
        }

        const vertices_header = try reader.readStruct(VerticesHeader);
        if (!vertices_header.isValid()) {
            log.debug("{}", .{vertices_header});
            return error.InvalidVerticesHeader;
        } else {
            var current_attribute_offset: usize = 0;
            try self.vertex_buffer.init(&vulkan.vma, .{
                .size = vertices_header.vertex_count * vertices_header.attribute_types.getCombinedSize(),
                .usage_flags = c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
            });

            for (std.enums.values(VertexAttributeType)) |attribute| {
                if (!vertices_header.attribute_types.hasAttribute(attribute)) {
                    continue;
                }

                const attribute_data_size = vertices_header.vertex_count * vertex_attributes.getVertexAttributeSize(attribute);
                var attribute_data = try memory.frame_allocator.alloc(u8, attribute_data_size);
                defer memory.frame_allocator.free(attribute_data);

                try reader.readNoEof(attribute_data);
                try vulkan.transfer.upload(&self.vertex_buffer, current_attribute_offset, attribute_data);

                try self.attribute_offsets.append(memory.default_allocator, current_attribute_offset);
                current_attribute_offset += attribute_data_size;
            }
        }

        const indices_header = try reader.readStruct(IndicesHeader);
        if (!indices_header.isValid()) {
            log.debug("{}", .{indices_header});
            return error.InvalidIndicesHeader;
        } else {
            self.index_type_bytes = @intCast(indices_header.index_type_bytes);

            try self.index_buffer.init(&vulkan.vma, .{
                .size = indices_header.index_count * indices_header.index_type_bytes,
                .usage_flags = c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
            });

            var index_data = try memory.frame_allocator.alloc(u8, self.index_buffer.size);
            defer memory.frame_allocator.free(index_data);

            try reader.readNoEof(index_data);
            try vulkan.transfer.upload(&self.index_buffer, 0, index_data);
        }

        if (reader.readBytesNoEof(4) != error.EndOfStream) {
            return error.UnexpectedFileData;
        }
    }

    pub fn deinit(self: *Mesh) void {
        self.attribute_offsets.deinit(memory.default_allocator);
        self.vertex_buffer.deinit();
        self.index_buffer.deinit();
        self.* = undefined;
    }

    pub fn getVertexAttributeCount(self: *Mesh) u32 {
        return @intCast(self.attribute_offsets.items.len);
    }

    pub fn getIndexCount(self: *Mesh) u32 {
        std.debug.assert(self.index_buffer.size % self.index_type_bytes == 0);
        return @intCast(self.index_buffer.size / self.index_type_bytes);
    }

    pub fn getIndexFormat(self: *Mesh) c.VkIndexType {
        switch (self.index_type_bytes) {
            2 => return c.VK_INDEX_TYPE_UINT16,
            4 => return c.VK_INDEX_TYPE_UINT32,
            else => unreachable,
        }
    }

    pub fn fillVertexBufferHandles(self: *Mesh, array: []c.VkBuffer) !void {
        if (self.attribute_offsets.items.len > array.len) {
            return error.InsufficientArraySize;
        }

        for (0..self.attribute_offsets.items.len) |index| {
            array[index] = self.vertex_buffer.handle;
        }
    }

    pub fn fillVertexBufferOffsets(self: *Mesh, array: []c.VkDeviceSize) !void {
        if (self.attribute_offsets.items.len > array.len) {
            return error.InsufficientArraySize;
        }

        for (0..self.attribute_offsets.items.len) |index| {
            array[index] = self.attribute_offsets.items[index];
        }
    }
};
