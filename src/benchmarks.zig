const std = @import("std");
const sw = @import("softwareRenderer.zig");
const stbi = @import("stb_image.zig");

var rand = std.rand.DefaultPrng.init(0);
var r: std.rand.Random = undefined;
var sprite: sw.Image = undefined;

var buffer: sw.Image = undefined;

const W = 320;
const H = 180;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());
    var allocator = gpa.allocator();

    var out = std.io.getStdOut();

    var buff_out = std.io.bufferedWriter(out.writer());
    defer buff_out.flush() catch unreachable;

    var w = buff_out.writer();

    sprite = try stbi.load_to_Image("res/ben_shmark.png", allocator);
    defer sprite.deinit(allocator);

    rand = std.rand.DefaultPrng.init(0);

    buffer = try sw.Image.init(allocator, W, H);
    defer buffer.deinit(allocator);

    bench("drawSprite", bench_draw_sprite, w);
    bench("drawSpriteNoAlhpa", bench_draw_sprite_no_alpha, w);

    try w.print("---\n", .{});

    bench("drawRect", bench_draw_rect, w);

    try w.print("---\n", .{});
    bench("reference", bench_draw_reference, w);
    bench("referenceBlit", bench_draw_reference_blit, w);
    bench("referenceBlitAlpha", bench_draw_reference_blit_alpha, w);

    std.mem.doNotOptimizeAway(sprite.pixels);
    // Bench 1:
}

fn bench_draw_sprite(i: usize) void {
    const x = @intCast(i32, i % (W + 16));
    const y = @intCast(i32, @divTrunc(i, (W + 16)) % H);

    buffer.drawImageRect(x, y, sprite, sprite.getRect(), .{ .flip_horizontal = i % 2 == 0, .flip_vertical = (@divTrunc(i, 2) % 2 == 0) });
}

fn bench_draw_sprite_no_alpha(i: usize) void {
    const x = @intCast(i32, i % (W + 16));
    const y = @intCast(i32, @divTrunc(i, (W + 16)) % H);

    buffer.drawImageRectNoAlpha(x, y, sprite, sprite.getRect());
}

fn bench_draw_rect(i: usize) void {
    const x = @intCast(i32, i % (W + 16));
    const y = @intCast(i32, @divTrunc(i, (W + 16)) % H);

    buffer.drawRect(x, y, sprite.width, sprite.height, sw.Color.fromRGB(0xFF0000));
}

fn reference(raw_buf: []u32, w: i32, h: i32, dest_x: i32, dest_y: i32, rw: i32, rh: i32, color: u32) void {
    const start_x = @max(0, dest_x);
    var y = @max(0, dest_y);
    const end_x = @min(dest_x + rw, w);
    const end_y = @min(dest_y + rh, h);

    while (y < end_y) : (y += 1) {
        var x = start_x;
        while (x < end_x) : (x += 1) {
            raw_buf[@intCast(usize, x + y * w)] = color;
        }
    }
}

fn bench_draw_reference(i: usize) void {
    const x = @intCast(i32, i % (W + 16));
    const y = @intCast(i32, @divTrunc(i, (W + 16)) % H);

    @call(.never_inline, reference, .{ @ptrCast([]u32, buffer.pixels), buffer.width, buffer.height, x, y, sprite.width, sprite.height, @intCast(u32, i) });
}

fn referenceBlit(raw_buf: [*]u32, w: i32, h: i32, dest_x: i32, dest_y: i32, rw: i32, rh: i32, src_buff: [*]u32) void {
    const start_x = @max(0, dest_x);
    const start_y = @max(0, dest_y);
    const end_x = @min(dest_x + rw, w) - start_x;
    const end_y = @min(dest_y + rh, h) - start_y;

    var y: i32 = 0;
    while (y < end_y) : (y += 1) {
        var x: i32 = 0;
        while (x < end_x) : (x += 1) {
            raw_buf[@intCast(usize, (start_x + x) + (start_y + y) * w)] = src_buff[@intCast(usize, x + y * rw)];
        }
    }
}

fn referenceBlitAlpha(noalias raw_buf: [*]u32, w: i32, h: i32, dest_x: i32, dest_y: i32, rw: i32, rh: i32, noalias src_buff: [*]const u32) void {
    const start_x = @max(0, dest_x);
    const start_y = @max(0, dest_y);
    const end_x = @min(dest_x + rw, w) - start_x;
    const end_y = @min(dest_y + rh, h) - start_y;

    var y: i32 = 0;
    while (y < end_y) : (y += 1) {
        var x: i32 = 0;
        while (x < end_x) : (x += 1) {
            const o = &raw_buf[@intCast(usize, (start_x + x) + (start_y + y) * w)];
            const c = src_buff[@intCast(usize, x + y * rw)];
            o.* = if (c != 0) c else o.*;
        }
    }
}

fn bench_draw_reference_blit(i: usize) void {
    const x = @intCast(i32, i % (W + 16));
    const y = @intCast(i32, @divTrunc(i, (W + 16)) % H);

    referenceBlit(@ptrCast([*]u32, buffer.pixels.ptr), buffer.width, buffer.height, x, y, sprite.width, sprite.height, @ptrCast([*]u32, sprite.pixels.ptr));
}

fn bench_draw_reference_blit_alpha(i: usize) void {
    const x = @intCast(i32, i % (W + 16));
    const y = @intCast(i32, @divTrunc(i, (W + 16)) % H);

    referenceBlitAlpha(@ptrCast([*]u32, buffer.pixels.ptr), buffer.width, buffer.height, x, y, sprite.width, sprite.height, @ptrCast([*]u32, sprite.pixels.ptr));
}

fn bench(name: []const u8, comptime func: anytype, w: anytype) void {
    const times = 1_000_000;
    var i: usize = times;

    var timer = std.time.Timer.start() catch unreachable;
    while (i != 0) : (i -= 1) {
        @call(.never_inline, func, .{i});
    }
    var time = timer.read();

    var time_f: f64 = @intToFloat(f64, time);
    var time_s = time_f / std.time.ns_per_s;
    var us_per_call = time_s / times * std.time.us_per_s;
    var num_in_a_frame = times / time_s / 60.0;

    w.print("benchmark : {s}\n", .{name}) catch unreachable;
    w.print("\tTook : {d:.4}s, Per Call : {d:.4}us, Num Per Frame (60fps) : {d: >6.0} \n", .{ time_s, us_per_call, num_in_a_frame }) catch unreachable;
}
