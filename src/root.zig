const std = @import("std");

pub const parse = @import("parse.zig").parse;
pub const stringify = @import("stringify.zig").stringify;
pub const Access = @import("access.zig").JsonAccess;

pub const Object = std.StringArrayHashMap(Value);
pub const Array = std.ArrayList(Value);

pub const Value = union(enum) {
    string: []const u8,
    number: f64,
    object: Object,
    array: Array,
    bool: bool,
    null: void,

    pub fn print(self: @This()) void {
        nosuspend stringify(self, std.io.getStdErr().writer()) catch return;
    }
};

test "deinit Parsed" {
    const parsed = try parse("[12, 23, 33]", std.testing.allocator);
    parsed.deinit();
}

pub const Parsed = struct {
    value: Value,
    arena: *std.heap.ArenaAllocator,

    pub fn deinit(self: @This()) void {
        const allocator = self.arena.child_allocator;
        self.arena.deinit();
        allocator.destroy(self.arena);
    }
};

test {
    _ = @import("access.zig");
    _ = @import("stringify.zig");
}

test "stringify" {
    const parsed = try parse("{\n \t \n \"name\": \"Bob\",       \"things\": \n [\"apple\", 12]}", std.testing.allocator);
    defer parsed.deinit();

    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    try stringify(parsed.value, list.writer());
    try std.testing.expectEqualSlices(u8, "{\"name\": \"Bob\", \"things\": [\"apple\", 12]}", list.items);
}
