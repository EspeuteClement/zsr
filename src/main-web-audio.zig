const std = @import("std");
const callocators = @import("callocators.zig");
const sound = @import("sounds.zig");

const c = @cImport({
    @cInclude("pocketmod.h");
    @cInclude("dr_wav.h");
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

var samples: []f32 = undefined;
var tempBuffer: []f32 = undefined;

var pocketmod: c.pocketmod_context = std.mem.zeroInit(c.pocketmod_context, .{});
var pocketmod_data = @embedFile("web/bananasplit.mod");
var soundPlayed: bool = true;

const soundData = brk: {
    const decls = @typeInfo(sound.SoundList).Struct.decls;
    var sounds: [decls.len][]const u8 = undefined;

    for (decls, 0..) |decl, i| {
        sounds[i] = @embedFile(@field(sound.SoundList, decl.name));
    }

    break :brk sounds;
};

const Sound = struct {
    ctx: c.drwav = undefined,
};

const State = struct {
    sounds: std.ArrayListUnmanaged(Sound) = .{},

    pub fn playSound(self: *Self, snd: sound.Sound) void {
        var ctx = self.sounds.addOne(allocator) catch return;

        var data = soundData[@enumToInt(snd)];
        var res = c.drwav_init_memory(&ctx.ctx, data.ptr, data.len, null);
        if (res == 0) @panic("couldn't init dr_wav");
    }

    const Self = @This();
};

var state: State = .{};

pub export fn init(rate: i32) void {
    allocator = gpa.allocator();
    callocators.allocator = allocator;

    samples = allocator.alloc(f32, 128 * 2) catch unreachable;
    tempBuffer = allocator.alloc(f32, 128 * 2) catch unreachable;

    {
        var res = c.pocketmod_init(&pocketmod, pocketmod_data, pocketmod_data.len, @intCast(c_int, rate));
        if (res == 0) @panic("couldn't init");
    }

    state.playSound(.@"test");
}

var counter: usize = 100;
pub export fn gen_samples(numSamples: i32) i32 {
    counter -= 1;
    if (counter == 0) {
        counter = 100;
        state.playSound(.@"test");
    }

    const numSamples2 = @intCast(usize, numSamples) * 2;
    if (samples.len < numSamples2) {
        samples = allocator.realloc(samples, numSamples2) catch unreachable;
        tempBuffer = allocator.realloc(tempBuffer, numSamples2) catch unreachable;
    }

    {
        const buff = std.mem.sliceAsBytes(samples);
        var buffPos: usize = 0;

        // pocketmod_render can render less samples than requested if at the end of the track
        while (buffPos < buff.len) {
            var subBuff = buff[buffPos..];

            var written = c.pocketmod_render(&pocketmod, subBuff.ptr, @intCast(c_int, subBuff.len));
            buffPos += @intCast(usize, written);
        }
    }

    {
        var idx: usize = state.sounds.items.len;
        while (idx > 0) {
            idx -= 1;
            const snd = &state.sounds.items[idx];
            const drwav = &snd.ctx;

            const numChannels = drwav.channels;
            if (numChannels > 2) @panic("Too Many Channels");
            const len = numSamples * numChannels;
            var read = @intCast(usize, c.drwav_read_pcm_frames_f32(drwav, @intCast(usize, len), tempBuffer.ptr));

            if (numChannels == 1) {
                mixMono(tempBuffer[0..read], samples[0 .. read * 2]);
            } else {
                mix(tempBuffer[0..read], samples[0..read]);
            }

            if (read < len) {
                var res = c.drwav_uninit(drwav);
                if (res == 0) @panic("wtf");
                _ = state.sounds.swapRemove(idx);
            }
        }
    }

    return @intCast(i32, @ptrToInt(samples.ptr));
}

fn mix(in: []f32, out: []f32) void {
    for (in, out) |sin, *sout| {
        sout.* += sin;
    }
}

fn mixMono(in: []f32, out: []f32) void {
    for (in, 0..) |sin, i| {
        out[i * 2] += sin;
        out[i * 2 + 1] += sin;
    }
}