const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    root_module.addIncludePath(b.path("."));
    root_module.addCSourceFile(.{ .file = b.path("miniaudio_impl.c") });

    const exe = b.addExecutable(.{
        .name = "daw",
        .root_module = root_module,
    });

    b.installArtifact(exe);
}
