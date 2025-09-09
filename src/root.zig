const std = @import("std");

test "backend" {
    std.testing.refAllDeclsRecursive(@import("backend/liburing.zig"));
}
