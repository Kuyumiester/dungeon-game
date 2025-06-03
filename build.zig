const std = @import("std");
const print = std.debug.print;

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
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

    // We will also create a module for our other entry point, 'main.zig'.
    const exe_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // This creates another `std.Build.Step.Compile`, but this one builds an executable
    // rather than a static library.
    const exe = b.addExecutable(.{
        .name = "using_raylib_directly",
        .root_module = exe_mod,
    });

    // where to find any c header files
    exe.root_module.addIncludePath(b.path("src"));

    const raylib_dep = b.dependency("raylib", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib = raylib_dep.artifact("raylib");
    exe.linkLibrary(raylib);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    const fs = std.fs;
    const cwd = fs.cwd(); // assumes we're in the project folder, and no deeper

    cwd.makeDir("./zig-out/bin/resources") catch |err| {
        switch (err) {
            error.PathAlreadyExists => {},
            else => ohno(err),
        }
    };

    //
    var source_path_buffer: [fs.max_path_bytes]u8 = undefined;
    const source_path_prefix = "./resources/";
    @memcpy(source_path_buffer[0..source_path_prefix.len], source_path_prefix); // first of two ways of doing this
    //
    var destination_path_buffer: [fs.max_path_bytes]u8 = undefined;
    const destination_path_prefix = "./zig-out/bin/resources/";
    @memcpy(@as([*]u8, &destination_path_buffer), destination_path_prefix); // second of two ways of doing this

    const dir = cwd.openDir("resources", .{ .iterate = true }) catch unreachable;
    var iterator = dir.iterate();
    while (iterator.next() catch unreachable) |entry| {
        switch (entry.kind) {
            .file => {
                @memcpy(source_path_buffer[source_path_prefix.len .. source_path_prefix.len + entry.name.len], entry.name); // first of two ways of doing this
                @memcpy(@as([*]u8, &destination_path_buffer) + destination_path_prefix.len, entry.name); // second of two ways of doing this
                cwd.copyFile(
                    source_path_buffer[0 .. source_path_prefix.len + entry.name.len],
                    cwd,
                    destination_path_buffer[0 .. destination_path_prefix.len + entry.name.len],
                    .{},
                ) catch |err| ohno(err);
            },
            else => unreachable,
        }
    }

    print("\ndone copying files!\n\n", .{});

    //var buf: [fs.max_path_bytes]u8 = undefined;
    //const yeah = fs.realpath("", &buf) catch "\noh no! our table!";
    //print("\n{s}", .{yeah});
    // nocheckin, remember to write code to check each folder in our path for build.zig
    // nocheckin, remember to make the resources directory
    //     also check which way zig checks for build.zig files: top to bottom or bottom to top?
    //     see if you can put a build.zig file way up in the hierarchy for no reason and see what zig does.
    // idea!: in build.zig, when compiling for ReleaseFast, warn us of "nocheckin"s in our files.
}

fn ohno(err: anyerror) void {
    print(terminal_error ++ "\n{!}" ++ terminal_default, .{err});
}

const csi = [2]u8{ 27, '[' }; //same as: "\x1B[";
const terminal_error = csi ++ "38;5;196m"; // red
const terminal_default = csi ++ "0m"; // back to default
