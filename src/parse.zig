const std = @import("std");

const Allocator = std.mem.Allocator;
const Arena = std.heap.ArenaAllocator;

const Object = @import("root.zig").Object;
const Array = @import("root.zig").Array;
const Value = @import("root.zig").Value;
const Parsed = @import("root.zig").Parsed;

test "parse json simple" {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const parsed = try parse("{\"hello\": \"there\"}", allocator);
    const value = parsed.value;

    try std.testing.expectEqualSlices(u8, "there", value.object.get("hello").?.string);
}

const JsonDecodeError = error{ InvalidFormat, OutOfMemory };

/// Decodes a JSON slice.
/// It wraps all allocations with an arena allocator for convinient freeing.
pub fn parse(data: []const u8, allocator: Allocator) JsonDecodeError!Parsed {
    var parsed = Parsed{
        .arena = try allocator.create(Arena),
        .value = undefined,
    };
    errdefer allocator.destroy(parsed.arena);

    parsed.arena.* = Arena.init(allocator);
    errdefer parsed.arena.deinit();

    var stream = CharacterStream.init(data);
    parsed.value = try parseValue(&stream, allocator);

    return parsed;
}

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

fn parseValue(stream: *CharacterStream, allocator: Allocator) JsonDecodeError!Value {
    consumeWhitespace(stream);
    const first_non_whitespace = stream.current();

    if (first_non_whitespace == null) {
        return JsonDecodeError.InvalidFormat;
    }

    const value: Value = switch (first_non_whitespace.?) {
        '{' => try parseObject(stream, allocator),
        '"' => try parseString(stream, allocator),
        '[' => try parseArray(stream, allocator),
        't' => try parseTrue(stream),
        'f' => try parseFalse(stream),
        'n' => try parseNull(stream),
        else => try parseNumber(stream, allocator),
    };

    consumeWhitespace(stream);

    return value;
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

fn isWhiteSpace(character: u8) bool {
    for (" \n\r\t") |c| {
        if (c == character) {
            return true;
        }
    }
    return false;
}

test "parse string" {
    var arena = Arena.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stream = CharacterStream.init("\"Who is this gentleman?\"");
    const value = try parseString(&stream, allocator);
    try std.testing.expectEqualStrings("Who is this gentleman?", value.string);
}

fn parseString(stream: *CharacterStream, allocator: Allocator) JsonDecodeError!Value {
    const start = stream.current();
    if (start == null or start.? != '"') {
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

test "parse number" {
    var arena = Arena.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stream = CharacterStream.init("-1.1231E2");
    const value = try parseNumber(&stream, allocator);
    try std.testing.expectEqual(-1.1231e2, value.number);
}

fn parseNumber(stream: *CharacterStream, allocator: Allocator) JsonDecodeError!Value {
    var number_string = std.ArrayList(u8).init(allocator);
    defer number_string.deinit();

    var c: ?u8 = stream.current();
    while (c != null and isJsonNumberCharacter(c.?)) {
        try number_string.append(c.?);
        stream.progress();
        c = stream.current();
    }

    const number = std.fmt.parseFloat(f64, number_string.items) catch JsonDecodeError.InvalidFormat;
    return Value{ .number = try number };
}

fn isJsonNumberCharacter(character: u8) bool {
    return switch (character) {
        '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '+', '-', 'e', 'E', '.' => true,
        else => false,
    };
}

test "parse object" {
    var arena = Arena.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stream = CharacterStream.init("{   \n     \"name\":      \"Sherlock Holmes\" \t  }");
    const value = try parseObject(&stream, allocator);
    try std.testing.expectEqualStrings("Sherlock Holmes", value.object.get("name").?.string);
}

fn parseObject(stream: *CharacterStream, allocator: Allocator) JsonDecodeError!Value {
    const start = stream.current();
    if (start == null or start.? != '{') {
        return JsonDecodeError.InvalidFormat;
    }

    var object = Object.init(allocator);

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

        const separator = stream.current();
        if (separator == null or separator.? != ':') {
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

test "parse array" {
    var arena = Arena.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stream = CharacterStream.init("[ \"this is not a number\",    \n\t    3.1415926535          ]");
    const value = try parseArray(&stream, allocator);

    try std.testing.expectEqualStrings("this is not a number", value.array.items[0].string);
    try std.testing.expectEqual(3.1415926535, value.array.items[1].number);
}

fn parseArray(stream: *CharacterStream, allocator: Allocator) JsonDecodeError!Value {
    const start = stream.current();
    if (start == null or start.? != '[') {
        return JsonDecodeError.InvalidFormat;
    }

    var array = std.ArrayList(Value).init(allocator);

    stream.progress();
    consumeWhitespace(stream);

    if (stream.current()) |c| {
        if (c == ']') {
            stream.progress();
            return Value{ .array = array };
        }
    } else {
        return JsonDecodeError.InvalidFormat;
    }

    while (true) {
        const value = try parseValue(stream, allocator);

        try array.append(value);

        if (stream.current()) |key_value_end| {
            switch (key_value_end) {
                ']' => {
                    stream.progress();
                    return Value{ .array = array };
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
    }
}

test "consume and match" {
    var stream = CharacterStream.init("true or false");
    try consumeAndMatch(&stream, "true");
}

fn consumeAndMatch(stream: *CharacterStream, slice: []const u8) JsonDecodeError!void {
    for (slice) |c2| {
        const c1 = stream.current();
        if (c1 == null or c1.? != c2) {
            return JsonDecodeError.InvalidFormat;
        }
        stream.progress();
    }
}

fn parseTrue(stream: *CharacterStream) JsonDecodeError!Value {
    try consumeAndMatch(stream, "true");
    return Value{ .bool = true };
}

fn parseFalse(stream: *CharacterStream) JsonDecodeError!Value {
    try consumeAndMatch(stream, "false");
    return Value{ .bool = false };
}

fn parseNull(stream: *CharacterStream) JsonDecodeError!Value {
    try consumeAndMatch(stream, "null");
    return Value{ .null = {} };
}
