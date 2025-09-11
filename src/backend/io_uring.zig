pub const Context = struct {
    ring: c.io_uring,

    pub fn setup(self: *Context) !void {
        _ = c.io_uring_queue_init(8, @ptrCast(&self.ring), 0);
    }

    pub fn close(self: *const Context) void {
        c.io_uring_queue_exit(@ptrCast(@constCast(&self.ring)));
    }
    pub fn register(self: *const Context, req: *const Request) !void {
        _ = self;
        _ = req;
    }

    /// The `Request` must outlive its dequeuing.
    pub fn queue(self: *const Context, req: *const Request) !void {
        const sqe = c.io_uring_get_sqe(@ptrCast(@constCast(&self.ring)));
        if (sqe == null) return error.QueueFull;
        switch (req.op_data) {
            .read => |buf| {
                c.io_uring_prep_read(sqe, @intCast(req.handle), buf.ptr, @intCast(buf.len), 0);
            },
            .write => |buf| {
                c.io_uring_prep_write(sqe, @intCast(req.handle), buf.ptr, @intCast(buf.len), 0);
            },
            .none => {},
        }
        c.io_uring_sqe_set_data(sqe, @constCast(req));
    }

    pub fn submit(self: *const Context) !void {
        const ret = c.io_uring_submit(@ptrCast(@constCast(&self.ring)));
        if (ret < 0) return @errorFromInt(@as(u16, @intCast(-ret)));
    }

    pub fn dequeue(self: *const Context, res: *i32) !*const Request {
        var cqe: ?*c.io_uring_cqe = null;
        const ret =
            c.io_uring_wait_cqe_nr(@ptrCast(@constCast(&self.ring)), &cqe, 1);

        if (ret < 0) return @errorFromInt(@as(u16, @intCast(-ret)));

        res.* = @intCast(cqe.?.res);
        return @ptrFromInt(@as(usize, @intCast(cqe.?.user_data)));
    }

    pub fn dequeue_timeout(self: *const Context, timeout_ms: u32, res: *i32) !?*const Request {
        var cqe: ?*c.io_uring_cqe = null;

        var timeout = c.struct___kernel_timespec{
            .tv_nsec = timeout_ms * 1000,
        };

        const ret = c.io_uring_wait_cqe_timeout(@ptrCast(@constCast(&self.ring)), &cqe, &timeout);

        if (ret < 0)
            return switch (@errorFromInt(@as(u16, @intCast(-ret)))) {
                error.ETIME => null,
                else => |err| err,
            };

        res.* = @intCast(cqe.?.res);

        return @ptrFromInt(@as(usize, @intCast(cqe.?.user_data)));
    }
};

pub const ControlBlock = void;

const root = @import("../root.zig");
const Request = root.Request;
const Operation = root.Operation;
const Result = root.Result;

const c = @cImport({
    @cInclude("liburing.h");
});

export fn io_uring_load_sq_head(ring: *const c.io_uring) c_uint {
    if (ring.flags & c.IORING_SETUP_SQPOLL != 0)
        return @atomicLoad(c_uint, @as(*const c_uint, @ptrCast(ring.sq.khead)), .acquire);
    return ring.sq.khead.*;
}

test "io_uring pipe write test" {
    const std = @import("std");
    const c_unistd = @cImport({
        @cInclude("unistd.h");
    });

    var context: Context = undefined;
    try context.setup();
    defer context.close();

    // Create a pipe
    var fds: [2]c_int = undefined;
    if (c_unistd.pipe(&fds) != 0) {
        std.debug.print("pipe creation failed\n", .{});
        return;
    }
    defer _ = c_unistd.close(fds[0]);
    defer _ = c_unistd.close(fds[1]);

    // Buffer to write
    const buf: []const u8 = @as([1000]u8, @splat(0xAA))[0..];

    // Queue a write to the pipe's write end
    var req = Request{
        .handle = @intCast(fds[1]),
        .op_data = .{ .write = buf },
    };

    try context.queue(&req);
    try context.submit();

    var res: i32 = 0;
    const completed_req = try context.dequeue(&res);
    try std.testing.expect(completed_req == &req);
    try std.testing.expect(res == buf.len);

    var read_buf: [1002]u8 = undefined;
    const n = c_unistd.read(fds[0], &read_buf, @intCast(read_buf.len));
    try std.testing.expectEqualSlices(u8, buf[0..], read_buf[0..@intCast(n)]);
}
