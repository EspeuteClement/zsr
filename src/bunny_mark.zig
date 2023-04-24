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

    var partyred_ralsei = try stbi.load_to_Image("res/ben_shmark.png", allocator);
    defer partyred_ralsei.deinit(allocator);

    const Ralsei = struct {
        x : i32,
        y : i32,
        vx : i32,
        vy : i32,
    };

    var ralseis = try std.ArrayList(Ralsei).initCapacity(allocator, 10_000);
    defer ralseis.deinit();

    var img = try sw.Image.init(allocator, windWidth, windHeight);
    defer img.deinit(allocator);

    const dk_gray = sw.Color.fromU32(0xFF222222);

    img.drawClear(dk_gray);

    _ = c.SDL_Init(c.SDL_INIT_EVERYTHING);

    var win  = c.SDL_CreateWindow("Hell World", c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED, windWidth*zoom, windHeight*zoom, 0); 

    var rend = c.SDL_CreateRenderer(win ,0, c.SDL_RENDERER_PRESENTVSYNC);

    var tex = c.SDL_CreateTexture(rend, c.SDL_PIXELFORMAT_ABGR8888, c.SDL_TEXTUREACCESS_STREAMING, windWidth, windHeight);

    var time : i32 = 0; 

    var timer = try std.time.Timer.start();

    var game_input : input.Input = .{};

    var draw_rects = false;
    var update = true;
    var draw = true;


    while (true) {
        var e : c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&e) != 0) {
            if (e.@"type" == c.SDL_QUIT) return;
        }


        // input
        {
            var num_keys : c_int = undefined;
            var kbd = c.SDL_GetKeyboardState(&num_keys);

            const Map = struct {b : input.VirtualButton, k : usize};
            const mapping = [_]Map{
                .{.b = .a,      .k = c.SDL_SCANCODE_X},
                .{.b = .b,      .k = c.SDL_SCANCODE_C},
                .{.b = .left,   .k = c.SDL_SCANCODE_LEFT},
                .{.b = .right,  .k = c.SDL_SCANCODE_RIGHT},
                .{.b = .up,     .k = c.SDL_SCANCODE_UP},
                .{.b = .down,   .k = c.SDL_SCANCODE_DOWN},
            };

            game_input.new_input_frame();

            for (mapping) |m| {
                game_input.set_input(m.b, kbd[m.k] != 0);
            }
        }


        // Game logic
        {
            if (game_input.is_down(.a)) {
                var i : i32 = 0;
                while (i < 100) : (i+=1) {
                    var ralsei = try ralseis.addOne();
                    ralsei.x = 16 << 16;
                    ralsei.y = 16 << 16;
                    ralsei.vx = i << 12;
                    ralsei.vy = i << 12;
                }
            }

            if (game_input.is_just_pressed(.b)) {
                draw_rects = !draw_rects;
            }

            if (game_input.is_just_pressed(.up)) {
                update = !update;
            }

            if (game_input.is_just_pressed(.down)) {
                draw = !draw;
            }

            if (update) {
                for (ralseis.items) |*ralsei| {
                    ralsei.x += ralsei.vx;
                    ralsei.y += ralsei.vy;

                    ralsei.vy += 10 << 8;

                    if (ralsei.x < 0 or (ralsei.x >> 16) > windWidth - partyred_ralsei.width) {
                        ralsei.vx = -ralsei.vx; 
                    }
                    if (ralsei.y < 0 or (ralsei.y >> 16) > windHeight - partyred_ralsei.height) {
                        ralsei.vy = -ralsei.vy;
                    }

                }
            }

        }


        {
            img.drawClear(dk_gray);

            if (draw) {
                if (draw_rects) {
                    for (ralseis.items) |ralsei| {
                        img.drawRectFast(ralsei.x >> 16,ralsei.y >> 16, partyred_ralsei.width, partyred_ralsei.height, sw.Color.fromRGB(0xFF0000));
                    }
                }
                else {
                    for (ralseis.items) |ralsei| {
                        img.drawImageRect(ralsei.x >> 16,ralsei.y >> 16, partyred_ralsei, partyred_ralsei.getRect());
                    }
                }
            }
        }        

        _ = c.SDL_UpdateTexture(tex, null, @ptrCast([*c]u8, img.pixels.ptr), 320 * 4);
        _ = c.SDL_RenderCopy(rend, tex, null, &c.SDL_Rect{.x = 0, .y = 0, .w = windWidth * zoom, .h = windHeight * zoom});
        _ = c.SDL_RenderPresent(rend);

        time += 1;
        var perf = timer.lap();
        std.debug.print("Ralseis : {d}, Time : {d:05.4}ms\n", .{ralseis.items.len, @intToFloat(f64, perf) / std.time.ns_per_ms});
    }
}