const std = @import("std");
const callocators = @import("callocators.zig");
const audio = @import("audio.zig");
const sound = @import("sounds.zig");


pub const std_options = struct {
    // Define logFn to override the std implementation
    pub const logFn = myLogFn;
};

pub fn myLogFn(
    comptime _: std.log.Level,
    comptime _: @TypeOf(.EnumLiteral),
    comptime _: []const u8,
    _: anytype,
) void {}

const Imports = struct {
    pub extern fn print(ptr: i32, length: i32) void;
};

pub fn print(str: []const u8) void {
    Imports.print(@intCast(i32, @ptrToInt(str.ptr)), @intCast(i32, str.len));
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    print("!!!PANIC!!!");
    print(msg);
    while (true) {}
}

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator: std.mem.Allocator = undefined;

pub export fn init(rate: i32) void {
    allocator = gpa.allocator();
    callocators.allocator = allocator;

    audio.init(rate, allocator);
}

pub export fn gen_samples(numSamples: i32) i32 {
    var samples = audio.gen_samples(numSamples);
    return @intCast(i32, @ptrToInt(samples.ptr));
}

pub export fn playSound(snd : i32) void {
	audio.state.playSound(@intToEnum(sound.Sound, snd));
}
