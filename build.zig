const std = @import("std");

const libs_root = "libs/";
const audio_libs = [_][]const u8{
    libs_root ++ "dr_wav/dr_mp3.c",
    libs_root ++ "dr_wav/dr_wav.c",
    libs_root ++ "pocketmod/pocketmod.c",
};
const audio_include_paths = [_][]const u8{
    libs_root ++ "pocketmod/",
    libs_root ++ "dr_wav/",
};

pub fn build(b: *std.build.Builder) void {

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize = b.standardOptimizeOption(.{});

    const exe = brk: {
        const exe = b.addExecutable(.{
            .name = "zsr",
            .root_source_file = .{ .path = "src/main-sdl.zig" },
            .target = target,
            .optimize = optimize,
        });

        const sdl_dep = b.dependency("sdl", .{
            .target = target,
            .optimize = .ReleaseFast,
        });

        exe.linkLibrary(sdl_dep.artifact("SDL2"));

        const audio = buildAudioLib(b, target, .ReleaseFast);
        exe.linkLibrary(audio);

        const stbi_lib = buildStbImage(b, target, .ReleaseFast);
        exe.linkLibrary(stbi_lib);

        if (target.isWindows()) exe.subsystem = .Windows;

        configureOptions(b, exe, optimize != .Debug);

        exe.linkLibC();

        if (optimize == .ReleaseFast or optimize == .ReleaseSafe) {
            exe.strip = true;
            exe.want_lto = true;
        }

        var exe_install = b.addInstallArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);

        const build_exe_step = b.step("exe", "Build and install the exe");
        build_exe_step.dependOn(&exe_install.step);

        run_cmd.step.dependOn(&exe_install.step);
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
        break :brk .{ .build_exe = build_exe_step, .exe = exe };
    };

    // Tests
    {
        const exe_tests = b.addTest(.{ .root_source_file = .{ .path = "src/main-sdl.zig" } });
        const stbi_lib = buildStbImage(b, target, optimize);

        exe_tests.linkLibrary(stbi_lib);
        var test_options = b.addOptions();
        const test_path = comptime (std.fs.path.dirname(@src().file) orelse ".") ++ "/src/test/";
        test_options.addOption([]const u8, "test_path", test_path);
        exe_tests.addOptions("tests", test_options);

        const run_test = b.addRunArtifact(exe_tests);

        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_test.step);
    }

    // Web build
    const web_build = brk: {
        var web_target = .{ .cpu_arch = .wasm32, .os_tag = .freestanding };

        const web = b.addSharedLibrary(.{
            .name = "module",
            .root_source_file = .{ .path = "src/main-web.zig" },
            .target = .{ .cpu_arch = .wasm32, .os_tag = .freestanding },
            .optimize = .ReleaseSmall,
        });

        web.addIncludePath("libs/stb/");

        const stbi_lib = buildStbImage(b, web_target, .ReleaseSmall);

        web.linkLibrary(stbi_lib);
        commonWasmSettings(web);

        configureOptions(b, web, true);

        // Audio -----
        const web_audio = b.addSharedLibrary(.{
            .name = "module-audio",
            .root_source_file = .{ .path = "src/main-web-audio.zig" },
            .target = .{ .cpu_arch = .wasm32, .os_tag = .freestanding },
            .optimize = optimize,
        });

        const audio = buildAudioLib(b, web_target, .ReleaseSmall);
        web_audio.linkLibrary(audio);

        web_audio.export_symbol_names = &[_][]const u8{ "init", "gen_samples", "playSound" };
        web_audio.import_memory = true;
        commonWasmSettings(web_audio);

        const dest_dir = std.build.InstallDir{ .custom = "web" };
        const dest_sub_dir = std.build.InstallDir{ .custom = "web/lib" };

        var install_html = b.addInstallFile(.{ .path = "src/web/index.html" }, "index.html");
        install_html.dir = dest_dir;

        var install_js = b.addInstallFile(.{ .path = "src/web/audio.js" }, "audio.js");
        install_js.dir = dest_dir;
        var install_module_audio = b.addInstallArtifact(web_audio);
        install_module_audio.dest_dir = dest_sub_dir;

        var install_module = b.addInstallArtifact(web);
        install_module.dest_dir = dest_sub_dir;

        const web_build = b.step("web", "Build the web version of the game");
        web_build.dependOn(&install_module.step);
        web_build.dependOn(&install_html.step);
        web_build.dependOn(&install_js.step);
        web_build.dependOn(&install_module_audio.step);

        break :brk web_build;
    };

    {
        var publish_step = b.step("web-publish", "Publish the game on itch");

        const butler_cmd = b.addSystemCommand(&[_][]const u8{ "butler", "push", "zig-out/web", "valden/hell-world:web" });
        butler_cmd.step.dependOn(web_build);

        publish_step.dependOn(&butler_cmd.step);
    }

    {
        var all = b.step("all", "Build all target, then run desktop target");
        all.dependOn(web_build);
        all.dependOn(exe.build_exe);

        var all_run = b.step("all-run", "Build all target, then run desktop target");

        const run_cmd = b.addRunArtifact(exe.exe);
        run_cmd.step.dependOn(all);
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        all_run.dependOn(&run_cmd.step);
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

fn buildAudioLib(b: *std.build.Builder, target: std.zig.CrossTarget, optimize: std.builtin.Mode) *std.Build.Step.Compile {
    const audio = b.addStaticLibrary(.{
        .name = "audio",
        .target = target,
        .optimize = optimize,
    });

    audio.linkLibC();
    audio.addCSourceFiles(&audio_libs, &.{});
    for (audio_include_paths) |path| {
        audio.installHeadersDirectory(path, "");
    }

    return audio;
}

fn buildStbImage(b: *std.build.Builder, target: std.zig.CrossTarget, optimize: std.builtin.Mode) *std.Build.Step.Compile {
    const stbi = b.addStaticLibrary(.{
        .name = "stbi",
        .target = target,
        .optimize = optimize,
    });

    stbi.linkLibC();

    stbi.addCSourceFile("libs/stb/stb_image.c", &.{});
    stbi.addCSourceFile("libs/stb/stb_image_write.c", &.{});

    stbi.installHeadersDirectory("libs/stb/", "");

    return stbi;
}

fn commonWasmSettings(compile: *std.build.Step.Compile) void {
    compile.strip = true;
    compile.stack_protector = false;
    compile.disable_sanitize_c = true;
    compile.disable_stack_probing = true;
    compile.rdynamic = true;
}

fn configureOptions(b: *std.build.Builder, compile: *std.build.Step.Compile, embed_structs: bool) void {
    const opt = b.addOptions();
    opt.addOption(bool, "embed_structs", embed_structs);

    if (!embed_structs) {
        const src_path = comptime (std.fs.path.dirname(@src().file) orelse ".") ++ "/src/";
        opt.addOption([]const u8, "src_path", src_path);
    }

    compile.addOptions("options", opt);
}
