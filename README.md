# Evil Json

A simple JSON decoding/encoding library.

## What can it do?
- Parse most\* JSON files (into a Value datatype provided by the library)
- Nicely access child values in a nested JSON Value
- Stringify Values into minimal JSON strings

\*: The library is not tailored to any specific standard though it mostly follows the basic JSON standard (ECMA-404).

## Installation

My recommendation: Don't use it. (Okay, maybe for fun...)

**Using the package manager:**

Run this command in the project's directory:
```
zig fetch --save https://github.com/Constanze3/evil-json/archive/refs/tags/v0.0.1.tar.gz
```

<details>
<summary>
Or add it manually to <code>build.zig.zon</code>:
</summary>
<br>

```zig
.{
    .name = "app",
    .version = "0.0.0",
    .dependencies = .{
        .@"evil-json" = .{
            .url = "https://github.com/Constanze3/evil-json/archive/refs/tags/v0.0.1.tar.gz",
            .hash = "122087e4c7cbc7852de86c575a1197c5d619dc75123efd89796eb746af43bffb1145",
        },
    },
}
```

</details>

Then update <code>build.zig</code> with the following:
```zig
const evil_json_module = b.dependency("evil-json", .{
    .target = target,
    .optimize = optimize,
}).module("evil-json");

exe.root_module.addImport("evil-json", evil_json_module);
```
(Replace exe with the executable you would like to add the module to.)

And finally you can import it:
```zig
const json = @import("evil-json");
```

## Examples

Examples can be run by calling.
```
zig build example -Dexample=<EXAMPLE NAME HERE>
```

The available examples are:
- basic : read data from a file into a string and parse it
- trivia : simple trivia game using Open Trivia DB

The basic example:
```zig
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

    // This isn't necessary here because of the arena allocator,
    // but parsed JSON values can be deinited.
    defer parsed.deinit();

    // This is the parsed value.
    const value = parsed.value;

    // Prints a child value, in this case from the initial object's "gods" we print the first
    // god's honorific name.
    std.debug.print("{s}", .{
        parsed.value
            .object.get("gods").?
            .array.items[0]
            .object.get("honorific name").?.string,
    });

    // Same thing as above, but using json.Access.
    // - o(key) appends and object key to the key sequence of the access.
    // - a(index) appends an array index to the key sequence of the access.
    // - get() evaluates the key sequence and obtains a Value.
    //
    // There also exists get_and_deinit() which also deinits the access.
    var a = json.Access.init(value, allocator);
    std.debug.print("{s}\n", .{
        (try a.o("gods").a(0).o("honorific name").get()).string,
    });
}
```

## Potential future plans
- Add options to stringify (such as pretty printing)
- Provide a way to scan files into JSON instead of just slices
- Parse into any struct instead of just Value (just like std)
