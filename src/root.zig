const std = @import("std");
const Backend = @import("backend/liburing.zig");

const EventLoop = struct {
    ctx: Backend.Context,
};

pub const Operation = enum { read, write, none };

pub const Request = struct {
    // the data word that will be submited with the queued entry
    token: usize,
    fd: u32,
    op_data: union(Operation) {
        read: []u8,
        write: []const u8,
        none: void,
    },

    user_data: ?*anyopaque,
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
