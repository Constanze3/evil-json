const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Static Library
    {
        const lib = b.addStaticLibrary(.{
            .name = "evil-json",
            .root_source_file = .{ .path = "src/root2.zig" },
            .target = target,
            .optimize = optimize,
        });

        b.installArtifact(lib);
    }

    // Test
    {
        const lib_unit_tests = b.addTest(.{
            .root_source_file = .{ .path = "src/root2.zig" },
            .target = target,
            .optimize = optimize,
        });

        const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_lib_unit_tests.step);
    }

    // Example
    {
        const evil_json = b.addModule("evil-json", .{ .root_source_file = .{ .path = "src/root2.zig" } });

        const opt = b.option([]const u8, "example", "The example to build and run") orelse "basic";
        const example_file = res: {
            if (std.mem.eql(u8, opt, "basic")) {
                break :res "examples/basic/main.zig";
            }

            if (std.mem.eql(u8, opt, "trivia")) {
                break :res "examples/trivia/main.zig";
            }

            break :res "examples/basic/main.zig";
        };

        const example = b.addExecutable(.{
            .name = opt,
            .root_source_file = .{ .path = example_file },
            .target = target,
            .optimize = optimize,
        });

        example.root_module.addImport("evil-json", evil_json);

        const run_example = b.addRunArtifact(example);
        run_example.step.dependOn(b.getInstallStep());

        const example_step = b.step("example", "Run example");
        example_step.dependOn(&run_example.step);
    }
}
