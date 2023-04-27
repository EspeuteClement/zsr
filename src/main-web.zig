const std = @import("std");
const sw = @import("softwareRenderer.zig");
const input = @import("input.zig");
const game = @import("game.zig");
const callocators = @import("callocators.zig");
const Sound = @import("sounds.zig").Sound;

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
	pub extern fn playSound(id : i32) void;
};

pub fn print(str: []const u8) void {
    Imports.print(@intCast(i32, @ptrToInt(str.ptr)), @intCast(i32, str.len));
}

pub fn draw(i: sw.Image) void {
    var bytes = std.mem.sliceAsBytes(i.pixels);
    Imports.draw(@intCast(i32, @ptrToInt(bytes.ptr)), @intCast(i32, bytes.len));
}

pub fn is_key_down(key: i32) bool {
    return Imports.isKeyDown(key) != 0;
}

pub fn playSoundCb(sound:Sound) void {
	Imports.playSound(@enumToInt(sound));
}

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator: std.mem.Allocator = undefined;

pub export fn init() void {
    allocator = gpa.allocator();
    callocators.allocator = allocator;
	game.playSoundCb = playSoundCb;
    game.init(allocator);
}

var time: f32 = 0.0;

var ralsei_x: i32 = 0;
var ralsei_y: i32 = 0;

pub export fn step() void {
    game.input.new_input_frame();
    inline for (@typeInfo(input.VirtualButton).Enum.fields) |i| {
        game.input.set_input(@intToEnum(input.VirtualButton, i.value), is_key_down(i.value));
    }

    game.step();

    draw(game.img);
}
