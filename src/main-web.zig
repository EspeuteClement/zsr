const std = @import("std");
const sw = @import("softwareRenderer.zig");
const stbi = @import("stb_image.zig");

pub const std_options = struct {
    // Set the log level to info
    pub const log_level = .warn;
    // Define logFn to override the std implementation
    pub const logFn = myLogFn;
};

pub fn myLogFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    // Ignore all non-error logging from sources other than
    // .my_project, .nice_library and the default
    const scope_prefix = "(" ++ @tagName(scope) ++ ")";
    const prefix = "[" ++ comptime level.asText() ++ "] " ++ scope_prefix;
    // Print the message to stderr, silently ignoring any errors

    var buff: [2048]u8 = undefined;
    var printSlice = nosuspend std.fmt.bufPrint(&buff, prefix ++ format ++ "\n", args) catch return;
    print(printSlice);
}

const Imports = struct {
    pub extern fn print(ptr: i32, length: i32) void;
    pub extern fn draw(ptr: i32, lenght: i32) void;
    pub extern fn isKeyDown(idx: i32) i32;
};

pub fn print(str: []const u8) void {
    Imports.print(@intCast(i32, @ptrToInt(str.ptr)), @intCast(i32, str.len));
}

pub fn draw(i: sw.Image) void {
    var bytes = std.mem.sliceAsBytes(i.pixels);
    Imports.draw(@intCast(i32, @ptrToInt(bytes.ptr)), @intCast(i32, bytes.len));
}

const Key = enum {
    left,
    right,
    down,
    up,
};

pub fn is_key_down(key: Key) bool {
    return Imports.isKeyDown(@enumToInt(key)) != 0;
}

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator: std.mem.Allocator = undefined;

const windWidth = 256;
const windHeight = 256;

var img: sw.Image = undefined;
var ralsei: sw.Image = undefined;

pub export fn init() void {
    allocator = gpa.allocator();
    stbi.init(allocator);
    print("init");
    img = sw.Image.init(allocator, windWidth, windHeight) catch unreachable;
    ralsei = stbi.load_from_memory_to_Image(@embedFile("web/ben_shmark.png"), allocator) catch @panic("aaa");
}

var time: f32 = 0.0;

var ralsei_x: i32 = 0;
var ralsei_y: i32 = 0;

pub export fn step() void {
    {
        if (is_key_down(.left))
            ralsei_x -= 1;
        if (is_key_down(.right))
            ralsei_x += 1;
        if (is_key_down(.up))
            ralsei_y -= 1;
        if (is_key_down(.down))
            ralsei_y += 1;
    }

    time += 0.016;
    var c = @floatToInt(u8, (@sin(time) * 0.5 + 0.5) * 255.0);
    img.drawClear(.{ .r = c, .g = c, .b = c, .a = 255 });
    img.drawImageRect(ralsei_x, ralsei_y, ralsei, ralsei.getRect(), .{});

    draw(img);
}
