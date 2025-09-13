const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zerio", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (target.result.os.tag == .linux) {
        if (target.query.isNative()) {
            mod.linkSystemLibrary("liburing", .{});
        } else {
            const liburing = b.addLibrary(.{
                .name = "uring",
                .root_module = b.createModule(.{
                    .target = target,
                    .optimize = optimize,
                    .link_libc = true, // doesn't mean it will use it
                }),
            });

            if (b.lazyDependency("liburing", .{})) |dep| {
                const gen_headers = dep.builder.addWriteFiles();

                _ = gen_headers.add("liburing/compat.h",
                    \\#ifndef LIBURING_COMPAT_H
                    \\#define LIBURING_COMPAT_H
                    \\#include <linux/time_types.h>
                    \\#include <linux/openat2.h>
                    \\#include <linux/futex.h>
                    \\#include <linux/blkdev.h>
                    \\#include <sys/wait.h>
                    \\#endif
                );

                _ = gen_headers.add("liburing/io_uring_version.h",
                    \\#ifndef LIBURING_VERSION_H
                    \\#define LIBURING_VERSION_H
                    \\
                    \\#define IO_URING_VERSION_MAJOR 2
                    \\#define IO_URING_VERSION_MINOR 12
                    \\
                    \\#endif
                );

                const config_header = dep.builder.addConfigHeader(.{}, .{
                    .CONFIG_NOLIBC = {},
                    .CONFIG_HAVE_KERNEL_RWF_T = {},
                    .CONFIG_HAVE_KERNEL_TIMESPEC = {},
                    .CONFIG_HAVE_OPEN_HOW = {},
                    .CONFIG_HAVE_STATX = {},
                    .CONFIG_HAVE_GLIBC_STATX = {},
                    .CONFIG_HAVE_CXX = {},
                    .CONFIG_HAVE_UCONTEXT = {},
                    .CONFIG_HAVE_STRINGOP_OVERFLOW = {},
                    .CONFIG_HAVE_ARRAY_BOUNDS = {},
                    .CONFIG_HAVE_MEMFD_CREATE = {},
                    .CONFIG_HAVE_NVME_URING = {},
                    .CONFIG_HAVE_FANOTIFY = {},
                    .CONFIG_HAVE_FUTEXV = {},
                    .CONFIG_HAVE_UBLK_HEADER = {},
                });

                liburing.root_module.addCSourceFiles(.{
                    .root = dep.path("src"),
                    .files = &.{
                        "setup.c",
                        "queue.c",
                        "register.c",
                        "syscall.c",
                        "version.c",
                        "nolibc.c",
                    },
                    .flags = &.{
                        "-D_GNU_SOURCE",
                        "-D_FILE_OFFSET_BITS=64",
                        "-D_LARGEFILE_SOURCE",
                        "-includeconfig.h",
                    },
                });

                liburing.installHeadersDirectory(dep.path("src/include"), "", .{});
                liburing.installHeadersDirectory(gen_headers.getDirectory(), "", .{});
                liburing.root_module.addIncludePath(dep.path("src/include"));
                liburing.root_module.addIncludePath(dep.path("src/arch"));
                liburing.root_module.addIncludePath(dep.path("src"));
                liburing.root_module.addIncludePath(gen_headers.getDirectory());

                liburing.root_module.addConfigHeader(config_header);
            }

            mod.linkLibrary(liburing);
        }
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
