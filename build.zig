const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Static Library
    {
        const lib = b.addStaticLibrary(.{
            .name = "evil-json",
            .root_source_file = .{ .path = "src/root.zig" },
            .target = target,
            .optimize = optimize,
        });

        b.installArtifact(lib);
    }

    // Tests
    {
        const lib_unit_tests = b.addTest(.{
            .root_source_file = .{ .path = "src/root.zig" },
            .target = target,
            .optimize = optimize,
        });

        const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_lib_unit_tests.step);
    }

    // Modules
    const lib_module = b.addModule("evil-json", .{ .root_source_file = .{ .path = "src/root.zig" } });

    // Examples
    {
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

        example.root_module.addImport("evil-json", lib_module);

        const run_example = b.addRunArtifact(example);
        run_example.step.dependOn(b.getInstallStep());

        const example_step = b.step("example", "Run example");
        example_step.dependOn(&run_example.step);
    }
}
