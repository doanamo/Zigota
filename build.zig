const std = @import("std");

var target: std.zig.CrossTarget = undefined;
var mode: std.builtin.Mode = undefined;

pub fn build(builder: *std.build.Builder) void {
    target = builder.standardTargetOptions(.{});
    mode = builder.standardReleaseOptions();

    createGame(builder) catch undefined;
    createTests(builder) catch undefined;
}

fn addDependencyMimalloc(builder: *std.build.Builder, exe: *std.build.LibExeObjStep) !void {
    const mimalloc = builder.addStaticLibrary("mimalloc", null);
    mimalloc.setTarget(target);
    mimalloc.setBuildMode(mode);

    var flags = std.ArrayList([]const u8).init(builder.allocator);
    try flags.append("-DMI_STATIC_LIB");

    if (mode == .Debug) {
        // NOTE Workaround for not being able to debug C code
        try flags.append("-g");
    }

    if (mode == .Debug or mode == .ReleaseSafe) {
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
    const glfw = builder.addStaticLibrary("glfw", null);
    glfw.setTarget(target);

    // Compile GLFW with optimizations for size
    glfw.setBuildMode(if (mode != .Debug) .ReleaseSmall else mode);

    var flags = std.ArrayList([]const u8).init(builder.allocator);
    if (mode == .Debug) {
        // NOTE Workaround for not being able to debug C code
        try flags.append("-g");
    }

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

fn addDependencyVulkan(builder: *std.build.Builder, exe: *std.build.LibExeObjStep) !void {
    const vulkan_sdk = try std.process.getEnvVarOwned(builder.allocator, "VULKAN_SDK");
    defer builder.allocator.free(vulkan_sdk);

    const vulkan_lib = try std.fmt.allocPrintZ(builder.allocator, "{s}{s}", .{ vulkan_sdk, "/Lib/" });
    defer builder.allocator.free(vulkan_lib);

    const vulkan_include = try std.fmt.allocPrintZ(builder.allocator, "{s}{s}", .{ vulkan_sdk, "/Include/" });
    defer builder.allocator.free(vulkan_include);

    const vulkan = builder.addStaticLibrary("vulkan", null);
    vulkan.setTarget(target);
    vulkan.setBuildMode(mode);

    var flags = std.ArrayList([]const u8).init(builder.allocator);
    if (mode == .Debug) {
        // NOTE Workaround for not being able to debug C code
        try flags.append("-g");
    }
    try flags.append("-std=c++11");

    vulkan.addIncludePath(vulkan_include);
    vulkan.addCSourceFile("src/c/vulkan.cpp", flags.items);
    vulkan.linkLibCpp();

    exe.addLibraryPath(vulkan_lib);
    exe.addIncludePath(vulkan_include);
    exe.linkSystemLibrary("vulkan-1");
    exe.linkLibrary(vulkan);
}

fn compileShaders(builder: *std.build.Builder, exe: *std.build.LibExeObjStep) !void {
    const input_dir_path = "assets/shaders/";
    const output_dir_path = "deploy/data/shaders/";

    try std.fs.cwd().makePath(output_dir_path);
    var input_dir = try std.fs.cwd().openIterableDir(input_dir_path, .{});
    defer input_dir.close();

    var walker = try input_dir.walk(builder.allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .File) {
            continue;
        }

        const input_file_path = try std.fs.path.join(builder.allocator, &[_][]const u8{ input_dir_path, entry.path });
        defer builder.allocator.free(input_file_path);

        const output_file_path = try std.fmt.allocPrint(builder.allocator, "{s}{s}.spv", .{ output_dir_path, entry.basename });
        defer builder.allocator.free(output_file_path);

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
    const game = builder.addExecutable("game", "src/main.zig");
    game.setTarget(target);
    game.setBuildMode(mode);

    if (mode == .ReleaseSmall) {
        // NOTE Workaround for errors in release-small mode
        // https://github.com/ziglang/zig/issues/13405
        game.strip = true;
    }

    if (mode == .ReleaseFast or mode == .ReleaseSmall) {
        // Hide console window in release mode
        game.subsystem = .Windows;
    }

    game.addIncludePath("src/c/");
    try addDependencyMimalloc(builder, game);
    try addDependencyGlfw(builder, game);
    try addDependencyVulkan(builder, game);
    try compileShaders(builder, game);
    game.install();

    const run_cmd = game.run();
    const run_step = builder.step("run", "Run game");
    run_step.dependOn(&run_cmd.step);
}

fn createTests(builder: *std.build.Builder) !void {
    const exe_tests = builder.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = builder.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
