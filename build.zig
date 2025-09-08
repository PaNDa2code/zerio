const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const liburing = blk: {
        const liburing = b.addLibrary(.{
            .name = "uring",
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            }),
        });

        if (b.lazyDependency("liburing", .{})) |dep| {
            liburing.root_module.addCSourceFiles(.{
                .root = dep.path("src"),
                .files = &.{
                    "setup.c",
                    "queue.c",
                    "register.c",
                    "syscall.c",
                    "version.c",
                },
            });
            liburing.installHeadersDirectory(dep.path("src/include"), "", .{});
            liburing.root_module.addIncludePath(dep.path("src/include"));
            liburing.root_module.addIncludePath(dep.path("src/arch"));
            liburing.root_module.addIncludePath(dep.path("src"));
            liburing.root_module.addCMacro("_GNU_SOURCE", "");
            liburing.root_module.addCMacro("_FILE_OFFSET_BITS", "64");
            liburing.root_module.addCMacro("_LARGEFILE_SOURCE", "");

        }

        b.installArtifact(liburing);

        break :blk liburing;
    };

    const mod = b.addModule("zerio", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    mod.linkLibrary(liburing);

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
