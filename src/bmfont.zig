// const std = @import("std");
// const sw = @import("softwareRenderer.zig");
// const Image = sw.Image;
// const stbi = @import("stb_image.zig");

// const CharData = struct {
//     x: i32,
//     y: i32,
//     xoffset: i32,
//     yoffset: i32,
//     height: i32,
//     xadvance: i32,
//     page: i32,
// };

// pub fn load_font(path: []const u8, allocator: std.mem.Allocator) !void {
//     var data = try std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(u32));
//     defer allocator.free(data);

//     var ascii_map = try std.ArrayListUnmanaged(CharData).initCapacity(allocator, 256);
//     errdefer ascii_map.deinit(allocator);
//     var map_array = ascii_map.addManyAsArrayAssumeCapacity(256);

//     var images = std.ArrayListUnmanaged(Image){};
//     errdefer images.deinit(allocator);

//     var line_iter = std.mem.split(u8, data, "\n");
//     line_loop: while (line_iter.next()) |line| {

//         //std.debug.print("{s}\n", .{line});

//         if (std.mem.startsWith(u8, line, "info")) {} else if (std.mem.startsWith(u8, line, "common")) {} else if (std.mem.startsWith(u8, line, "page")) {
//             var word_iter = std.mem.split(u8, line, " ");
//             var page_path: ?[]u8 = null;

//             var subpath = std.fs.path.dirname(path) orelse ".";

//             var found_id: ?i32 = null;

//             while (word_iter.next()) |word| {
//                 if (std.mem.startsWith(u8, word, "id")) {
//                     var iter = std.mem.splitBackwards(u8, word, "=");
//                     found_id = std.fmt.parseInt(i32, iter.first(), 10) catch continue :line_loop;
//                 } else if (std.mem.startsWith(u8, word, "file")) {
//                     var iter = std.mem.splitBackwards(u8, word, "=");
//                     page_path = iter.first();
//                     page_path = std.mem.trimLeft(u8, page_path, "\"");
//                     page_path = std.mem.trimRight(u8, page_path, "\"");
//                 }
//             }

//             if (found_id) |id| {
//                 if (page_path) |p| {
//                     var join = std.fs.path.join(allocator, &[_][]const u8{ subpath, page_path });
//                     defer allocator.free(join);

//                     var img = try stbi.load_to_Image(join, allocator);
//                     _ = img;
//                     _ = id;
//                     _ = p;
//                     //images.ensureTotalCapacity
//                 }
//             }
//         } else if (std.mem.startsWith(u8, line, "char")) {
//             var char: CharData = undefined;
//             var found_id: ?i32 = null;

//             var word_iter = std.mem.split(u8, line, " ");
//             while (word_iter.next()) |word| {
//                 if (std.mem.startsWith(u8, word, "id")) {
//                     var iter = std.mem.splitBackwards(u8, word, "=");
//                     found_id = std.fmt.parseInt(i32, iter.first(), 10) catch continue :line_loop;
//                 }
//                 inline for (comptime std.meta.fieldNames(CharData)) |field| {
//                     if (std.mem.startsWith(u8, word, field)) {
//                         var iter = std.mem.splitBackwards(u8, word, "=");
//                         var value = std.fmt.parseInt(i32, iter.first(), 10) catch continue :line_loop;
//                         @field(char, field) = value;
//                     }
//                 }
//             }

//             if (found_id) |id| {
//                 if (id < 256 and id >= 0) {
//                     map_array[@intCast(usize, id)] = char;
//                     std.debug.print("id: {d} -> {}\n", .{ id, char });
//                 }
//             }
//         }
//     }

//     return .{
//         .ascii_map = ascii_map,
//     };
// }

// pub const Font = struct {
//     ascii_map: std.ArrayListUnmanaged(CharData),

//     fn deinit(self: *Font, allocator: std.mem.Allocator) void {
//         self.ascii_map.deinit(allocator);
//     }
// };

// // test load_font {
// //     try load_font("res/fonts/5x7.fnt", std.testing.allocator);
// // }
