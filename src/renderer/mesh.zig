const std = @import("std");
const c = @import("../cimport/c.zig");
const memory = @import("../common/memory.zig");
const utility = @import("../common/utility.zig");
const log = std.log.scoped(.Renderer);

const Vulkan = @import("../vulkan/vulkan.zig").Vulkan;
const Transfer = @import("../vulkan/transfer.zig").Transfer;
const Buffer = @import("../vulkan/buffer.zig").Buffer;

const vertex_attributes = @import("../vulkan/vertex_attributes.zig");
const VertexAttributeType = vertex_attributes.VertexAttributeType;
const VertexAttributeFlags = vertex_attributes.VertexAttributeFlags;

pub const Mesh = struct {
    const FileHeader = extern struct {
        const expected_magic = 0xB2E2AA2A; // 30-01-1991 46
        const expected_version = 2;

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

    vertex_buffer: Buffer = .{},
    vertex_attributes: std.ArrayListUnmanaged(struct {
        type: VertexAttributeType,
        offset: usize,
    }) = .{},

    index_buffer: Buffer = .{},
    index_type_bytes: u8 = undefined,

    pub fn init(self: *Mesh, vulkan: *Vulkan, path: []const u8) !void {
        errdefer self.deinit();

        self.loadFromFile(vulkan, path) catch |err| {
            log.err("Failed to load mesh from \"{s}\" file: {}", .{ path, err });
            return error.FailedToLoadFromFile;
        };
    }

    pub fn deinit(self: *Mesh) void {
        self.vertex_attributes.deinit(memory.default_allocator);
        self.vertex_buffer.deinit();
        self.index_buffer.deinit();
        self.* = .{};
    }

    fn loadFromFile(self: *Mesh, vulkan: *Vulkan, path: []const u8) !void {
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
            try self.vertex_buffer.init(vulkan, .{
                .size = vertices_header.vertex_count * vertices_header.attribute_types.getTotalSize(),
                .usage_flags = c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
            });

            for (std.enums.values(VertexAttributeType)) |attribute| {
                if (!vertices_header.attribute_types.hasAttribute(attribute)) {
                    continue;
                }

                const attribute_data_size = vertices_header.vertex_count * vertex_attributes.getVertexAttributeSize(attribute);
                try vulkan.transfer.uploadFromReader(&self.vertex_buffer, current_attribute_offset, attribute_data_size, reader);

                try self.vertex_attributes.append(memory.default_allocator, .{
                    .type = attribute,
                    .offset = current_attribute_offset,
                });
                current_attribute_offset += attribute_data_size;
            }
        }

        const indices_header = try reader.readStruct(IndicesHeader);
        if (!indices_header.isValid()) {
            log.debug("{}", .{indices_header});
            return error.InvalidIndicesHeader;
        } else {
            self.index_type_bytes = @intCast(indices_header.index_type_bytes);
            try self.index_buffer.init(vulkan, .{
                .size = indices_header.index_count * indices_header.index_type_bytes,
                .usage_flags = c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
            });

            try vulkan.transfer.uploadFromReader(&self.index_buffer, 0, self.index_buffer.size, reader);
        }

        if (reader.readBytesNoEof(4) != error.EndOfStream) {
            return error.UnexpectedFileData;
        }

        log.info("Loaded mesh from \"{s}\" file ({} bytes, {} attributes, {} vertices, {} indices)", .{
            path,
            self.vertex_buffer.size + self.index_buffer.size,
            vertices_header.attribute_types.getAttributeCount(),
            vertices_header.vertex_count,
            indices_header.index_count,
        });
    }

    pub fn getAttributeCount(self: *Mesh) u32 {
        return @intCast(self.vertex_attributes.items.len);
    }

    pub fn getIndexCount(self: *Mesh) u32 {
        std.debug.assert(self.index_buffer.size % self.index_type_bytes == 0);
        return @intCast(self.index_buffer.size / self.index_type_bytes);
    }

    pub fn getIndexFormat(self: *Mesh) c.VkIndexType {
        std.debug.assert(self.index_type_bytes != 0);
        switch (self.index_type_bytes) {
            2 => return c.VK_INDEX_TYPE_UINT16,
            4 => return c.VK_INDEX_TYPE_UINT32,
            else => unreachable,
        }
    }

    pub fn fillVertexBufferHandles(self: *Mesh, array: []c.VkBuffer) void {
        std.debug.assert(self.vertex_attributes.items.len != 0);
        std.debug.assert(self.vertex_attributes.items.len <= array.len);

        for (0..self.vertex_attributes.items.len) |index| {
            array[index] = self.vertex_buffer.handle;
        }
    }

    pub fn fillVertexBufferOffsets(self: *Mesh, array: []c.VkDeviceSize) void {
        std.debug.assert(self.vertex_attributes.items.len != 0);
        std.debug.assert(self.vertex_attributes.items.len <= array.len);

        for (0..self.vertex_attributes.items.len) |index| {
            array[index] = self.vertex_attributes.items[index].offset;
        }
    }
};
