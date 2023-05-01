const std = @import("std");
const sw = @import("softwareRenderer.zig");
const input = @import("input.zig");
const stbi = @import("stb_image.zig");
const audio = @import("audio.zig");
const Game = @import("game.zig");
const Sound = @import("sounds.zig").Sound;

const c = @cImport({
    @cInclude("SDL.h");
});

const callocators = @import("callocators.zig");

pub fn sdl_audio_callback(_: ?*anyopaque, data: [*c]u8, len: c_int) callconv(.C) void {
    var output = std.mem.bytesAsSlice(f32, @alignCast(@alignOf(f32), data)[0..@intCast(usize, len)]);

    var samples = audio.gen_samples(128);

    for (output, samples) |*o, i| {
        o.* = i;
    }
}

pub fn playSoundCb(snd: Sound) void {
    c.SDL_LockAudioDevice(audio_device);
    audio.state.playSound(snd);
    c.SDL_UnlockAudioDevice(audio_device);
}

const Map = struct { b: input.VirtualButton, k: usize };
const mapping = [_]Map{
    .{ .b = .a, .k = c.SDL_SCANCODE_X },
    .{ .b = .b, .k = c.SDL_SCANCODE_C },
    .{ .b = .left, .k = c.SDL_SCANCODE_LEFT },
    .{ .b = .right, .k = c.SDL_SCANCODE_RIGHT },
    .{ .b = .up, .k = c.SDL_SCANCODE_UP },
    .{ .b = .down, .k = c.SDL_SCANCODE_DOWN },
    .{ .b = .start, .k = c.SDL_SCANCODE_RETURN },
};

var audio_device: c.SDL_AudioDeviceID = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    var allocator = gpa.allocator();
    callocators.allocator = allocator;

    const zoom = 2;

    _ = c.SDL_Init(c.SDL_INIT_EVERYTHING);

    var win = c.SDL_CreateWindow("Hell World", c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED, Game.game_width * zoom, Game.game_height * zoom, 0);

    var rend = c.SDL_CreateRenderer(win, 0, c.SDL_RENDERER_PRESENTVSYNC);

    var tex = c.SDL_CreateTexture(rend, c.SDL_PIXELFORMAT_ABGR8888, c.SDL_TEXTUREACCESS_STREAMING, Game.game_width, Game.game_height);

    const wanted_audiospec = c.SDL_AudioSpec{
        .freq = 44100,
        .format = c.AUDIO_F32,
        .silence = 0,
        .channels = 2,
        .samples = 128,
        .padding = 0,
        .size = 0,
        .callback = sdl_audio_callback,
        .userdata = null,
    };

    var got_audiospec: c.SDL_AudioSpec = undefined;

    audio_device = c.SDL_OpenAudioDevice(
        null,
        @boolToInt(false),
        &wanted_audiospec,
        &got_audiospec,
        @boolToInt(false),
    );

    if (audio_device == 0) return error.AudioInitFailed;

    audio.init(wanted_audiospec.freq, allocator);
    defer audio.deinit();

    var seed = @bitCast(u64, std.time.timestamp());

    var game = try Game.init(allocator, playSoundCb, seed);
    defer game.deinit();

    c.SDL_PauseAudioDevice(audio_device, 0);

    //audio.init(rate: i32, alloc: std.mem.Allocator)
    var time = c.SDL_GetPerformanceCounter();
    const freq = @intToFloat(f64, c.SDL_GetPerformanceFrequency());
    var accumulator: f64 = 0;
    var _error: f64 = 0;

    mainLoop: while (true) {
        var time2 = c.SDL_GetPerformanceCounter();
        var delta = time2 - time;
        time = time2;

        var deltaS = @intToFloat(f64, delta) / freq;

        const timeEpsilon = 0.0009;

        if (std.math.fabs(deltaS - 1.0 / 60.0) < timeEpsilon) {
            _error += deltaS - 1.0 / 60.0;
            deltaS = 1.0 / 60.0;
        } else if (std.math.fabs(deltaS - 1.0 / 30.0) < timeEpsilon) {
            _error += deltaS - 1.0 / 30.0;
            deltaS = 1.0 / 30.0;
        } else {
            //std.log.warn("Delta ouside of epsilon : {d:0<6.4}. Accumulator : {d:0<6.4}", .{ deltaS, accumulator });
        }
        //std.log.info("Error is : {d:0<4.4}ms. Accumulator : {d:0<6.4}ms. ", .{ _error * 1000.0, accumulator * 1000.0 });

        accumulator += deltaS;

        var updatesThisLoop: u32 = 0;
        // Stable 60fps loop
        while (accumulator >= 1.0 / 60.0) {
            if (std.math.fabs(_error) > 1.0 / 60.0) {
                std.log.warn("Error too big, skipping a frame : {d:0<4.4}", .{_error});
                _error -= std.math.sign(_error) * 1.0 / 60.0;
            } else {
                var ev: c.SDL_Event = undefined;
                while (c.SDL_PollEvent(&ev) != 0) {
                    if (ev.type == c.SDL_QUIT)
                        break :mainLoop;
                }

                {
                    game.input.new_input_frame();
                    var num_keys: c_int = undefined;
                    var kbd = c.SDL_GetKeyboardState(&num_keys);

                    for (mapping) |m| {
                        game.input.set_input(m.b, kbd[m.k] != 0);
                    }
                }

                var timer = std.time.Timer.start() catch unreachable;
                try game.step();
                var step_time = @intToFloat(f64, timer.read());
                std.debug.print("step : {d:0>6}ms\n", .{step_time / std.time.ns_per_ms});
            }

            updatesThisLoop += 1;

            accumulator -= 1.0 / 60.0;
        }

        if (updatesThisLoop != 1) {
            std.log.warn("Updated {} time(s) this loop.", .{updatesThisLoop});
        }

        _ = c.SDL_UpdateTexture(tex, null, @ptrCast([*c]u8, game.img.pixels.ptr), Game.game_width * 4);
        _ = c.SDL_RenderCopy(rend, tex, null, &c.SDL_Rect{ .x = 0, .y = 0, .w = Game.game_width * zoom, .h = Game.game_height * zoom });
        _ = c.SDL_RenderPresent(rend);
    }

    // while (true) {
    //     var e: c.SDL_Event = undefined;
    //     while (c.SDL_PollEvent(&e) != 0) {
    //         if (e.type == c.SDL_QUIT) return;
    //     }

    //     // input
    //     {
    //         game.input.new_input_frame();
    //         var num_keys: c_int = undefined;
    //         var kbd = c.SDL_GetKeyboardState(&num_keys);

    //         for (mapping) |m| {
    //             game.input.set_input(m.b, kbd[m.k] != 0);
    //         }
    //     }

    //     try game.step();

    //     _ = c.SDL_UpdateTexture(tex, null, @ptrCast([*c]u8, game.img.pixels.ptr), Game.game_width * 4);
    //     _ = c.SDL_RenderCopy(rend, tex, null, &c.SDL_Rect{ .x = 0, .y = 0, .w = Game.game_width * zoom, .h = Game.game_height * zoom });
    //     _ = c.SDL_RenderPresent(rend);
    // }
}

test {
    _ = std.testing.refAllDeclsRecursive(sw);
    _ = std.testing.refAllDeclsRecursive(input);
    _ = std.testing.refAllDeclsRecursive(@import("bmfont.zig"));
}
