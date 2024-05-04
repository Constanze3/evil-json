const std = @import("std");
const json = @import("root.zig");

const Value = json.Value;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

test "json access" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var array = json.Array.init(allocator);
    try array.append(Value{ .string = "One" });
    try array.append(Value{ .string = "Two" });

    var object = json.Object.init(allocator);
    try object.put("numbers", Value{ .array = array });

    const value = Value{ .object = object };

    var access = Access.init(value, allocator);
    const string = try access.o("numbers").a(1).get_string();
    try std.testing.expectEqualSlices(u8, "Two", string);

    var access2 = Access.init(value, allocator);
    var err_index: usize = undefined;
    _ = access2.o("numbers").o("he").get_with_errinfo(&err_index) catch |err| {
        try std.testing.expectEqual(Access.Error.InvalidKeyType, err);
        try std.testing.expectEqual(1, err_index);
    };
}

/// Struct that provides an easy way to access child JSON values of a JSON value.
/// Use it only for convenience.
pub const Access = struct {
    target: Value,
    key_sequence: ArrayList(Key),
    out_of_memory: bool,

    /// A key to access a child value of a JSON value.
    const Key = union(enum) {
        object_key: []const u8,
        array_index: usize,
    };

    const Error = error{
        InvalidKeyType, // When object key is used on array or the reverse
        NoChildren, // When a child of a non object/array is attempted to be accessed
        NoSuchField, // When the value is an object and the specified key doesn't exist in the object
        IndexOutOfBounds, // When the value is an array and the specified index is out of bounds of the array
        OutOfMemory, // Couldn't append some key to the key sequence
    };

    /// Initializes a new JsonAccess
    pub fn init(target: Value, allocator: Allocator) @This() {
        return @This(){
            .target = target,
            .key_sequence = ArrayList(Key).init(allocator),
            .out_of_memory = false,
        };
    }

    /// Releases all allocated memory
    pub fn deinit(self: *@This()) void {
        self.key_sequence.deinit();
    }

    /// Appends a JsonAccessKey to the access sequence.
    pub fn append(self: *@This(), key: Key) *@This() {
        if (self.out_of_memory) {
            return self;
        }

        self.key_sequence.append(key) catch |err| switch (err) {
            Allocator.Error.OutOfMemory => {
                self.out_of_memory = true;
            },
        };

        return self;
    }

    /// Appends an object key to the access sequence.
    pub fn o(self: *@This(), key: []const u8) *@This() {
        return self.append(Key{ .object_key = key });
    }

    /// Appends an array index to the access sequence.
    /// Accepts anything that can coerce to `usize`.
    pub fn a(self: *@This(), index: anytype) *@This() {
        return self.append(Key{ .array_index = @as(usize, index) });
    }

    /// Evaluates the access sequence. In case of an error it reports the index of the key that caused it.
    pub fn get_with_errinfo(self: @This(), err_index: *usize) Error!Value {
        if (self.out_of_memory) {
            err_index.* = 0;
            return Error.OutOfMemory;
        }

        var current = self.target;

        for (self.key_sequence.items, 0..) |key, i| {
            switch (current) {
                .object => |obj| {
                    switch (key) {
                        .object_key => |k| {
                            if (obj.get(k)) |value| {
                                current = value;
                            } else {
                                err_index.* = i;
                                return Error.NoSuchField;
                            }
                        },
                        .array_index => {
                            err_index.* = i;
                            return Error.InvalidKeyType;
                        },
                    }
                },
                .array => |arr| {
                    switch (key) {
                        .object_key => {
                            err_index.* = i;
                            return Error.InvalidKeyType;
                        },
                        .array_index => |k| {
                            if (0 <= k and k < arr.items.len) {
                                current = arr.items[k];
                            } else {
                                err_index.* = i;
                                return Error.IndexOutOfBounds;
                            }
                        },
                    }
                },
                inline else => {
                    err_index.* = i;
                    return Error.NoChildren;
                },
            }
        }

        return current;
    }

    /// Evaluates the key sequence and returns the resulting value.
    pub fn get(self: @This()) Error!Value {
        var err_index: usize = undefined;
        return self.get_with_errinfo(&err_index);
    }

    /// Evaluates the key sequence and returns the resulting value.
    /// Also deinits the access.
    pub fn get_and_deinit(self: *@This()) Error!Value {
        const value = self.get();
        self.deinit();
        return value;
    }

    // Creates a copy of this access using the same allocator.
    pub fn clone(self: @This()) Allocator.Error!@This() {
        return @This(){
            .target = self.target,
            .key_sequence = try self.key_sequence.clone(),
            .out_of_memory = self.out_of_memory,
        };
    }
};
