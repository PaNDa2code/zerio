pub const Context = struct {
    pub const ControlBlock = OVERLAPPED;

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
        // TODO
    }

    pub fn dequeue_timeout(self: *const Context, timeout_ns: u32, res: *i32) !?*const Request {
        // TODO
    }
};

const root = @import("../root.zig");
const Request = root.Request;
const Operation = root.Operation;
const Result = root.Result;

const windows = @import("std").os.windows;
const kernel32 = windows.kernel32;
const HANDLE = windows.HANDLE;
const INVALID_HANDLE_VALUE = windows.INVALID_HANDLE_VALUE;
const OVERLAPPED = windows.OVERLAPPED;
const CreateIoCompletionPort = windows.CreateIoCompletionPort;
const CloseHandle = windows.CloseHandle;
const ReadFile = kernel32.ReadFile;
const WriteFile = kernel32.WriteFile;
