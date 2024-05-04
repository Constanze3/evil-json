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

    // Parses the JSON value in the string.
    const parsed = try json.parse(data, allocator);

    // This isn't necessary here because of the arena allocator, but parsed JSON values can be deinited.
    defer parsed.deinit();

    // This is the parsed value.
    const value = parsed.value;

    // Prints a child value, in this case from the initial object's "gods" we print the first god's honorific name.
    std.debug.print("{s}", .{parsed.value.object.get("gods").?.array.items[0].object.get("honorific name").?.string});

    // Same thing as above, but using json.Access.
    // o(key) appends and object key to the key sequence of the access.
    // a(index) appends an array index to the key sequence of the access.
    // get() evaluates the key sequence and obtains a Value. There also exists get_and_deinit() which also deinits the value.
    var a = json.Access.init(value, allocator);
    std.debug.print("{s}\n", .{(try a.o("gods").a(0).o("honorific name").get()).string});
}
