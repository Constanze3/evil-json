const std = @import("std");

/// Hash context for std.ArrayList(u8)
const ArrayListU8HashContext = struct {
    pub fn hash(_: ArrayListU8HashContext, key: std.ArrayList(u8)) u64 {
        var h = std.hash.Fnv1a_64.init();
        h.update(key.items);
        return h.final();
    }

    pub fn eql(_: ArrayListU8HashContext, a: std.ArrayList(u8), b: std.ArrayList(u8)) bool {
        return std.mem.eql(u8, a.items, b.items);
    }
};

/// Data structure for Json values.
pub const Json = union(enum) {
    string: std.ArrayList(u8),
    number: f64,
    object: Object(),
    array: std.ArrayList(*const Json),
    /// Json bool values are named boolean instead since bool is a Zig type.
    boolean: bool,

    /// std.HashMap with K: ArrayList(u8) V: \*const Json.
    pub fn Object() type {
        return std.HashMap(
            std.ArrayList(u8),
            *const Json,
            ArrayListU8HashContext,
            std.hash_map.default_max_load_percentage,
        );
    }
};

test "json model" {
    // var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    // defer arena.deinit();

    // const allocator = arena.allocator();

    // const u = Util{ .allocator = allocator };

    // const j1 = Json{
    //     .string = try u.string("very weak"),
    // };

    // var j2_object = Json.Object().init(allocator);
    // try j2_object.put(try u.string("strength"), &j1);
    // const j2 = Json{ .object = j2_object };

    // try std.testing.expectEqualStrings("very weak", j2.object.get(try u.string("strength")).?.string.items);
}

/// A key to access a child JSON value of a JSON value.
pub const JsonAccessKey = union(enum) {
    object_key: std.ArrayList(u8),
    array_index: usize,
};

/// Error set in case evaluating a `JsonAccess` fails.
pub const JsonAccessError = error{ InvalidKeyType, NoChildren, NoSuchField };

/// Struct that provides an easy way to access child JSON values of a JSON value.
pub const JsonAccess = struct {
    allocator: std.mem.Allocator,
    target: *const Json,
    key_sequence: std.ArrayList(JsonAccessKey),

    pub fn new(target: *const Json, allocator: std.mem.Allocator) JsonAccess {
        return JsonAccess{
            .allocator = allocator,
            .target = target,
            .key_sequence = std.ArrayList(JsonAccessKey).init(allocator),
        };
    }

    /// Appends an object key to the access sequence.
    /// Accepts anything that can coerce to `[]const u8` or an `std.ArrayList(u8)`.
    pub fn o(self: *JsonAccess, key: anytype) *JsonAccess {
        const access_key = parse_access_key: {
            switch (@TypeOf(key)) {
                std.ArrayList(u8) => {
                    break :parse_access_key JsonAccessKey{ .object_key = key };
                },
                else => {
                    var list = std.ArrayList(u8).init(self.allocator);
                    list.appendSlice(@as([]const u8, key)) catch unreachable;
                    break :parse_access_key JsonAccessKey{ .object_key = list };
                },
            }
        };

        return self.append(access_key);
    }

    /// Appends an array index to the access sequence.
    /// Accepts anything that can coerce to `usize`.
    pub fn a(self: *JsonAccess, index: anytype) *JsonAccess {
        return self.append(JsonAccessKey{
            .array_index = @as(usize, index),
        });
    }

    /// Appends a JsonAccessKey to the access sequence.
    pub fn append(self: *JsonAccess, key: JsonAccessKey) *JsonAccess {
        self.key_sequence.append(key) catch unreachable;
        return self;
    }

    /// Evaluates the access sequence.
    pub fn get(self: *const JsonAccess) JsonAccessError!*const Json {
        var current: *const Json = self.target;
        for (self.key_sequence.items) |key| {
            switch (current.*) {
                .object => |obj| {
                    switch (key) {
                        .object_key => |k| {
                            if (obj.get(k)) |*value| {
                                current = value.*;
                            } else {
                                return JsonAccessError.NoSuchField;
                            }
                        },
                        .array_index => return JsonAccessError.InvalidKeyType,
                    }
                },
                .array => |arr| {
                    switch (key) {
                        .object_key => return JsonAccessError.InvalidKeyType,
                        .array_index => |k| {
                            current = arr.items[k];
                        },
                    }
                },
                inline else => return JsonAccessError.NoChildren,
            }
        }

        return current;
    }

    /// Evaluates the access sequence and returns its string value.
    /// It must be certain that the obtained value is a string, if it is not, switch on get() instead.
    pub fn get_string(self: *const JsonAccess) JsonAccessError![]const u8 {
        const val = try self.get();
        return val.string.items;
    }

    /// Evaulates the access sequence and returns its number value.
    /// It must be certain that the obtained value is a number, if it is not, switch on get() instead.
    pub fn get_number(self: *const JsonAccess) JsonAccessError!f64 {
        const val = try self.get();
        return val.number;
    }

    /// Evaluates the access sequence and returns its object value.
    /// It must be certain that the obtained value is an object, if it is not, switch on get() instead.
    pub fn get_object(self: *const JsonAccess) JsonAccessError!*const Json.Object() {
        const val = try self.get();
        return val.object;
    }

    /// Evaluates the access sequence and returns its array value.
    /// It must be certain that the obtained value is an array, if it is not, switch on get() instead.
    pub fn get_array(self: *const JsonAccess) JsonAccessError![]const *const Json {
        const val = try self.get();
        return val.array.items;
    }

    /// Evaluates the access sequence and returns its boolean value.
    /// It must be certain that the obtained value is a boolean, if it is not, switch on get() instead.
    pub fn get_boolean(self: *const JsonAccess) JsonAccessError!bool {
        const val = try self.get();
        return val.boolean;
    }
};

// pub fn decodeJson(data: []const u8) Json {
//     _ = data;
// }
