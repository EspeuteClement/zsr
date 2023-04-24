const std = @import("std");
const sw = @import("softwareRenderer.zig");
const input = @import("input.zig");
const stbi = @import("stb_image.zig");

const c = @cImport({
    @cInclude("SDL.h");
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());

    var allocator = gpa.allocator();

    const windWidth = 320;
    const windHeight = 160;
    const zoom = 3;

    var fb = try allocator.alloc(u32, windWidth * windHeight);
    defer allocator.free(fb);

    std.mem.set(u32, fb, 0xFF777777);

    var partyred_ralsei = try stbi.load_to_Image("res/partired_ralsei2.png", allocator);
    defer partyred_ralsei.deinit(allocator);

    var ralsei_x: i32 = 0;
    var ralsei_y: i32 = 0;

    var img = try sw.Image.init(allocator, windWidth, windHeight);
    defer img.deinit(allocator);

    const dk_gray = sw.Color.fromU32(0xFF222222);
    const lt_gray = sw.Color.fromU32(0xFF999999);
    const red = sw.Color{ .r = 255, .g = 0, .b = 0 };
    const green = sw.Color{ .r = 0, .g = 255, .b = 0 };
    const blue = sw.Color{ .r = 0, .g = 0, .b = 255 };

    img.drawClear(dk_gray);
    img.drawPixel(8, 8, lt_gray);

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

        // Game logic
        {
            if (game_input.is_down(.left))
                ralsei_x -= 1;
            if (game_input.is_down(.right))
                ralsei_x += 1;
            if (game_input.is_down(.up))
                ralsei_y -= 1;
            if (game_input.is_down(.down))
                ralsei_y += 1;
        }

        var loops: usize = 1;
        while (loops > 0) : (loops -= 1) {
            img.drawClear(dk_gray);

            const tt = time;
            var y: i32 = 0;
            while (y < img.height) : (y += 1) {
                var x: i32 = 0;
                while (x < img.width) : (x += 1) {
                    var p = @divTrunc(x + tt, @as(i32, 8)) + @divTrunc(y + tt, @as(i32, 8));
                    if (@mod(p, 2) == 0) {
                        const col = switch (@mod(@divTrunc(p, 2), 3)) {
                            0 => red,
                            1 => blue,
                            2 => green,
                            else => unreachable,
                        };
                        img.drawPixelFast(x, y, col);
                    }
                }
            }

            img.drawImageRect(ralsei_x, ralsei_y, partyred_ralsei, partyred_ralsei.getRect(), .{});
        }

        _ = c.SDL_UpdateTexture(tex, null, @ptrCast([*c]u8, img.pixels.ptr), 320 * 4);
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
