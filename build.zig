const std = @import("std");
const utility = @import("src/common/utility.zig");

const Environment = struct {
    vulkan_sdk_path: []const u8,
    vulkan_include_path: []const u8,
    glslc_exe_path: []const u8,
    blender_exe_path: []const u8,

    pub fn init() !Environment {
        const vulkan_sdk_path = try std.process.getEnvVarOwned(allocator, "VULKAN_SDK");
        errdefer allocator.free(vulkan_sdk_path);

        const vulkan_include_path = try std.fs.path.join(allocator, &[_][]const u8{ vulkan_sdk_path, "Include" });
        errdefer allocator.free(vulkan_include_path);

        const glslc_exe_path = try utility.findExecutable(allocator, "glslc");
        errdefer allocator.free(glslc_exe_path);

        const blender_exe_path = try utility.findExecutable(allocator, "blender");
        errdefer allocator.free(blender_exe_path);

        return Environment{
            .vulkan_sdk_path = vulkan_sdk_path,
            .vulkan_include_path = vulkan_include_path,
            .glslc_exe_path = glslc_exe_path,
            .blender_exe_path = blender_exe_path,
        };
    }

    pub fn deinit(self: *Environment) void {
        allocator.free(self.vulkan_sdk_path);
        allocator.free(self.vulkan_include_path);
        allocator.free(self.glslc_exe_path);
        allocator.free(self.blender_exe_path);
    }
};

var allocator: std.mem.Allocator = undefined;
var environment: Environment = undefined;
var target: std.zig.CrossTarget = undefined;
var optimize: std.builtin.Mode = undefined;

pub fn build(builder: *std.build.Builder) !void {
    allocator = builder.allocator;

    environment = try Environment.init();
    defer environment.deinit();

    target = builder.standardTargetOptions(.{});
    optimize = builder.standardOptimizeOption(.{});

    try createGame(builder);
    try createTests(builder);
}

fn addDependencyMimalloc(builder: *std.build.Builder, exe: *std.build.LibExeObjStep) !void {
    const mimalloc = builder.addStaticLibrary(.{
        .name = "mimalloc",
        .target = target,
        .optimize = optimize,
    });

    var flags = std.ArrayList([]const u8).init(allocator);
    defer flags.deinit();

    try flags.append("-DMI_STATIC_LIB");
    if (optimize == .Debug or optimize == .ReleaseSafe) {
        try flags.append("-DMI_SECURE=4");
    }

    switch (target.getOsTag()) {
        .windows => {
            mimalloc.addCSourceFiles(&.{
                "deps/mimalloc/src/prim/windows/prim.c",
            }, flags.items);
        },
        else => unreachable,
    }

    mimalloc.addCSourceFiles(&.{
        "deps/mimalloc/src/prim/prim.c",
        "deps/mimalloc/src/alloc-aligned.c",
        "deps/mimalloc/src/alloc-posix.c",
        "deps/mimalloc/src/alloc.c",
        "deps/mimalloc/src/arena.c",
        "deps/mimalloc/src/bitmap.c",
        "deps/mimalloc/src/heap.c",
        "deps/mimalloc/src/init.c",
        "deps/mimalloc/src/options.c",
        "deps/mimalloc/src/os.c",
        "deps/mimalloc/src/page.c",
        "deps/mimalloc/src/random.c",
        "deps/mimalloc/src/segment-map.c",
        "deps/mimalloc/src/segment.c",
        "deps/mimalloc/src/stats.c",
    }, flags.items);

    mimalloc.addIncludePath(.{ .path = "deps/mimalloc/include/" });
    mimalloc.linkLibC();

    exe.addIncludePath(.{ .path = "deps/mimalloc/include/" });
    exe.linkLibrary(mimalloc);
}

fn addDependencyGlfw(builder: *std.build.Builder, exe: *std.build.LibExeObjStep) !void {
    const glfw = builder.addStaticLibrary(.{
        .name = "glfw",
        .target = target,
        .optimize = if (optimize != .Debug) .ReleaseSmall else optimize,
    });

    var flags = std.ArrayList([]const u8).init(allocator);
    defer flags.deinit();

    switch (target.getOsTag()) {
        .windows => {
            try flags.append("-D_GLFW_WIN32");

            glfw.addCSourceFiles(&.{
                "deps/glfw/src/win32_init.c",
                "deps/glfw/src/win32_joystick.c",
                "deps/glfw/src/win32_monitor.c",
                "deps/glfw/src/win32_time.c",
                "deps/glfw/src/win32_thread.c",
                "deps/glfw/src/win32_window.c",
                "deps/glfw/src/wgl_context.c",
                "deps/glfw/src/egl_context.c",
                "deps/glfw/src/osmesa_context.c",
            }, flags.items);

            glfw.linkSystemLibrary("gdi32");
        },
        else => unreachable,
    }

    glfw.addCSourceFiles(&.{
        "deps/glfw/src/context.c",
        "deps/glfw/src/init.c",
        "deps/glfw/src/input.c",
        "deps/glfw/src/monitor.c",
        "deps/glfw/src/vulkan.c",
        "deps/glfw/src/window.c",
    }, flags.items);
    glfw.linkLibC();

    exe.addIncludePath(.{ .path = "deps/glfw/include/" });
    exe.linkLibrary(glfw);
}

fn addDependencyVolk(builder: *std.build.Builder, exe: *std.build.LibExeObjStep) !void {
    const volk = builder.addStaticLibrary(.{
        .name = "volk",
        .target = target,
        .optimize = optimize,
    });

    var flags = std.ArrayList([]const u8).init(allocator);
    defer flags.deinit();

    switch (target.getOsTag()) {
        .windows => {
            try flags.append("-DVK_USE_PLATFORM_WIN32_KHR");
            exe.defineCMacroRaw("VK_USE_PLATFORM_WIN32_KHR");
        },
        else => unreachable,
    }

    volk.addIncludePath(.{ .path = environment.vulkan_include_path });
    volk.addIncludePath(.{ .path = "deps/volk/" });
    volk.addCSourceFile(.{ .file = .{ .path = "deps/volk/volk.c" }, .flags = flags.items });
    volk.linkLibC();

    exe.addIncludePath(.{ .path = "deps/volk/" });
    exe.linkLibrary(volk);
}

fn addDependencyVulkan(builder: *std.build.Builder, exe: *std.build.LibExeObjStep) !void {
    const vulkan = builder.addStaticLibrary(.{
        .name = "vulkan",
        .target = target,
        .optimize = optimize,
    });

    var flags = std.ArrayList([]const u8).init(builder.allocator);
    defer flags.deinit();

    try flags.append("-std=c++11");

    vulkan.addIncludePath(.{ .path = environment.vulkan_include_path });
    vulkan.addCSourceFile(.{ .file = .{ .path = "src/cimport/vulkan.cpp" }, .flags = flags.items });
    vulkan.linkLibCpp();

    exe.addIncludePath(.{ .path = environment.vulkan_include_path });
    exe.linkLibrary(vulkan);
}

fn addDependencySpirvReflect(builder: *std.build.Builder, exe: *std.build.LibExeObjStep) !void {
    const spirv_reflect = builder.addStaticLibrary(.{
        .name = "spirv_reflect",
        .target = target,
        .optimize = optimize,
    });

    var flags = std.ArrayList([]const u8).init(allocator);
    defer flags.deinit();

    spirv_reflect.addIncludePath(.{ .path = "deps/spirv-reflect/" });
    spirv_reflect.addCSourceFile(.{ .file = .{ .path = "deps/spirv-reflect/spirv_reflect.c" }, .flags = flags.items });
    spirv_reflect.linkLibC();

    exe.addIncludePath(.{ .path = "deps/spirv-reflect/" });
    exe.linkLibrary(spirv_reflect);
}

fn addDependencyVma(builder: *std.build.Builder, exe: *std.build.LibExeObjStep) !void {
    const vma = builder.addStaticLibrary(.{
        .name = "vma",
        .target = target,
        .optimize = optimize,
    });

    var flags = std.ArrayList([]const u8).init(allocator);
    defer flags.deinit();

    try flags.append("-std=c++14");

    vma.addIncludePath(.{ .path = environment.vulkan_include_path });
    vma.addIncludePath(.{ .path = "deps/vma/src/" });
    vma.addCSourceFile(.{ .file = .{ .path = "src/cimport/vma.cpp" }, .flags = flags.items });
    vma.linkLibCpp();

    exe.addIncludePath(.{ .path = "deps/vma/src/" });
    exe.linkLibrary(vma);
}

fn compileShaders(builder: *std.build.Builder, exe: *std.build.LibExeObjStep) !void {
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

        _ = try manifest.addFile(environment.glslc_exe_path, null);
        _ = try manifest.addFile(input_file_path, null);
        if (try manifest.hit() and output_exists) {
            continue;
        }

        exe.step.dependOn(&builder.addSystemCommand(&[_][]const u8{
            environment.glslc_exe_path,
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

fn exportMeshes(builder: *std.build.Builder, exe: *std.build.LibExeObjStep) !void {
    const export_script_path = "tools/mesh_export.py";
    const input_dir_path = "assets/meshes/";
    const output_dir_path = "deploy/data/meshes/";
    try std.fs.cwd().makePath(output_dir_path);

    var manifest_dir = try std.fs.cwd().makeOpenPath("zig-cache/assets/meshes/", .{});
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

        const output_file_name = try std.fmt.allocPrint(allocator, "{s}.bin", .{std.fs.path.stem(entry.path)});
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

        _ = try manifest.addFile(environment.blender_exe_path, null);
        _ = try manifest.addFile(export_script_path, null);
        _ = try manifest.addFile(input_file_path, null);
        if (try manifest.hit() and output_exists) {
            continue;
        }

        exe.step.dependOn(&builder.addSystemCommand(&[_][]const u8{
            environment.blender_exe_path,
            input_file_path,
            "-b",
            "-P",
            export_script_path,
            "--",
            output_file_path,
        }).step);

        if (manifest.have_exclusive_lock) {
            try manifest.writeManifest();
        }
    }
}

fn createGame(builder: *std.build.Builder) !void {
    const game = builder.addExecutable(.{
        .name = "game",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    if (optimize == .ReleaseFast or optimize == .ReleaseSmall) {
        game.subsystem = .Windows; // Hide console window
    }

    game.addIncludePath(.{ .path = "src/cimport/" });
    try addDependencyMimalloc(builder, game);
    try addDependencyGlfw(builder, game);
    try addDependencyVolk(builder, game);
    try addDependencyVulkan(builder, game);
    try addDependencySpirvReflect(builder, game);
    try addDependencyVma(builder, game);
    try compileShaders(builder, game);
    try exportMeshes(builder, game);

    builder.installArtifact(game);
    const run = builder.addRunArtifact(game);
    const run_step = builder.step("run", "Run game");
    run_step.dependOn(&run.step);
}

fn createTests(builder: *std.build.Builder) !void {
    const tests = builder.addTest(.{
        .name = "tests",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const install = builder.addInstallArtifact(tests, .{});
    const test_step = builder.step("tests", "Build tests");
    test_step.dependOn(&install.step);
}
