const std = @import("std");

pub const Color = packed struct(u32) {
    r: u8 = 255,
    g: u8 = 255,
    b: u8 = 255,
    a: u8 = 255,

    pub fn fromU32(value: u32) Color {
        return @bitCast(Color, value);
    }

    pub fn fromRGB(value: u24) Color {
        return .{
            .r = @truncate(u8, value >> 16),
            .g = @truncate(u8, value >> 8),
            .b = @truncate(u8, value >> 0),
        };
    }

    inline fn fToU8(v: f32) u8 {
        return @floatToInt(u8, std.math.clamp(v, 0.0, 1.0) * 255);
    }

    pub fn fromHSV(h: f32, s: f32, v: f32, a: f32) Color {
        const c = v * s;
        const x = c * (1.0 - @fabs(@mod(h / 60.0, 2.0) - 1.0));
        const m = v - c;

        const rgb: struct { r: f32, g: f32, b: f32 } = if (h < 60.0)
            .{ .r = c, .g = x, .b = 0 }
        else if (h < 120.0)
            .{ .r = x, .g = c, .b = 0 }
        else if (h < 180)
            .{ .r = 0, .g = c, .b = x }
        else if (h < 240)
            .{ .r = 0, .g = x, .b = c }
        else if (h < 300)
            .{ .r = x, .g = 0, .b = c }
        else
            .{ .r = c, .g = 0, .b = x };

        return .{
            .r = fToU8(rgb.r + m),
            .g = fToU8(rgb.g + m),
            .b = fToU8(rgb.b + m),
            .a = fToU8(a),
        };
    }

    test fromRGB {
        var c = fromRGB(0xabcdef);
        var ref = Color{
            .r = 0xab,
            .g = 0xcd,
            .b = 0xef,
        };

        try std.testing.expectEqual(ref, c);
    }

    const black = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
    const white = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
};

// check if the value is in the range [min: max[
inline fn between(value: anytype, min: anytype, max: anytype) bool {
    return value >= min and value < max;
}

const DrawFlags = packed struct {
    flip_horizontal: bool = false,
    flip_vertical: bool = false,
};

// Pixels with a width and height
pub const Texture = struct {
    width: i32,
    height: i32,
    pixels: []Color,

    pub fn init(alloc: std.mem.Allocator, width: i32, height: i32) !Texture {
        return .{
            .width = width,
            .height = height,
            .pixels = try alloc.alloc(Color, @intCast(usize, width * height)),
        };
    }

    pub fn deinit(texture: *Self, alloc: std.mem.Allocator) void {
        alloc.free(texture.pixels);
        texture.* = undefined;
    }

    /// Draw the given pixel at the specific coordinate on the Surface, without any boundary check.
    /// Only use this function if you have pre-clipped your coordinates
    pub inline fn drawPixelFast(self: Self, x: i32, y: i32, pixel: Color) void {
        self.pixels[self.index(x, y)] = pixel;
    }

    pub inline fn getPixelFast(self: Self, x: i32, y: i32) Color {
        return self.pixels[self.index(x, y)];
    }

    pub inline fn index(self: Self, x: i32, y: i32) usize {
        return @intCast(usize, x + y * self.width);
    }

    pub inline fn getRect(self: Self) Rect {
        return Rect.xywh(0, 0, self.width, self.height);
    }

    pub inline fn indexFlags(self: Self, x: i32, y: i32, w: i32, h: i32, ox: i32, oy: i32, comptime flag: DrawFlags) usize {
        const ix = x + if (flag.flip_horizontal) w - ox - 1 else ox;
        const iy = y + if (flag.flip_vertical) h - oy - 1 else oy;
        return @intCast(usize, ix + iy * self.width);
    }

    const Self = @This();
};

// An texture that you can draw on
pub const Surface = struct {
    texture: Texture,
    camera_x: i32,
    camera_y: i32,

    pub fn init(alloc: std.mem.Allocator, width: i32, height: i32) !Surface {
        return .{
            .texture = try Texture.init(alloc, width, height),
            .camera_x = 0,
            .camera_y = 0,
        };
    }

    inline fn offset(self: Surface, x: i32, y: i32) struct { x: i32, y: i32 } {
        return .{ .x = x - self.camera_x, .y = y - self.camera_y };
    }

    pub fn deinit(self: *Surface, alloc: std.mem.Allocator) void {
        self.texture.deinit(alloc);
        self.* = undefined;
    }

    /// Clear the image with the given color
    pub fn drawClear(self: Surface, color: Color) void {
        @memset(self.texture.pixels, color);
    }

    test drawClear {
        var img = try Surface.init(std.testing.allocator, 8, 16);
        defer img.deinit(std.testing.allocator);

        img.drawClear(Color.fromRGB(0xabcdef));
        try testTextureEquals("drawClear.png", img.texture);
    }

    /// Put the given pixel at the specific coordinate on the Surface.
    /// If the pixel is outside the screen, does nothing
    pub fn drawPixel(self: Surface, x: i32, y: i32, pixel: Color) void {
        var p = self.offset(x, y);
        if (between(p.x, 0, self.texture.width) and between(p.y, 0, self.texture.height)) {
            self.texture.drawPixelFast(p.x, p.y, pixel);
        }
    }

    test drawPixel {
        var img = try Surface.init(std.testing.allocator, 8, 16);
        defer img.deinit(std.testing.allocator);

        img.drawClear(Color.fromRGB(0xabcdef));

        img.drawPixel(0, 0, Color.fromRGB(0x76428a));
        img.drawPixel(5, 2, Color.fromRGB(0x5b6ee1));
        img.drawPixel(7, 15, Color.fromRGB(0xac3232));

        // drawing outside the image shouldn't affect the image
        img.drawPixel(-1, -1, Color.fromRGB(0x777777));
        img.drawPixel(16, 0, Color.fromRGB(0x777777));
        img.drawPixel(8, 24, Color.fromRGB(0x777777));

        try testTextureEquals("drawPixel.png", img.texture);
    }

    pub fn drawRect(dest: Surface, dest_x: i32, dest_y: i32, width: i32, height: i32, color: Color) void {
        const p = dest.offset(dest_x, dest_y);

        const start_x = @max(0, p.x);
        var y = @max(0, p.y);
        const end_x = @min(p.x + width, dest.texture.width);
        const end_y = @min(p.y + height, dest.texture.height);

        while (y < end_y) : (y += 1) {
            var x = start_x;
            while (x < end_x) : (x += 1) {
                dest.texture.drawPixelFast(x, y, color);
            }
        }
    }

    test drawRect {
        {
            var img = try Surface.init(std.testing.allocator, 8, 16);
            defer img.deinit(std.testing.allocator);

            img.drawClear(Color.fromRGB(0xabcdef));

            const red = Color.fromRGB(0xFF0000);
            img.drawRect(1, -1, 5, 6, red);
            img.drawRect(1, 7, 3, 4, red);
            img.drawRect(6, 7, 6, 5, red);
            img.drawRect(-2, 14, 4, 4, red);

            img.drawRect(7, 15, 1, 1, red);

            try testTextureEquals("drawRect.png", img.texture);
        }
    }

    pub fn drawTextureRectNoAlpha(dest: Surface, dest_x: i32, dest_y: i32, source: Texture, source_rect: Rect) void {
        const p = dest.offset(dest_x, dest_y);
        const start_x = @max(0, p.x);
        const start_y = @max(0, p.y);
        const w = @min(p.x + source_rect.w, dest.texture.width) - start_x;
        const h = @min(p.y + source_rect.h, dest.texture.height) - start_y;
        var y: i32 = 0;

        const ox = (start_x - p.x);
        const oy = (start_y - p.y);

        while (y < h) : (y += 1) {
            var x: i32 = 0;
            while (x < w) : (x += 1) {
                const pixel = source.getPixelFast(source_rect.x + x + ox, source_rect.y + y + oy);
                dest.texture.drawPixelFast(x + start_x, y + start_y, pixel);
            }
        }
    }

    fn drawTextureRectComptime(dest: Surface, dest_x: i32, dest_y: i32, source: Texture, source_rect: Rect, comptime flags: DrawFlags) void {
        const p = dest.offset(dest_x, dest_y);
        const start_x = @max(0, p.x);
        const start_y = @max(0, p.y);
        const w = @min(p.x + source_rect.w, dest.texture.width) - start_x;
        const h = @min(p.y + source_rect.h, dest.texture.height) - start_y;
        var y: i32 = 0;

        const ox = (start_x - p.x);
        const oy = (start_y - p.y);

        while (y < h) : (y += 1) {
            var x: i32 = 0;
            while (x < w) : (x += 1) {
                const pixel = source.pixels[source.indexFlags(source_rect.x, source_rect.y, source_rect.w, source_rect.h, x + ox, y + oy, flags)];
                const write = if (pixel.a != 0) pixel else dest.texture.getPixelFast(x + start_x, y + start_y);
                dest.texture.drawPixelFast(x + start_x, y + start_y, write);
            }
        }
    }

    pub fn drawTextureRect(dest: Surface, dest_x: i32, dest_y: i32, source: Texture, source_rect: Rect, flags: DrawFlags) void {
        if (flags.flip_horizontal) {
            if (flags.flip_vertical) {
                drawTextureRectComptime(dest, dest_x, dest_y, source, source_rect, .{ .flip_horizontal = true, .flip_vertical = true });
            } else {
                drawTextureRectComptime(dest, dest_x, dest_y, source, source_rect, .{ .flip_horizontal = true, .flip_vertical = false });
            }
        } else {
            if (flags.flip_vertical) {
                drawTextureRectComptime(dest, dest_x, dest_y, source, source_rect, .{ .flip_horizontal = false, .flip_vertical = true });
            } else {
                drawTextureRectComptime(dest, dest_x, dest_y, source, source_rect, .{ .flip_horizontal = false, .flip_vertical = false });
            }
        }
    }

    test drawTextureRect {
        const stbi = @import("stb_image.zig");

        {
            var spr = try stbi.loadFromMemToTexture(@embedFile("test/sprite.png"), std.testing.allocator);
            defer spr.deinit(std.testing.allocator);

            var img = try Surface.init(std.testing.allocator, 8, 16);
            defer img.deinit(std.testing.allocator);

            img.drawClear(Color.fromRGB(0xabcdef));

            var rect = spr.getRect();
            img.drawTextureRect(-2, -2, spr, rect, .{});
            img.drawTextureRect(3, 1, spr, rect, .{});
            img.drawTextureRect(6, 14, spr, rect, .{});
            img.drawTextureRect(0, 12, spr, rect, .{});

            img.drawTextureRect(5, 7, spr, Rect.xywh(2, 1, 2, 3), .{});
            img.drawTextureRect(-1, 3, spr, Rect.xywh(0, 2, 2, 2), .{});

            try testTextureEquals("drawSprite.png", img.texture);
        }

        {
            var spr = try stbi.loadFromMemToTexture(@embedFile("test/sprite.png"), std.testing.allocator);
            defer spr.deinit(std.testing.allocator);

            var img = try Surface.init(std.testing.allocator, 8, 16);
            defer img.deinit(std.testing.allocator);

            img.drawClear(Color.fromRGB(0xabcdef));

            var rect = spr.getRect();
            img.drawTextureRect(1, 1, spr, rect, .{ .flip_horizontal = true });
            img.drawTextureRect(0, 5, spr, rect, .{ .flip_vertical = true });
            img.drawTextureRect(0, 10, spr, rect, .{ .flip_horizontal = true, .flip_vertical = true });
            img.drawTextureRect(6, 10, spr, rect, .{ .flip_horizontal = true, .flip_vertical = true });

            img.drawTextureRect(6, -2, spr, rect, .{ .flip_horizontal = true });
            img.drawTextureRect(-2, -3, spr, rect, .{ .flip_vertical = true });
            img.drawTextureRect(2, 15, spr, rect, .{ .flip_vertical = true });

            img.drawTextureRect(4, 6, spr, Rect.xywh(1, 1, 3, 3), .{ .flip_horizontal = true });

            try testTextureEquals("drawSpriteFlip.png", img.texture);
        }
    }
};

pub const XY = struct {
    x_start: i32 = 0,
    x: i32 = 0,
    y: i32 = 0,
    w: i32 = 0,
    y_end: i32 = 0,

    pub inline fn start(x: i32, y: i32, w: i32, h: i32) XY {
        return .{
            .x_start = x,
            .x = x,
            .y = y,
            .w = x + w,
            .y_end = y + h,
        };
    }

    pub inline fn next(self: *XY) ?struct { x: i32, y: i32 } {
        if (self.x >= self.w) {
            self.x = self.x_start;
            self.y += 1;
        }
        if (self.y >= self.y_end) {
            return null;
        }

        const x = self.x;
        self.x += 1;
        return .{
            .x = x,
            .y = self.y,
        };
    }
};

pub const Rect = struct {
    x: i32 = 0,
    y: i32 = 0,
    w: i32 = 0,
    h: i32 = 0,

    pub fn xywh(x: i32, y: i32, w: i32, h: i32) Rect {
        return .{
            .x = x,
            .y = y,
            .w = w,
            .h = h,
        };
    }

    pub inline fn xw(self: Rect) i32 {
        return self.x + self.w;
    }

    pub inline fn yh(self: Rect) i32 {
        return self.y + self.h;
    }

    pub fn fromCorners(x0: i32, y0: i32, x1: i32, y1: i32) Rect {
        return .{
            .x = x0,
            .y = y0,
            .w = x1 - x0,
            .h = y1 - y0,
        };
    }

    pub fn intersection(a: Rect, b: Rect) Rect {
        var x0 = @max(a.x, b.x);
        var y0 = @max(a.y, b.y);
        var x1 = @min(a.xw(), b.xw());
        var y1 = @min(a.yh(), b.yh());

        return fromCorners(x0, y0, x1, y1);
    }

    test intersection {
        {
            var a = Rect.xywh(0, 0, 16, 16);
            var b = Rect.fromCorners(4, 4, 8, 8);

            try std.testing.expectEqual(b, a.intersection(b));
            try std.testing.expectEqual(b, b.intersection(a));
        }

        {
            var a = Rect.xywh(0, 0, 16, 16);
            var b = Rect.fromCorners(4, 4, 24, 8);

            try std.testing.expectEqual(Rect.fromCorners(4, 4, 16, 8), a.intersection(b));
            try std.testing.expectEqual(Rect.fromCorners(4, 4, 16, 8), b.intersection(a));
        }

        {
            var a = Rect.xywh(0, 0, 16, 16);
            var b = Rect.fromCorners(-8, 4, 8, 24);

            try std.testing.expectEqual(Rect.fromCorners(0, 4, 8, 16), a.intersection(b));
            try std.testing.expectEqual(Rect.fromCorners(0, 4, 8, 16), b.intersection(a));
        }
    }

    const Iterator = struct {
        x: i32,
        y: i32,
        rect: Rect,

        inline fn next(self: *Iterator) bool {
            self.x += 1;
            if (self.x >= self.rect.w) {
                self.x = 0;
                self.y += 1;
            }
            if (self.y >= self.rect.h) {
                return false;
            }

            return true;
        }

        inline fn rectX(self: Iterator) i32 {
            return self.x + self.rect.x;
        }

        inline fn rectY(self: Iterator) i32 {
            return self.y + self.rect.y;
        }

        inline fn index(self: Iterator, w: i32) usize {
            return @intCast(usize, self.x + self.rect.x + (self.y + self.rect.y) * w);
        }
    };

    pub inline fn iterate(self: Rect) Iterator {
        return .{
            .x = -1,
            .y = 0,
            .rect = self,
        };
    }

    test iterate {
        {
            var rect = Rect.xywh(16, 24, 4, 3);

            var sum: i32 = 0;
            var sum_abs: i32 = 0;
            var sum_i: usize = 0;
            var iterator = rect.iterate();
            while (iterator.next()) {
                sum += iterator.x * iterator.y;
                sum_abs += iterator.rectX() * iterator.rectY();
                sum_i += iterator.index(42);
            }

            try std.testing.expectEqual(@as(i32, 18), sum);
            try std.testing.expectEqual(@as(i32, 5250), sum_abs);
            try std.testing.expectEqual(@as(usize, 12810), sum_i);
        }
    }
};

fn testTextureEquals(comptime ref_path: []const u8, img: Texture) !void {
    const stbi = @import("stb_image.zig");
    stbi.initAllocatorsTest();

    const full_ours_path = comptime @import("tests").test_path ++ ref_path[0 .. ref_path.len - 4] ++ ".ours.png";

    var refImg = try stbi.loadFromMemToTexture(@embedFile("test/" ++ ref_path), std.testing.allocator);
    defer refImg.deinit(std.testing.allocator);

    try stbi.write_png(full_ours_path, img.width, img.height, 4, img.pixels.ptr, 0);

    try std.testing.expectEqual(refImg.width, img.width);
    try std.testing.expectEqual(refImg.height, img.height);

    try std.testing.expectEqualSlices(u8, std.mem.sliceAsBytes(refImg.pixels), std.mem.sliceAsBytes(img.pixels));
}
