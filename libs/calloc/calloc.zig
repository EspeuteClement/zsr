// from : https://gist.github.com/pfgithub/65c13d7dc889a4b2ba25131994be0d20
// Copyright 2021 pfg
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
// associated documentation files (the "Software"), to deal in the Software without restriction,
// including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
// subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or substantial
// portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
// NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
// IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
// SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

//! comptime {
//!     @import("calloc").wrapAllocator(struct {
//!         pub fn getAllocator() std.mem.Allocator {
//!             return …;
//!         }
//!     }).exportAs(.{
//!         .malloc = "zig_malloc",
//!         .calloc = "zig_calloc",
//!         .realloc = "zig_realloc",
//!         .free = "zig_free"}
//!     );
//! }

const std = @import("std");

const max_align_t = @cImport({
    @cInclude("stddef.h");
}).max_align_t;
const alignment = @alignOf(max_align_t);

pub fn wrapAllocator(comptime AllocMaker: type) type {
    return struct {
        var am: AllocMaker = .{};

        // if(releasefast)
        //    MagicType = void;
        //    MAGIC = {};
        //    NOMAGIC = {};

        const MAGIC = 0xABCDEF;
        const NOMAGIC = 0;
        const MagicType = usize;

        const MallocHeader = struct {
            magic: MagicType = MAGIC,
            size: usize,
            comptime {
                if (@alignOf(MallocHeader) > alignment) @compileError("oops");
            }
            const size_of_aligned = (std.math.divCeil(usize, @sizeOf(MallocHeader), alignment) catch @panic("Unaligned")) * alignment;
        };

        fn getHeader(ptr: [*]align(alignment) u8) *MallocHeader {
            const inptr = ptr - MallocHeader.size_of_aligned;
            return @ptrCast(*MallocHeader, inptr);
        }

        fn allocate(size: usize) ?[]align(alignment) u8 {
            const result = am.getAllocator().allocWithOptions(
                u8,
                MallocHeader.size_of_aligned + size,
                alignment,
                null,
            ) catch return null;

            const final = result[MallocHeader.size_of_aligned..];

            getHeader(final.ptr).* = .{
                .size = size,
            };

            return final;
        }

        /// allocates a *align(16) [size]u8. returns uninitialized memory.
        pub fn malloc(size: usize) callconv(.C) ?[*]align(alignment) u8 {
            const result = allocate(size) orelse return null;
            for (result) |*v| v.* = undefined;
            return result.ptr;
        }

        /// allocates a *align(16) [size * nmemb]u8. returns zero-initialized memory.
        pub fn calloc(length: usize, size: usize) callconv(.C) ?[*]align(alignment) u8 {
            std.log.info("calloc {d} {d}", .{ length, size });
            const result = allocate(length * size) orelse return null;
            for (result) |*v| v.* = 0;
            return result.ptr;
        }

        /// allocates a new *align(16) [size]u8 and copies the original data to the new one
        /// expanding or contracting the existing area pointed to by ptr, if possible.
        /// The contents of the area remain unchanged up to the lesser of the new and
        /// old sizes. If the area is expanded, the contents of the new part of the
        /// array are undefined.
        pub fn realloc(ptr_opt: ?[*]align(alignment) u8, size: usize) callconv(.C) ?[*]align(alignment) u8 {
            const ptr = ptr_opt orelse return null;

            const header = getHeader(ptr);
            if (header.magic != MAGIC) @panic("trying to realloc a non-malloc'd pointer | double free");

            const old = ptr[0..header.size];

            const new = allocate(size) orelse return null;

            const max_len = std.math.min(new.len, old.len);

            std.mem.copy(u8, new, old[0..max_len]);
            for (new[max_len..]) |*v| v.* = undefined;

            free(old.ptr);

            return new.ptr;
        }

        /// frees a pointer
        pub fn free(ptr_opt: ?[*]align(alignment) u8) callconv(.C) void {
            const ptr = ptr_opt orelse return;

            // check header
            const header = getHeader(ptr);
            if (header.magic != MAGIC) @panic("trying to free a non-malloc'd pointer | double free");
            header.magic = NOMAGIC; // prevent double free

            // get the original slice (subtract from the pointer and do something idk)
            const original = ptr - MallocHeader.size_of_aligned;
            const original_slice = original[0 .. MallocHeader.size_of_aligned + header.size];

            // free the original
            am.getAllocator().free(original_slice);
        }

        const ExportDesc = struct {
            malloc: ?[]const u8 = null,
            calloc: ?[]const u8 = null,
            realloc: ?[]const u8 = null,
            free: ?[]const u8 = null,
        };
        pub fn exportAs(comptime desc: ExportDesc) void {
            comptime {
                if (desc.malloc) |malloc_name| @export(malloc, .{ .name = malloc_name, .linkage = .Strong });
                if (desc.calloc) |calloc_name| @export(calloc, .{ .name = calloc_name, .linkage = .Strong });
                if (desc.realloc) |realloc_name| @export(realloc, .{ .name = realloc_name, .linkage = .Strong });
                if (desc.free) |free_name| @export(free, .{ .name = free_name, .linkage = .Strong });
            }
        }
    };
}

test "test" {
    const AllocMaker = struct {
        pub fn getAllocator(_: *@This()) std.mem.Allocator {
            return std.testing.allocator;
        }
    };
    const cator = wrapAllocator(AllocMaker);

    var five = cator.malloc(5) orelse @panic("oom");
    five = cator.realloc(five, 10) orelse {
        cator.free(five);
        @panic("realloc failed");
    };
    cator.free(five);

    var six = cator.calloc(6, 1) orelse @panic("oom");
    for (six[0..6], 0..) |*v, i| v.* = @intCast(u8, i);
    cator.free(six);

    const aligned = cator.malloc(@sizeOf(max_align_t)) orelse @panic("oom");

    // const aligned_v = @ptrCast(*max_align_t, aligned);
    // aligned_v.* = 10.0; // wow can't even float_init_bigfloat

    cator.free(aligned);
}
