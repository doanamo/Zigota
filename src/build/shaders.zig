const std = @import("std");
const utility = @import("../common/utility.zig");

pub fn compileAll(allocator: std.mem.Allocator, builder: *std.build.Builder, exe: *std.build.LibExeObjStep) !void {
    const glslc_exe_path = try utility.findExecutable(allocator, "glslc");
    defer allocator.free(glslc_exe_path);

    const input_dir_path = "assets/shaders/";
    const output_dir_path = "deploy/data/shaders/";
    try std.fs.cwd().makePath(output_dir_path);

    var manifest_dir = try std.fs.cwd().makeOpenPath("zig-cache/assets/shaders/", .{});
    defer manifest_dir.close();

    var working_dir = try std.fs.cwd().openDir(".", .{});
    defer working_dir.close();

    var cache = std.Build.Cache{ .gpa = allocator, .manifest_dir = manifest_dir };
    cache.addPrefix(.{ .path = null, .handle = working_dir });

    var input_dir = try std.fs.cwd().openIterableDir(input_dir_path, .{});
    defer input_dir.close();

    var walker = try input_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) {
            continue;
        }

        const input_file_path = try std.fs.path.join(allocator, &[_][]const u8{ input_dir_path, entry.path });
        defer allocator.free(input_file_path);

        const output_file_name = try std.fmt.allocPrint(allocator, "{s}.spv", .{entry.path});
        defer allocator.free(output_file_name);

        const output_file_path = try std.fs.path.join(allocator, &[_][]const u8{ output_dir_path, output_file_name });
        defer allocator.free(output_file_path);

        var output_exists = true;
        std.fs.cwd().access(output_file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => output_exists = false,
            else => return err,
        };

        var manifest = cache.obtain();
        defer manifest.deinit();

        _ = try manifest.addFile(glslc_exe_path, null);
        _ = try manifest.addFile(input_file_path, null);
        if (try manifest.hit() and output_exists) {
            continue;
        }

        exe.step.dependOn(&builder.addSystemCommand(&[_][]const u8{
            glslc_exe_path,
            "-Werror",
            "-O",
            "-o",
            output_file_path,
            input_file_path,
        }).step);

        if (manifest.have_exclusive_lock) {
            try manifest.writeManifest();
        }
    }
}
