const std = @import("std");

const Environment = struct {
    vulkan_sdk_path: []const u8,
    vulkan_include_path: [:0]const u8,
    vulkan_lib_path: [:0]const u8,
    vulkan_bin_path: [:0]const u8,
    vulkan_glslc_path: [:0]const u8,
    blender_path: [:0]const u8,
    blender_exe_path: [:0]const u8,

    pub fn init() !Environment {
        const vulkan_sdk_path = try std.process.getEnvVarOwned(allocator, "VULKAN_SDK");
        errdefer allocator.free(vulkan_sdk_path);

        const vulkan_include_path = try std.fs.path.joinZ(allocator, &[_][]const u8{ vulkan_sdk_path, "Include" });
        errdefer allocator.free(vulkan_include_path);

        const vulkan_lib_path = try std.fs.path.joinZ(allocator, &[_][]const u8{ vulkan_sdk_path, "Lib" });
        errdefer allocator.free(vulkan_lib_path);

        const vulkan_bin_path = try std.fs.path.joinZ(allocator, &[_][]const u8{ vulkan_sdk_path, "Bin" });
        errdefer allocator.free(vulkan_bin_path);

        const vulkan_glslc_path = try std.fs.path.joinZ(allocator, &[_][]const u8{ vulkan_bin_path, "glslc.exe" });
        errdefer allocator.free(vulkan_glslc_path);

        const blender_path_hardcoded_windows = "C:\\Program Files\\Blender Foundation\\Blender 3.6";
        const blender_exe_path_hardcoded_windows = try std.fs.path.joinZ(allocator, &[_][]const u8{ blender_path_hardcoded_windows, "blender.exe" });
        errdefer allocator.free(blender_exe_path_hardcoded_windows);

        return Environment{
            .vulkan_sdk_path = vulkan_sdk_path,
            .vulkan_include_path = vulkan_include_path,
            .vulkan_lib_path = vulkan_lib_path,
            .vulkan_bin_path = vulkan_bin_path,
            .vulkan_glslc_path = vulkan_glslc_path,
            .blender_path = blender_path_hardcoded_windows,
            .blender_exe_path = blender_exe_path_hardcoded_windows,
        };
    }

    pub fn deinit(self: *Environment) void {
        allocator.free(self.vulkan_sdk_path);
        allocator.free(self.vulkan_include_path);
        allocator.free(self.vulkan_lib_path);
        allocator.free(self.vulkan_bin_path);
        allocator.free(self.vulkan_glslc_path);
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

    mimalloc.addIncludePath("deps/mimalloc/include/");
    mimalloc.linkLibC();

    exe.addIncludePath("deps/mimalloc/include/");
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

    exe.addIncludePath("deps/glfw/include/");
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

    volk.addIncludePath(environment.vulkan_include_path);
    volk.addIncludePath("deps/volk/");
    volk.addCSourceFile("deps/volk/volk.c", flags.items);
    volk.linkLibC();

    exe.addIncludePath("deps/volk/");
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

    vulkan.addIncludePath(environment.vulkan_include_path);
    vulkan.addCSourceFile("src/c/vulkan.cpp", flags.items);
    vulkan.linkLibCpp();

    exe.addIncludePath(environment.vulkan_include_path);
    exe.linkLibrary(vulkan);
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

    vma.addIncludePath(environment.vulkan_include_path);
    vma.addIncludePath("deps/vma/src/");
    vma.addCSourceFile("src/c/vma.cpp", flags.items);
    vma.linkLibCpp();

    exe.addIncludePath("deps/vma/src/");
    exe.linkLibrary(vma);
}

fn compileShaders(builder: *std.build.Builder, exe: *std.build.LibExeObjStep) !void {
    const input_dir_path = "assets/shaders/";
    var input_dir = try std.fs.cwd().openIterableDir(input_dir_path, .{});
    defer input_dir.close();

    const output_dir_path = "deploy/data/shaders/";
    try std.fs.cwd().makePath(output_dir_path);

    var vulkan_bin_dir = try std.fs.openDirAbsolute(environment.vulkan_bin_path, .{});
    defer vulkan_bin_dir.close();

    var cache = std.Build.Cache{
        .gpa = allocator,
        .manifest_dir = try std.fs.cwd().makeOpenPath("zig-cache/assets/shaders/", .{}),
    };
    cache.addPrefix(.{ .path = input_dir_path, .handle = input_dir.dir });
    cache.addPrefix(.{ .path = environment.vulkan_bin_path, .handle = vulkan_bin_dir });
    defer cache.manifest_dir.close();

    var walker = try input_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) {
            continue;
        }

        const input_file_path = try std.fs.path.joinZ(allocator, &[_][]const u8{ input_dir_path, entry.path });
        defer allocator.free(input_file_path);

        const output_file_path = try std.fmt.allocPrint(allocator, "{s}{s}.spv", .{ output_dir_path, entry.path });
        defer allocator.free(output_file_path);

        var output_exists = true;
        std.fs.cwd().access(output_file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => output_exists = false,
            else => return err,
        };

        var manifest = cache.obtain();
        defer manifest.deinit();

        _ = try manifest.addFile(environment.vulkan_glslc_path, null);
        _ = try manifest.addFile(entry.path, null);
        if (try manifest.hit() and output_exists) {
            continue;
        }

        const glslc = builder.addSystemCommand(&[_][]const u8{
            environment.vulkan_glslc_path,
            "-O",
            "-o",
            output_file_path,
            input_file_path,
        });

        exe.step.dependOn(&glslc.step);

        if (manifest.have_exclusive_lock) {
            try manifest.writeManifest();
        }
    }
}

fn exportMeshes(builder: *std.build.Builder, exe: *std.build.LibExeObjStep) !void {
    const input_dir_path = "assets/meshes/";
    var input_dir = try std.fs.cwd().openIterableDir(input_dir_path, .{});
    defer input_dir.close();

    const output_dir_path = "deploy/data/meshes/";
    try std.fs.cwd().makePath(output_dir_path);

    var blender_dir = try std.fs.openDirAbsolute(environment.blender_path, .{});
    defer blender_dir.close();

    var cache = std.Build.Cache{
        .gpa = allocator,
        .manifest_dir = try std.fs.cwd().makeOpenPath("zig-cache/assets/meshes/", .{}),
    };
    cache.addPrefix(.{ .path = input_dir_path, .handle = input_dir.dir });
    cache.addPrefix(.{ .path = environment.blender_path, .handle = blender_dir });
    defer cache.manifest_dir.close();

    const export_script_path = try std.fs.path.joinZ(allocator, &[_][]const u8{ input_dir_path, "export.py" });
    defer allocator.free(export_script_path);

    var walker = try input_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) {
            continue;
        }

        const input_file_path = try std.fs.path.joinZ(allocator, &[_][]const u8{ input_dir_path, entry.path });
        defer allocator.free(input_file_path);

        if (std.mem.eql(u8, input_file_path, export_script_path)) {
            continue;
        }

        const output_file_path = try std.fmt.allocPrint(allocator, "{s}{s}.bin", .{ output_dir_path, std.fs.path.stem(entry.path) });
        defer allocator.free(output_file_path);

        var output_exists = true;
        std.fs.cwd().access(output_file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => output_exists = false,
            else => return err,
        };

        var manifest = cache.obtain();
        defer manifest.deinit();

        _ = try manifest.addFile(environment.blender_exe_path, null);
        _ = try manifest.addFile(entry.path, null);
        if (try manifest.hit() and output_exists) {
            continue;
        }

        const export_mesh = builder.addSystemCommand(&[_][]const u8{
            environment.blender_exe_path,
            input_file_path,
            "-b",
            "-P",
            export_script_path,
            "--",
            output_file_path,
        });

        exe.step.dependOn(&export_mesh.step);

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

    game.addIncludePath("src/c/");
    try addDependencyMimalloc(builder, game);
    try addDependencyGlfw(builder, game);
    try addDependencyVolk(builder, game);
    try addDependencyVulkan(builder, game);
    try addDependencyVma(builder, game);
    try compileShaders(builder, game);
    try exportMeshes(builder, game);
    builder.installArtifact(game);

    const run = builder.addRunArtifact(game);
    const run_step = builder.step("run", "Run game");
    run_step.dependOn(&run.step);
}

fn createTests(builder: *std.build.Builder) !void {
    const exe_tests = builder.addTest(.{
        .name = "tests",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const test_step = builder.step("test", "Run tests");
    test_step.dependOn(&exe_tests.step);
}
