const std = @import("std");

pub const SoundList = struct {
    pub const @"test" = "web/sound.wav";
};

pub const Sound = std.meta.DeclEnum(SoundList);
