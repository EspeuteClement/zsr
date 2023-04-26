const std = @import("std");

pub fn build(b: *std.build.Builder) void {

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize = b.standardOptimizeOption(.{});

    {
        const exe = b.addExecutable(.{
            .name = "zsr",
            .root_source_file = .{ .path = "src/main.zig" },
            .target = target,
            .optimize = optimize,
        });
        configure(b, exe);

        exe.addCSourceFile("libs/dr_wav/dr_wav.c", &.{});
        exe.addCSourceFile("libs/pocketmod/pocketmod.c", &.{});
        exe.addIncludePath("libs/pocketmod/");
        exe.addIncludePath("libs/dr_wav/");

        var exe_install = b.addInstallArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);

        var install_res = b.addInstallDirectory(.{
            .source_dir = "res",
            .install_dir = .{ .custom = "" },
            .install_subdir = "bin/res/",
        });

        exe.step.dependOn(&install_res.step);
        const build_exe_step = b.step("exe", "Build and install the exe");
        build_exe_step.dependOn(&exe.step);

        run_cmd.step.dependOn(&exe_install.step);
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }

    // Tests
    {
        const exe_tests = b.addTest(.{ .root_source_file = .{ .path = "src/main.zig" } });
        configure(b, exe_tests);

        var test_options = b.addOptions();
        const test_path = comptime (std.fs.path.dirname(@src().file) orelse ".") ++ "/src/test/";
        test_options.addOption([]const u8, "test_path", test_path);
        exe_tests.addOptions("tests", test_options);

        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&exe_tests.step);
    }

    // Web build
    {
        const web = b.addSharedLibrary(.{
            .name = "module",
            .root_source_file = .{ .path = "src/main-web.zig" },
            .target = .{ .cpu_arch = .wasm32, .os_tag = .freestanding },
            .optimize = optimize,
        });

        web.addIncludePath("libs/stb/");

        var stbilib = b.addStaticLibrary(.{
            .name = "stbi",
            .target = .{ .cpu_arch = .wasm32, .os_tag = .freestanding },
            .optimize = .ReleaseSmall,
        });
        stbilib.linkLibC();
        stbilib.addCSourceFile("libs/stb/stb_image.c", &.{});
        stbilib.disable_sanitize_c = true;
        stbilib.disable_stack_probing = true;
        stbilib.stack_protector = false;

        web.linkLibrary(stbilib);
        web.stack_protector = false;
        web.disable_sanitize_c = true;
        web.disable_stack_probing = true;
        web.export_symbol_names = &[_][]const u8{ "init", "step" };
        web.import_memory = true;
        web.strip = true;

        const web_audio = b.addSharedLibrary(.{
            .name = "module-audio",
            .root_source_file = .{ .path = "src/main-web-audio.zig" },
            .target = .{ .cpu_arch = .wasm32, .os_tag = .freestanding },
            .optimize = optimize,
        });
        web_audio.addIncludePath("libs/pocketmod/");
        web_audio.addIncludePath("libs/dr_wav/");

        var drwav = b.addStaticLibrary(.{
            .name = "drwav",
            .target = .{ .cpu_arch = .wasm32, .os_tag = .freestanding },
            .optimize = .ReleaseSmall,
        });
        drwav.linkLibC();
        drwav.addCSourceFile("libs/dr_wav/dr_wav.c", &.{});
        drwav.disable_sanitize_c = true;
        drwav.disable_stack_probing = true;
        drwav.stack_protector = false;

        web_audio.addCSourceFile("libs/pocketmod/pocketmod.c", &.{});
        web_audio.export_symbol_names = &[_][]const u8{ "init", "gen_samples" };
        web_audio.import_memory = true;
        web_audio.strip = false;
        web_audio.linkLibrary(drwav);
        web_audio.stack_protector = false;
        web_audio.disable_sanitize_c = true;
        web_audio.disable_stack_probing = true;

        var install_html = b.addInstallFile(.{ .path = "src/web/index.html" }, "index.html");
        var install_js = b.addInstallFile(.{ .path = "src/web/audio.js" }, "audio.js");
        var install_module_audio = b.addInstallArtifact(web_audio);

        var install_module = b.addInstallArtifact(web);
        const web_build = b.step("web", "Build the web version of the game");
        web_build.dependOn(&install_module.step);
        web_build.dependOn(&install_html.step);
        web_build.dependOn(&install_js.step);
        web_build.dependOn(&install_module_audio.step);
    }

    // {
    //     const bench = b.addExecutable("bench", "src/benchmarks.zig");
    //     configure(b, bench, target, .ReleaseFast);

    //     var install = b.addInstallArtifact(bench);

    //     const b_run = bench.run();
    //     b_run.step.dependOn(&install.step);
    //     b_run.step.dependOn(&install_res.step);

    //     if (b.args) |args| {
    //         b_run.addArgs(args);
    //     }

    //     const b_run_step = b.step("bench", "Run Benchmarks");
    //     b_run_step.dependOn(&b_run.step);
    // }
}

fn configure(b: *std.build.Builder, exe: *std.build.LibExeObjStep) void {
    exe.addCSourceFile("libs/stb/stb_image.c", &.{});
    exe.addCSourceFile("libs/stb/stb_image_write.c", &.{});

    exe.addIncludePath("libs/stb/");

    exe.addIncludePath("libs/sdl/include");
    exe.addLibraryPath("libs/sdl/lib");
    exe.linkSystemLibrary("sdl2");
    exe.linkLibC();

    const install_sdl = b.addInstallBinFile(.{ .path = "libs/sdl/lib/SDL2.dll" }, "SDL2.dll");
    exe.step.dependOn(&install_sdl.step);
}
