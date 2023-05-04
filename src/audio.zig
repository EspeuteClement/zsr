const std = @import("std");
const sound = @import("sounds.zig");

const oggSupport = false;

const c = @cImport({
    @cInclude("pocketmod.h");
    @cInclude("dr_wav.h");
    @cInclude("dr_mp3.h");
    if (oggSupport) @cInclude("stb_vorbis.h");
});

var samples: []f32 = undefined;
var tempBuffer: []f32 = undefined;

const music_start = 1240;
const music_end = 4705329;

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
    mp3: ?c.drmp3 = null,
    mp3_current_sample: usize = 0,

    vorbis_alloc: if (oggSupport) c.stb_vorbis_alloc else void = undefined,
    ogg: if (oggSupport) ?*c.stb_vorbis else void = if (oggSupport) null else undefined,

    pub fn playSound(self: *Self, snd: sound.Sound) void {
        var data = soundData[@enumToInt(snd)];
        var kind: sound.Kind = sound.defs.get(snd);
        switch (kind) {
            .Wav => self.playSoundWav(data),
            .Mod => self.playSoundMod(data),
            .Mp3 => self.playSoundMp3(data),
            .Ogg => self.playSoundOgg(data),
        }
    }

    pub fn playSoundOgg(self: *Self, data: []const u8) void {
        if (!oggSupport) return;
        if (self.ogg) |ogg| {
            c.stb_vorbis_close(ogg);
        }
        var err: c_int = undefined;
        self.ogg = c.stb_vorbis_open_memory(data.ptr, @intCast(c_int, data.len), &err, &state.vorbis_alloc);
        if (self.ogg == null) @panic("Couln't play ogg");
        _ = c.stb_vorbis_seek(self.ogg.?, 33 * 44100);
    }

    pub fn playSoundMp3(self: *Self, data: []const u8) void {
        if (self.mp3) |*mp3| {
            c.drmp3_uninit(mp3);
        }
        self.mp3 = std.mem.zeroInit(c.drmp3, .{});
        var res = c.drmp3_init_memory(&self.mp3.?, data.ptr, data.len, null);
        if (res == 0) @panic("Couln't play mp3");
        self.seekMp3(0);
    }

    pub fn seekMp3(self: *Self, sample: usize) void {
        _ = c.drmp3_seek_to_pcm_frame(&self.mp3.?, sample + music_start);
        self.mp3_current_sample = sample;
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

    pub fn deinit(self: *Self) void {
        if (self.mp3) |*mp3| {
            c.drmp3_uninit(mp3);
        }

        if (oggSupport) {
            if (self.ogg) |ogg| {
                c.stb_vorbis_close(ogg);
            }
        }

        for (&self.sounds) |*snd| {
            if (snd.playing) {
                var res = c.drwav_uninit(&snd.ctx);
                if (res != 0) @panic("wtf");
            }
        }
    }

    const Self = @This();
};

pub var state: State = .{};
var allocator: std.mem.Allocator = undefined;

pub fn init(rate: i32, alloc: std.mem.Allocator) void {
    allocator = alloc;
    state.rate = @intCast(usize, rate);

    if (oggSupport) {
        state.vorbis_alloc = brk: {
            var al = allocator.alloc(u8, 200 * 1024 * 1024) catch @panic("OOM"); // ~200kbi for ogg
            break :brk .{
                .alloc_buffer = al.ptr,
                .alloc_buffer_length_in_bytes = @intCast(c_int, al.len),
            };
        };
    }

    r = random.random();

    samples = allocator.alloc(f32, 128 * 2) catch unreachable;
    tempBuffer = allocator.alloc(f32, 128 * 2) catch unreachable;
}

pub fn deinit() void {
    state.deinit();
    allocator.free(samples);
    allocator.free(tempBuffer);
}

var random = std.rand.DefaultPrng.init(0);
var r: std.rand.Random = undefined;
pub fn gen_samples(numSamples: i32) []f32 {
    const numSamples2 = @intCast(usize, numSamples) * 2;
    if (samples.len < numSamples2) {
        samples = allocator.realloc(samples, numSamples2) catch unreachable;
        tempBuffer = allocator.realloc(tempBuffer, numSamples2) catch unreachable;
    }

    @memset(samples, 0.0);
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

    if (state.mp3) |*mp3| {
        var buffPos: usize = 0;

        const buff = tempBuffer;

        // pocketmod_render can render less samples than requested if at the end of the track
        while (buffPos < buff.len) {
            var frames_to_read = @min(music_end - state.mp3_current_sample, buff.len / 2);
            var subBuff = buff[buffPos..];

            const numChannels = @intCast(usize, mp3.channels);
            if (numChannels > 2) @panic("Too Many Channels");
            var read = c.drmp3_read_pcm_frames_f32(mp3, frames_to_read, subBuff.ptr);

            buffPos += @intCast(usize, read) * numChannels;
            // loop
            if (buffPos < buff.len) {
                state.seekMp3(0);
            }
        }
        mixScale(tempBuffer, samples, 0.25);
    }

    if (oggSupport) {
        if (state.ogg) |ogg| {
            var buffPos: usize = 0;

            const buff = tempBuffer;

            // pocketmod_render can render less samples than requested if at the end of the track
            while (buffPos < buff.len) {
                var subBuff = buff[buffPos..];

                var read = c.stb_vorbis_get_samples_float_interleaved(ogg, 2, subBuff.ptr, @intCast(c_int, subBuff.len));

                buffPos += @intCast(usize, read) * 2;
                // loop
                if (buffPos < buff.len) {
                    _ = c.stb_vorbis_seek_start(ogg);
                }
            }
            mix(tempBuffer, samples);
        }
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

pub fn mixScale(in: []f32, out: []f32, vol: f32) void {
    for (in, out) |sin, *sout| {
        sout.* += sin * vol;
    }
}

pub fn mixMono(in: []f32, out: []f32) void {
    for (in, 0..) |sin, i| {
        out[i * 2] += sin;
        out[i * 2 + 1] += sin;
    }
}
