const std = @import("std");
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
var data = @embedFile("web/bananasplit.mod");
var data_wav = @embedFile("web/sound.wav");
var dr_wav: c.drwav = undefined;
var soundPlayed: bool = true;

const alignment = 16;
const padded_metadata_size = std.mem.alignForward(@sizeOf(Metadata), alignment);
const Metadata = struct {
    size: usize,

    fn fullLen(_data: Metadata) usize {
        return padded_metadata_size + _data.size;
    }
};

export fn zig_malloc(size: usize) ?[*]align(alignment) u8 {
    const metadata = Metadata{
        .size = size,
    };
    const full_alloc = allocator.alignedAlloc(u8, alignment, metadata.fullLen()) catch return null;
    std.mem.bytesAsValue(Metadata, full_alloc[0..@sizeOf(Metadata)]).* = metadata;
    return full_alloc[padded_metadata_size..].ptr;
}

export fn zig_realloc(maybe_ptr: ?[*]align(alignment) u8, new_size: usize) ?[*]align(alignment) u8 {
    const ptr = maybe_ptr orelse return @call(.always_inline, zig_malloc, .{new_size});
    const old_ptr = ptr - padded_metadata_size;
    const old_metadata = std.mem.bytesToValue(Metadata, old_ptr[0..@sizeOf(Metadata)]);
    const new_metadata = Metadata{
        .size = new_size,
    };
    const new_slice = allocator.realloc(old_ptr[0..old_metadata.fullLen()], new_metadata.fullLen()) catch
        return null;
    std.mem.bytesAsValue(Metadata, new_slice[0..@sizeOf(Metadata)]).* = new_metadata;
    return new_slice[padded_metadata_size..].ptr;
}

export fn zig_free(maybe_ptr: ?[*]align(alignment) u8) void {
    const ptr = maybe_ptr orelse return;
    const real_ptr = ptr - padded_metadata_size;
    const metadata = std.mem.bytesToValue(Metadata, real_ptr[0..@sizeOf(Metadata)]);
    allocator.free(real_ptr[0..metadata.fullLen()]);
}

const drwavalloc: c.drwav_allocation_callbacks = .{
    .pUserData = null,
    .onMalloc = null,
    .onRealloc = null,
    .onFree = null,
};

pub export fn init(rate: i32) void {
    allocator = gpa.allocator();

    samples = allocator.alloc(f32, 128 * 2) catch unreachable;
    tempBuffer = allocator.alloc(f32, 128 * 2) catch unreachable;

    {
        var res = c.pocketmod_init(&pocketmod, data, data.len, @intCast(c_int, rate));
        if (res == 0) @panic("couldn't init");
    }

    {
        var res = c.drwav_init_memory(&dr_wav, data_wav, data_wav.len, null);
        if (res == 0) @panic("couldn't init dr_wav");
    }
}

pub export fn gen_samples(numSamples: i32) i32 {
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

    if (soundPlayed) {
        const numChannels = dr_wav.channels;
        if (numChannels > 2) @panic("Too Many Channels");
        const len = numSamples * numChannels;
        var read = @intCast(usize, c.drwav_read_pcm_frames_f32(&dr_wav, @intCast(usize, len), tempBuffer.ptr));

        if (read < len) {
            soundPlayed = false;
        }
        if (numChannels == 1) {
            mixMono(tempBuffer[0..read], samples[0 .. read * 2]);
        } else {
            mix(tempBuffer[0..read], samples[0..read]);
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
