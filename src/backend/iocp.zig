pub const Context = struct {
    iocp: windows.HANDLE,

    pub fn setup(self: *Context) !void {
        self.iocp =
            try CreateIoCompletionPort(INVALID_HANDLE_VALUE, null, 0, 0);
    }

    pub fn close(self: *const Context) void {
        CloseHandle(self.iocp);
    }

    pub fn register(self: *const Context, req: *const Request) !void {
        _ = try CreateIoCompletionPort(req.handle, self.iocp, @intFromPtr(req), 0);
    }

    /// The `Request` must outlive its dequeuing.
    pub fn queue(self: *const Context, req: *const Request) !void {
        _ = self;

        const cb_ptr: *ControlBlock = @constCast(&req.control_block);

        const ret = switch (req.op_data) {
            .read => |buf| ReadFile(req.handle, buf.ptr, @intCast(buf.len), null, cb_ptr),
            .write => |buf| WriteFile(req.handle, buf.ptr, @intCast(buf.len), null, cb_ptr),
            .none => 1,
        };

        if (ret == 0) {
            return switch (windows.GetLastError()) {
                .IO_PENDING => {},
                .INVALID_USER_BUFFER => error.SystemResources,
                .NOT_ENOUGH_MEMORY => error.SystemResources,
                .OPERATION_ABORTED => error.OperationAborted,
                .NOT_ENOUGH_QUOTA => error.SystemResources,
                .NO_DATA => error.BrokenPipe,
                .INVALID_HANDLE => error.NotOpenForWriting,
                .LOCK_VIOLATION => error.LockViolation,
                .NETNAME_DELETED => error.ConnectionResetByPeer,
                .ACCESS_DENIED => error.AccessDenied,
                .WORKING_SET_QUOTA => error.SystemResources,
                else => |err| windows.unexpectedError(err),
            };
        }
    }

    pub fn submit(self: *const Context) !void {
        _ = self;
    }

    pub fn dequeue(self: *const Context, res: *i32) !*const Request {
        return (try self.dequeue_timeout(INFINITE, res)) orelse unreachable;
    }

    pub fn dequeue_timeout(self: *const Context, timeout_ms: u32, res: *i32) !?*const Request {
        var bytes: u32 = 0;
        var overlapped: ?*OVERLAPPED = null;
        var request_address: usize = 0;
        const stat = GetQueuedCompletionStatus(
            self.iocp,
            &bytes,
            &request_address,
            &overlapped,
            timeout_ms,
        );

        switch (stat) {
            .Normal => {
                res.* = @intCast(bytes);
                return @ptrFromInt(request_address);
            },
            .Timeout => return null,
            else => return windows.unexpectedError(windows.GetLastError()),
        }
    }
};

pub const ControlBlock = OVERLAPPED;

const root = @import("../root.zig");
const Request = root.Request;
const Operation = root.Operation;
const Result = root.Result;

const windows = @import("std").os.windows;
const kernel32 = windows.kernel32;
const HANDLE = windows.HANDLE;
const INVALID_HANDLE_VALUE = windows.INVALID_HANDLE_VALUE;
const INFINITE = windows.INFINITE;
const OVERLAPPED = windows.OVERLAPPED;
const CreateIoCompletionPort = windows.CreateIoCompletionPort;
const GetQueuedCompletionStatus = windows.GetQueuedCompletionStatus;
const CloseHandle = windows.CloseHandle;
const ReadFile = kernel32.ReadFile;
const WriteFile = kernel32.WriteFile;

test "iocp pipe write test (Windows)" {
    const std = @import("std");
    const c = @cImport({
        @cInclude("io.h");
        @cInclude("fcntl.h");
    });

    var context: Context = undefined;
    try context.setup();
    defer context.close();

    // Create a pipe
    var fds: [2]c_int = undefined;

    if (c._pipe(&fds, 4096, c._O_BINARY) != 0) {
        std.debug.print("pipe creation failed\n", .{});
        return;
    }

    defer _ = c._close(fds[0]);
    defer _ = c._close(fds[1]);

    const buf: []const u8 = @as([1000]u8, @splat(0xAA))[0..];

    var req = Request{
        .token = 1,
        .handle = @ptrFromInt(@as(usize, @intCast(fds[1]))),
        .op_data = .{ .write = buf },
        .user_data = null,
    };

    try context.queue(&req);
    try context.submit();

    var res: i32 = 0;
    const completed_req = try context.dequeue(&res);
    try std.testing.expect(completed_req == &req);
    try std.testing.expect(res == buf.len);

    var read_buf: [1002]u8 = undefined;
    const n = c._read(fds[0], &read_buf, @intCast(read_buf.len));
    try std.testing.expectEqualSlices(u8, buf[0..], read_buf[0..@intCast(n)]);
}
