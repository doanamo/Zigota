const std = @import("std");
const shaders = @import("src/build/shaders.zig");
const meshes = @import("src/build/meshes.zig");

var allocator: std.mem.Allocator = undefined;
var target: std.zig.CrossTarget = undefined;
var optimize: std.builtin.Mode = undefined;

var vulkan_sdk_path: []const u8 = undefined;
var vulkan_include_path: []const u8 = undefined;

pub fn build(builder: *std.build.Builder) !void {
    allocator = builder.allocator;
    target = builder.standardTargetOptions(.{});
    optimize = builder.standardOptimizeOption(.{});

    vulkan_sdk_path = try std.process.getEnvVarOwned(allocator, "VULKAN_SDK");
    defer allocator.free(vulkan_sdk_path);

    vulkan_include_path = try std.fs.path.join(allocator, &[_][]const u8{ vulkan_sdk_path, "Include" });
    defer allocator.free(vulkan_include_path);

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

    volk.addIncludePath(.{ .path = vulkan_include_path });
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

    vulkan.addIncludePath(.{ .path = vulkan_include_path });
    vulkan.addCSourceFile(.{ .file = .{ .path = "src/cimport/vulkan.cpp" }, .flags = flags.items });
    vulkan.linkLibCpp();

    exe.addIncludePath(.{ .path = vulkan_include_path });
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

    vma.addIncludePath(.{ .path = vulkan_include_path });
    vma.addIncludePath(.{ .path = "deps/vma/src/" });
    vma.addCSourceFile(.{ .file = .{ .path = "src/cimport/vma.cpp" }, .flags = flags.items });
    vma.linkLibCpp();

    exe.addIncludePath(.{ .path = "deps/vma/src/" });
    exe.linkLibrary(vma);
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

    try shaders.compileAll(allocator, builder, game);
    try meshes.exportAll(allocator, builder, game);

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
