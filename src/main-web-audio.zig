const std = @import("std");
const c = @cImport({
    @cInclude("pocketmod.h");
});

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

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var alloc: std.mem.Allocator = undefined;

var samples: []f32 = undefined;

var pocketmod: c.pocketmod_context = std.mem.zeroInit(c.pocketmod_context, .{});
var data = @embedFile("web/bananasplit.mod");

pub export fn init(rate: i32) void {
    alloc = gpa.allocator();
    samples = alloc.alloc(f32, 128 * 2) catch unreachable;

    var res = c.pocketmod_init(&pocketmod, data, data.len, @intCast(c_int, rate));
    if (res == 0) @panic("couldn't init");
}

pub export fn gen_samples(numSamples: i32) i32 {
    const numSamples2 = @intCast(usize, numSamples) * 2;
    if (samples.len < numSamples2) {
        samples = alloc.realloc(samples, numSamples2) catch unreachable;
    }

    const buff = std.mem.sliceAsBytes(samples);
    var buffPos: usize = 0;

    // pocketmod_render can render less samples than requested if at the end of the track
    while (buffPos < buff.len) {
        var subBuff = buff[buffPos..];

        var written = c.pocketmod_render(&pocketmod, subBuff.ptr, @intCast(c_int, subBuff.len));
        buffPos += @intCast(usize, written);
    }
    return @intCast(i32, @ptrToInt(buff.ptr));
}
