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

    _ = try json.decodeJson(data);

    // const u = Util{ .allocator = allocator };

    // const j1 = json.Json{
    //     .string = try u.string("very weak"),
    // };

    // var j2_object = json.Json.Object().init(allocator);
    // try j2_object.put(try u.string("strength"), &j1);
    // const j2 = json.Json{ .object = j2_object };

    // var j = json.JsonAccess.new(&j2, allocator);

    // const res = try j.o("strength").get_string();
    // std.debug.print("{s}", .{res});
}
