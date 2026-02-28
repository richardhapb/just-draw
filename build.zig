const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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

    // Core minifb sources
    minifb_mod.addCSourceFiles(.{
        .files = &.{
            "minifb/src/MiniFB_common.c",
            "minifb/src/MiniFB_internal.c",
            "minifb/src/MiniFB_timer.c",
        },
    });

    // macOS-specific sources (Objective-C) - no ARC, minifb uses manual retain/release
    minifb_mod.addCSourceFiles(.{
        .files = &.{
            "minifb/src/macosx/MacMiniFB.m",
            "minifb/src/macosx/OSXView.m",
            "minifb/src/macosx/OSXViewDelegate.m",
            "minifb/src/macosx/OSXWindow.m",
        },
    });

    minifb_mod.linkFramework("Cocoa", .{});
    minifb_mod.linkFramework("Metal", .{});
    minifb_mod.linkFramework("MetalKit", .{});
    minifb_mod.linkFramework("QuartzCore", .{});

    // --- Zig bindings via translate-c ---
    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/c.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    translate_c.addIncludePath(b.path("minifb/include"));

    const c_module = translate_c.createModule();
    c_module.linkLibrary(minifb);

    // --- Main executable ---
    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("c", c_module);

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
