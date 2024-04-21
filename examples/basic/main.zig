const std = @import("std");
const json = @import("evil-json");

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

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const file = try std.fs.cwd().openFile("examples/basic/data.json", .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const data = try file.readToEndAlloc(allocator, file_size);

    const parsed: *json.Json = try json.decode_json(data, allocator);
    // var ja = json.JsonAccess.new(parsed, allocator);

    // const res = try ja.o("gods").a(0).o("name").get_string();

    const stuff: *std.ArrayList(*json.Json) = parsed.object.get("gods").?.array;
    std.debug.print("{d}\n", .{stuff.items.len});
}
