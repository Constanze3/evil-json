const std = @import("std");

const Allocator = std.mem.Allocator;
const Arena = std.heap.ArenaAllocator;

pub const parse = @import("parse.zig").parse;
pub const stringify = @import("stringify.zig").stringify;
pub const Access = @import("access.zig").Access;

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
    arena: *Arena,

    pub fn deinit(self: @This()) void {
        const allocator = self.arena.child_allocator;
        self.arena.deinit();
        allocator.destroy(self.arena);
    }

    /// Returns a JSON Access from the JSON value of this struct
    /// allocated with the arena allocator of this struct.
    pub fn access(self: @This()) Access {
        return self.accessUnmanaged(self.arena.allocator());
    }

    /// Returns a JSON Access from the Json value of this struct.
    pub fn accessUnmanaged(self: @This(), allocator: Allocator) Access {
        return Access.init(self.value, allocator);
    }
};

test {
    _ = @import("access.zig");
    _ = @import("stringify.zig");
}

test "stringify" {
    const parsed = try parse(
        "{\n \t \n \"name\": \"Bob\",       \"things\": \n [\"apple\", 12]}",
        std.testing.allocator,
    );
    defer parsed.deinit();

    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    try stringify(parsed.value, list.writer());
    try std.testing.expectEqualSlices(u8, "{\"name\": \"Bob\", \"things\": [\"apple\", 12]}", list.items);
}
