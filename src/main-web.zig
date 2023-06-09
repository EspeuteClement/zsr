const std = @import("std");
const sw = @import("softwareRenderer.zig");
const input = @import("input.zig");
const Game = @import("game.zig");
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
    pub extern fn playSound(id: i32) void;
};

pub fn print(str: []const u8) void {
    Imports.print(@intCast(i32, @ptrToInt(str.ptr)), @intCast(i32, str.len));
}

pub fn draw(i: sw.Surface) void {
    var bytes = std.mem.sliceAsBytes(i.texture.pixels);
    Imports.draw(@intCast(i32, @ptrToInt(bytes.ptr)), @intCast(i32, bytes.len));
}

pub fn is_key_down(key: i32) bool {
    return Imports.isKeyDown(key) != 0;
}

pub fn playSoundCb(sound: Sound) void {
    Imports.playSound(@enumToInt(sound));
}

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator: std.mem.Allocator = undefined;

var game: Game = undefined;

pub export fn init(seed: i32) void {
    allocator = gpa.allocator();
    callocators.allocator = allocator;
    game = Game.init(allocator, playSoundCb, @bitCast(u64, @as(i64, seed))) catch unreachable;
    game.input.new_input_frame();
}

var time: f64 = 0.0;
var accumulator: f64 = 0;
var _error: f64 = 0;

pub export fn step(time2: f64) void {
    var delta = time2 - time;
    delta = @min(delta, 4.0 / 60.0 * 1000_0);
    time = time2;

    var deltaS = delta / 1_000.0;

    const timeEpsilon = 0.0009;

    if (std.math.fabs(deltaS - 1.0 / 60.0) < timeEpsilon) {
        _error += deltaS - 1.0 / 60.0;
        deltaS = 1.0 / 60.0;
    } else if (std.math.fabs(deltaS - 1.0 / 30.0) < timeEpsilon) {
        _error += deltaS - 1.0 / 30.0;
        deltaS = 1.0 / 30.0;
    } else {
        //std.log.warn("Delta ouside of epsilon : {d:0<6.4}. Accumulator : {d:0<6.4}", .{ deltaS, accumulator });
    }
    //std.log.info("Error is : {d:0<4.4}ms. Accumulator : {d:0<6.4}ms. ", .{ _error * 1000.0, accumulator * 1000.0 });

    accumulator += deltaS;

    var updatesThisLoop: u32 = 0;

    inline for (@typeInfo(input.VirtualButton).Enum.fields) |i| {
        game.input.accumulate_input(@intToEnum(input.VirtualButton, i.value), is_key_down(i.value));
    }

    const target_delta = 1.0 / 60.0;
    // Stable 60fps loop
    while (accumulator >= target_delta) {
        if (std.math.fabs(_error) > target_delta) {
            std.log.warn("Error too big, skipping a frame : {d:0<4.4}", .{_error});
            _error -= std.math.sign(_error) * target_delta;
        } else {
            game.step() catch unreachable;
            draw(game.img);
        }

        game.input.new_input_frame();

        updatesThisLoop += 1;

        accumulator -= target_delta;
    }
}
