const std = @import("std");

fn configureHidApiIncludes(translate_c: *std.Build.Step.TranslateC, os_tag: std.Target.Os.Tag) void {
    translate_c.addSystemIncludePath(.{ .cwd_relative = "/usr/include" });
    translate_c.addSystemIncludePath(.{ .cwd_relative = "/usr/local/include" });

    switch (os_tag) {
        .macos => {
            translate_c.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
        },
        .linux => {},
        else => @panic("unsupported target OS for hidapi"),
    }
}

fn configureHidApiLink(mod: *std.Build.Module, os_tag: std.Target.Os.Tag) void {
    switch (os_tag) {
        .macos => {
            mod.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
            mod.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
            mod.linkSystemLibrary("hidapi", .{});
        },
        .linux => mod.linkSystemLibrary("hidapi-hidraw", .{}),
        else => @panic("unsupported target OS for hidapi"),
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const os_tag = target.result.os.tag;

    // --- Build minifb as a static library ---
    const minifb_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    minifb_mod.addIncludePath(b.path("minifb/include"));
    minifb_mod.addIncludePath(b.path("minifb/src"));

    const minifb = b.addLibrary(.{
        .name = "minifb",
        .linkage = .static,
        .root_module = minifb_mod,
    });

    switch (os_tag) {
        .macos => {
            // Core files and Objective-C files use manual retain/release; do not enable ARC.
            minifb_mod.addCSourceFiles(.{
                .files = &.{
                    "minifb/src/MiniFB_common.c",
                    "minifb/src/MiniFB_internal.c",
                    "minifb/src/MiniFB_timer.c",
                    "minifb/src/macosx/MacMiniFB.m",
                    "minifb/src/macosx/OSXView.m",
                    "minifb/src/macosx/OSXViewDelegate.m",
                    "minifb/src/macosx/OSXWindow.m",
                },
                .flags = &.{"-DUSE_METAL_API"},
            });
        },
        .linux => {
            minifb_mod.addCSourceFiles(.{
                .files = &.{
                    "minifb/src/MiniFB_common.c",
                    "minifb/src/MiniFB_internal.c",
                    "minifb/src/MiniFB_timer.c",
                    "minifb/src/MiniFB_linux.c",
                    "minifb/src/x11/X11MiniFB.c",
                },
            });
        },
        else => @panic("unsupported target OS for just_draw"),
    }

    // --- Zig bindings via translate-c ---
    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/c.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    translate_c.addIncludePath(b.path("minifb/include"));
    configureHidApiIncludes(translate_c, os_tag);

    const c_module = translate_c.createModule();
    c_module.linkLibrary(minifb);

    const devs_mod = b.createModule(.{ .target = target, .optimize = optimize, .root_source_file = b.path("src/devices.zig") });

    devs_mod.addImport("c", c_module);

    // --- Main executable ---
    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("c", c_module);


    const hidder_dep = b.dependency("hidder", .{
        .target = target,
        .optimize = optimize,
    });
    const hidder_mod = hidder_dep.module("hidder");

    mod.addImport("hidder", hidder_mod);

    configureHidApiLink(mod, os_tag);

    switch (os_tag) {
        .macos => {
            mod.linkFramework("Cocoa", .{});
            mod.linkFramework("Metal", .{});
            mod.linkFramework("MetalKit", .{});
            mod.linkFramework("QuartzCore", .{});
            mod.addCSourceFiles(.{ .files = &.{"src/menu.m"} });
        },
        .linux => {
            mod.linkSystemLibrary("X11", .{});
            mod.linkSystemLibrary("xkbcommon", .{});
        },
        else => unreachable,
    }

    const exe = b.addExecutable(.{
        .name = "just_draw",
        .root_module = mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
