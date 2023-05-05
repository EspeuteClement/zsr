const std = @import("std");
const sw = @import("softwareRenderer.zig");
const stbi = @import("stb_image.zig");
const Input = @import("input.zig").Input;
const Sound = @import("sounds.zig").Sound;
const res = @import("resources.zig");
const options = @import("options");

img: sw.Image = undefined,

allocator: std.mem.Allocator = undefined,
input: Input = Input{},

state: State = undefined,
global_frames: u64 = undefined,

playSoundCb: ?*const fn (Sound) void = null,

pub const game_width = 240;
pub const game_height = 160;

const Self = @This();

const State = struct {};

pub fn init(alloc: std.mem.Allocator, playSoundCB: ?*const fn (Sound) void, seed: u64) !Self {
    var game: Self = .{};
    game.global_frames = seed;
    game.allocator = alloc;
    game.playSoundCb = playSoundCB;
    game.img = try sw.Image.init(alloc, game_width, game_height);
    errdefer game.img.deinit(alloc);

    game.reset();

    return game;
}

pub fn reset(self: *Self) void {
    self.state = State{};
}

pub fn deinit(self: *Self) void {
    self.img.deinit(self.allocator);
}

pub fn playSound(self: *Self, snd: Sound) void {
    if (self.playSoundCb) |cb| {
        cb(snd);
    } else {
        @panic("play sound not registered");
    }
}

fn aabb(x0: f32, y0: f32, w0: f32, h0: f32, x1: f32, y1: f32, w1: f32, h1: f32) bool {
    return !(x0 + w0 < x1 or
        x0 > x1 + w1 or
        y0 + h0 < y1 or
        y0 > y1 + h1);
}

inline fn ptrCast(comptime T: type, ptr: *anyopaque) T {
    return @ptrCast(T, @alignCast(@alignOf(@typeInfo(T).Pointer.child), ptr));
}

inline fn constPtrCast(comptime T: type, ptr: *const anyopaque) T {
    return @ptrCast(T, @alignCast(@alignOf(@typeInfo(T).Pointer.child), ptr));
}

pub fn step(self: *Self) !void {
    self.global_frames += 1;
    var c = @intCast(u8, self.global_frames % 255);
    var col = sw.Color{ .r = c, .b = c, .g = c, .a = 255 };
    self.img.drawClear(col);
}
