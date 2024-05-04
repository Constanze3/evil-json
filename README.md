# Evil Json

A simple JSON decoding/encoding library.

## What can it do?
- Parse most\* JSON files (into a Value datatype provided by the library)
- Nicely access child values in a nested JSON Value
- Stringify Values into minimal JSON strings

\*: The library is not tailored to any specific standard thoguh it mostly follows the basic JSON standard (ECMA-404).

## Usage

My recommendation: Don't use it. (Okay, maybe for fun...)

**Using the package manager**

Example build.zig.zon file
```zig
.{
    .name = "app",
    .version = "0.0.0",
    .dependencies = .{
        .evil-json = .{
            .url = "TODO",
        },
    },
}
```

## Examples

Examples can be run by calling.
```
zig build example -Dexample=<EXAMPLE NAME HERE>
```

The available examples are:
- basic : reads data from a file into a string and parses it
- trivia : simple trivia game using Open Trivia DB (TODO)

The basic example:
```zig
TODO paste example here
```

## Possbile future plans
- Add options to stringify (such as pretty printing)
- Parse into any struct instead of just Value (just like std)
