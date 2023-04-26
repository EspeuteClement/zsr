const std = @import("std");

pub var allocator: std.mem.Allocator = undefined;
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
