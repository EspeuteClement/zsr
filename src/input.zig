const std = @import("std");

pub const VirtualButton = enum {
    left,
    right,
    down,
    up,
    a,
    b,
    x,
    y,
    start,
    select,
};

pub const Input = struct {
    current_state: Array = Array.initFill(false),
    previous_state: Array = Array.initFill(false),

    const Array = std.EnumArray(VirtualButton, bool);

    pub fn new_input_frame(self: *Input) void {
        self.previous_state = self.current_state;
        self.current_state = Array.initFill(false);
    }

    pub fn set_input(self: *Input, button: VirtualButton, pressed: bool) void {
        self.current_state.set(button, pressed);
    }

    pub fn accumulate_input(self: *Input, button: VirtualButton, pressed: bool) void {
        if (!self.current_state.get(button)) {
            self.current_state.set(button, pressed);
        }
    }

    pub fn is_down(self: *Input, button: VirtualButton) bool {
        return self.current_state.get(button);
    }

    pub fn is_just_pressed(self: *Input, button: VirtualButton) bool {
        return self.current_state.get(button) and !self.previous_state.get(button);
    }

    pub fn is_just_released(self: *Input, button: VirtualButton) bool {
        return !self.current_state.get(button) and self.previous_state.get(button);
    }

    test is_down {
        var i: Input = .{};
        i.new_input_frame();
        i.set_input(.a, true);

        try std.testing.expect(i.is_down(.a));
        try std.testing.expect(!i.is_down(.b));
    }

    test is_just_pressed {
        var i: Input = .{};
        i.new_input_frame();
        i.set_input(.b, true);

        i.new_input_frame();
        i.set_input(.a, true);

        try std.testing.expect(i.is_just_pressed(.a));
        try std.testing.expect(!i.is_just_pressed(.b));
    }

    test is_just_released {
        var i: Input = .{};
        i.new_input_frame();
        i.set_input(.b, true);

        i.new_input_frame();
        i.set_input(.a, true);

        try std.testing.expect(!i.is_just_released(.a));
        try std.testing.expect(i.is_just_released(.b));
    }
};

test {
    _ = std.testing.refAllDecls(Input);
}
