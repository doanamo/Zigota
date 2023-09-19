const std = @import("std");
const utility = @import("../common/utility.zig");

fn hasValidExtension(extension: []const u8) bool {
    if (std.mem.eql(u8, extension, ".vert"))
        return true;

    if (std.mem.eql(u8, extension, ".frag"))
        return true;

    if (std.mem.eql(u8, extension, ".comp"))
        return true;

    if (std.mem.eql(u8, extension, ".geom"))
        return true;

    if (std.mem.eql(u8, extension, ".tesc"))
        return true;

    if (std.mem.eql(u8, extension, ".tese"))
        return true;

    return false;
}

fn addManifestDependencies(
    allocator: std.mem.Allocator,
    manifest: *std.Build.Cache.Manifest,
    glslc_exe_path: []const u8,
    input_file_path: []const u8,
) !void {
    const arguments = &[_][]const u8{
        glslc_exe_path,
        "-M",
        input_file_path,
    };

    var process = std.ChildProcess.init(arguments, allocator);
    process.stderr_behavior = .Close;
    process.stdout_behavior = .Pipe;
    process.stdin_behavior = .Close;
    try process.spawn();

    const output = try process.stdout.?.readToEndAlloc(allocator, utility.megabytes(1));
    defer allocator.free(output);

    switch (try process.wait()) {
        .Exited => |code| {
            if (code != 0)
                return error.ProcessFailed;
        },
        else => return error.ProcessFailed,
    }

    var it = std.mem.tokenize(u8, output, " \t\r\n");
    _ = it.next(); // Skip the first token

    while (it.next()) |dependency_path| {
        const resolved_path = try std.fs.path.resolve(allocator, &[_][]const u8{dependency_path});
        defer allocator.free(resolved_path);

        _ = try manifest.addFile(resolved_path, null);
    }
}

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

        if (!hasValidExtension(std.fs.path.extension(entry.path))) {
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
        try addManifestDependencies(allocator, &manifest, glslc_exe_path, input_file_path);
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
