const c = @cImport({
    @cInclude("stb_image.h");
    @cInclude("stb_image_write.h");
});

const std = @import("std");
const sw = @import("softwareRenderer.zig");

var arena: std.heap.ArenaAllocator = undefined;
var allocator: std.mem.Allocator = undefined;

const alignment = 16;
const padded_metadata_size = std.mem.alignForward(@sizeOf(Metadata), alignment);
const Metadata = struct {
    size: usize,

    fn fullLen(data: Metadata) usize {
        return padded_metadata_size + data.size;
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

pub fn init(_allocator: std.mem.Allocator) void {
    arena = std.heap.ArenaAllocator.init(_allocator);
    allocator = arena.allocator();
}

pub inline fn load_from_memory(buffer: []const u8, out_x: *i32, out_y: *i32, out_channels: *i32, desierd_channels: usize) ![]u8 {
    var data = c.stbi_load_from_memory(buffer.ptr, @intCast(c_int, buffer.len), @ptrCast(*i32, out_x), @ptrCast(*i32, out_y), @ptrCast(*c_int, out_channels), @as(c_int, desierd_channels)) orelse return error.STBIError;
    return data[0..@intCast(usize, out_x.* * out_y.* * out_channels.*)];
}

pub inline fn free(image: *anyopaque) void {
    c.stbi_image_free(image);
}

pub inline fn write_png(filename: []const u8, width: i32, height: i32, components: i32, data: *anyopaque, stride_in_bytes: i32) !void {
    var res = c.stbi_write_png(filename.ptr, @as(c_int, width), @as(c_int, height), @as(c_int, components), data, @as(c_int, stride_in_bytes));
    if (res == 0) return error.WriteFail;
    return;
}

pub inline fn load_from_memory_to_Image(buffer: []const u8, _allocator: std.mem.Allocator) !sw.Image {
    var i: sw.Image = undefined;
    var out_channels: i32 = undefined;
    var img = try load_from_memory(buffer, &i.width, &i.height, &out_channels, 4);
    //defer _ = arena.reset(.retain_capacity);
    defer free(img.ptr);

    i.pixels = try _allocator.dupe(sw.Color, std.mem.bytesAsSlice(sw.Color, @alignCast(4, img)));

    return i;
}

pub inline fn load_to_Image(filename: []const u8, _allocator: std.mem.Allocator) !sw.Image {
    var data = try std.fs.cwd().readFileAlloc(allocator, filename, std.math.maxInt(u32));
    defer _allocator.free(data);

    return load_from_memory_to_Image(data, _allocator);
}
