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

    var access = JsonAccess.init(value, allocator);
    const string = try access.o("numbers").a(1).get_string();
    try std.testing.expectEqualSlices(u8, "Two", string);

    var access2 = JsonAccess.init(value, allocator);
    var err_index: usize = undefined;
    _ = access2.o("numbers").o("he").get_with_errinfo(&err_index) catch |err| {
        try std.testing.expectEqual(JsonAccess.Error.InvalidKeyType, err);
        try std.testing.expectEqual(1, err_index);
    };
}

/// Struct that provides an easy way to access child JSON values of a JSON value.
/// Use it only for convenience.
pub const JsonAccess = struct {
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

    /// Initialize a new JsonAccess
    pub fn init(target: Value, allocator: Allocator) @This() {
        return @This(){
            .target = target,
            .key_sequence = ArrayList(Key).init(allocator),
            .out_of_memory = false,
        };
    }

    /// Release all allocated memory
    pub fn deinit(self: *@This()) void {
        self.key_sequence.deinit();
    }

    /// Append a JsonAccessKey to the access sequence.
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

    /// Append an object key to the access sequence.
    pub fn o(self: *@This(), key: []const u8) *@This() {
        return self.append(Key{ .object_key = key });
    }

    /// Append an array index to the access sequence.
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

    /// Evaluates the access sequence.
    pub fn get(self: @This()) Error!Value {
        var err_index: usize = undefined;
        return self.get_with_errinfo(&err_index);
    }

    /// Evaluate the access sequence and return it as a string value.
    /// It should be certain that the obtained value is a string, if it is not, switch on get() instead.
    pub fn get_string(self: @This()) Error![]const u8 {
        return (try self.get()).string;
    }

    /// Evaulate the access sequence and return the result as a number value.
    /// It should be certain that the obtained value is a number, if it is not, switch on get() instead.
    pub fn get_number(self: @This()) Error!f64 {
        return (try self.get()).number;
    }

    /// Evaluate the access sequence and return the result as an json.Object value.
    /// It should be certain that the obtained value is an object, if it is not, switch on get() instead.
    pub fn get_object(self: @This()) Error!json.Object {
        return (try self.get()).object;
    }

    /// Evaluate the access sequence and return the result as a json.Array value.
    /// It should be certain that the obtained value is an array, if it is not, switch on get() instead.
    pub fn get_array(self: @This()) Error!json.Array {
        return (try self.get()).array;
    }

    /// Evaluate the access sequence and return the result as a bool value.
    /// It should be certain that the obtained value is a boolean, if it is not, switch on get() instead.
    pub fn get_boolean(self: @This()) Error!bool {
        return (try self.get()).bool;
    }
};
