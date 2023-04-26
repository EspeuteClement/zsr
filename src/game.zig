const std = @import("std");
const sw = @import("softwareRenderer.zig");
const stbi = @import("stb_image.zig");
const Input = @import("input.zig").Input;

var allocator: std.mem.Allocator = undefined;

const windWidth = 256;
const windHeight = 256;

pub var img: sw.Image = undefined;
var ralsei: sw.Image = undefined;

pub fn init(alloc: std.mem.Allocator) void {
    allocator = alloc;
    img = sw.Image.init(allocator, windWidth, windHeight) catch unreachable;
    ralsei = stbi.load_from_memory_to_Image(@embedFile("web/ben_shmark.png"), allocator) catch @panic("aaa");
}

var time: f32 = 0.0;

var ralsei_x: i32 = 0;
var ralsei_y: i32 = 0;

pub var input = Input{};

pub fn step() void {
    {
        if (input.is_down(.left))
            ralsei_x -= 1;
        if (input.is_down(.right))
            ralsei_x += 1;
        if (input.is_down(.up))
            ralsei_y -= 1;
        if (input.is_down(.down))
            ralsei_y += 1;
    }

    time += 0.016;
    var c = @floatToInt(u8, (@sin(time) * 0.5 + 0.5) * 255.0);
    img.drawClear(.{ .r = c, .g = c, .b = c, .a = 255 });
    img.drawImageRect(ralsei_x, ralsei_y, ralsei, ralsei.getRect(), .{});
}
