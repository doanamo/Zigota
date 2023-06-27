const std = @import("std");

const Environment = struct {
    vulkan_sdk: []u8,
    vulkan_include: []u8,
    vulkan_lib: []u8,

    pub fn init() !Environment {
        const vulkan_sdk = try std.process.getEnvVarOwned(allocator, "VULKAN_SDK");
        errdefer allocator.free(vulkan_sdk);

        const vulkan_include = try std.fmt.allocPrintZ(allocator, "{s}{s}", .{ vulkan_sdk, "/Include/" });
        errdefer allocator.free(vulkan_include);

        const vulkan_lib = try std.fmt.allocPrintZ(allocator, "{s}{s}", .{ vulkan_sdk, "/Lib/" });
        errdefer allocator.free(vulkan_lib);

        return Environment{
            .vulkan_sdk = vulkan_sdk,
            .vulkan_include = vulkan_include,
            .vulkan_lib = vulkan_lib,
        };
    }

    pub fn deinit(self: *Environment) void {
        allocator.free(self.vulkan_sdk);
        allocator.free(self.vulkan_include);
        allocator.free(self.vulkan_lib);
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

    volk.addIncludePath(environment.vulkan_include);
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

    vulkan.addIncludePath(environment.vulkan_include);
    vulkan.addCSourceFile("src/c/vulkan.cpp", flags.items);
    vulkan.linkLibCpp();

    exe.addIncludePath(environment.vulkan_include);
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

    vma.addIncludePath(environment.vulkan_include);
    vma.addIncludePath("deps/vma/src/");
    vma.addCSourceFile("src/c/vma.cpp", flags.items);
    vma.linkLibCpp();

    exe.addIncludePath("deps/vma/src/");
    exe.linkLibrary(vma);
}

fn compileShaders(builder: *std.build.Builder, exe: *std.build.LibExeObjStep) !void {
    const input_dir_path = "assets/shaders/";
    const output_dir_path = "deploy/data/shaders/";

    try std.fs.cwd().makePath(output_dir_path);
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

        const output_file_path = try std.fmt.allocPrint(allocator, "{s}{s}.spv", .{ output_dir_path, entry.basename });
        defer allocator.free(output_file_path);

        const glslc = builder.addSystemCommand(&[_][]const u8{
            "glslc",
            "-O",
            "-o",
            output_file_path,
            input_file_path,
        });

        exe.step.dependOn(&glslc.step);
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
