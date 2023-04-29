const std = @import("std");
const sw = @import("softwareRenderer.zig");
const stbi = @import("stb_image.zig");
const Input = @import("input.zig").Input;
const Sound = @import("sounds.zig").Sound;

img: sw.Image = undefined,
ralsei: sw.Image = undefined,
allocator: std.mem.Allocator = undefined,
time: f32 = 0.0,
ralsei_x: i32 = 0,
ralsei_y: i32 = 0,
input: Input = Input{},

playSoundCb: ?*const fn (Sound) void = null,

const Self = @This();

pub const game_width = 240;
pub const game_height = 160;

pub fn init(alloc: std.mem.Allocator, playSoundCB: ?*const fn (Sound) void) !Self {
    var game: Self = .{};

    game.allocator = alloc;
    game.playSoundCb = playSoundCB;
    game.img = try sw.Image.init(alloc, game_width, game_height);
    errdefer game.img.deinit(alloc);

    game.ralsei = try stbi.load_from_memory_to_Image(@embedFile("web/ben_shmark.png"), alloc);
    errdefer game.img.deinit(alloc);

    game.playSound(.music);

    return game;
}

pub fn deinit(self: *Self) void {
    self.img.deinit(self.allocator);
    self.ralsei.deinit(self.allocator);
}

pub fn playSound(self: *Self, snd: Sound) void {
    if (self.playSoundCb) |cb| {
        cb(snd);
    } else {
        @panic("play sound not registered");
    }
}

pub fn step(self: *Self) !void {
    {
        if (self.input.is_down(.left))
            self.ralsei_x -= 1;
        if (self.input.is_down(.right))
            self.ralsei_x += 1;
        if (self.input.is_down(.up))
            self.ralsei_y -= 1;
        if (self.input.is_down(.down))
            self.ralsei_y += 1;
        if (self.input.is_just_pressed(.a))
            self.playSound(.music);
    }

    self.time += 0.016;
    var c = @floatToInt(u8, (@sin(self.time) * 0.5 + 0.5) * 255.0);
    self.img.drawClear(.{ .r = c, .g = c, .b = c, .a = 255 });
    self.img.drawImageRect(self.ralsei_x, self.ralsei_y, self.ralsei, self.ralsei.getRect(), .{});
}
