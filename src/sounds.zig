const std = @import("std");

pub const SoundList = struct {
    pub const @"test" = SoundDef{ .path = "web/sound.wav", .kind = .Wav };
    pub const jump = SoundDef{ .path = "web/jump.wav", .kind = .Wav };
    pub const land = SoundDef{ .path = "web/land.wav", .kind = .Wav };
    pub const death = SoundDef{ .path = "web/death.wav", .kind = .Wav };

    pub const music = SoundDef{ .path = "web/music.mp3", .kind = .Mp3 };
};

pub const SoundDef = struct {
    path: []const u8,
    kind: Kind,
    start: ?usize = null,
};

pub const Kind = enum {
    Wav,
    Mod,
    Mp3,
    Ogg,
};

pub const Sound = std.meta.DeclEnum(SoundList);
pub const defs: std.EnumArray(Sound, Kind) = brk: {
    var arr: std.EnumArray(Sound, Kind) = undefined;

    for (@typeInfo(SoundList).Struct.decls, &arr.values) |d, *a| {
        a.* = @field(SoundList, d.name).kind;
    }

    break :brk arr;
};
