const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

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
    const String = ArrayList(u8);

    const j1 = Json{
        .string = try u.string("very weak"),
    };

    var j2_keys = u.list(String);
    try j2_keys.append(try u.string("strength"));

    var j2_values = u.list(*const Json);
    try j2_values.append(&j1);

    const j2 = Json{ .object = try JsonObject.create(j2_keys, j2_values) };

    try std.testing.expectEqualStrings("very weak", j2.object.values.items[0].string.items);
}

pub fn main() !void {
    const file = try std.fs.cwd().openFile("test.json", .{});
    defer file.close();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const file_size = try file.getEndPos();
    const data = try file.readToEndAlloc(allocator, file_size);

    std.debug.print("{s}\n\n", .{data});
}

const Json = union(enum) {
    string: ArrayList(u8),
    number: f64,
    object: JsonObject,
    array: ArrayList(*const Json),
    boolean: bool,
};

const JsonObjectError = error{
    NonEqKeyValueLen,
};

const JsonObject = struct {
    // inv: keys.items.len == values.items.len
    keys: ArrayList(ArrayList(u8)),
    values: ArrayList(*const Json),

    fn create(keys: ArrayList(ArrayList(u8)), values: ArrayList(*const Json)) JsonObjectError!JsonObject {
        if (keys.items.len != values.items.len) {
            return JsonObjectError.NonEqKeyValueLen;
        }

        return JsonObject{
            .keys = keys,
            .values = values,
        };
    }
};

// const JsonAccessKey = union(enum) {
//     object: []const u8,
//     array: usize,
// };
//
// const JsonAccessError = error{ InvalidKeyType, NoChildren, NoSuchField };
//
// const JsonAccess = struct {
//     value: ?Json,
//
//     fn c(self: *const JsonAccess, key: JsonAccessKey) JsonAccessError!*const JsonAccess {
//         const value = self.value orelse return JsonAccessError.NoChildren;
//
//         switch (key) {
//             .object => |object_key| {
//                 switch (value) {
//                     .object => |obj| {
//                         return for (obj.keys, 0..) |possible_key, i| {
//                             if (std.mem.eql(u8, object_key, possible_key)) {
//                                 break obj.values[i];
//                             }
//                         } else return JsonAccessError.NoSuchField;
//                     },
//                     .array => {
//                         return JsonAccessError.InvalidKeyType;
//                     },
//                     inline else => {
//                         return JsonAccessError.NoChildren;
//                     },
//                 }
//             },
//             .array => |array_index| {
//                 switch (value) {
//                     .array => |arr| {
//                         return arr[array_index];
//                     },
//                     .object => {
//                         return JsonAccessError.InvalidKeyType;
//                     },
//                     inline else => {
//                         return JsonAccessError.NoChildren;
//                     },
//                 }
//             },
//         }
//     }
//
//     fn v(self: *const JsonAccess, comptime T: type) ?T {
//         const value = self.value orelse return null;
//         switch (value) {
//             .string => |val| {
//                 return @as(T, val);
//             },
//             inline else => |val| {
//                 _ = val;
//                 return "hi";
//             },
//         }
//     }
// };

// TODO make it so only v evaluates chained c and have some immediate c so i_c instead?

// pub fn decodeJson(data: []const u8) Json {
//     _ = data;
// }
