const std = @import("std");

pub const List = struct {
    pub const part = Def{ .path = "res/part.json" };
    pub const blocks = Def{ .path = "res/blocks.tmj" };
};

pub const Def = struct {
    path: []const u8,
};

pub const Resource = std.meta.DeclEnum(List);

pub const defs: std.EnumArray(Resource, Def) = brk: {
    var arr: std.EnumArray(Resource, Def) = undefined;

    for (@typeInfo(List).Struct.decls, &arr.values) |d, *a| {
        a.* = @field(List, d.name);
    }

    break :brk arr;
};

pub const data: std.EnumArray(Resource, []const u8) = brk: {
    var arr: std.EnumArray(Resource, []const u8) = undefined;

    for (defs.values, &arr.values) |d, *a| {
        a.* = @embedFile(d.path);
    }

    break :brk arr;
};
