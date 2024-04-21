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
    string: *std.ArrayList(u8),
    number: f64,
    object: *Object(),
    array: *std.ArrayList(*Json),
    /// Json bool values are named boolean instead since bool is a Zig type.
    boolean: bool,
    null: void,

    pub fn Object() type {
        return std.StringHashMap(*Json);
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
    target: *Json,
    key_sequence: std.ArrayList(JsonAccessKey),

    pub fn new(target: *Json, allocator: std.mem.Allocator) JsonAccess {
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
    pub fn get(self: *const JsonAccess) JsonAccessError!*Json {
        var current: *Json = self.target;
        for (self.key_sequence.items) |key| {
            switch (current.*) {
                .object => |obj| {
                    switch (key) {
                        .object_key => |k| {
                            if (obj.get(k.items)) |*value| {
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
    pub fn get_object(self: *const JsonAccess) JsonAccessError!*Json.Object() {
        const val = try self.get();
        return val.object;
    }

    /// Evaluates the access sequence and returns its array value.
    /// It must be certain that the obtained value is an array, if it is not, switch on get() instead.
    pub fn get_array(self: *const JsonAccess) JsonAccessError![]const *Json {
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

const CharacterIteratorError = error{NoCurrentYet};
const CharacterIterator = struct {
    slice: []const u8,
    i: usize,

    fn new(slice: []const u8) CharacterIterator {
        return CharacterIterator{ .slice = slice, .i = 0 };
    }

    fn current(self: *CharacterIterator) CharacterIteratorError!?u8 {
        if (self.i == 0) {
            return CharacterIteratorError.NoCurrentYet;
        }

        if (self.i - 1 == self.slice.len) {
            return null;
        }

        return self.slice[self.i - 1];
    }

    fn next(self: *CharacterIterator) ?u8 {
        if (self.i < self.slice.len) {
            const value = self.slice[self.i];
            self.i += 1;
            return value;
        }

        self.i = self.slice.len + 1;
        return null;
    }
};

const JsonDecodeError = error{ InvalidFormat, NotImplementedYet, OutOfMemory };

pub fn decode_json(data: []const u8, allocator: std.mem.Allocator) JsonDecodeError!*Json {
    var iter = CharacterIterator.new(data);
    const result = try JsonDecoderUnmanaged.parse_value(&iter, allocator);

    if (iter.next() != null) {
        return JsonDecodeError.InvalidFormat;
    }

    return result;
}

const JsonDecoderUnmanaged = struct {
    fn is_whitespace(character: u8) bool {
        for (" \n\r\t") |c| {
            if (c == character) {
                return true;
            }
        }
        return false;
    }

    fn consume_whitespace(iter: *CharacterIterator) void {
        var c = iter.current() catch iter.next();
        while (true) {
            if (c == null or !is_whitespace(c.?)) {
                break;
            }
            c = iter.next();
        }
    }

    fn parse_value(iter: *CharacterIterator, allocator: std.mem.Allocator) JsonDecodeError!*Json {
        consume_whitespace(iter);

        const first_non_whitespace = iter.current() catch unreachable;
        if (first_non_whitespace == null) {
            return JsonDecodeError.InvalidFormat;
        }

        var value: Json = val: {
            switch (first_non_whitespace.?) {
                '{' => {
                    std.debug.print("object\n", .{});
                    break :val Json{ .object = try parse_object(iter, allocator) };
                },
                '[' => {
                    std.debug.print("array\n", .{});
                    break :val Json{ .array = try parse_array(iter, allocator) };
                },
                '"' => {
                    std.debug.print("string\n", .{});
                    break :val Json{ .string = try parse_string(iter, allocator) };
                },
                't' => {
                    std.debug.print("boolean\n", .{});
                    try confirm(iter, "true");
                    break :val Json{ .boolean = true };
                },
                'f' => {
                    std.debug.print("boolean\n", .{});
                    try confirm(iter, "false");
                    break :val Json{ .boolean = false };
                },
                'n' => {
                    std.debug.print("null\n", .{});
                    try confirm(iter, "null");
                    break :val Json{ .null = {} };
                },
                else => {
                    break :val Json{ .number = try parse_number(iter, allocator) };
                },
            }
        };

        consume_whitespace(iter);

        switch (value) {
            .array => |a| {
                std.debug.print("{d}\n", .{a.items.len});
            },
            else => {},
        }

        return &value;
    }

    fn parse_string(iter: *CharacterIterator, allocator: std.mem.Allocator) JsonDecodeError!*std.ArrayList(u8) {
        const start = iter.current() catch unreachable;
        if (start == null or start.? != '"') {
            return JsonDecodeError.InvalidFormat;
        }

        var string = std.ArrayList(u8).init(allocator);

        while (true) {
            if (iter.next()) |c| {
                if (c == '"') {
                    break;
                }

                try string.append(c);
            } else {
                return JsonDecodeError.InvalidFormat;
            }
        }

        _ = iter.next();
        return &string;
    }

    fn parse_number(iter: *CharacterIterator, allocator: std.mem.Allocator) JsonDecodeError!f64 {
        var string = std.ArrayList(u8).init(allocator);

        var c: ?u8 = iter.current() catch unreachable;
        while (c != null and (('0' <= c.? and c.? <= '9') or c.? == '+' or c.? == '-' or c.? == 'e' or c.? == 'E' or c.? == '.')) {
            try string.append(c.?);
            c = iter.next();
        }

        std.debug.print("number: {s}\n", .{string.items});

        const result: JsonDecodeError!f64 = std.fmt.parseFloat(f64, string.items) catch JsonDecodeError.InvalidFormat;
        return result;
    }

    fn parse_object(iter: *CharacterIterator, allocator: std.mem.Allocator) JsonDecodeError!*Json.Object() {
        const start = iter.current() catch unreachable;
        if (start == null or start.? != '{') {
            return JsonDecodeError.InvalidFormat;
        }
        _ = iter.next();

        var object = Json.Object().init(allocator);

        consume_whitespace(iter);
        const first_non_whitespace = iter.current() catch unreachable;
        if (first_non_whitespace == null) {
            return JsonDecodeError.InvalidFormat;
        } else if (first_non_whitespace.? == '}') {
            _ = iter.next();

            return &object;
        }

        while (true) {
            const key = try parse_string(iter, allocator);

            consume_whitespace(iter);
            const key_value_separator = iter.current() catch unreachable;
            if (key_value_separator == null or key_value_separator.? != ':') {
                return JsonDecodeError.InvalidFormat;
            }
            _ = iter.next();

            const value = try parse_value(iter, allocator);
            try object.put(key.items, value);

            if (iter.current() catch unreachable) |key_value_end| {
                if (key_value_end == '}') {
                    _ = iter.next();
                    return &object;
                } else if (key_value_end != ',') {
                    return JsonDecodeError.InvalidFormat;
                }
            } else {
                return JsonDecodeError.InvalidFormat;
            }
            _ = iter.next();

            consume_whitespace(iter);
        }
    }

    fn parse_array(iter: *CharacterIterator, allocator: std.mem.Allocator) JsonDecodeError!*std.ArrayList(*Json) {
        const start = iter.current() catch unreachable;
        if (start == null or start.? != '[') {
            return JsonDecodeError.InvalidFormat;
        }
        _ = iter.next();

        var array = std.ArrayList(*Json).init(allocator);

        consume_whitespace(iter);
        const first_non_whitespace = iter.current() catch unreachable;
        if (first_non_whitespace == null) {
            return JsonDecodeError.InvalidFormat;
        } else if (first_non_whitespace.? == ']') {
            _ = iter.next();
            return &array;
        }

        while (true) {
            const value = try parse_value(iter, allocator);

            try array.append(value);

            if (iter.current() catch unreachable) |value_end| {
                if (value_end == ']') {
                    _ = iter.next();
                    return &array;
                } else if (value_end != ',') {
                    return JsonDecodeError.InvalidFormat;
                }
            } else {
                return JsonDecodeError.InvalidFormat;
            }
            _ = iter.next();
        }
    }

    /// Confirms whether the iterator's next values match the provided slice.
    /// It iterates over the slice while also taking the iterator's next character always and checks that they are equal.
    fn confirm(iter: *CharacterIterator, slice: []const u8) JsonDecodeError!void {
        var c: ?u8 = iter.current() catch unreachable;
        for (slice) |e| {
            if (c == null or e != c.?) {
                return JsonDecodeError.InvalidFormat;
            }
            c = iter.next();
        }
    }
};
