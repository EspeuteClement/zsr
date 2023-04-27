const std = @import("std");

pub const SoundList = struct {
    pub const @"test" = SoundDef{ .path = "web/sound.wav", .kind = .Wav };
    pub const jump = SoundDef{ .path = "web/jump.wav", .kind = .Wav };
    pub const music = SoundDef{ .path = "web/bananasplit.mod", .kind = .Mod };
};

pub const SoundDef = struct {
    path: []const u8,
    kind: Kind,
};

pub const Kind = enum {
    Wav,
    Mod,
};

pub const Sound = std.meta.DeclEnum(SoundList);
pub const defs: std.EnumArray(Sound, Kind) = brk: {
    var arr: std.EnumArray(Sound, Kind) = undefined;

    for (@typeInfo(SoundList).Struct.decls, &arr.values) |d, *a| {
        a.* = @field(SoundList, d.name).kind;
    }

    break :brk arr;
};
