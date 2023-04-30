const std = @import("std");
const sw = @import("softwareRenderer.zig");
const stbi = @import("stb_image.zig");
const Input = @import("input.zig").Input;
const Sound = @import("sounds.zig").Sound;
const options = @import("options");

img: sw.Image = undefined,
backbuffer: sw.Image = undefined,

//ralsei: sw.Image = undefined,
allocator: std.mem.Allocator = undefined,
input: Input = Input{},

state: State = undefined,

playSoundCb: ?*const fn (Sound) void = null,

fx_file_map: if (options.embed_structs) void else std.StringArrayHashMapUnmanaged(FXInfo) = if (options.embed_structs) undefined else .{},

const FXInfo = struct {
    last_edit_time: i128,
    data: *const anyopaque,
    original_data: *const anyopaque = undefined,
    data_size: usize,
    data_alignment_log2: u8,
};

pub const game_width = 240;
pub const game_height = 160;

const player_width = 8;
const player_jump_force = -3.0;
const player_max_speed = 6.0;
const gravity = 1.0;

const Self = @This();

const Foo = struct {
    bar: f32 = 0,
};

const State = struct {
    allocator: std.mem.Allocator,
    player_x: f32 = 24,
    player_y: f32 = game_height / 2,
    player_vy: f32 = 0,
    player_gravity: f32 = 1,

    game_over: bool = false,

    blocks: [Block.num_max]?Block = [_]?Block{null} ** Block.num_max,

    particles: std.ArrayListUnmanaged(Particle) = .{},

    fx_random: std.rand.Xoshiro256 = undefined,

    scr_shake_x: f32 = 0,
    scr_shake_y: f32 = 0,
    scr_offset_x: f32 = 0,
    scr_offset_y: f32 = 0,

    pub fn init(allocator: std.mem.Allocator) State {
        var st = State{
            .allocator = allocator,
        };
        st.fx_random = std.rand.Xoshiro256.init(0);
        return st;
    }

    pub fn deinit(self: *State) void {
        self.particles.deinit(self.allocator);
        self.* = undefined;
    }

    const Self = @This();

    const Particle = struct {
        x: f32 = 0,
        y: f32 = 0,
        w: f32 = 0,
        h: f32 = 0,

        vx: f32 = 0,
        vy: f32 = 0,
        vw: f32 = 0,
        vh: f32 = 0,

        ax: f32 = 0,
        ay: f32 = 0,
        damping: f32 = 0.95,

        lifetime: f32 = 0,
    };

    const ParticleParams = struct {
        ox: f32 = 0,
        oy: f32 = 0,
        count: usize = 0,
        lifetime: f32 = 1.0,
        start_angle: f32 = 0,
        size: f32 = 4,
        random_size: f32 = 2,
        vx: f32 = 0,
        vy: f32 = 0,
        vw: f32 = 0,
        vh: f32 = 0,
        ax: f32 = 0,
        ay: f32 = 0,
        initial_speed: f32 = 0,
        random_speed: f32 = 0,
        random_angle: f32 = 0,
        acceleration: f32 = 0,
        random_acceleration: f32 = 0,
        damping: f32 = 1.0,
    };

    pub fn particleBurst(self: *State, params: ParticleParams) void {
        self.particles.ensureUnusedCapacity(self.allocator, params.count) catch return;

        for (0..params.count) |i| {
            var part = self.particles.addOneAssumeCapacity();
            const angle = @intToFloat(f32, i) + params.start_angle + (self.fx_random.random().float(f32) * 2.0 - 1.0) * params.random_angle;
            const angle2 = self.fx_random.random().float(f32) * std.math.tau;
            const ra = self.fx_random.random().float(f32) * 0.005;
            const rs = (self.fx_random.random().float(f32) * 2.0 - 1.0) * params.random_speed;
            const rsize = self.fx_random.random().float(f32) * params.random_size;
            part.* = .{
                .x = params.ox,
                .y = params.oy,
                .w = params.size + rsize,
                .h = params.size + rsize,
                .vw = params.vw,
                .vh = params.vh,
                .vx = params.vx + @cos(angle) * (params.initial_speed + rs),
                .vy = params.vy + @sin(angle) * (params.initial_speed + rs),
                .ax = params.ax + @cos(angle2) * ra,
                .ay = params.ay + @sin(angle2) * ra,
                .lifetime = params.lifetime,
                .damping = params.damping,
            };
            if (std.math.isNan(part.vx))
                @breakpoint();
        }
    }

    pub fn stepParticles(self: *State) void {
        const len = self.particles.items.len;
        for (0..len) |i| {
            const idx = len - 1 - i;
            const part = &self.particles.items[idx];
            part.vx = part.vx * part.damping + part.ax;
            part.vy = part.vy * part.damping + part.ay;
            part.x += part.vx;
            if (std.math.isNan(part.x))
                @breakpoint();
            part.y += part.vy;
            part.w = @max(0.0, part.w + part.vw);
            part.h = @max(0.0, part.h + part.vh);

            part.lifetime -= 1.0 / 60.0;

            if (part.lifetime < 0.0) {
                _ = self.particles.swapRemove(idx);
            }
        }
    }

    pub fn drawParticles(self: *State, img: *sw.Image) void {
        for (self.particles.items) |part| {
            var x = @floatToInt(i32, part.x - part.w / 2);
            var y = @floatToInt(i32, part.y - part.h / 2);

            img.drawRect(x, y, @floatToInt(i32, part.w), @floatToInt(i32, part.h), sw.Color.fromRGB(0xFFFFFF));
        }
    }
};

const Block = struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,

    vx: f32 = 0,
    vy: f32 = 0,

    const num_max = 128;
};

pub fn init(alloc: std.mem.Allocator, playSoundCB: ?*const fn (Sound) void) !Self {
    var game: Self = .{};

    game.allocator = alloc;
    game.playSoundCb = playSoundCB;
    game.img = try sw.Image.init(alloc, game_width, game_height);
    errdefer game.img.deinit(alloc);

    game.backbuffer = try sw.Image.init(alloc, game_width, game_height);
    errdefer .backbuffer.deinit(alloc);

    //game.ralsei = try stbi.load_from_memory_to_Image(@embedFile("web/ben_shmark.png"), alloc);
    //errdefer game.img.deinit(alloc);

    //game.playSound(.music);
    game.reset();

    return game;
}

pub fn reset(self: *Self) void {
    self.state = State.init(self.allocator);
    const s = &self.state;

    s.blocks[0] = .{
        .x = 0,
        .y = game_height - 16,
        .h = 32,
        .w = game_width * 10,
        .vx = -1.0,
        .vy = 0.0,
    };

    s.blocks[1] = .{
        .x = 0,
        .y = -16,
        .h = 32,
        .w = game_width * 10,
        .vx = -1.0,
        .vy = 0.0,
    };

    s.blocks[2] = .{
        .x = 100,
        .y = game_height - 32,
        .h = 32,
        .w = 32,
        .vx = -1.0,
        .vy = 0.0,
    };
}

pub fn deinit(self: *Self) void {
    self.img.deinit(self.allocator);
    self.backbuffer.deinit(self.allocator);
    self.state.deinit();
    if (comptime !options.embed_structs) {
        var it = self.fx_file_map.iterator();
        while (it.next()) |kv| {
            if (kv.value_ptr.original_data != kv.value_ptr.data) {
                const non_const_ptr = @ptrCast([*]u8, @constCast(kv.value_ptr.data));

                // Because we can't recosntrucuct the type at runtime, we call RawFree with the relevant information
                self.allocator.rawFree(non_const_ptr[0..kv.value_ptr.data_size], kv.value_ptr.data_alignment_log2, @returnAddress());
            }
        }

        self.fx_file_map.deinit(self.allocator);
    }
    //self.ralsei.deinit(self.allocator);
}

pub fn playSound(self: *Self, snd: Sound) void {
    if (self.playSoundCb) |cb| {
        cb(snd);
    } else {
        @panic("play sound not registered");
    }
}

fn aabb(x0: f32, y0: f32, w0: f32, h0: f32, x1: f32, y1: f32, w1: f32, h1: f32) bool {
    return !(x0 + w0 < x1 or
        x0 > x1 + w1 or
        y0 + h0 < y1 or
        y0 > y1 + h1);
}

pub fn lerp(start: u8, end: u8, numerator: u8, denominator: u8) u8 {
    const int = @as(i16, start) + @divFloor(@as(i16, @as(i9, end) - @as(i9, start)) * @as(i16, numerator), denominator);
    return @intCast(u8, std.math.clamp(int, 0, 255));
}

pub fn decay(val: anytype, rate: anytype, min: anytype) @TypeOf(val) {
    var v = val * rate;
    if (v > -min and v < min) {
        v = 0.0;
    }
    return v;
}

pub fn absmax(a: anytype, b: anytype) @TypeOf(a, b) {
    if (@fabs(a) > @fabs(b)) {
        return a;
    }
    return b;
}

pub fn loadFXComptime(comptime path: []const u8, comptime T: type) T {
    comptime {
        var s = std.json.TokenStream.init(@embedFile(path));
        const res = std.json.parse(T, &s, .{ .allow_trailing_data = true }) catch @compileError("Couldn't parse FX of type " ++ T ++ " from " ++ path);
        return res;
    }
}

inline fn ptrCast(comptime T: type, ptr: *anyopaque) T {
    return @ptrCast(T, @alignCast(@alignOf(@typeInfo(T).Pointer.child), ptr));
}

inline fn constPtrCast(comptime T: type, ptr: *const anyopaque) T {
    return @ptrCast(T, @alignCast(@alignOf(@typeInfo(T).Pointer.child), ptr));
}

pub fn loadFX(self: *Self, comptime path: []const u8, comptime T: type) struct { was_reloaded: bool, fx: T } {
    @setEvalBranchQuota(20_000);

    if (comptime options.embed_structs) {
        return .{ .was_reloaded = false, .fx = comptime loadFXComptime(path, T) };
    } else {
        var info = self.fx_file_map.getOrPut(self.allocator, path) catch unreachable;
        if (!info.found_existing) {
            info.value_ptr.* = .{
                .last_edit_time = 0,
                .data = &(comptime loadFXComptime(path, T)),
                .data_size = @sizeOf(T),
                .data_alignment_log2 = std.math.log2(@alignOf(T)),
            };
            info.value_ptr.original_data = info.value_ptr.data;
        }
        var fx: **const anyopaque = &info.value_ptr.data;
        var defreturn: T = constPtrCast(*const T, fx.*).*;
        var buff: [512]u8 = undefined;
        var full_path = std.fmt.bufPrintZ(&buff, "{s}{s}", .{ options.src_path, path }) catch return .{ .was_reloaded = false, .fx = defreturn };
        var file = std.fs.openFileAbsoluteZ(full_path, .{}) catch return .{ .was_reloaded = false, .fx = defreturn };
        defer file.close();

        var stat = file.stat() catch return .{ .was_reloaded = false, .fx = defreturn };

        if (stat.mtime <= info.value_ptr.last_edit_time)
            return .{ .was_reloaded = false, .fx = defreturn };

        var data = file.readToEndAlloc(self.allocator, 100_000) catch return .{ .was_reloaded = false, .fx = defreturn };
        defer self.allocator.free(data);

        var s = std.json.TokenStream.init(data);

        var oldptr = constPtrCast(*const T, fx.*);
        fx.* = brk: {
            var res = self.allocator.create(T) catch return .{ .was_reloaded = false, .fx = defreturn };
            errdefer self.allocator.destroy(res);
            res.* = std.json.parse(T, &s, .{ .allow_trailing_data = true }) catch return .{ .was_reloaded = false, .fx = defreturn };
            break :brk res;
        };
        info.value_ptr.last_edit_time = stat.mtime;
        if (constPtrCast(*const T, info.value_ptr.original_data) != oldptr) {
            self.allocator.destroy(oldptr);
        }
        return .{ .was_reloaded = true, .fx = constPtrCast(*const T, fx.*).* };
    }
}

pub fn step(self: *Self) !void {
    var s = &self.state;

    if (comptime !options.embed_structs) {
        if (self.loadFX("res/part.json", State.ParticleParams).was_reloaded) {
            s.deinit();
            self.reset();
        }
    }

    if (self.input.is_just_pressed(.start)) {
        s.deinit();
        self.reset();
    }

    //s = &self.state;

    for (&s.blocks) |*block_null| {
        var block = &(block_null.* orelse continue);
        const collide_before = aabb(s.player_x - player_width / 2, s.player_y - player_width / 2, player_width, player_width, block.x, block.y, block.w, block.h);
        block.x += block.vx;

        if (!s.game_over and !collide_before) {
            const collide_after = aabb(s.player_x - player_width / 2, s.player_y - player_width / 2, player_width, player_width, block.x, block.y, block.w, block.h);
            if (collide_after) {
                s.game_over = true;
                std.log.info("Game over", .{});
                var fx = self.loadFX("res/part.json", State.ParticleParams).fx;
                fx.ox = s.player_x;
                fx.oy = s.player_y;

                s.particleBurst(fx);
                s.scr_shake_x = 5;
                s.scr_shake_y = 5;
            }
        }

        block.y += block.vy;
    }

    if (!s.game_over) {
        if (self.input.is_just_pressed(.a)) {
            self.playSound(.jump);
            s.player_gravity *= -1.0;
        }

        var prev_v = s.player_vy;
        s.player_vy += gravity * s.player_gravity;
        s.player_vy = std.math.clamp(s.player_vy, -player_max_speed, player_max_speed);
        var next_y = s.player_y + s.player_vy;

        for (&s.blocks) |*block_null| {
            var block = &(block_null.* orelse continue);

            if (s.player_x < block.x - player_width / 2 or s.player_x > block.x + block.w + player_width / 2) {
                continue;
            }

            var grounded = false;
            {
                const h = block.y - player_width / 2;
                if (s.player_y <= h and next_y > h) {
                    next_y = h;
                    grounded = true;
                }
            }

            {
                const h = block.y + block.h + player_width / 2;
                if (s.player_y >= h and next_y < h) {
                    next_y = h;
                    grounded = true;
                    s.scr_shake_x = absmax(s.scr_shake_x, std.math.fabs(prev_v) * 0.25);
                    s.scr_offset_y = absmax(s.scr_offset_y, -prev_v * 0.25);
                    s.player_vy = 0;
                }
            }

            if (grounded) {
                s.scr_shake_x = absmax(s.scr_shake_x, std.math.fabs(prev_v) * 0.25);
                s.scr_offset_y = absmax(s.scr_offset_y, -prev_v * 0.25);
                s.player_vy = 0;
                s.particleBurst(.{
                    .ox = s.player_x - player_width / 2,
                    .oy = s.player_y + (player_width / 2 * s.player_gravity),
                    .count = 1,
                    .lifetime = 1.0,
                    .initial_speed = 1.0,
                    .vw = -0.1,
                    .vh = -0.1 * s.player_gravity,
                    .size = 2,
                    .start_angle = std.math.pi * (1.0 + s.player_gravity * 0.1),
                    .random_angle = 0.2,
                });
            }
        }

        s.player_y = next_y;
    }

    s.scr_shake_x = decay(s.scr_shake_x, 0.80, 0.1);
    s.scr_shake_y = decay(s.scr_shake_y, 0.80, 0.1);
    s.scr_offset_x = decay(s.scr_offset_x, 0.80, 0.1);
    s.scr_offset_y = decay(s.scr_offset_y, 0.80, 0.1);

    s.stepParticles();

    // DRAW

    self.img.camera_x = 0;
    self.img.camera_y = 0;

    std.mem.copy(sw.Color, self.backbuffer.pixels, self.img.pixels);

    self.img.drawClear(sw.Color.fromRGB(0xFF00FF));

    self.img.camera_x = @floatToInt(i32, s.scr_offset_x + s.scr_shake_x * std.math.clamp(s.fx_random.random().float(f32) * 2.0 - 1.0, -1.0, 1.0));
    self.img.camera_y = @floatToInt(i32, s.scr_offset_y + s.scr_shake_y * std.math.clamp(s.fx_random.random().float(f32) * 2.0 - 1.0, -1.0, 1.0));

    for (self.img.pixels, self.backbuffer.pixels) |*p, *b| {
        p.r = lerp(p.r, b.r, 3, 4);
        p.g = lerp(p.g, b.g, 3, 4);
        p.b = lerp(p.b, b.b, 3, 4);
    }

    for (s.blocks) |block_null| {
        var block = block_null orelse continue;
        self.img.drawRect(@floatToInt(i32, block.x), @floatToInt(i32, block.y), @floatToInt(i32, block.w), @floatToInt(i32, block.h), sw.Color.fromRGB(0x00FFFF));
    }

    s.drawParticles(&self.img);

    if (!s.game_over) {
        var x = @floatToInt(i32, s.player_x - player_width / 2);
        var y = @floatToInt(i32, s.player_y - player_width / 2);

        self.img.drawRect(x, y, player_width, player_width, sw.Color.fromRGB(0xFFFFFF));
    }

    //self.img.drawImageRect(self.ralsei_x, self.ralsei_y, self.ralsei, self.ralsei.getRect(), .{});
}
