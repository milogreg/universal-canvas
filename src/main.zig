const std = @import("std");
const render = @import("render.zig");

const js = struct {
    extern fn printString(ptr: [*]const u8, len: usize) void;

    extern fn getTime() f64;

    extern fn fillImageBitmap(
        pixels: [*]render.Color,
        width: usize,
        height: usize,
        old_pixels: [*]render.Color,
        old_width: usize,
        old_height: usize,
    ) void;

    extern fn imageBitmapFilled() bool;

    extern fn renderImage(
        offset_x: f64,
        offset_y: f64,
        zoom: f64,
        old_offset_x: f64,
        old_offset_y: f64,
        old_zoom: f64,
        updated_pixels: bool,
        max_detail: bool,
    ) void;
};

pub const Panic = struct {
    pub fn call(
        msg: []const u8,
        error_return_trace: ?*const std.builtin.StackTrace,
        first_trace_addr: ?usize,
    ) noreturn {
        @branchHint(.cold);

        _ = error_return_trace; // autofix
        _ = first_trace_addr; // autofix

        var panic_msg_buf: [1000]u8 = undefined;

        const panic_msg = std.fmt.bufPrint(&panic_msg_buf, "panic: {s}", .{msg}) catch msg;

        js.printString(panic_msg.ptr, panic_msg.len);

        @trap();
    }

    pub fn sentinelMismatch(expected: anytype, found: @TypeOf(expected)) noreturn {
        @branchHint(.cold);
        std.debug.panicExtra(null, @returnAddress(), "sentinel mismatch: expected {any}, found {any}", .{
            expected, found,
        });
    }

    pub fn unwrapError(ert: ?*std.builtin.StackTrace, err: anyerror) noreturn {
        @branchHint(.cold);
        std.debug.panicExtra(ert, @returnAddress(), "attempt to unwrap error: {s}", .{@errorName(err)});
    }

    pub fn outOfBounds(index: usize, len: usize) noreturn {
        @branchHint(.cold);
        std.debug.panicExtra(null, @returnAddress(), "index out of bounds: index {d}, len {d}", .{ index, len });
    }

    pub fn startGreaterThanEnd(start: usize, end: usize) noreturn {
        @branchHint(.cold);
        std.debug.panicExtra(null, @returnAddress(), "start index {d} is larger than end index {d}", .{ start, end });
    }

    pub fn inactiveUnionField(active: anytype, accessed: @TypeOf(active)) noreturn {
        @branchHint(.cold);
        std.debug.panicExtra(null, @returnAddress(), "access of union field '{s}' while field '{s}' is active", .{
            @tagName(accessed), @tagName(active),
        });
    }

    pub const messages = std.debug.SimplePanic.messages;
};

const allocator: std.mem.Allocator = std.heap.wasm_allocator;

fn jsPrint(comptime fmt: []const u8, args: anytype) void {
    const to_print = std.fmt.allocPrint(allocator, fmt, args) catch @panic("OOM");
    defer allocator.free(to_print);
    js.printString(to_print.ptr, to_print.len);
}

var offset_initial_states: [4]?render.SelfConsumingReaderState = @splat(null);

var state_tree: render.StateStems = undefined;

var iteration_states: [4]?render.FillIterationState = @splat(null);

const max_square_size = 2048;

// const iteration_rate = 1000000;
const iteration_rate = 300;

var state_iteration_count: usize = 0;
var iteration_done: bool = false;

// const root_color: render.Color = .{
//     .r = 50,
//     .g = 50,
//     .b = 50,
//     .a = 255,
// };

const root_color: render.Color = .{
    .r = 128,
    .g = 128,
    .b = 128,
    .a = 255,
};

var parent_pixels_buf: []render.Color = &.{};
var parent_pixels: []render.Color = &.{};
var parent_square_size: usize = 0;

var display_pixels_buf: []render.Color = &.{};
var display_pixels: []render.Color = &.{};
var display_square_size: usize = 0;

var old_display_pixels_buf: []render.Color = &.{};
var old_display_pixels: []render.Color = &.{};
var old_display_square_size: usize = 0;

var updated_pixels = false;
var position_dirty = true;
var filled_pixels = false;

var display_client: ClientPosition = .{
    .zoom = 1,
    .offset_x = 0,
    .offset_y = 0,
    .canvas_width = 1,
    .canvas_height = 1,
    .at_min_border_x = false,
    .at_min_border_y = false,
    .at_max_border_x = false,
    .at_max_border_y = false,
};

var old_display_client: ClientPosition = .{
    .zoom = 1,
    .offset_x = 0,
    .offset_y = 0,
    .canvas_width = 1,
    .canvas_height = 1,
    .at_min_border_x = false,
    .at_min_border_y = false,
    .at_max_border_x = false,
    .at_max_border_y = false,
};

var backup_client: ClientPosition = .{
    .zoom = 1,
    .offset_x = 0,
    .offset_y = 0,
    .canvas_width = 1,
    .canvas_height = 1,
    .at_min_border_x = false,
    .at_min_border_y = false,
    .at_max_border_x = false,
    .at_max_border_y = false,
};

const ClientPosition = struct {
    zoom: f64,
    offset_x: f64,
    offset_y: f64,

    canvas_width: usize,
    canvas_height: usize,

    at_min_border_x: bool,
    at_min_border_y: bool,
    at_max_border_x: bool,
    at_max_border_y: bool,

    pub fn updatePosition(this: *ClientPosition, mouse_x: f64, mouse_y: f64, zoom_delta: f64) void {
        this.zoom *= zoom_delta;
        this.offset_x = mouse_x - (mouse_x - this.offset_x) * zoom_delta;
        this.offset_y = mouse_y - (mouse_y - this.offset_y) * zoom_delta;
    }

    pub fn move(this: *ClientPosition, offset_x: f64, offset_y: f64) void {
        this.offset_x += offset_x;
        this.offset_y += offset_y;
    }

    pub fn clampToViewport(this: *ClientPosition) void {
        if (this.zoom < 1) {
            this.zoom = 1;
        }

        const maxOffsetX = 0;
        const maxOffsetY = 0;

        const min_offset_x = -@as(f64, @floatFromInt(this.canvas_width)) * this.zoom + @as(f64, @floatFromInt(this.canvas_width));
        const min_offset_y = -@as(f64, @floatFromInt(this.canvas_height)) * this.zoom + @as(f64, @floatFromInt(this.canvas_height));

        this.offset_x = @max(this.offset_x, min_offset_x);
        this.offset_x = @min(this.offset_x, maxOffsetX);

        this.offset_y = @max(this.offset_y, min_offset_y);
        this.offset_y = @min(this.offset_y, maxOffsetY);
    }

    pub fn areaInViewport(this: ClientPosition) f64 {
        const maxOffsetX = 0;
        const maxOffsetY = 0;

        const min_offset_x = -@as(f64, @floatFromInt(this.canvas_width)) * this.zoom + @as(f64, @floatFromInt(this.canvas_width));
        const min_offset_y = -@as(f64, @floatFromInt(this.canvas_height)) * this.zoom + @as(f64, @floatFromInt(this.canvas_height));

        const x_not_in_viewport = @max(this.offset_x - maxOffsetX, 0) + @max(min_offset_x - this.offset_x, 0);

        const y_not_in_viewport = @max(this.offset_y - maxOffsetY, 0) + @max(min_offset_y - this.offset_y, 0);

        return @max(0, ((@as(f64, @floatFromInt(this.canvas_width)) - x_not_in_viewport))) * @max(0, (@as(f64, @floatFromInt(this.canvas_height)) - y_not_in_viewport));
    }

    pub fn areaInViewportRatio(this: ClientPosition) f64 {
        return this.areaInViewport() / (@as(f64, @floatFromInt(this.canvas_width)) * @as(f64, @floatFromInt(this.canvas_height)));
    }

    pub fn testUpdatePosition(this_arg: ClientPosition, mouse_x: f64, mouse_y: f64, zoom_delta: f64) bool {
        var this = this_arg;

        this.zoom *= zoom_delta;

        if (this.zoom < 1) {
            return false;
        }

        const maxOffsetX = 0;
        const maxOffsetY = 0;

        const min_offset_x = -@as(f64, @floatFromInt(this.canvas_width)) * this.zoom + @as(f64, @floatFromInt(this.canvas_width));
        const min_offset_y = -@as(f64, @floatFromInt(this.canvas_height)) * this.zoom + @as(f64, @floatFromInt(this.canvas_height));

        this.offset_x = mouse_x - (mouse_x - this.offset_x) * zoom_delta;

        this.offset_y = mouse_y - (mouse_y - this.offset_y) * zoom_delta;

        // return !(this.offset_x > maxOffsetX or this.offset_y > maxOffsetY or this.offset_x < minOffsetX or this.offset_y < minOffsetY);
        return !((!this.at_max_border_x and this.offset_x > maxOffsetX) or
            (!this.at_max_border_y and this.offset_y > maxOffsetY) or
            (!this.at_min_border_x and this.offset_x < min_offset_x) or
            (!this.at_min_border_y and this.offset_y < min_offset_y));
    }

    pub fn testUpdatePosition2(this_arg: ClientPosition, mouse_x: f64, mouse_y: f64, zoom_delta: f64) bool {
        var this = this_arg;

        this.zoom *= zoom_delta;

        if (this.zoom < 1) {
            return false;
        }

        const maxOffsetX = 0;
        const maxOffsetY = 0;

        const min_offset_x = -@as(f64, @floatFromInt(this.canvas_width)) * this.zoom + @as(f64, @floatFromInt(this.canvas_width));
        const min_offset_y = -@as(f64, @floatFromInt(this.canvas_height)) * this.zoom + @as(f64, @floatFromInt(this.canvas_height));

        this.offset_x = mouse_x - (mouse_x - this.offset_x) * zoom_delta;

        this.offset_y = mouse_y - (mouse_y - this.offset_y) * zoom_delta;

        return !(this.offset_x > maxOffsetX or this.offset_y > maxOffsetY or this.offset_x < min_offset_x or this.offset_y < min_offset_y);
        // return !((!this.at_max_border_x and this.offset_x > maxOffsetX) or
        //     (!this.at_max_border_y and this.offset_y > maxOffsetY) or
        //     (!this.at_min_border_x and this.offset_x < minOffsetX) or
        //     (!this.at_min_border_y and this.offset_y < minOffsetY));
    }

    pub fn updateDimensions(this: *ClientPosition, canvas_width: usize, canvas_height: usize) void {
        if (this.canvas_width == canvas_width and this.canvas_height == canvas_height) {
            return;
        }

        this.offset_x /= @as(f64, @floatFromInt(this.canvas_width));
        this.offset_y /= @as(f64, @floatFromInt(this.canvas_height));

        this.canvas_width = canvas_width;
        this.canvas_height = canvas_height;

        this.offset_x *= @as(f64, @floatFromInt(this.canvas_width));
        this.offset_y *= @as(f64, @floatFromInt(this.canvas_height));
    }

    pub fn inBounds(this: ClientPosition) bool {
        const max_offset_x = 0;
        const max_offset_y = 0;

        const min_offset_x = -@as(f64, @floatFromInt(this.canvas_width)) * (this.zoom - 1);
        const min_offset_y = -@as(f64, @floatFromInt(this.canvas_height)) * (this.zoom - 1);

        // return !(this.offset_x > max_offset_x or this.offset_y > max_offset_y or this.offset_x < min_offset_x or this.offset_y < min_offset_y);
        return !((!this.at_max_border_x and this.offset_x > max_offset_x) or
            (!this.at_max_border_y and this.offset_y > max_offset_y) or
            (!this.at_min_border_x and this.offset_x < min_offset_x) or
            (!this.at_min_border_y and this.offset_y < min_offset_y));
    }

    pub fn minOffsetX(this: ClientPosition) f64 {
        return -@as(f64, @floatFromInt(this.canvas_width)) * (this.zoom - 1);
    }

    pub fn minOffsetY(this: ClientPosition) f64 {
        return -@as(f64, @floatFromInt(this.canvas_height)) * (this.zoom - 1);
    }

    pub fn removeDigit(this: *ClientPosition, digit: u2) void {
        this.zoom *= 2;
        if (digit & 1 == 1) {
            this.offset_x -= @as(f64, @floatFromInt(this.canvas_width)) * 0.25 * this.zoom;
        }

        if (digit >> 1 == 1) {
            this.offset_y -= @as(f64, @floatFromInt(this.canvas_height)) * 0.25 * this.zoom;
        }
    }

    pub fn appendDigit(this: *ClientPosition, digit: u2) void {
        this.zoom /= 2;

        if (digit & 1 == 1) {
            this.offset_x += @as(f64, @floatFromInt(this.canvas_width)) * 0.5 * this.zoom;
        }

        if (digit >> 1 == 1) {
            this.offset_y += @as(f64, @floatFromInt(this.canvas_height)) * 0.5 * this.zoom;
        }
    }

    pub fn digitDecrement(this: *ClientPosition, digit: u2) void {
        if (digit & 1 == 1) {
            this.offset_x -= @as(f64, @floatFromInt(this.canvas_width)) * 0.5 * this.zoom;
        }

        if (digit >> 1 == 1) {
            this.offset_y -= @as(f64, @floatFromInt(this.canvas_height)) * 0.5 * this.zoom;
        }
    }

    pub fn digitIncrement(this: *ClientPosition, digit: u2) void {
        if (digit & 1 == 1) {
            this.offset_x += @as(f64, @floatFromInt(this.canvas_width)) * 0.5 * this.zoom;
        }

        if (digit >> 1 == 1) {
            this.offset_y += @as(f64, @floatFromInt(this.canvas_height)) * 0.5 * this.zoom;
        }
    }
};

fn appendDigit(digit: u2) void {
    var new_offset_initial_states: [4]?render.SelfConsumingReaderState = @splat(null);

    for (&new_offset_initial_states, 0..) |*new_initial_state, i| {
        if (i & 1 == 1) {
            state_tree.decrementX(i);
        }

        if (i >> 1 == 1) {
            state_tree.decrementY(i);
        }

        state_tree.appendDigit(i, digit) catch @panic("OOM");

        if (i & 1 == 1) {
            state_tree.incrementX(i);
        }
        if (i >> 1 == 1) {
            state_tree.incrementY(i);
        }

        const last_digit = state_tree.quadrant_digits[i].get(state_tree.quadrant_digits[i].length - 1);

        const parent_digit = i & digit;

        if (offset_initial_states[parent_digit]) |initial_state| {
            const virtual_digit_array = render.VirtualDigitArray.fromDigitArray(state_tree.quadrant_digits[i], 0, 0, 0);

            new_initial_state.* = initial_state.iterate(last_digit, virtual_digit_array);
        }
    }

    offset_initial_states = new_offset_initial_states;
}

fn removeDigit() void {
    for (0..4) |i| {
        if (i & 1 == 1) {
            state_tree.decrementX(i);
        }

        if (i >> 1 == 1) {
            state_tree.decrementY(i);
        }

        state_tree.removeDigit(i);

        if (i & 1 == 1) {
            state_tree.incrementX(i);
        }
        if (i >> 1 == 1) {
            state_tree.incrementY(i);
        }
    }

    offset_initial_states = @splat(null);
}

fn digitIncrement(digit: u2) void {
    for (0..4) |i| {
        if (digit & 1 == 1) {
            state_tree.incrementX(i);
        }
        if (digit >> 1 == 1) {
            state_tree.incrementY(i);
        }
    }

    offset_initial_states = @splat(null);
}

fn digitIncrementAndAppend(increment_digit: u2, append_digit: u2) void {
    var new_offset_initial_states: [4]?render.SelfConsumingReaderState = @splat(null);

    for (&new_offset_initial_states, 0..) |*new_initial_state, i| {
        if (i & 1 == 1 and increment_digit & 1 == 0) {
            state_tree.decrementX(i);
        }

        if (i & 1 == 0 and increment_digit & 1 == 1) {
            state_tree.incrementX(i);
        }

        if (i >> 1 == 1 and increment_digit >> 1 == 0) {
            state_tree.decrementY(i);
        }

        if (i >> 1 == 0 and increment_digit >> 1 == 1) {
            state_tree.incrementY(i);
        }

        state_tree.appendDigit(i, append_digit) catch @panic("OOM");

        if (i & 1 == 1) {
            state_tree.incrementX(i);
        }
        if (i >> 1 == 1) {
            state_tree.incrementY(i);
        }

        const last_digit = state_tree.quadrant_digits[i].get(state_tree.quadrant_digits[i].length - 1);

        const parent_digit = @as(usize, increment_digit) + @as(usize, i & append_digit);

        if (parent_digit < 4) {
            if (offset_initial_states[parent_digit]) |initial_state| {
                const virtual_digit_array = render.VirtualDigitArray.fromDigitArray(state_tree.quadrant_digits[i], 0, 0, 0);

                var new_initial_state_non_opt: render.SelfConsumingReaderState = undefined;

                initial_state.iterate(last_digit, virtual_digit_array, &new_initial_state_non_opt);

                new_initial_state.* = new_initial_state_non_opt;
            }
        }
    }

    offset_initial_states = new_offset_initial_states;
}

fn removeDigitAndDecrement(decrement_digit: u2) void {
    for (0..4) |i| {
        if (i & 1 == 1) {
            state_tree.decrementX(i);
        }

        if (i >> 1 == 1) {
            state_tree.decrementY(i);
        }

        state_tree.removeDigit(i);

        if (i & 1 == 1 and decrement_digit & 1 == 0) {
            state_tree.incrementX(i);
        }

        if (i & 1 == 0 and decrement_digit & 1 == 1) {
            state_tree.decrementX(i);
        }

        if (i >> 1 == 1 and decrement_digit >> 1 == 0) {
            state_tree.incrementY(i);
        }

        if (i >> 1 == 0 and decrement_digit >> 1 == 1) {
            state_tree.decrementY(i);
        }
    }

    offset_initial_states = @splat(null);
}

fn digitDecrement(digit: u2) void {
    for (0..4) |i| {
        if (digit & 1 == 1) {
            state_tree.decrementX(i);
        }
        if (digit >> 1 == 1) {
            state_tree.decrementY(i);
        }
    }

    offset_initial_states = @splat(null);
}

var wait_until_backup = true;

var has_max_detail = false;

export fn renderPixels() void {
    js.renderImage(
        display_client.offset_x,
        display_client.offset_y,
        display_client.zoom,

        old_display_client.offset_x,
        old_display_client.offset_y,
        old_display_client.zoom,

        updated_pixels and !wait_until_backup,
        has_max_detail,
    );

    updated_pixels = false;
}

export fn zoomViewport(mouse_x: f64, mouse_y: f64, zoom_delta: f64) void {
    position_dirty = true;

    old_display_client.updatePosition(mouse_x, mouse_y, zoom_delta);
    display_client.updatePosition(mouse_x, mouse_y, zoom_delta);
    backup_client.updatePosition(mouse_x, mouse_y, zoom_delta);
}

export fn moveViewport(offset_x: f64, offset_y: f64) void {
    position_dirty = true;

    old_display_client.move(offset_x, offset_y);
    display_client.move(offset_x, offset_y);
    backup_client.move(offset_x, offset_y);
}

export fn resizeViewport(canvas_width: usize, canvas_height: usize) void {
    std.debug.assert(canvas_width > 0 and canvas_height > 0);

    position_dirty = true;

    old_display_client.updateDimensions(canvas_width, canvas_height);
    display_client.updateDimensions(canvas_width, canvas_height);
    backup_client.updateDimensions(canvas_width, canvas_height);
}

// fn printDigits() void {
//     var list = std.ArrayList(u2).init(allocator);
//     defer list.deinit();

//     for (0..quadrant_offset_digits[0].array.length) |i| {
//         const digit = quadrant_offset_digits[0].array.get(i);

//         list.append(digit) catch @panic("OOM");
//     }

//     jsPrint("digits: {any}", .{list.items});
// }

const WorkCycleState = struct {
    update_position: UpdatePosition,
    fill_pixels: FillPixels,
    refresh_display: RefreshDisplay,

    pub const init: WorkCycleState = .{
        .update_position = .{},
        .fill_pixels = .init,
        .refresh_display = .init,
    };

    const UpdatePosition = struct {
        pub fn canIterate(this: UpdatePosition) bool {
            _ = this; // autofix
            return position_dirty;
        }

        pub fn iterate(this: *UpdatePosition, iteration_amount: usize) bool {
            _ = this; // autofix
            _ = iteration_amount; // autofix

            const at_min_edge_y = state_tree.quadrant_digits[0].isMinY();
            const at_min_edge_x = state_tree.quadrant_digits[0].isMinX();

            backup_client.at_max_border_x = at_min_edge_x;
            backup_client.at_max_border_y = at_min_edge_y;

            const at_edge_y = state_tree.quadrant_digits[3].isMaxY();
            const at_edge_x = state_tree.quadrant_digits[3].isMaxX();

            backup_client.at_min_border_x = at_edge_x;
            backup_client.at_min_border_y = at_edge_y;

            if (!backup_client.inBounds() and state_tree.quadrant_digits[0].length > 1) {
                const movement_unit = @as(f64, @floatFromInt(backup_client.canvas_width)) * 0.5 * backup_client.zoom;

                var increment_digit: u2 = 0;
                var decrement_digit: u2 = 0;

                const max_offset_x: f64 = 0;
                const max_offset_y: f64 = 0;

                const min_offset_x = backup_client.minOffsetX();
                const min_offset_y = backup_client.minOffsetY();

                const offset_x = if (at_min_edge_x)
                    @min(max_offset_x, backup_client.offset_x)
                else if (at_edge_x)
                    @max(min_offset_x, backup_client.offset_x)
                else
                    backup_client.offset_x;

                // const offset_x = backup_client.offset_x;

                const offset_y = if (at_min_edge_y)
                    @min(max_offset_y, backup_client.offset_y)
                else if (at_edge_y)
                    @max(min_offset_y, backup_client.offset_y)
                else
                    backup_client.offset_y;

                // const offset_y = backup_client.offset_y;

                if (offset_x < min_offset_x and offset_x + movement_unit <= max_offset_x) {
                    increment_digit |= 0b01;
                }

                if (offset_y < min_offset_y and offset_y + movement_unit <= max_offset_y) {
                    increment_digit |= 0b10;
                }

                if (offset_x > max_offset_x and offset_x - movement_unit >= min_offset_x) {
                    decrement_digit |= 0b01;
                }

                if (offset_y > max_offset_y and offset_y - movement_unit >= min_offset_y) {
                    decrement_digit |= 0b10;
                }

                backup_client.digitIncrement(increment_digit);

                backup_client.digitDecrement(decrement_digit);

                digitIncrement(increment_digit);
                digitDecrement(decrement_digit);

                if (increment_digit == 0 and decrement_digit == 0) {
                    var additional_decrement: u2 = 0;

                    if (state_tree.quadrant_digits[0].isMaxXBelow(state_tree.quadrant_digits[0].length - 1)) {
                        additional_decrement |= 0b01;
                    }

                    if (state_tree.quadrant_digits[0].isMaxYBelow(state_tree.quadrant_digits[0].length - 1)) {
                        additional_decrement |= 0b10;
                    }

                    const last_digit = state_tree.quadrant_digits[0].get(state_tree.quadrant_digits[0].length - 1);

                    backup_client.removeDigit(last_digit);
                    backup_client.digitDecrement(additional_decrement);

                    removeDigitAndDecrement(additional_decrement);
                }

                state_iteration_count = 0;
                parent_square_size = 64;
                filled_pixels = false;

                return true;
            } else if (backup_client.zoom >= 2 and backup_client.inBounds()) {
                for (0..4) |increment_digit| {
                    for (0..4) |append_digit| {
                        if ((at_edge_x and append_digit & 1 == 1 and increment_digit & 1 == 1) or
                            (at_edge_y and append_digit >> 1 == 1 and increment_digit >> 1 == 1))
                        {
                            continue;
                        }

                        var test_client = backup_client;

                        test_client.digitIncrement(@intCast(increment_digit));

                        test_client.appendDigit(@intCast(append_digit));

                        const initial_states = offset_initial_states;

                        digitIncrementAndAppend(@intCast(increment_digit), @intCast(append_digit));

                        {
                            test_client.at_max_border_x = state_tree.quadrant_digits[0].isMinX();
                            test_client.at_max_border_y = state_tree.quadrant_digits[0].isMinY();

                            test_client.at_min_border_x = state_tree.quadrant_digits[3].isMaxX();
                            test_client.at_min_border_y = state_tree.quadrant_digits[3].isMaxY();
                        }

                        if (test_client.inBounds()) {
                            backup_client = test_client;

                            state_iteration_count = 0;

                            const square_size_shift: usize = @intFromFloat(@max(0, (std.math.log2(display_client.zoom / 2))));

                            if (parent_square_size > display_square_size >> @intCast(square_size_shift)) {
                                parent_square_size = display_square_size >> @intCast(square_size_shift);
                            }

                            filled_pixels = false;

                            return true;
                        }

                        removeDigitAndDecrement(@intCast(increment_digit));

                        offset_initial_states = initial_states;
                    }
                }
            }

            position_dirty = false;

            return false;
        }
    };

    const FillPixels = struct {
        initialized: bool,
        output_color_chunks: [4][][]render.Color,
        output_color_chunks_backing: [][]render.Color,
        setup_initial_states: bool,

        pub const init: FillPixels = .{
            .initialized = false,
            .output_color_chunks = undefined,
            .output_color_chunks_backing = undefined,
            .setup_initial_states = undefined,
        };

        pub fn canIterate(this: FillPixels) bool {
            return (this.initialized or state_iteration_count == 0) and !filled_pixels;
        }

        fn initialize(this: *FillPixels) void {
            this.initialized = true;

            this.setup_initial_states = false;

            state_iteration_count = 1;

            if (parent_pixels.len > 0 and parent_pixels.len != parent_square_size * parent_square_size) {
                if (parent_pixels_buf.len < parent_square_size * parent_square_size) {
                    parent_pixels_buf = allocator.realloc(parent_pixels_buf, parent_square_size * parent_square_size) catch @panic("OOM");
                }

                parent_pixels = parent_pixels_buf[0 .. parent_square_size * parent_square_size];
            } else if (parent_pixels.len == 0) {
                parent_pixels_buf = allocator.alloc(render.Color, parent_square_size * parent_square_size) catch @panic("OOM");

                parent_pixels = parent_pixels_buf[0 .. parent_square_size * parent_square_size];
            }

            this.output_color_chunks_backing = allocator.alloc([]render.Color, parent_square_size * 2) catch @panic("OOM");

            const sub_square_size = parent_square_size / 2;

            for (&this.output_color_chunks, 0..) |*output_color_chunk, i| {
                output_color_chunk.* = this.output_color_chunks_backing[i * sub_square_size .. (i + 1) * sub_square_size];
            }

            for (&this.output_color_chunks, 0..) |output_color_chunk, i| {
                const x_offset = (i & 1) * sub_square_size;
                const y_offset = (i >> 1) * sub_square_size;

                for (0..parent_square_size / 2) |y| {
                    const offset_x = x_offset;
                    const offset_y = y + y_offset;

                    const start_idx = offset_y * (parent_square_size) + offset_x;

                    output_color_chunk[y] = parent_pixels[start_idx .. start_idx + sub_square_size];
                }
            }
        }

        fn deinitialize(this: *FillPixels) void {
            this.reset();

            filled_pixels = true;
        }

        fn reset(this: *FillPixels) void {
            allocator.free(this.output_color_chunks_backing);

            this.initialized = false;
        }

        pub fn iterate(this: *FillPixels, iteration_amount: usize) bool {
            if (this.initialized and state_iteration_count == 0) {
                this.reset();
            }

            if (!this.initialized) {
                this.initialize();

                return true;
            }

            // const start_time_outer = js.getTime();
            // defer {
            //     const end_time_outer = js.getTime();

            //     if (end_time_outer - start_time_outer > 3) {
            //         jsPrint("fillPixelsIterate time: {d} ms", .{end_time_outer - start_time_outer});
            //     }
            // }

            const sub_square_size = parent_square_size / 2;

            if (!this.setup_initial_states) {
                for (0..4) |i| {
                    if (offset_initial_states[i] == null) {
                        const start_time = js.getTime();

                        const initial_state = state_tree.stateAt(i, state_tree.quadrant_digits[i].length - 1) catch @panic("OOM");

                        // const tester = render.stateFromDigits(
                        //     render.SelfConsumingReaderState.init(0, root_color),
                        //     state_tree.quadrant_digits[i],
                        //     state_tree.quadrant_digits[i].length,
                        // );

                        // if (initial_state.color != tester.color) {
                        //     jsPrint("MISMATCH: {} {}", .{ initial_state.color, tester.color });
                        //     @panic("");
                        // }

                        const end_time = js.getTime();

                        if (end_time - start_time > 2) {
                            jsPrint("traverseFromRoot time: {d} ms", .{end_time - start_time});
                        }

                        offset_initial_states[i] = initial_state;
                    }

                    const initial_state = offset_initial_states[i].?;

                    const color_chunks = this.output_color_chunks[i];

                    if (iteration_states[i] == null) {
                        iteration_states[i] = render.FillIterationState.init(
                            allocator,
                            sub_square_size,
                            state_tree.quadrant_digits[i],
                            initial_state,
                            color_chunks,
                        ) catch @panic("OOM");
                    } else {
                        const start_time = js.getTime();

                        defer {
                            const end_time = js.getTime();

                            if (end_time - start_time > 2) {
                                jsPrint("iteration_states reset time: {d} ms", .{end_time - start_time});
                            }
                        }

                        iteration_states[i].?.reset(
                            sub_square_size,
                            state_tree.quadrant_digits[i],
                            initial_state,
                            color_chunks,
                        ) catch @panic("OOM");
                    }
                }

                this.setup_initial_states = true;

                return true;
            }

            var all_iterations_done = true;

            for (0..4) |i| {
                const iteration_state = &(iteration_states[i].?);

                const start_time = js.getTime();

                const temp = iteration_state.iterate(iteration_amount);

                const end_time = js.getTime();

                if (end_time - start_time > 2) {
                    jsPrint("iteration_state iterate time: {d} ms", .{end_time - start_time});
                }

                all_iterations_done = all_iterations_done and !temp;
            }

            if (!all_iterations_done) {
                return true;
            }

            this.deinitialize();

            return false;
        }
    };

    const RefreshDisplay = struct {
        initialized: bool,
        update_old_display: bool,
        display_pixels_copy_state: MemcpyIterationState(render.Color),
        old_display_pixels_copy_state: MemcpyIterationState(render.Color),
        started_filling_bitmap: bool,

        pub const init: RefreshDisplay = .{
            .initialized = false,
            .update_old_display = undefined,
            .display_pixels_copy_state = undefined,
            .old_display_pixels_copy_state = undefined,
            .started_filling_bitmap = false,
        };

        pub fn canIterate(this: RefreshDisplay) bool {
            _ = this; // autofix

            return filled_pixels;
        }

        fn initialize(this: *RefreshDisplay) void {
            this.initialized = true;

            if (display_pixels.len != parent_pixels.len) {
                if (display_pixels_buf.len < parent_pixels.len) {
                    if (display_pixels_buf.len == 0) {
                        display_pixels_buf = allocator.alloc(render.Color, parent_pixels.len) catch @panic("OOM");
                    } else {
                        display_pixels_buf = allocator.realloc(display_pixels_buf, parent_pixels.len) catch @panic("OOM");
                    }
                }

                display_pixels = display_pixels_buf[0..parent_pixels.len];
            }
            this.display_pixels_copy_state = MemcpyIterationState(render.Color).init(display_pixels, parent_pixels);

            const adjusted_old_display_square_size = @as(f64, @floatFromInt(old_display_square_size)) / old_display_client.zoom;
            const adjusted_display_square_size = @as(f64, @floatFromInt(parent_square_size)) / backup_client.zoom;

            const area_ratio = old_display_client.areaInViewportRatio();

            this.update_old_display = wait_until_backup or
                old_display_pixels.len == 0 or
                @as(f64, @floatFromInt(parent_square_size)) >= @min(@as(f64, @floatFromInt(old_display_square_size)), (@as(f64, @floatFromInt(old_display_square_size)) * old_display_client.zoom * 2)) or
                area_ratio == 0 or
                adjusted_old_display_square_size < adjusted_display_square_size;

            if (this.update_old_display) {
                if (old_display_pixels_buf.len < parent_pixels.len) {
                    if (old_display_pixels_buf.len == 0) {
                        old_display_pixels_buf = allocator.alloc(render.Color, parent_pixels.len) catch @panic("OOM");
                    } else {
                        old_display_pixels_buf = allocator.realloc(old_display_pixels_buf, parent_pixels.len) catch @panic("OOM");
                    }
                }

                old_display_pixels = old_display_pixels_buf[0..parent_pixels.len];

                this.old_display_pixels_copy_state = MemcpyIterationState(render.Color).init(old_display_pixels, parent_pixels);
            }
        }

        fn deinitialize(this: *RefreshDisplay) void {
            this.initialized = false;
            this.started_filling_bitmap = false;

            display_square_size = parent_square_size;

            filled_pixels = false;

            display_client = backup_client;

            if (this.update_old_display) {
                old_display_square_size = parent_square_size;
                old_display_client = backup_client;
            }

            wait_until_backup = false;

            if (parent_square_size < max_square_size) {
                parent_square_size *= 2;
                state_iteration_count = 0;
            }

            updated_pixels = true;

            renderPixels();
        }

        pub fn iterate(this: *RefreshDisplay, iteration_amount: usize) bool {
            if (!this.initialized) {
                this.initialize();

                return true;
            }

            const start_time = js.getTime();
            defer {
                const end_time = js.getTime();

                if (end_time - start_time > 1) {
                    jsPrint("refresh_display time: {d} ms", .{end_time - start_time});
                }
            }

            if (this.display_pixels_copy_state.iterate(iteration_amount)) {
                return true;
            }

            if (this.update_old_display) {
                if (this.old_display_pixels_copy_state.iterate(iteration_amount)) {
                    return true;
                }
            }

            if (!this.started_filling_bitmap) {
                if (this.update_old_display) {
                    js.fillImageBitmap(
                        display_pixels.ptr,
                        parent_square_size,
                        parent_square_size,
                        old_display_pixels.ptr,
                        parent_square_size,
                        parent_square_size,
                    );
                } else {
                    js.fillImageBitmap(
                        display_pixels.ptr,
                        parent_square_size,
                        parent_square_size,
                        old_display_pixels.ptr,
                        old_display_square_size,
                        old_display_square_size,
                    );
                }
                this.started_filling_bitmap = true;
            }

            if (!js.imageBitmapFilled()) {
                return true;
            }

            this.deinitialize();

            return false;
        }
    };

    pub fn cycle(this: *WorkCycleState, iteration_amount: usize) bool {
        if (parent_square_size < 2) {
            parent_square_size = 2;
            state_iteration_count = 0;

            return true;
        }

        if (this.refresh_display.canIterate()) {
            if (this.refresh_display.iterate(iteration_amount)) {
                return true;
            }
        }

        if (this.update_position.canIterate()) {
            if (this.update_position.iterate(iteration_amount)) {
                return true;
            }
        }

        if (this.fill_pixels.canIterate()) {
            if (this.fill_pixels.iterate(iteration_amount)) {
                return true;
            }
        }

        return false;
    }
};

fn MemcpyIterationState(comptime T: type) type {
    return struct {
        dst: []T,
        src: []T,
        idx: usize,

        const Self = @This();

        pub fn init(noalias dst: []T, noalias src: []T) Self {
            return .{
                .dst = dst,
                .src = src,
                .idx = 0,
            };
        }

        pub fn iterate(this: *Self, iteration_amount_arg: usize) bool {
            const iteration_amount = iteration_amount_arg * 100;

            const copies_left = this.dst.len - this.idx;

            if (copies_left <= iteration_amount) {
                if (copies_left > 0) {
                    @memcpy(this.dst[this.idx .. this.idx + copies_left], this.src[this.idx .. this.idx + copies_left]);
                    this.idx += copies_left;
                }

                return false;
            }

            @memcpy(this.dst[this.idx .. this.idx + iteration_amount], this.src[this.idx .. this.idx + iteration_amount]);

            this.idx += iteration_amount;

            return true;
        }
    };
}

var work_cycle_state = WorkCycleState.init;

export fn workCycle() bool {
    return work_cycle_state.cycle(iteration_rate);
}

export fn init() void {
    state_tree = render.StateStems.init(allocator, root_color) catch @panic("OOM");

    const square_size = 256;

    const starting_colors = allocator.alloc(render.Color, square_size * square_size) catch @panic("OOM");
    defer allocator.free(starting_colors);

    for (starting_colors, 0..) |*color, i| {
        const x = i % square_size;
        const y = i / square_size;

        const radius: comptime_float = square_size / 2;
        const center_x: comptime_float = square_size / 2;
        const center_y: comptime_float = square_size / 2;

        // Calculate distance from the center
        const dx = @as(isize, @intCast(x)) - @as(isize, @intFromFloat(center_x));
        const dy = @as(isize, @intCast(y)) - @as(isize, @intFromFloat(center_y));
        const distance_squared = dx * dx + dy * dy;

        // Define eye properties
        const eye_radius = radius / 8.0;
        const eye_offset_x = radius / 2.0;
        const eye_offset_y = radius / 3.0;

        // Left eye center
        const left_eye_x = center_x - eye_offset_x;
        const left_eye_y = center_y - eye_offset_y;

        // Right eye center
        const right_eye_x = center_x + eye_offset_x;
        const right_eye_y = center_y - eye_offset_y;

        // Mouth properties
        const mouth_radius = radius / 1.5;
        const mouth_center_y = center_y + radius / 4.0;

        const dx_left_eye = @as(isize, @intCast(x)) - @as(isize, @intFromFloat(left_eye_x));
        const dy_left_eye = @as(isize, @intCast(y)) - @as(isize, @intFromFloat(left_eye_y));
        const distance_left_eye = dx_left_eye * dx_left_eye + dy_left_eye * dy_left_eye;

        const dx_right_eye = @as(isize, @intCast(x)) - @as(isize, @intFromFloat(right_eye_x));
        const dy_right_eye = @as(isize, @intCast(y)) - @as(isize, @intFromFloat(right_eye_y));
        const distance_right_eye = dx_right_eye * dx_right_eye + dy_right_eye * dy_right_eye;

        const dx_mouth = @as(isize, @intCast(x)) - @as(isize, @intFromFloat(center_x));
        const dy_mouth = @as(isize, @intCast(y)) - @as(isize, @intFromFloat(mouth_center_y));
        const distance_mouth = dx_mouth * dx_mouth + dy_mouth * dy_mouth;

        const is_in_face = distance_squared <= radius * radius;
        const is_in_left_eye = distance_left_eye <= eye_radius * eye_radius;
        const is_in_right_eye = distance_right_eye <= eye_radius * eye_radius;
        const is_in_mouth_arc = (distance_mouth >= @as(isize, @intFromFloat(mouth_radius * 0.7 * mouth_radius * 0.7))) and (distance_mouth <= @as(isize, @intFromFloat(mouth_radius * mouth_radius))) and (dy_mouth > 0); // Only draw lower half of the circle for the mouth

        // Assign colors based on position in smiley face features
        color.* = if (is_in_face) .{
            .r = if (is_in_left_eye or is_in_right_eye) 0 else if (is_in_mouth_arc) 255 else 255,
            .g = if (is_in_left_eye or is_in_right_eye or is_in_mouth_arc) 0 else 255,
            .b = if (is_in_left_eye or is_in_right_eye or is_in_mouth_arc) 0 else 0,
            .a = 255,
        } else .{
            .r = 123,
            .g = 100,
            .b = 100,
            .a = 255,
        };

        // Assign colors based on position in smiley face features

        // color.* = if (is_in_face) .{
        //     .r = if (is_in_left_eye or is_in_right_eye) 0 else if (is_in_mouth_arc) 0 else 127,
        //     .g = if (is_in_left_eye or is_in_right_eye or is_in_mouth_arc) 0 else 0,
        //     .b = if (is_in_left_eye or is_in_right_eye or is_in_mouth_arc) 0 else 0,
        //     .a = 255,
        // } else .{
        //     .r = 120,
        //     .g = 0,
        //     .b = 0,
        //     .a = 255,
        // };
    }

    // for (0..4) |i| {
    //     state_tree.appendDigit(i, 0) catch @panic("OOM");
    // }

    // for (0..1000000) |_| {
    //     for (0..4) |i| {
    //         state_tree.appendDigit(i, 1) catch @panic("OOM");
    //     }
    // }

    // const color_file = @embedFile("output_image_small.bin");
    // @memcpy(std.mem.sliceAsBytes(starting_colors), color_file);

    // var enc = render.encodeColors(allocator, starting_colors) catch @panic("OOM");
    // defer enc.deinit(allocator);

    // for (0..enc.length) |i| {
    //     const digit = enc.get(i);
    //     for (0..4) |j| {
    //         state_tree.appendDigit(j, digit) catch @panic("OOM");
    //     }
    // }

    for (0..4) |i| {
        state_tree.appendDigit(i, @intCast(i)) catch @panic("OOM");
    }
}

var offset_digits_packed_with_digit_offset: []u8 = &.{};
var offset_digits_packed: []u8 = &.{};

export fn setOffsetAlloc(size: usize) [*]u8 {
    std.debug.assert(size >= 1);

    offset_digits_packed_with_digit_offset = allocator.alloc(u8, size) catch @panic("OOM");
    offset_digits_packed = offset_digits_packed_with_digit_offset[0 .. offset_digits_packed_with_digit_offset.len - 1];
    return offset_digits_packed_with_digit_offset.ptr;
}

export fn setOffset() void {
    state_iteration_count = 0;
    // iteration_done = false;
    position_dirty = true;

    wait_until_backup = true;

    backup_client.offset_x = 0;
    backup_client.offset_y = 0;
    backup_client.zoom = 1;
    parent_square_size = 64;

    offset_initial_states = @splat(null);

    defer allocator.free(offset_digits_packed_with_digit_offset);

    const digit_offset = offset_digits_packed_with_digit_offset[offset_digits_packed_with_digit_offset.len - 1];

    const offset_digits_packed_count = (offset_digits_packed.len * 4) -
        ((4 - (digit_offset % 4)) % 4);

    state_tree.clearDigits();

    for (offset_digits_packed, 0..) |packed_digit, i| {
        for (0..4) |j| {
            const idx = i * 4 + j;
            if (idx < offset_digits_packed_count) {
                // new_offset_digits[i * 4 + j] = @intCast((packed_digit >> @intCast(j * 2)) & 0b11);
                const digit: u2 = @intCast((packed_digit >> @intCast(j * 2)) & 0b11);
                for (0..4) |quadrant| {
                    state_tree.appendDigit(quadrant, digit) catch @panic("OOM");
                }
            }
        }
    }

    const max_x = state_tree.quadrant_digits[0].isMaxX();
    const max_y = state_tree.quadrant_digits[0].isMaxY();

    for (0..4) |i| {
        if (max_x) {
            if (i & 1 == 0) {
                state_tree.decrementX(i);
            }
        } else {
            if (i & 1 == 1) {
                state_tree.incrementX(i);
            }
        }

        if (max_y) {
            if (i >> 1 == 0) {
                state_tree.decrementY(i);
            }
        } else {
            if (i >> 1 == 1) {
                state_tree.incrementY(i);
            }
        }
    }

    state_tree.trim(state_tree.quadrant_digits[0].length);
}

var find_image_data: []render.Color = &.{};

export fn findImageAlloc(size: usize) [*]render.Color {
    std.debug.assert(size >= 1);

    find_image_data = allocator.alloc(render.Color, @divExact(size, 4)) catch @panic("OOM");

    return find_image_data.ptr;
}

export fn findImage() void {
    state_iteration_count = 0;
    // iteration_done = false;
    position_dirty = true;

    wait_until_backup = true;

    backup_client.offset_x = 0;
    backup_client.offset_y = 0;

    backup_client.zoom = 1;
    parent_square_size = 64;

    backup_client.move(@as(f64, @floatFromInt(backup_client.canvas_width)) / 4.0, @as(f64, @floatFromInt(backup_client.canvas_height)) / 4.0);

    offset_initial_states = @splat(null);

    var enc = render.encodeColors(allocator, find_image_data) catch @panic("OOM");
    defer enc.deinit(allocator);

    allocator.free(find_image_data);

    state_tree.clearDigits();
    for (0..enc.length) |i| {
        const digit = enc.get(i);
        for (0..4) |j| {
            state_tree.appendDigit(j, digit) catch @panic("OOM");
        }
    }

    for (0..4) |i| {
        state_tree.appendDigit(i, @intCast(i)) catch @panic("OOM");
    }

    state_tree.trim(state_tree.quadrant_digits[0].length);
}

export fn getOffsetAlloc() [*]u8 {
    offset_digits_packed_with_digit_offset = allocator.alloc(u8, ((state_tree.quadrant_digits[0].length + 3) / 4) + 1) catch @panic("OOM");
    offset_digits_packed = offset_digits_packed_with_digit_offset[0 .. offset_digits_packed_with_digit_offset.len - 1];

    for (offset_digits_packed, 0..) |*packed_digit, i| {
        packed_digit.* = 0;
        for (0..4) |j| {
            // const idx = ((i + 1) * 4 - j - 1);
            const idx = i * 4 + j;
            if (idx < state_tree.quadrant_digits[0].length) {
                const offset_digit = state_tree.quadrant_digits[0].get(idx);
                packed_digit.* |= @as(u8, offset_digit) << @intCast(j * 2);
            }
        }
    }

    offset_digits_packed_with_digit_offset[offset_digits_packed_with_digit_offset.len - 1] = @intCast(state_tree.quadrant_digits[0].length % 4);

    return offset_digits_packed_with_digit_offset.ptr;
}

export fn getOffsetLen() usize {
    return offset_digits_packed_with_digit_offset.len;
}

export fn getOffsetFree() void {
    allocator.free(offset_digits_packed_with_digit_offset);
}
