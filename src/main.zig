const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;

const Util = struct {
    allocator: Allocator,

    fn string(self: *const Util, slice: []const u8) Allocator.Error!ArrayList(u8) {
        var str = ArrayList(u8).init(self.allocator);
        try str.appendSlice(slice);
        return str;
    }

    fn list(self: *const Util, comptime T: type) ArrayList(T) {
        return ArrayList(T).init(self.allocator);
    }
};

test "json model" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const u = Util{ .allocator = allocator };

    const j1 = Json{
        .string = try u.string("very weak"),
    };

    var j2_object = Json.Object().init(allocator);
    try j2_object.put(try u.string("strength"), &j1);
    const j2 = Json{ .object = j2_object };

    try std.testing.expectEqualStrings("very weak", j2.object.get(try u.string("strength")).?.string.items);
}

pub fn main() !void {
    const file = try std.fs.cwd().openFile("test.json", .{});
    defer file.close();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const file_size = try file.getEndPos();
    const data = try file.readToEndAlloc(allocator, file_size);

    _ = data;
    // std.debug.print("{s}\n\n", .{data});

    const u = Util{ .allocator = allocator };

    const j1 = Json{
        .string = try u.string("very weak"),
    };

    var j2_object = Json.Object().init(allocator);
    try j2_object.put(try u.string("strength"), &j1);
    const j2 = Json{ .object = j2_object };

    var j = JsonAccess.new(&j2, allocator);

    const res = try j.oc("strength").v_string();
    std.debug.print("{s}", .{res.items});
}

const ArrayListHashContext = struct {
    pub fn hash(_: ArrayListHashContext, key: ArrayList(u8)) u64 {
        var h = std.hash.Fnv1a_64.init();
        h.update(key.items);
        return h.final();
    }

    pub fn eql(_: ArrayListHashContext, a: ArrayList(u8), b: ArrayList(u8)) bool {
        return std.mem.eql(u8, a.items, b.items);
    }
};

const Json = union(enum) {
    string: ArrayList(u8),
    number: f64,
    object: Object(),
    array: ArrayList(*const Json),
    boolean: bool,

    /// std.HashMap with K: ArrayList(u8) V: \*const Json
    pub fn Object() type {
        return std.HashMap(
            ArrayList(u8),
            *const Json,
            ArrayListHashContext,
            std.hash_map.default_max_load_percentage,
        );
    }
};

const JsonAccessKey = union(enum) {
    object_key: ArrayList(u8),
    array_index: usize,
};

const JsonAccessError = error{ InvalidKeyType, NoChildren, NoSuchField };

const JsonAccessErrorData = struct {
    index: usize,
    key: JsonAccessKey,
};

const JsonAccess = struct {
    allocator: std.mem.Allocator,
    target: *const Json,
    key_sequence: ArrayList(JsonAccessKey),

    fn new(target: *const Json, allocator: std.mem.Allocator) JsonAccess {
        return JsonAccess{
            .allocator = allocator,
            .target = target,
            .key_sequence = ArrayList(JsonAccessKey).init(allocator),
        };
    }

    fn oc(self: *JsonAccess, key: anytype) *JsonAccess {
        const access_key = parse_access_key: {
            switch (@TypeOf(key)) {
                ArrayList(u8) => {
                    break :parse_access_key JsonAccessKey{ .object_key = key };
                },
                else => {
                    var list = ArrayList(u8).init(self.allocator);
                    list.appendSlice(@as([]const u8, key)) catch unreachable;
                    break :parse_access_key JsonAccessKey{ .object_key = list };
                },
            }
        };

        return self.c(access_key);
    }

    fn ac(self: *JsonAccess, index: anytype) *JsonAccess {
        return self.c(JsonAccessKey{
            .array_index = @as(usize, index),
        });
    }

    fn c(self: *JsonAccess, key: JsonAccessKey) *JsonAccess {
        self.key_sequence.append(key) catch unreachable;
        return self;
    }

    fn v(self: *const JsonAccess) JsonAccessError!*const Json {
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

    fn v_string(self: *const JsonAccess) JsonAccessError!ArrayList(u8) {
        const val = try self.v();
        return val.string;
    }

    fn v_errdata(self: *const JsonAccess, out_failed_at: JsonAccessErrorData) JsonAccessError!Json {
        _ = out_failed_at;
        _ = self;
        return JsonAccessError.NoChildren;
    }
};

// pub fn decodeJson(data: []const u8) Json {
//     _ = data;
// }
