const std = @import("std");
const sw = @import("softwareRenderer.zig");
const stbi = @import("stb_image.zig");
const Input = @import("input.zig").Input;
const Sound = @import("sounds.zig").Sound;
const res = @import("resources.zig");
const options = @import("options");

img: sw.Image = undefined,
backbuffer: sw.Image = undefined,

//ralsei: sw.Image = undefined,
sprite: sw.Image = undefined,
allocator: std.mem.Allocator = undefined,
input: Input = Input{},

state: State = undefined,
global_frames: u128 = undefined,

playSoundCb: ?*const fn (Sound) void = null,

resource_cache: std.EnumArray(res.Resource, ?ResourceInfo) = std.EnumArray(res.Resource, ?ResourceInfo).initFill(null),
resource_allocator: std.mem.Allocator = undefined,

const ResourceInfo = struct {
    last_edit_time: i128,
    data: *const anyopaque,
    cleanup_func: *const fn (self2: *Self, info: *ResourceInfo) void,

    const Tag = enum {
        static,
        dynamic,
    };
    const OriginalData = union(Tag) {
        static: *const anyopaque,
        dynamic: std.mem.Allocator,
    };
};

pub const game_width = 240;
pub const game_height = 160;

const player_width = 8;
const player_jump_force = -3.0;
const player_max_speed = 4.0;
const gravity = 1.0;

const Self = @This();

const Foo = struct {
    bar: f32 = 0,
};

const Tiled = struct {
    layers: []const Layer,

    const Layer = struct {
        name: []const u8,
        objects: []const Object,

        const Object = struct {
            height: i32,
            width: i32,
            visible: bool,
            x: i32,
            y: i32,

            pub fn toBlock(self: @This(), offset_x: f32) Block {
                return .{
                    .x = @intToFloat(f32, self.x) + offset_x,
                    .y = @intToFloat(f32, self.y),
                    .w = @intToFloat(f32, self.width),
                    .h = @intToFloat(f32, self.height),
                };
            }
        };
    };
};

const State = struct {
    allocator: std.mem.Allocator,
    player_x: f32 = 24,
    player_y: f32 = game_height / 2,
    player_vy: f32 = 0,
    player_gravity: f32 = 1,
    player_can_jump: bool = false,

    speed: f32 = -3.0,

    game_over: bool = false,

    blocks: std.ArrayListUnmanaged(Block) = .{},

    particles: std.ArrayListUnmanaged(Particle) = .{},

    fx_random: std.rand.Xoshiro256 = undefined,
    game_random: std.rand.Xoshiro256 = undefined,

    scr_shake_x: f32 = 0,
    scr_shake_y: f32 = 0,
    scr_offset_x: f32 = 0,
    scr_offset_y: f32 = 0,

    pub fn init(allocator: std.mem.Allocator, seed: u64) State {
        var st = State{
            .allocator = allocator,
        };
        st.fx_random = std.rand.Xoshiro256.init(seed);
        st.game_random = std.rand.Xoshiro256.init(seed);
        return st;
    }

    pub fn deinit(self: *State) void {
        self.particles.deinit(self.allocator);
        self.blocks.deinit(self.allocator);
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

pub fn init(alloc: std.mem.Allocator, playSoundCB: ?*const fn (Sound) void, seed: u64) !Self {
    var game: Self = .{};

    game.sprite = sw.Image.init(alloc, 16, 16) catch unreachable;
    for (game.sprite.pixels, 0..) |*p, i| {
        const x: u8 = (@intCast(u8, i) % 16) * 16;
        const y: u8 = @divTrunc(@intCast(u8, i), 16) * 16;
        const c = x ^ y;
        p.* = .{ .r = c, .g = c, .b = c, .a = 255 };
    }
    game.global_frames = seed;
    game.allocator = alloc;
    game.playSoundCb = playSoundCB;
    game.img = try sw.Image.init(alloc, game_width, game_height);
    errdefer game.img.deinit(alloc);

    game.backbuffer = try sw.Image.init(alloc, game_width, game_height);
    errdefer .backbuffer.deinit(alloc);

    game.resource_allocator = game.allocator;

    _ = game.loadJsonResourceAllocate(.blocks, Tiled);

    //game.ralsei = try stbi.load_from_memory_to_Image(@embedFile("web/ben_shmark.png"), alloc);
    //errdefer game.img.deinit(alloc);

    //game.playSound(.music);
    game.reset();

    return game;
}

pub fn reset(self: *Self) void {
    self.state = State.init(self.allocator, @truncate(u64, self.global_frames));

    self.spawnBlocks(self.getNumBlocks(), 0.0);

    // Always spawn the first pattern as a preview when in debug mode
    if (comptime !options.embed_structs) {
        self.spawnBlocks(0, game_width + 16);
    }
}

pub fn deinit(self: *Self) void {
    self.img.deinit(self.allocator);
    self.backbuffer.deinit(self.allocator);
    self.state.deinit();
    {
        for (&self.resource_cache.values) |*info_or_null| {
            var info = &(info_or_null.* orelse continue);

            info.cleanup_func(self, info);
            info_or_null.* = null;
        }
    }
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

inline fn ptrCast(comptime T: type, ptr: *anyopaque) T {
    return @ptrCast(T, @alignCast(@alignOf(@typeInfo(T).Pointer.child), ptr));
}

inline fn constPtrCast(comptime T: type, ptr: *const anyopaque) T {
    return @ptrCast(T, @alignCast(@alignOf(@typeInfo(T).Pointer.child), ptr));
}

pub fn loadJsonResourceComptime(comptime res_id: res.Resource, comptime T: type) T {
    @setEvalBranchQuota(20_000);

    comptime {
        const path = res.defs.get(res_id).path;
        var json_stream = std.json.TokenStream.init(@embedFile(path));

        const resource = std.json.parse(T, &json_stream, .{ .allow_trailing_data = true }) catch @compileError("Couldn't parse FX of type " ++ T ++ " from " ++ path);
        return resource;
    }
}

pub fn loadJsonResourceAllocate(self: *Self, res_id: res.Resource, comptime T: type) LoadJsonResult(T) {
    @setEvalBranchQuota(20_000);

    const parse_json_params = std.json.ParseOptions{
        .allocator = self.resource_allocator,
        .allow_trailing_data = true,
        .ignore_unknown_fields = true,
    };

    const path = res.defs.get(res_id).path;

    var res_info_or_null = self.resource_cache.getPtr(res_id);
    if (res_info_or_null.* == null) {
        const CleanupCtx = struct {
            pub fn cleanup(self2: *Self, info: *ResourceInfo) void {
                const parse_json_params2 = std.json.ParseOptions{
                    .allocator = self2.resource_allocator,
                    .allow_trailing_data = true,
                    .ignore_unknown_fields = true,
                };

                const non_const_typed_ptr = ptrCast(*T, @constCast(info.data));
                std.json.parseFree(T, non_const_typed_ptr.*, parse_json_params2);
                self2.allocator.destroy(non_const_typed_ptr);
            }
        };

        var json_stream = std.json.TokenStream.init(res.data.get(res_id));

        // note : we panic here because it means we couldn't load data bundled with the binary which is an error
        const data = self.allocator.create(T) catch @panic("OOM");
        data.* = std.json.parse(T, &json_stream, parse_json_params) catch @panic("Parse error");
        res_info_or_null.* = .{
            .last_edit_time = 0,
            .data = data,
            .cleanup_func = CleanupCtx.cleanup,
        };
    }
    const res_info = &(res_info_or_null.*.?);

    const fx = &res_info.data;
    const defreturn = constPtrCast(*const T, fx.*).*;

    if (comptime options.embed_structs) {
        return .{ .was_reloaded = false, .fx = defreturn };
    } else {
        var file = brk: {
            var buff: [512]u8 = undefined;
            var full_path = std.fmt.bufPrintZ(&buff, "{s}{s}", .{ options.src_path, path }) catch return .{ .was_reloaded = false, .fx = defreturn };
            break :brk std.fs.openFileAbsoluteZ(full_path, .{}) catch return .{ .was_reloaded = false, .fx = defreturn };
        };
        defer file.close();

        const stat = file.stat() catch return .{ .was_reloaded = false, .fx = defreturn };

        if (stat.mtime <= res_info.last_edit_time)
            return .{ .was_reloaded = false, .fx = defreturn };

        const data = file.readToEndAlloc(self.allocator, 100_000) catch return .{ .was_reloaded = false, .fx = defreturn };
        defer self.allocator.free(data);

        res_info.last_edit_time = stat.mtime;

        const newPtr = brk: {
            var json_stream = std.json.TokenStream.init(data);

            var resource = self.allocator.create(T) catch return .{ .was_reloaded = false, .fx = defreturn };
            var success = false;
            defer {
                if (!success) {
                    self.allocator.destroy(resource);
                }
            }
            resource.* = std.json.parse(T, &json_stream, parse_json_params) catch return .{ .was_reloaded = false, .fx = defreturn };

            success = true;
            break :brk resource;
        };

        res_info.cleanup_func(self, res_info);
        res_info.data = newPtr;

        return .{ .was_reloaded = true, .fx = constPtrCast(*const T, fx.*).* };
    }
}

fn LoadJsonResult(comptime T: type) type {
    return struct { was_reloaded: bool, fx: T };
}

pub fn loadJsonResource(self: *Self, comptime res_id: res.Resource, comptime T: type) LoadJsonResult(T) {
    @setEvalBranchQuota(20_000);

    if (comptime options.embed_structs) {
        return .{ .was_reloaded = false, .fx = comptime loadJsonResourceComptime(res_id, T) };
    } else {
        return loadJsonResourceAllocate(self, res_id, T);
    }
}

pub fn die(self: *Self) void {
    var s = &self.state;
    s.game_over = true;
    std.log.info("Game over", .{});
    var fx = self.loadJsonResource(.part, State.ParticleParams).fx;
    fx.ox = s.player_x;
    fx.oy = s.player_y;

    s.particleBurst(fx);
    s.scr_shake_x = 5;
    s.scr_shake_y = 5;
}

pub fn step(self: *Self) !void {
    self.global_frames +%= 1;
    var s = &self.state;
    s.speed -= 4.0 / 60.0 / 60.0;

    if (comptime !options.embed_structs) {
        if (self.loadJsonResource(.part, State.ParticleParams).was_reloaded) {
            s.deinit();
            self.reset();
        }

        if (self.loadJsonResourceAllocate(.blocks, Tiled).was_reloaded) {
            s.deinit();
            self.reset();
        }
    }

    if (self.input.is_just_pressed(.start)) {
        s.deinit();
        self.reset();
    }

    //s = &self.state;

    for (s.blocks.items) |*block| {
        const collide_before = aabb(s.player_x - player_width / 2, s.player_y - (player_width - 2.0) / 2, player_width, player_width - 2.0, block.x, block.y, block.w, block.h);
        block.x += block.vx + s.speed;

        if (!s.game_over and !collide_before) {
            const collide_after = aabb(s.player_x - player_width / 2, s.player_y - (player_width - 2.0) / 2, player_width, player_width - 2.0, block.x, block.y, block.w, block.h);
            if (collide_after) {
                self.die();
            }
        }

        block.y += block.vy;
    }

    if (!s.game_over) {
        if (self.input.is_just_pressed(.a) and s.player_can_jump) {
            self.playSound(.jump);
            s.player_gravity *= -1.0;
            s.player_can_jump = false;
        }

        var prev_v = s.player_vy;
        s.player_vy += gravity * s.player_gravity;
        s.player_vy = std.math.clamp(s.player_vy, -player_max_speed + s.speed, player_max_speed - s.speed);
        var next_y = s.player_y + s.player_vy;

        for (s.blocks.items) |block| {
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
                s.player_can_jump = true;
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

        if (s.player_y > game_height or s.player_y < 0) {
            self.die();
        }
    }

    s.scr_shake_x = decay(s.scr_shake_x, 0.80, 0.1);
    s.scr_shake_y = decay(s.scr_shake_y, 0.80, 0.1);
    s.scr_offset_x = decay(s.scr_offset_x, 0.80, 0.1);
    s.scr_offset_y = decay(s.scr_offset_y, 0.80, 0.1);

    s.stepParticles();

    {
        var farthest_x: f32 = 0;
        // garbage collect blocks
        {
            var i = s.blocks.items.len;
            while (i > 0) {
                i -= 1;
                const block = &s.blocks.items[i];
                const dist = block.x + block.w;
                if (dist < 0) {
                    _ = s.blocks.swapRemove(i);
                }
                if (dist > farthest_x) {
                    farthest_x = dist;
                }
            }
        }

        if (farthest_x < game_width + 16) {
            var num = self.getNumBlocks();
            var chosen = s.game_random.random().intRangeLessThan(usize, 0, num);
            self.spawnBlocks(chosen, farthest_x);
        }
    }

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

    for (s.blocks.items) |block| {
        self.img.drawRect(@floatToInt(i32, block.x), @floatToInt(i32, block.y), @floatToInt(i32, block.w), @floatToInt(i32, block.h), sw.Color.fromRGB(0x00FFFF));
    }

    s.drawParticles(&self.img);

    for (0..20) |_| {
        for (0..game_height / 16) |y| {
            for (0..game_width / 16) |x| {
                self.img.drawImageRect(@intCast(i32, x) * 16, @intCast(i32, y) * 16, self.sprite, self.sprite.getRect(), .{});
            }
        }
    }

    if (!s.game_over) {
        var x = @floatToInt(i32, s.player_x - player_width / 2);
        var y = @floatToInt(i32, s.player_y - player_width / 2);

        self.img.drawRect(x, y, player_width, player_width, sw.Color.fromRGB(0xFFFFFF));
    }

    //self.img.drawImageRect(self.ralsei_x, self.ralsei_y, self.ralsei, self.ralsei.getRect(), .{});
}

fn spawnBlocks(self: *Self, num: usize, offset: f32) void {
    var blocks: Tiled = self.loadJsonResourceAllocate(.blocks, Tiled).fx;
    const layer = blocks.layers[num];

    for (layer.objects) |obj| {
        (self.state.blocks.addOne(self.allocator) catch unreachable).* = obj.toBlock(offset);
    }
}

fn getNumBlocks(self: *Self) usize {
    return self.loadJsonResourceAllocate(.blocks, Tiled).fx.layers.len - 2;
}
