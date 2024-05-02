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

    const parsed = try json.decodeJson(data, allocator);

    const value = parsed.value;

    std.debug.print("{s}", .{parsed.value.object.get("gods").?.array.items[0].object.get("honorific name").?.string});

    var access = json.Access.init(value, allocator);
    const result = try access.o("gods").a(0).o("honorific name").get_string();
    std.debug.print("{s}\n", .{result});
}
