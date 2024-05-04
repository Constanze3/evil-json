const std = @import("std");
const json = @import("root.zig");

// TODO pretty printing

/// Writes the given value to the `std.io.Writer` stream.
pub fn stringify(value: json.Value, out_stream: anytype) @TypeOf(out_stream).Error!void {
    var w = WriteStream(@TypeOf(out_stream)).init(out_stream);
    try w.write(value);
}

/// Writes JSON formatted data to a stream.
pub fn WriteStream(comptime OutStream: type) type {
    return struct {
        pub const Stream = OutStream;

        stream: OutStream,
        indent_level: usize = 0,

        pub fn init(out_stream: OutStream) @This() {
            return @This(){
                .stream = out_stream,
            };
        }

        pub fn write(self: *@This(), value: json.Value) OutStream.Error!void {
            switch (value) {
                .string => |val| {
                    try self.stream.print("\"{s}\"", .{val});
                },
                .number => |val| {
                    try self.stream.print("{d}", .{val});
                },
                .object => |val| {
                    try self.stream.print("{{", .{});

                    var iter = val.iterator();
                    var entry = iter.next();
                    while (true) {
                        try self.stream.print("\"{s}\": ", .{entry.?.key_ptr.*});
                        try self.write(entry.?.value_ptr.*);

                        entry = iter.next();
                        if (entry == null) {
                            break;
                        } else {
                            try self.stream.print(", ", .{});
                        }
                    }

                    try self.stream.print("}}", .{});
                },
                .array => |val| {
                    try self.stream.print("[", .{});

                    for (val.items, 1..) |item, i| {
                        try self.write(item);

                        if (i < val.items.len) {
                            try self.stream.print(", ", .{});
                        }
                    }

                    try self.stream.print("]", .{});
                },
                .bool => |val| {
                    try self.stream.print("{any}", .{val});
                },
                .null => {
                    try self.stream.print("null", .{});
                },
            }
        }
    };
}
