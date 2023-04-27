const std = @import("std");

pub const SoundList = struct {
    pub const @"test" = SoundDef{.path = "web/sound.wav", .kind = .Wav};
	pub const jump = SoundDef{.path = "web/jump.wav", .kind = .Wav};
	pub const music = SoundDef{.path = "web/bananasplit.mod", .kind = .Mod};


	const SoundDef = struct {
		path : []const u8,
		kind : Kind,
	};

	const Kind = enum {
		Wav,
		Mod,
	};
};

pub const Sound = std.meta.DeclEnum(SoundList);
