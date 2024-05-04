const std = @import("std");
const json = @import("evil-json");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const file = try std.fs.cwd().openFile("examples/basic/data.json", .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const data = try file.readToEndAlloc(allocator, file_size);

    const parsed = try json.parse(data, allocator);

    const value = parsed.value;

    std.debug.print("{s}", .{parsed.value.object.get("gods").?.array.items[0].object.get("honorific name").?.string});

    var access = json.Access.init(value, allocator);
    const result = try access.o("gods").a(0).o("honorific name").get_string();
    std.debug.print("{s}\n", .{result});
}
