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

pub const Image = struct {
    width: i32,
    height: i32,
    pixels: []Color,
    camera_x: i32,
    camera_y: i32,

    pub fn init(alloc: std.mem.Allocator, width: i32, height: i32) !Image {
        return .{
            .width = width,
            .height = height,
            .pixels = try alloc.alloc(Color, @intCast(usize, width * height)),
            .camera_x = 0,
            .camera_y = 0,
        };
    }

    pub fn deinit(self: *Image, alloc: std.mem.Allocator) void {
        alloc.free(self.pixels);
        self.* = undefined;
    }

    /// Clear the image with the given color
    pub fn drawClear(self: Image, color: Color) void {
        std.mem.set(Color, self.pixels, color);
    }

    test drawClear {
        var img = try Image.init(std.testing.allocator, 8, 16);
        defer img.deinit(std.testing.allocator);

        img.drawClear(Color.fromRGB(0xabcdef));
        try test_image_equals("drawClear.png", img);
    }

    /// Put the given pixel at the specific coordinate on the Image.
    /// If the pixel is outside the screen, does nothing
    pub fn drawPixel(self: Image, x: i32, y: i32, pixel: Color) void {
        if (between(x, 0, self.width) and between(y, 0, self.height)) {
            self.drawPixelFast(x, y, pixel);
        }
    }

    test drawPixel {
        var img = try Image.init(std.testing.allocator, 8, 16);
        defer img.deinit(std.testing.allocator);

        img.drawClear(Color.fromRGB(0xabcdef));

        img.drawPixel(0, 0, Color.fromRGB(0x76428a));
        img.drawPixel(5, 2, Color.fromRGB(0x5b6ee1));
        img.drawPixel(7, 15, Color.fromRGB(0xac3232));

        // drawing outside the image shouldn't affect the image
        img.drawPixel(-1, -1, Color.fromRGB(0x777777));
        img.drawPixel(16, 0, Color.fromRGB(0x777777));
        img.drawPixel(8, 24, Color.fromRGB(0x777777));

        try test_image_equals("drawPixel.png", img);
    }

    /// Draw the given pixel at the specific coordinate on the Image, without any boundary check.
    /// Only use this function if you have pre-clipped your coordinates
    pub inline fn drawPixelFast(self: Image, x: i32, y: i32, pixel: Color) void {
        self.pixels[self.index(x, y)] = pixel;
    }

    pub inline fn index(self: Image, x: i32, y: i32) usize {
        return @intCast(usize, x + y * self.width);
    }

    pub inline fn indexFlags(self: Image, x: i32, y: i32, w: i32, h: i32, ox: i32, oy: i32, comptime flag: DrawFlags) usize {
        const ix = x + if (flag.flip_horizontal) w - ox - 1 else ox;
        const iy = y + if (flag.flip_vertical) h - oy - 1 else oy;
        return @intCast(usize, ix + iy * self.width);
    }

    pub inline fn getPixelFast(self: Image, x: i32, y: i32) Color {
        return self.pixels[self.index(x, y)];
    }

    pub inline fn getRect(self: Image) Rect {
        return Rect.xywh(0, 0, self.width, self.height);
    }

    pub fn drawRect(dest: Image, dest_x: i32, dest_y: i32, width: i32, height: i32, color: Color) void {
        const start_x = @max(0, dest_x - dest.camera_x);
        var y = @max(0, dest_y - dest.camera_y);
        const end_x = @min(dest_x + width - dest.camera_x, dest.width);
        const end_y = @min(dest_y + height - dest.camera_y, dest.height);

        while (y < end_y) : (y += 1) {
            var x = start_x;
            while (x < end_x) : (x += 1) {
                dest.drawPixelFast(x, y, color);
            }
        }
    }

    test drawRect {
        {
            var img = try Image.init(std.testing.allocator, 8, 16);
            defer img.deinit(std.testing.allocator);

            img.drawClear(Color.fromRGB(0xabcdef));

            const red = Color.fromRGB(0xFF0000);
            img.drawRect(1, -1, 5, 6, red);
            img.drawRect(1, 7, 3, 4, red);
            img.drawRect(6, 7, 6, 5, red);
            img.drawRect(-2, 14, 4, 4, red);

            img.drawRect(7, 15, 1, 1, red);

            try test_image_equals("drawRect.png", img);
        }
    }

    pub fn drawImageRectNoAlpha(dest: Image, dest_x: i32, dest_y: i32, source: Image, source_rect: Rect) void {
        const start_x = @max(0, dest_x);
        const start_y = @max(0, dest_y);
        const w = @min(dest_x + source_rect.w, dest.width) - start_x;
        const h = @min(dest_y + source_rect.h, dest.height) - start_y;
        var y: i32 = 0;

        const ox = (start_x - dest_x);
        const oy = (start_y - dest_y);

        while (y < h) : (y += 1) {
            var x: i32 = 0;
            while (x < w) : (x += 1) {
                const pixel = source.getPixelFast(source_rect.x + x + ox, source_rect.y + y + oy);
                dest.drawPixelFast(x + start_x, y + start_y, pixel);
            }
        }
    }

    fn drawImageRectComptime(dest: Image, dest_x: i32, dest_y: i32, source: Image, source_rect: Rect, comptime flags: DrawFlags) void {
        const start_x = @max(0, dest_x);
        const start_y = @max(0, dest_y);
        const w = @min(dest_x + source_rect.w, dest.width) - start_x;
        const h = @min(dest_y + source_rect.h, dest.height) - start_y;
        var y: i32 = 0;

        const ox = (start_x - dest_x);
        const oy = (start_y - dest_y);

        while (y < h) : (y += 1) {
            var x: i32 = 0;
            while (x < w) : (x += 1) {
                const pixel = source.pixels[source.indexFlags(source_rect.x, source_rect.y, source_rect.w, source_rect.h, x + ox, y + oy, flags)];
                const write = if (pixel.a != 0) pixel else dest.getPixelFast(x + start_x, y + start_y);
                dest.drawPixelFast(x + start_x, y + start_y, write);
            }
        }
    }

    pub fn drawImageRect(dest: Image, dest_x: i32, dest_y: i32, source: Image, source_rect: Rect, flags: DrawFlags) void {
        if (flags.flip_horizontal) {
            if (flags.flip_vertical) {
                drawImageRectComptime(dest, dest_x, dest_y, source, source_rect, .{ .flip_horizontal = true, .flip_vertical = true });
            } else {
                drawImageRectComptime(dest, dest_x, dest_y, source, source_rect, .{ .flip_horizontal = true, .flip_vertical = false });
            }
        } else {
            if (flags.flip_vertical) {
                drawImageRectComptime(dest, dest_x, dest_y, source, source_rect, .{ .flip_horizontal = false, .flip_vertical = true });
            } else {
                drawImageRectComptime(dest, dest_x, dest_y, source, source_rect, .{ .flip_horizontal = false, .flip_vertical = false });
            }
        }
    }

    const DrawFlags = packed struct {
        flip_horizontal: bool = false,
        flip_vertical: bool = false,
    };

    test drawImageRect {
        const stbi = @import("stb_image.zig");

        {
            var spr = try stbi.load_from_memory_to_Image(@embedFile("test/sprite.png"), std.testing.allocator);
            defer spr.deinit(std.testing.allocator);

            var img = try Image.init(std.testing.allocator, 8, 16);
            defer img.deinit(std.testing.allocator);

            img.drawClear(Color.fromRGB(0xabcdef));

            var rect = spr.getRect();
            img.drawImageRect(-2, -2, spr, rect, .{});
            img.drawImageRect(3, 1, spr, rect, .{});
            img.drawImageRect(6, 14, spr, rect, .{});
            img.drawImageRect(0, 12, spr, rect, .{});

            img.drawImageRect(5, 7, spr, Rect.xywh(2, 1, 2, 3), .{});
            img.drawImageRect(-1, 3, spr, Rect.xywh(0, 2, 2, 2), .{});

            try test_image_equals("drawSprite.png", img);
        }

        {
            var spr = try stbi.load_from_memory_to_Image(@embedFile("test/sprite.png"), std.testing.allocator);
            defer spr.deinit(std.testing.allocator);

            var img = try Image.init(std.testing.allocator, 8, 16);
            defer img.deinit(std.testing.allocator);

            img.drawClear(Color.fromRGB(0xabcdef));

            var rect = spr.getRect();
            img.drawImageRect(1, 1, spr, rect, .{ .flip_horizontal = true });
            img.drawImageRect(0, 5, spr, rect, .{ .flip_vertical = true });
            img.drawImageRect(0, 10, spr, rect, .{ .flip_horizontal = true, .flip_vertical = true });
            img.drawImageRect(6, 10, spr, rect, .{ .flip_horizontal = true, .flip_vertical = true });

            img.drawImageRect(6, -2, spr, rect, .{ .flip_horizontal = true });
            img.drawImageRect(-2, -3, spr, rect, .{ .flip_vertical = true });
            img.drawImageRect(2, 15, spr, rect, .{ .flip_vertical = true });

            img.drawImageRect(4, 6, spr, Rect.xywh(1, 1, 3, 3), .{ .flip_horizontal = true });

            try test_image_equals("drawSpriteFlip.png", img);
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

fn test_image_equals(comptime ref_path: []const u8, img: Image) !void {
    const stbi = @import("stb_image.zig");

    const full_ours_path = comptime @import("tests").test_path ++ ref_path[0 .. ref_path.len - 4] ++ ".ours.png";

    var refImg = try stbi.load_from_memory_to_Image(@embedFile("test/" ++ ref_path), std.testing.allocator);
    defer refImg.deinit(std.testing.allocator);

    try stbi.write_png(full_ours_path, img.width, img.height, 4, img.pixels.ptr, 0);

    try std.testing.expectEqual(refImg.width, img.width);
    try std.testing.expectEqual(refImg.height, img.height);

    try std.testing.expectEqualSlices(u8, std.mem.sliceAsBytes(refImg.pixels), std.mem.sliceAsBytes(img.pixels));
}
