const c = @cImport({
    @cInclude("stb_image.h");
    @cInclude("stb_image_write.h");
});

const std = @import("std");
const sw = @import("softwareRenderer.zig");

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
    c.stbi_set_flip_vertically_on_load_thread(0);
    var img = try load_from_memory(buffer, &i.width, &i.height, &out_channels, 4);
    defer free(img.ptr);

    i.pixels = try _allocator.dupe(sw.Color, std.mem.bytesAsSlice(sw.Color, @alignCast(4, img)));

    return i;
}

pub inline fn load_to_Image(filename: []const u8, _allocator: std.mem.Allocator) !sw.Image {
    var data = try std.fs.cwd().readFileAlloc(_allocator, filename, std.math.maxInt(u32));
    defer _allocator.free(data);

    return load_from_memory_to_Image(data, _allocator);
}
