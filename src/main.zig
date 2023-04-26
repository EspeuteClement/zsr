const std = @import("std");
const sw = @import("softwareRenderer.zig");
const input = @import("input.zig");
const stbi = @import("stb_image.zig");

const c = @cImport({
    @cInclude("SDL.h");
});

const callocators = @import("callocators.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());

    var allocator = gpa.allocator();
    callocators.allocator = allocator;

    const windWidth = 256;
    const windHeight = 256;
    const zoom = 3;

    _ = c.SDL_Init(c.SDL_INIT_EVERYTHING);

    var win = c.SDL_CreateWindow("Hell World", c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED, windWidth * zoom, windHeight * zoom, 0);

    var rend = c.SDL_CreateRenderer(win, 0, c.SDL_RENDERER_PRESENTVSYNC);

    var tex = c.SDL_CreateTexture(rend, c.SDL_PIXELFORMAT_ABGR8888, c.SDL_TEXTUREACCESS_STREAMING, windWidth, windHeight);

    var time: i32 = 0;

    var timer = try std.time.Timer.start();

    var game_input: input.Input = .{};

    while (true) {
        var e: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&e) != 0) {
            if (e.type == c.SDL_QUIT) return;
        }

        // input
        {
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
                game_input.set_input(m.b, kbd[m.k] != 0);
            }
        }

        //_ = c.SDL_UpdateTexture(tex, null, @ptrCast([*c]u8, img.pixels.ptr), 320 * 4);
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
