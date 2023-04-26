const std = @import("std");
const sw = @import("softwareRenderer.zig");
const input = @import("input.zig");
const stbi = @import("stb_image.zig");
const audio = @import("audio.zig");
const game = @import("game.zig");

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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());

    var allocator = gpa.allocator();
    callocators.allocator = allocator;

    const windWidth = 256;
    const windHeight = 256;
    const zoom = 2;

    _ = c.SDL_Init(c.SDL_INIT_EVERYTHING);

    var win = c.SDL_CreateWindow("Hell World", c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED, windWidth * zoom, windHeight * zoom, 0);

    var rend = c.SDL_CreateRenderer(win, 0, c.SDL_RENDERER_PRESENTVSYNC);

    var tex = c.SDL_CreateTexture(rend, c.SDL_PIXELFORMAT_ABGR8888, c.SDL_TEXTUREACCESS_STREAMING, windWidth, windHeight);

    var time: i32 = 0;

    var timer = try std.time.Timer.start();

    const wanted_audiospec = c.SDL_AudioSpec{
        .freq = 48000,
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

    var audio_device = c.SDL_OpenAudioDevice(
        null,
        @boolToInt(false),
        &wanted_audiospec,
        &got_audiospec,
        @boolToInt(false),
    );

    if (audio_device == 0) return error.AudioInitFailed;

    audio.init(wanted_audiospec.freq, allocator);
    game.init(allocator);

    c.SDL_PauseAudioDevice(audio_device, 0);

    //audio.init(rate: i32, alloc: std.mem.Allocator)

    while (true) {
        var e: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&e) != 0) {
            if (e.type == c.SDL_QUIT) return;
        }

        // input
        {
            game.input.new_input_frame();
            var num_keys: c_int = undefined;
            var kbd = c.SDL_GetKeyboardState(&num_keys);

            const Map = struct { b: input.VirtualButton, k: usize };
            const mapping = [_]Map{
                .{ .b = .a, .k = c.SDL_SCANCODE_X },
                .{ .b = .b, .k = c.SDL_SCANCODE_C },
                .{ .b = .left, .k = c.SDL_SCANCODE_LEFT },
                .{ .b = .right, .k = c.SDL_SCANCODE_RIGHT },
                .{ .b = .up, .k = c.SDL_SCANCODE_UP },
                .{ .b = .down, .k = c.SDL_SCANCODE_DOWN },
            };

            for (mapping) |m| {
                game.input.set_input(m.b, kbd[m.k] != 0);
            }
        }

        game.step();

        _ = c.SDL_UpdateTexture(tex, null, @ptrCast([*c]u8, game.img.pixels.ptr), windWidth * 4);
        _ = c.SDL_RenderCopy(rend, tex, null, &c.SDL_Rect{ .x = 0, .y = 0, .w = windWidth * zoom, .h = windHeight * zoom });
        _ = c.SDL_RenderPresent(rend);

        time += 1;
        var perf = timer.lap();
        std.debug.print("Time : {d:05.4}ms\n", .{@intToFloat(f64, perf) / std.time.ns_per_ms});
    }
}

test {
    _ = std.testing.refAllDeclsRecursive(sw);
    _ = std.testing.refAllDeclsRecursive(input);
    _ = std.testing.refAllDeclsRecursive(@import("bmfont.zig"));
}
