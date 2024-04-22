const std = @import("std");

// test "simple" {
//     var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
//     defer arena.deinit();
//
//     const allocator = arena.allocator();
//
//     const value = try decodeJson("{\"hello\": \"there\"}", allocator);
//     try std.testing.expectEqualSlices(u8, "there", value.object.get("hello").?.string);
// }

pub const Value = union(enum) {
    string: []const u8,
    number: f64,
    object: std.StringHashMap(Value),
    array: std.ArrayList(Value),
    bool: bool,
    null: void,
};

// pub const Parsed = struct {
//     value: Value,
//     allocator: std.mem.Allocator,
// };

test "character stream" {
    var stream = CharacterStream.init("apple");
    stream.progress();
    stream.progress();

    try std.testing.expectEqual('p', stream.current());
}

const CharacterStream = struct {
    input: []const u8,
    cursor: usize = 0,

    fn init(input: []const u8) @This() {
        return .{
            .input = input,
        };
    }

    fn progress(self: *@This()) void {
        if (self.cursor < self.input.len) {
            self.cursor += 1;
        }
    }

    fn current(self: *const @This()) ?u8 {
        if (self.cursor == self.input.len) {
            return null;
        }

        return self.input[self.cursor];
    }
};

const JsonDecodeError = error{ InvalidFormat, OutOfMemory };

pub fn decodeJson(data: []const u8, allocator: std.mem.Allocator) JsonDecodeError!Value {
    _ = allocator;
    _ = data;

    return JsonDecodeError.InvalidFormat;
}

fn parseValue(stream: *CharacterStream, allocator: std.mem.Allocator) JsonDecodeError!Value {
    consumeWhitespace(stream);
    const first_non_whitespace = stream.current();

    if (first_non_whitespace == null) {
        return JsonDecodeError.InvalidFormat;
    }

    const value: Value =
        switch (first_non_whitespace.?) {
        '{' => try parseObject(stream, allocator),
        '"' => try parseString(stream, allocator),
        else => Value{ .null = {} },
    };

    consumeWhitespace(stream);

    return value;
}

fn isWhiteSpace(character: u8) bool {
    for (" \n\r\t") |c| {
        if (c == character) {
            return true;
        }
    }
    return false;
}

test "consume whitespace" {
    var stream = CharacterStream.init(" \t\r\n\n\t\r\n   \n\n\t a \t \n");
    consumeWhitespace(&stream);
    try std.testing.expectEqual('a', stream.current().?);
}

fn consumeWhitespace(stream: *CharacterStream) void {
    var c = stream.current();
    while (c != null and isWhiteSpace(c.?)) {
        stream.progress();
        c = stream.current();
    }
}

test "parse object" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stream = CharacterStream.init("{ \"name\": \"Sherlock Holmes\" }");
    const value = try parseObject(&stream, allocator);
    try std.testing.expectEqualStrings("Sherlock Holmes", value.object.get("name").?.string);
}

fn parseObject(stream: *CharacterStream, allocator: std.mem.Allocator) JsonDecodeError!Value {
    if (stream.current() == null or stream.current() != '{') {
        return JsonDecodeError.InvalidFormat;
    }

    var object = std.StringHashMap(Value).init(allocator);

    stream.progress();
    consumeWhitespace(stream);

    if (stream.current()) |c| {
        if (c == '}') {
            stream.progress();
            return Value{ .object = object };
        }
    } else {
        return JsonDecodeError.InvalidFormat;
    }

    while (true) {
        const key = try parseString(stream, allocator);

        consumeWhitespace(stream);

        if (stream.current() == null or stream.current().? != ':') {
            return JsonDecodeError.InvalidFormat;
        }
        stream.progress();

        const value = try parseValue(stream, allocator);
        try object.put(key.string, value);

        if (stream.current()) |key_value_end| {
            switch (key_value_end) {
                '}' => {
                    stream.progress();
                    return Value{ .object = object };
                },
                ',' => {
                    stream.progress();
                },
                else => {
                    return JsonDecodeError.InvalidFormat;
                },
            }
        } else {
            return JsonDecodeError.InvalidFormat;
        }

        consumeWhitespace(stream);
    }
}

test "parse string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stream = CharacterStream.init("\"Who is this gentleman?\"");
    const value = try parseString(&stream, allocator);
    try std.testing.expectEqualStrings("Who is this gentleman?", value.string);
}

fn parseString(stream: *CharacterStream, allocator: std.mem.Allocator) JsonDecodeError!Value {
    if (stream.current() == null or stream.current() != '"') {
        return JsonDecodeError.InvalidFormat;
    }

    var string = std.ArrayList(u8).init(allocator);

    while (true) {
        stream.progress();

        if (stream.current()) |c| {
            if (c == '"') {
                stream.progress();
                return Value{ .string = string.items };
            }

            try string.append(c);
        } else {
            return JsonDecodeError.InvalidFormat;
        }
    }
}
