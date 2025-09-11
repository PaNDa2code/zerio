const std = @import("std");
const builtin = @import("builtin");

const Backend = switch (builtin.os.tag) {
    .windows => @import("backend/iocp.zig"),
    .linux => @import("backend/io_uring.zig"),
    else => @compileError("Target os is not supported"),
};

const EventLoop = struct {
    ctx: Backend.Context,
};

pub const Operation = enum { read, write, none };

pub const Request = struct {
    const ControlBlock = Backend.ControlBlock;

    // the data word that will be submited with the queued entry
    token: usize,
    handle: if (builtin.os.tag == .windows) *anyopaque else u32,
    op_data: union(Operation) {
        read: []u8,
        write: []const u8,
        none: void,
    },
    control_block: ControlBlock = std.mem.zeroes(ControlBlock),

    user_data: ?*anyopaque = null,
};

pub const Result = struct {
    req: *Request,
    od_res: union(Operation) {
        read: usize,
        write: usize,
        none,
    },
};

test Backend {
    std.testing.refAllDeclsRecursive(Backend);
}
