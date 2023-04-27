const std = @import("std");
const sound = @import("sounds.zig");

const c = @cImport({
    @cInclude("pocketmod.h");
    @cInclude("dr_wav.h");
});

var samples: []f32 = undefined;
var tempBuffer: []f32 = undefined;

const soundData = brk: {
    const decls = @typeInfo(sound.SoundList).Struct.decls;
    var sounds: [decls.len][]const u8 = undefined;

    for (decls, 0..) |decl, i| {
        sounds[i] = @embedFile(@field(sound.SoundList, decl.name).path);
    }

    break :brk sounds;
};

const Sound = struct {
    ctx: c.drwav = undefined,
    playing: bool = false,
};

const State = struct {
    rate: usize = 0,
    sounds: [64]Sound = [_]Sound{.{}} ** 64,
    firstSound: usize = 0,
    pocketmod: ?c.pocketmod_context = null,

    pub fn playSound(self: *Self, snd: sound.Sound) void {
        var data = soundData[@enumToInt(snd)];
        var kind: sound.Kind = sound.defs.get(snd);
        switch (kind) {
            .Wav => self.playSoundWav(data),
            .Mod => self.playSoundMod(data),
        }
    }

    pub fn playSoundMod(self: *Self, data: []const u8) void {
        self.pocketmod = std.mem.zeroInit(c.pocketmod_context, .{});
        var res = c.pocketmod_init(&self.pocketmod.?, data.ptr, @intCast(c_int, data.len), @intCast(c_int, self.rate));
        if (res == 0) @panic("couldn't init");
    }

    pub fn playSoundWav(self: *Self, data: []const u8) void {
        var ctx: *Sound = for (&self.sounds) |*ctx| {
            if (!ctx.playing)
                break ctx;
        } else return;

        ctx.playing = true;
        var res = c.drwav_init_memory(&ctx.ctx, data.ptr, data.len, null);
        if (res == 0) @panic("couldn't init dr_wav");
    }

    const Self = @This();
};

pub var state: State = .{};
var allocator: std.mem.Allocator = undefined;

pub fn init(rate: i32, alloc: std.mem.Allocator) void {
    allocator = alloc;
    state.rate = @intCast(usize, rate);

    r = random.random();

    samples = allocator.alloc(f32, 128 * 2) catch unreachable;
    tempBuffer = allocator.alloc(f32, 128 * 2) catch unreachable;

    state.playSound(.@"test");
}

var random = std.rand.DefaultPrng.init(0);
var r: std.rand.Random = undefined;
pub fn gen_samples(numSamples: i32) []f32 {
    const numSamples2 = @intCast(usize, numSamples) * 2;
    if (samples.len < numSamples2) {
        samples = allocator.realloc(samples, numSamples2) catch unreachable;
        tempBuffer = allocator.realloc(tempBuffer, numSamples2) catch unreachable;
    }

    std.mem.set(f32, samples, 0.0);
    if (state.pocketmod) |*pocketmod| {
        var buffPos: usize = 0;

        const buff = std.mem.sliceAsBytes(tempBuffer);

        // pocketmod_render can render less samples than requested if at the end of the track
        while (buffPos < buff.len) {
            var subBuff = buff[buffPos..];

            var written = c.pocketmod_render(pocketmod, subBuff.ptr, @intCast(c_int, subBuff.len));
            buffPos += @intCast(usize, written);
        }

        mix(tempBuffer, samples);
    }

    {
        for (&state.sounds) |*snd| {
            if (!snd.playing) continue;
            const drwav = &snd.ctx;

            const numChannels = drwav.channels;
            if (numChannels > 2) @panic("Too Many Channels");
            const len = numSamples * numChannels;
            var read = @intCast(usize, c.drwav_read_pcm_frames_f32(drwav, @intCast(usize, len), tempBuffer.ptr));

            if (read < len) {
                var res = c.drwav_uninit(drwav);
                if (res != 0) @panic("wtf");
                snd.ctx = undefined;
                snd.playing = false;
            }

            if (numChannels == 1) {
                mixMono(tempBuffer[0..read], samples[0 .. read * 2]);
            } else {
                mix(tempBuffer[0..read], samples[0..read]);
            }
        }
    }

    return samples;
}

pub fn mix(in: []f32, out: []f32) void {
    for (in, out) |sin, *sout| {
        sout.* += sin;
    }
}

pub fn mixMono(in: []f32, out: []f32) void {
    for (in, 0..) |sin, i| {
        out[i * 2] += sin;
        out[i * 2 + 1] += sin;
    }
}
