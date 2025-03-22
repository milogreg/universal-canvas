const std = @import("std");
const render = @import("render.zig");

const js = struct {
    extern fn printString(ptr: [*]const u8, len: usize) void;

    extern fn getTime() f64;

    extern fn fillImageBitmap(
        pixels: [*]render.Color,
        width: usize,
        height: usize,
    ) void;

    extern fn imageBitmapFilled() bool;

    extern fn renderImage(
        offset_x: f64,
        offset_y: f64,
        zoom: f64,
        clip_x: f64,
        clip_y: f64,
        clip_width: f64,
        clip_height: f64,
        updated_pixels: bool,
        max_detail: bool,
        version: u64,
    ) void;
};

fn panicFn(
    msg: []const u8,
    first_trace_addr: ?usize,
) noreturn {
    @branchHint(.cold);

    _ = first_trace_addr; // autofix

    var panic_msg_buf: [1000]u8 = undefined;

    const panic_msg = std.fmt.bufPrint(&panic_msg_buf, "panic: {s}", .{msg}) catch msg;

    js.printString(panic_msg.ptr, panic_msg.len);

    @trap();
}

pub const panic = std.debug.FullPanic(panicFn);

const allocator: std.mem.Allocator = std.heap.wasm_allocator;

// const allocator: std.mem.Allocator = std.heap.page_allocator;

fn jsPrint(comptime fmt: []const u8, args: anytype) void {
    const to_print = std.fmt.allocPrint(allocator, fmt, args) catch @panic("OOM");
    defer allocator.free(to_print);
    js.printString(to_print.ptr, to_print.len);
}

var state_tree: render.StateStems = undefined;

var iteration_states: [4]?render.FillIterationState = @splat(null);

const iteration_rate = 1000000;
// const iteration_rate = 300;

var state_iteration_count: usize = 1;

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

var parent_pixels_width: usize = 0;
var parent_pixels_height: usize = 0;

var display_pixels_buf: []render.Color = &.{};
var display_pixels: []render.Color = &.{};

var updated_pixels = false;
var position_dirty = false;
var filled_pixels = false;

var pixel_ratio: f64 = 1;

const base_zoom_multiplier = 1;

var pixels_clean_region: [2][2]usize = undefined;
var pixels_offsets: ?[2]isize = null;

var backup_client_version: u64 = 0;

var backup_client: ClientPosition = .{
    .zoom = 1,
    .offset_x = 0,
    .offset_y = 0,
    .canvas_width = 1,
    .canvas_height = 1,
};

var initial_display_client: ClientPosition = .{
    .zoom = 1,
    .offset_x = 0,
    .offset_y = 0,
    .canvas_width = 1,
    .canvas_height = 1,
};

var display_client: ClientPosition = .{
    .zoom = 1,
    .offset_x = 0,
    .offset_y = 0,
    .canvas_width = 1,
    .canvas_height = 1,
};

const ClientPosition = struct {
    zoom: f64,
    offset_x: f64,
    offset_y: f64,

    canvas_width: usize,
    canvas_height: usize,

    pub fn updatePosition(this: *ClientPosition, mouse_x: f64, mouse_y: f64, zoom_delta: f64) void {
        this.zoom *= zoom_delta;
        this.offset_x = mouse_x - (mouse_x - this.offset_x) * zoom_delta;
        this.offset_y = mouse_y - (mouse_y - this.offset_y) * zoom_delta;
    }

    pub fn movePixels(this: *ClientPosition, offset_x: isize, offset_y: isize, units_per_pixel: f64) void {
        this.offset_x += @as(f64, @floatFromInt(offset_x)) * units_per_pixel * this.zoom;
        this.offset_y += @as(f64, @floatFromInt(offset_y)) * units_per_pixel * this.zoom;
    }

    pub fn removeDigit(this: *ClientPosition, digit: u2, units_per_pixel: f64) void {
        this.zoom *= 2;

        const move_x: isize = @intCast(digit & 1);
        const move_y: isize = @intCast(digit >> 1);

        this.movePixels(-move_x, -move_y, units_per_pixel);
    }
};

fn digitIncrement(digit: u2) void {
    if (digit & 1 == 1) {
        state_tree.incrementX();
    }
    if (digit >> 1 == 1) {
        state_tree.incrementY();
    }
}

fn digitDecrement(digit: u2) void {
    if (digit & 1 == 1) {
        state_tree.decrementX();
    }
    if (digit >> 1 == 1) {
        state_tree.decrementY();
    }
}

var wait_until_backup = true;

var has_max_detail = false;

export fn renderPixels() void {
    const repeat = !(backup_client.offset_x == display_client.offset_x and
        backup_client.offset_y == display_client.offset_y and
        backup_client.zoom == display_client.zoom and
        backup_client.canvas_width == display_client.canvas_width and
        backup_client.canvas_height == display_client.canvas_height);

    const position_mutation = diffPositionMutation(initial_display_client, display_client);

    backup_client = applyPositionMutation(backup_client, position_mutation);

    // const width_diff = @as(f64, @floatFromInt(display_client.canvas_width)) - @as(f64, @floatFromInt(backup_client.canvas_width));
    // const height_diff = @as(f64, @floatFromInt(display_client.canvas_height)) - @as(f64, @floatFromInt(backup_client.canvas_height));

    // backup_client.offset_x += (width_diff * backup_client.zoom) / 2;
    // backup_client.offset_y += (height_diff * backup_client.zoom) / 2;

    backup_client_version &= ~(@as(u64, 1));

    backup_client_version |= @intFromBool(repeat);

    // jsPrint("repeat: {}", .{repeat});

    js.renderImage(
        backup_client.offset_x,
        backup_client.offset_y,
        backup_client.zoom,

        @floatFromInt(pixels_clean_region[0][0]),
        @floatFromInt(pixels_clean_region[0][1]),

        @floatFromInt(pixels_clean_region[1][0] - pixels_clean_region[0][0]),
        @floatFromInt(pixels_clean_region[1][1] - pixels_clean_region[0][1]),

        updated_pixels and !wait_until_backup,
        has_max_detail,
        backup_client_version,
    );

    // backup_client_version |= @intFromBool(position_dirty);

    // jsPrint("position_dirty: {}", .{position_dirty});

    updated_pixels = false;
}

export fn updatePosition(offset_x: f64, offset_y: f64, zoom: f64, viewport_width: f64, viewport_height: f64, version: u64) void {
    display_client = .{
        .canvas_width = @intFromFloat(viewport_width),
        .canvas_height = @intFromFloat(viewport_height),
        .offset_x = offset_x,
        .offset_y = offset_y,
        .zoom = zoom,
    };

    if (version == backup_client_version) {
        position_dirty = true;

        backup_client = display_client;

        initial_display_client = display_client;

        parent_pixels_width = @intFromFloat(@as(f64, @floatFromInt(display_client.canvas_width)) / pixel_ratio);
        parent_pixels_height = @intFromFloat(@as(f64, @floatFromInt(display_client.canvas_height)) / pixel_ratio);

        backup_client_version &= ~@as(u64, 1);

        backup_client_version += 2;
    }
}

export fn resetPosition(viewport_width: f64, viewport_height: f64) void {
    state_iteration_count = 0;

    position_dirty = true;

    wait_until_backup = true;

    filled_pixels = false;

    pixels_offsets = null;

    backup_client.canvas_width = @intFromFloat(viewport_width);
    backup_client.canvas_height = @intFromFloat(viewport_height);

    parent_pixels_width = @intFromFloat(@as(f64, @floatFromInt(backup_client.canvas_width)) / pixel_ratio);
    parent_pixels_height = @intFromFloat(@as(f64, @floatFromInt(backup_client.canvas_height)) / pixel_ratio);

    backup_client.offset_x = (@as(f64, @floatFromInt(backup_client.canvas_width)) -
        @as(f64, @floatFromInt(((std.math.ceilPowerOfTwo(usize, @min(parent_pixels_width, parent_pixels_height)) catch unreachable) / 2)))) * (pixel_ratio / 2.0);
    backup_client.offset_y = (@as(f64, @floatFromInt(backup_client.canvas_height)) -
        @as(f64, @floatFromInt(((std.math.ceilPowerOfTwo(usize, @min(parent_pixels_width, parent_pixels_height)) catch unreachable) / 2)))) * (pixel_ratio / 2.0);
    backup_client.zoom = 1;

    state_tree.clearDigits();

    for (0..std.math.log2_int_ceil(usize, @max(4, @min(parent_pixels_width, parent_pixels_height))) - 1) |_| {
        state_tree.appendDigit(0) catch @panic("OOM");
    }
}

fn printDigits() void {
    const num_to_print = 10;

    const digits = state_tree.digits;

    var list1 = std.ArrayList(u2).init(allocator);
    defer list1.deinit();

    for (0..@min(num_to_print, digits.length)) |i| {
        const digit = digits.get(i);

        list1.append(digit) catch @panic("OOM");
    }

    var list2 = std.ArrayList(u2).init(allocator);
    defer list2.deinit();

    for (digits.length -| num_to_print..digits.length) |i| {
        const digit = digits.get(i);

        list2.append(digit) catch @panic("OOM");
    }

    jsPrint("digits: {any} ... {any}", .{ list1.items, list2.items });
}

const PositionMutation = struct {
    offset_x: f64,
    offset_y: f64,
    zoom: f64,
};

fn diffPositionMutation(start: ClientPosition, end: ClientPosition) PositionMutation {
    const zoom = end.zoom / start.zoom;

    return .{
        .offset_x = end.offset_x - start.offset_x * zoom,
        .offset_y = end.offset_y - start.offset_y * zoom,
        .zoom = zoom,
    };
}

fn applyPositionMutation(position: ClientPosition, mutation: PositionMutation) ClientPosition {
    return .{
        .offset_x = position.offset_x * mutation.zoom + mutation.offset_x,
        .offset_y = position.offset_y * mutation.zoom + mutation.offset_y,
        .zoom = position.zoom * mutation.zoom,
        .canvas_width = position.canvas_width,
        .canvas_height = position.canvas_height,
    };
}

fn digitPositionMutation(position: ClientPosition) PositionMutation {
    var position_updated = position;

    for (1..state_tree.digits.length) |i| {
        if (position_updated.zoom >= 1 * base_zoom_multiplier) {
            break;
        }

        const idx = state_tree.digits.length - i;

        const last_digit = state_tree.digits.get(idx);

        const move_x_pixels: f64 = @floatFromInt(last_digit & 1);
        const move_y_pixels: f64 = @floatFromInt(last_digit >> 1);

        const move_x = move_x_pixels;
        const move_y = move_y_pixels;

        position_updated.zoom *= 2;

        position_updated.offset_x += move_x * position_updated.zoom * pixel_ratio;
        position_updated.offset_y += move_y * position_updated.zoom * pixel_ratio;
    }

    while (position_updated.zoom >= 2 * base_zoom_multiplier) {
        position_updated.zoom /= 2;
    }

    {
        var move_x: isize = 0;
        var move_y: isize = 0;

        const base_offset_x = @max(0.0, @as(f64, @floatFromInt(position_updated.canvas_width)) * base_zoom_multiplier - @as(f64, @floatFromInt(position_updated.canvas_width))) / 2.0;

        const adjusted_offset_x: isize = @intFromFloat(@round((-(position_updated.offset_x + base_offset_x) / position_updated.zoom) / pixel_ratio));

        if (adjusted_offset_x > 0) {
            const to_add = @abs(adjusted_offset_x);

            move_x = @as(isize, @intCast(to_add));
        } else if (adjusted_offset_x < 0) {
            const to_subtract = @abs(adjusted_offset_x);

            move_x = -@as(isize, @intCast(to_subtract));
        }

        const base_offset_y = @max(0.0, @as(f64, @floatFromInt(position_updated.canvas_height)) * base_zoom_multiplier - @as(f64, @floatFromInt(position_updated.canvas_height))) / 2.0;

        const adjusted_offset_y: isize = @intFromFloat(@round((-(position_updated.offset_y + base_offset_y) / position_updated.zoom) / pixel_ratio));

        if (adjusted_offset_y > 0) {
            const to_add = @abs(adjusted_offset_y);

            move_y = @as(isize, @intCast(to_add));
        } else if (adjusted_offset_y < 0) {
            const to_subtract = @abs(adjusted_offset_y);

            move_y = -@as(isize, @intCast(to_subtract));
        }

        position_updated.offset_x += @as(f64, @floatFromInt(move_x)) * position_updated.zoom * pixel_ratio;
        position_updated.offset_y += @as(f64, @floatFromInt(move_y)) * position_updated.zoom * pixel_ratio;
    }

    var initial_res: PositionMutation = .{
        .offset_x = @round((position_updated.offset_x - position.offset_x) / (pixel_ratio * position.zoom)),
        .offset_y = @round((position_updated.offset_y - position.offset_y) / (pixel_ratio * position.zoom)),
        .zoom = position_updated.zoom / position.zoom,
    };

    initial_res.offset_x = @min(initial_res.offset_x, @as(f64, @floatFromInt(state_tree.diffToMaxX())));
    initial_res.offset_y = @min(initial_res.offset_y, @as(f64, @floatFromInt(state_tree.diffToMaxY())));

    initial_res.offset_x = @max(initial_res.offset_x, -@as(f64, @floatFromInt(state_tree.diffToMinX())));
    initial_res.offset_y = @max(initial_res.offset_y, -@as(f64, @floatFromInt(state_tree.diffToMinY())));

    position_updated = .{
        .offset_x = position.offset_x + position.zoom * initial_res.offset_x * pixel_ratio,
        .offset_y = position.offset_y + position.zoom * initial_res.offset_y * pixel_ratio,
        .zoom = position.zoom * initial_res.zoom,
        .canvas_width = position.canvas_width,
        .canvas_height = position.canvas_height,
    };

    return diffPositionMutation(position, position_updated);
}

fn applyDigitPositionMutation(position: ClientPosition, position_mutation_init: PositionMutation) void {
    const mutated_position = applyPositionMutation(position, position_mutation_init);

    const digits_move_x: isize = @intFromFloat(@round((mutated_position.offset_x - position.offset_x) / (pixel_ratio * position.zoom)));
    const digits_move_y: isize = @intFromFloat(@round((mutated_position.offset_y - position.offset_y) / (pixel_ratio * position.zoom)));

    if (digits_move_x > 0) {
        state_tree.addX(@intCast(digits_move_x));
    } else {
        state_tree.subtractX(@intCast(-digits_move_x));
    }

    if (digits_move_y > 0) {
        state_tree.addY(@intCast(digits_move_y));
    } else {
        state_tree.subtractY(@intCast(-digits_move_y));
    }

    const add_or_remove_count_float = @round(std.math.log2(mutated_position.zoom / position.zoom));

    if (std.math.isFinite(add_or_remove_count_float)) {
        const add_or_remove_count: isize = @intFromFloat(add_or_remove_count_float);
        if (add_or_remove_count != 0) {
            pixels_offsets = null;
            if (add_or_remove_count > 0) {
                for (0..@intCast(add_or_remove_count)) |_| {
                    state_tree.removeDigit();
                }
            } else {
                for (0..@intCast(-add_or_remove_count)) |_| {
                    state_tree.appendDigit(0) catch @panic("OOM");
                }
            }
        }
    }

    if (pixels_offsets) |*pixels_offsets_unwrapped| {
        pixels_offsets_unwrapped[0] -= digits_move_x;
        pixels_offsets_unwrapped[1] -= digits_move_y;
    }
}

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

            const position_mutation = digitPositionMutation(backup_client);

            applyDigitPositionMutation(backup_client, position_mutation);

            backup_client = applyPositionMutation(backup_client, position_mutation);

            state_iteration_count = 0;
            filled_pixels = false;
            position_dirty = false;

            return false;
        }
    };

    const FillPixels = struct {
        initialized: bool,
        rect_iteration_state: ?render.FillRectIterationState,
        regions: ?[4]struct {
            start_x: usize,
            end_x: usize,
            start_y: usize,
            end_y: usize,
        },
        current_region: usize,

        pub const init: FillPixels = .{
            .initialized = false,
            .rect_iteration_state = null,
            .regions = null,
            .current_region = 0,
        };

        pub fn canIterate(this: FillPixels) bool {
            return (this.initialized or state_iteration_count == 0) and !filled_pixels;
        }

        fn initialize(this: *FillPixels) void {
            this.initialized = true;

            state_iteration_count = 1;

            const new_parent_pixels_len = (parent_pixels_width) * (parent_pixels_height);

            if (parent_pixels.len > 0 and parent_pixels.len != new_parent_pixels_len) {
                if (parent_pixels_buf.len < new_parent_pixels_len) {
                    parent_pixels_buf = allocator.realloc(parent_pixels_buf, new_parent_pixels_len) catch @panic("OOM");
                }

                parent_pixels = parent_pixels_buf[0..new_parent_pixels_len];

                pixels_offsets = null;
            } else if (parent_pixels.len == 0) {
                parent_pixels_buf = allocator.alloc(render.Color, new_parent_pixels_len) catch @panic("OOM");

                parent_pixels = parent_pixels_buf[0..new_parent_pixels_len];

                pixels_offsets = null;
            }

            // @memset(parent_pixels, .{
            //     .r = 0,
            //     .g = 0,
            //     .b = 255,
            //     .a = 60,
            // });
        }

        fn deinitialize(this: *FillPixels) void {
            this.reset();

            filled_pixels = true;
        }

        fn reset(this: *FillPixels) void {
            if (this.rect_iteration_state) |*rect_state| {
                allocator.free(rect_state.output_colors);
                rect_state.deinit();
            }

            this.initialized = false;
            this.rect_iteration_state = null;
            this.regions = null;
            this.current_region = 0;
        }

        pub fn iterate(this: *FillPixels, iteration_amount: usize) bool {
            _ = iteration_amount; // autofix
            if (this.initialized and state_iteration_count == 0) {
                this.reset();
            }

            if (!this.initialized) {
                this.initialize();

                return true;
            }

            var temp_client = backup_client;

            temp_client.updatePosition(@as(f64, @floatFromInt(temp_client.canvas_width)) / 2.0, @as(f64, @floatFromInt(temp_client.canvas_height)) / 2.0, @as(f64, 1.0) / base_zoom_multiplier);

            const region_clip_min_x_float = @max(0, -temp_client.offset_x / ((temp_client.zoom * pixel_ratio)));
            var region_clip_min_x: usize = @intFromFloat(region_clip_min_x_float);

            const region_clip_min_y_float = @max(0, -temp_client.offset_y / ((temp_client.zoom * pixel_ratio)));
            var region_clip_min_y: usize = @intFromFloat(region_clip_min_y_float);

            const region_clip_width: usize = @intFromFloat(@ceil(@as(f64, @floatFromInt(parent_pixels_width)) / temp_client.zoom));
            const region_clip_height: usize = @intFromFloat(@ceil(@as(f64, @floatFromInt(parent_pixels_height)) / temp_client.zoom));

            var region_clip_max_x = @min(state_tree.diffToMaxX() +| 1, parent_pixels_width, region_clip_min_x + region_clip_width + 1);
            var region_clip_max_y = @min(state_tree.diffToMaxY() +| 1, parent_pixels_height, region_clip_min_y + region_clip_height + 1);

            if (region_clip_min_x > region_clip_max_x or region_clip_min_y > region_clip_max_y) {
                region_clip_min_x = 0;
                region_clip_min_y = 0;

                region_clip_max_x = 0;
                region_clip_max_y = 0;
            }

            // Initialize regions if not already done
            if (this.regions == null) {
                // if (pixels_offsets) |pixels_offsets_unwrapped| {
                //     const temp_pixels = allocator.alloc(render.Color, parent_pixels.len) catch @panic("OOM");
                //     defer allocator.free(temp_pixels);

                //     for (0..parent_pixels_height) |old_y| {
                //         for (0..parent_pixels_width) |old_x| {
                //             const new_x = @as(isize, @intCast(old_x)) + pixels_offsets_unwrapped[0];
                //             const new_y = @as(isize, @intCast(old_y)) + pixels_offsets_unwrapped[1];

                //             if (new_x >= 0 and new_x < parent_pixels_width and new_y >= 0 and new_y < parent_pixels_height) {
                //                 temp_pixels[@intCast(new_y * @as(isize, @intCast(parent_pixels_width)) + new_x)] = parent_pixels[old_y * (parent_pixels_width) + old_x];
                //             }
                //         }
                //     }

                //     @memset(parent_pixels_buf, .{
                //         .r = 255,
                //         .g = 0,
                //         .b = 0,
                //         .a = 50,
                //     });

                //     for (0..parent_pixels_height) |old_y| {
                //         for (0..parent_pixels_width) |old_x| {
                //             const new_x = @as(isize, @intCast(old_x)) + pixels_offsets_unwrapped[0];
                //             const new_y = @as(isize, @intCast(old_y)) + pixels_offsets_unwrapped[1];

                //             if (new_x >= 0 and new_x < parent_pixels_width and new_y >= 0 and new_y < parent_pixels_height) {
                //                 parent_pixels[@intCast(new_y * @as(isize, @intCast(parent_pixels_width)) + new_x)] = temp_pixels[@intCast(new_y * @as(isize, @intCast(parent_pixels_width)) + new_x)];
                //             }
                //         }
                //     }
                // }

                if (pixels_offsets) |pixels_offsets_unwrapped| {
                    const temp_pixels = allocator.alloc(render.Color, parent_pixels.len) catch @panic("OOM");
                    defer allocator.free(temp_pixels);

                    for (pixels_clean_region[0][1]..pixels_clean_region[1][1]) |old_y| {
                        for (pixels_clean_region[0][0]..pixels_clean_region[1][0]) |old_x| {
                            const new_x = @as(isize, @intCast(old_x)) + pixels_offsets_unwrapped[0];
                            const new_y = @as(isize, @intCast(old_y)) + pixels_offsets_unwrapped[1];

                            if (new_x >= 0 and new_x < parent_pixels_width and new_y >= 0 and new_y < parent_pixels_height) {
                                temp_pixels[@intCast(new_y * @as(isize, @intCast(parent_pixels_width)) + new_x)] = parent_pixels[old_y * (parent_pixels_width) + old_x];
                            }
                        }
                    }

                    // @memset(parent_pixels_buf, .{
                    //     .r = 255,
                    //     .g = 0,
                    //     .b = 0,
                    //     .a = 50,
                    // });

                    for (pixels_clean_region[0][1]..pixels_clean_region[1][1]) |old_y| {
                        for (pixels_clean_region[0][0]..pixels_clean_region[1][0]) |old_x| {
                            const new_x = @as(isize, @intCast(old_x)) + pixels_offsets_unwrapped[0];
                            const new_y = @as(isize, @intCast(old_y)) + pixels_offsets_unwrapped[1];

                            if (new_x >= 0 and new_x < parent_pixels_width and new_y >= 0 and new_y < parent_pixels_height) {
                                parent_pixels[@intCast(new_y * @as(isize, @intCast(parent_pixels_width)) + new_x)] = temp_pixels[@intCast(new_y * @as(isize, @intCast(parent_pixels_width)) + new_x)];
                            }
                        }
                    }
                }

                var clean_pixel_range_x: [2]usize = @splat(0);
                var clean_pixel_range_y: [2]usize = @splat(0);

                // if (pixels_offsets) |pixels_offsets_unwrapped| {
                //     if (@abs(pixels_offsets_unwrapped[0]) < parent_pixels_width and @abs(pixels_offsets_unwrapped[1]) < parent_pixels_height) {
                //         if (pixels_offsets_unwrapped[0] < 0) {
                //             clean_pixel_range_x = .{
                //                 0,
                //                 @intCast(@as(isize, @intCast(parent_pixels_width)) + pixels_offsets_unwrapped[0]),
                //             };
                //         } else {
                //             clean_pixel_range_x = .{
                //                 @intCast(pixels_offsets_unwrapped[0]),
                //                 parent_pixels_width,
                //             };
                //         }

                //         if (pixels_offsets_unwrapped[1] < 0) {
                //             clean_pixel_range_y = .{
                //                 0,
                //                 @intCast(@as(isize, @intCast(parent_pixels_height)) + pixels_offsets_unwrapped[1]),
                //             };
                //         } else {
                //             clean_pixel_range_y = .{
                //                 @intCast(pixels_offsets_unwrapped[1]),
                //                 parent_pixels_height,
                //             };
                //         }
                //     }
                // }

                if (pixels_offsets) |pixels_offsets_unwrapped| {
                    const pixel_offset_x = pixels_offsets_unwrapped[0];
                    const pixel_offset_y = pixels_offsets_unwrapped[1];

                    const pixels_clean_region_start_x: isize = @intCast(pixels_clean_region[0][0]);
                    const pixels_clean_region_end_x: isize = @intCast(pixels_clean_region[1][0]);

                    const pixels_clean_region_start_y: isize = @intCast(pixels_clean_region[0][1]);
                    const pixels_clean_region_end_y: isize = @intCast(pixels_clean_region[1][1]);

                    clean_pixel_range_x = .{
                        @intCast(@max(0, pixels_clean_region_start_x + pixel_offset_x)),
                        @intCast(@max(0, @min(@as(isize, @intCast(parent_pixels_width)), pixels_clean_region_end_x + pixel_offset_x))),
                    };

                    clean_pixel_range_y = .{
                        @intCast(@max(0, pixels_clean_region_start_y + pixel_offset_y)),
                        @intCast(@max(0, @min(@as(isize, @intCast(parent_pixels_height)), pixels_clean_region_end_y + pixel_offset_y))),
                    };
                }

                const pixel_width = parent_pixels_width;
                const pixel_height = parent_pixels_height;

                this.regions = .{
                    // Top region
                    .{
                        .start_x = 0,
                        .end_x = pixel_width,
                        .start_y = 0,
                        .end_y = clean_pixel_range_y[0],
                    },
                    // Bottom region
                    .{
                        .start_x = 0,
                        .end_x = pixel_width,
                        .start_y = clean_pixel_range_y[1],
                        .end_y = pixel_height,
                    },
                    // Left region (middle)
                    .{
                        .start_x = 0,
                        .end_x = clean_pixel_range_x[0],
                        .start_y = clean_pixel_range_y[0],
                        .end_y = clean_pixel_range_y[1],
                    },
                    // Right region (middle)
                    .{
                        .start_x = clean_pixel_range_x[1],
                        .end_x = pixel_width,
                        .start_y = clean_pixel_range_y[0],
                        .end_y = clean_pixel_range_y[1],
                    },
                };

                if (this.regions) |*regions| {
                    for (regions) |*region| {
                        region.start_x = @max(region.start_x, region_clip_min_x);
                        region.start_y = @max(region.start_y, region_clip_min_y);

                        // region.end_x = @max(region.end_x, region_clip_min_x);
                        // region.end_y = @max(region.end_y, region_clip_min_y);

                        // region.start_x = @min(region.start_x, region_clip_max_x);
                        // region.start_y = @min(region.start_y, region_clip_max_y);

                        region.end_x = @min(region.end_x, region_clip_max_x);
                        region.end_y = @min(region.end_y, region_clip_max_y);

                        region.start_y = @min(region.start_y, region.end_y);
                        region.start_x = @min(region.start_x, region.end_x);
                    }
                }

                this.current_region = 0;

                pixels_offsets = null;
            }

            // Process one region at a time
            if (this.current_region < 4) {
                const regions = this.regions.?;
                const region = regions[this.current_region];

                // Skip empty regions
                if (region.end_x <= region.start_x or region.end_y <= region.start_y) {
                    this.rect_iteration_state = null;
                    this.current_region += 1;
                    return true;
                }

                const chunks_width = region.end_x - region.start_x;
                const chunks_height = region.end_y - region.start_y;

                state_tree.addX(region.start_x);
                state_tree.addY(region.start_y);

                defer {
                    state_tree.subtractX(region.start_x);
                    state_tree.subtractY(region.start_y);
                }

                if (this.rect_iteration_state == null) {
                    // Prepare chunks for this region
                    const chunks = allocator.alloc([]render.Color, chunks_height) catch @panic("OOM");

                    const pixel_width = parent_pixels_width;
                    for (chunks, 0..) |*chunks_row, i| {
                        chunks_row.* = parent_pixels[(i + region.start_y) * pixel_width + region.start_x ..][0..chunks_width];
                    }

                    // Initialize the FillRectIterationState for this region
                    this.rect_iteration_state = render.FillRectIterationState.init(
                        allocator,
                        &state_tree,
                        chunks,
                    ) catch @panic("OOM");
                }

                // Perform one iteration of filling
                if (this.rect_iteration_state.?.iterate(iteration_rate * 100) catch @panic("OOM")) {
                    // Still processing this region
                    return true;
                } else {
                    // This region is done, clean up
                    if (this.rect_iteration_state) |*rect_state| {
                        allocator.free(rect_state.output_colors);
                        rect_state.deinit();
                    }
                    this.rect_iteration_state = null;

                    // Move to the next region
                    this.current_region += 1;

                    // If we have more regions to process, continue
                    if (this.current_region < 4) {
                        return true;
                    }
                }
            }

            // for (0..parent_pixels_height) |y| {
            //     for (0..parent_pixels_width) |x| {
            //         if (y >= region_clip_max_y or x >= region_clip_max_x or y < region_clip_min_y or x < region_clip_min_x) {
            //             parent_pixels[y * (parent_pixels_width) + x] = .{
            //                 .r = 255,
            //                 .g = 0,
            //                 .b = 0,
            //                 .a = 70,
            //             };
            //         }
            //     }
            // }

            if (region_clip_min_y > 0) {
                for (region_clip_min_x -| 1..@min(parent_pixels_width, region_clip_max_x + 1)) |x| {
                    const y = region_clip_min_y - 1;
                    parent_pixels[y * (parent_pixels_width) + x] = .{
                        .r = 0,
                        .g = 0,
                        .b = 0,
                        .a = 0,
                    };
                }
            }

            if (region_clip_max_y < parent_pixels_height) {
                for (region_clip_min_x -| 1..@min(parent_pixels_width, region_clip_max_x + 1)) |x| {
                    const y = region_clip_max_y;
                    parent_pixels[y * (parent_pixels_width) + x] = .{
                        .r = 0,
                        .g = 0,
                        .b = 0,
                        .a = 0,
                    };
                }
            }

            if (region_clip_min_x > 0) {
                for (region_clip_min_y -| 1..@min(parent_pixels_height, region_clip_max_y + 1)) |y| {
                    const x = region_clip_min_x - 1;
                    parent_pixels[y * (parent_pixels_width) + x] = .{
                        .r = 0,
                        .g = 0,
                        .b = 0,
                        .a = 0,
                    };
                }
            }

            if (region_clip_max_x < parent_pixels_width) {
                for (region_clip_min_y -| 1..@min(parent_pixels_height, region_clip_max_y + 1)) |y| {
                    const x = region_clip_max_x;
                    parent_pixels[y * (parent_pixels_width) + x] = .{
                        .r = 0,
                        .g = 0,
                        .b = 0,
                        .a = 0,
                    };
                }
            }

            pixels_offsets = .{ 0, 0 };

            pixels_clean_region = .{ .{ region_clip_min_x, region_clip_min_y }, .{ region_clip_max_x, region_clip_max_y } };

            // pixels_offsets = null;

            this.deinitialize();

            return false;
        }
    };

    const RefreshDisplay = struct {
        initialized: bool,
        display_pixels_copy_state: MemcpyIterationState(render.Color),
        started_filling_bitmap: bool,

        pub const init: RefreshDisplay = .{
            .initialized = false,
            .display_pixels_copy_state = undefined,
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
        }

        fn deinitialize(this: *RefreshDisplay) void {
            this.initialized = false;
            this.started_filling_bitmap = false;

            filled_pixels = false;

            wait_until_backup = false;

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

                if (end_time - start_time > 10) {
                    jsPrint("refresh_display time: {d} ms", .{end_time - start_time});
                }
            }

            if (this.display_pixels_copy_state.iterate(iteration_amount)) {
                return true;
            }

            if (!this.started_filling_bitmap) {
                js.fillImageBitmap(
                    display_pixels.ptr,
                    parent_pixels_width,
                    parent_pixels_height,
                );
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

    // for (0..100000) |i| {
    //     state_tree.appendDigit(@intCast(i % 4)) catch @panic("OOM");
    // }

    // state_tree.appendDigit(0) catch @panic("OOM");

    // for (0..1000000) |_| {
    //     state_tree.appendDigit(3) catch @panic("OOM");
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

    for (0..10) |i| {
        state_tree.appendDigit(@truncate(i)) catch @panic("OOM");
    }

    // for (0..std.math.log2(parent_square_size)) |_| {
    //     state_tree.appendDigit(0) catch @panic("OOM");
    // }

    // trailing_digit_count = std.math.log2(parent_square_size);

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

    position_dirty = true;

    wait_until_backup = true;

    filled_pixels = false;

    pixels_offsets = null;

    backup_client.offset_x = 0;
    backup_client.offset_y = 0;
    backup_client.zoom = 1;

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
                state_tree.appendDigit(digit) catch @panic("OOM");
            }
        }
    }
}

var find_image_data: []render.Color = &.{};

export fn findImageAlloc(size: usize) [*]render.Color {
    std.debug.assert(size >= 1);

    find_image_data = allocator.alloc(render.Color, @divExact(size, 4)) catch @panic("OOM");

    return find_image_data.ptr;
}

export fn findImage() void {
    state_iteration_count = 0;

    position_dirty = true;

    wait_until_backup = true;

    filled_pixels = false;

    pixels_offsets = null;

    parent_pixels_width = @intFromFloat(@as(f64, @floatFromInt(backup_client.canvas_width)) / pixel_ratio);
    parent_pixels_height = @intFromFloat(@as(f64, @floatFromInt(backup_client.canvas_height)) / pixel_ratio);

    // backup_client.offset_x = (@as(f64, @floatFromInt(backup_client.canvas_width)) - @as(f64, @floatFromInt(image_square_size * pixel_ratio)) / 2.0) / 2.0;
    // backup_client.offset_y = (@as(f64, @floatFromInt(backup_client.canvas_height)) - @as(f64, @floatFromInt(image_square_size * pixel_ratio)) / 2.0) / 2.0;
    // backup_client.zoom = 1;

    backup_client.offset_x = (@as(f64, @floatFromInt(backup_client.canvas_width)) -
        @as(f64, @floatFromInt(((std.math.ceilPowerOfTwo(usize, @min(parent_pixels_width, parent_pixels_height)) catch unreachable) / 2)))) * (pixel_ratio / 2.0);
    backup_client.offset_y = (@as(f64, @floatFromInt(backup_client.canvas_height)) -
        @as(f64, @floatFromInt(((std.math.ceilPowerOfTwo(usize, @min(parent_pixels_width, parent_pixels_height)) catch unreachable) / 2)))) * (pixel_ratio / 2.0);
    backup_client.zoom = 1;

    // backup_client.updatePosition(
    //     @as(f64, @floatFromInt(backup_client.canvas_width)) / 2.0,
    //     @as(f64, @floatFromInt(backup_client.canvas_height)) / 2.0,
    //     0.5,
    // );

    var enc = render.encodeColors(allocator, find_image_data) catch @panic("OOM");
    defer enc.deinit(allocator);

    allocator.free(find_image_data);

    state_tree.clearDigits();
    for (0..enc.length) |i| {
        const digit = enc.get(i);

        state_tree.appendDigit(digit) catch @panic("OOM");
    }

    for (0..std.math.log2_int_ceil(usize, @min(parent_pixels_width, parent_pixels_height)) - 1) |_| {
        state_tree.appendDigit(0) catch @panic("OOM");
    }
}

export fn getOffsetAlloc() [*]u8 {
    offset_digits_packed_with_digit_offset = allocator.alloc(u8, ((state_tree.digits.length + 3) / 4) + 1) catch @panic("OOM");
    offset_digits_packed = offset_digits_packed_with_digit_offset[0 .. offset_digits_packed_with_digit_offset.len - 1];

    for (offset_digits_packed, 0..) |*packed_digit, i| {
        packed_digit.* = 0;
        for (0..4) |j| {
            // const idx = ((i + 1) * 4 - j - 1);
            const idx = i * 4 + j;
            if (idx < state_tree.digits.length) {
                const offset_digit = state_tree.digits.get(idx);
                packed_digit.* |= @as(u8, offset_digit) << @intCast(j * 2);
            }
        }
    }

    offset_digits_packed_with_digit_offset[offset_digits_packed_with_digit_offset.len - 1] = @intCast(state_tree.digits.length % 4);

    return offset_digits_packed_with_digit_offset.ptr;
}

export fn getOffsetLen() usize {
    return offset_digits_packed_with_digit_offset.len;
}

export fn getOffsetFree() void {
    allocator.free(offset_digits_packed_with_digit_offset);
}

export fn makeImage(square_size: usize) [*]render.Color {
    std.debug.assert(std.math.isPowerOfTwo(square_size));

    const image = allocator.alloc(render.Color, square_size * square_size) catch @panic("OOM");

    const output_color_chunks_backing = allocator.alloc([]render.Color, square_size * 2) catch @panic("OOM");

    const sub_square_size = square_size / 2;

    var output_color_chunks: [4][][]render.Color = undefined;

    for (&output_color_chunks, 0..) |*output_color_chunk, i| {
        output_color_chunk.* = output_color_chunks_backing[i * sub_square_size .. (i + 1) * sub_square_size];
    }

    for (&output_color_chunks, 0..) |output_color_chunk, i| {
        const x_offset = (i & 1) * sub_square_size;
        const y_offset = (i >> 1) * sub_square_size;

        for (0..square_size / 2) |y| {
            const offset_x = x_offset;
            const offset_y = y + y_offset;

            const start_idx = offset_y * (square_size) + offset_x;

            output_color_chunk[y] = image[start_idx .. start_idx + sub_square_size];
        }
    }

    for (0..4) |i| {
        digitIncrement(@intCast(i));

        var iteration_state = render.FillIterationState.init(allocator, sub_square_size, state_tree.digits, state_tree.endingState() catch @panic("OOM"), output_color_chunks[i]) catch @panic("OOM");
        defer iteration_state.deinit();

        while (iteration_state.iterate(100000)) {}

        digitDecrement(@intCast(i));
    }

    return image.ptr;
}

export fn freeImage(image: [*]render.Color, square_size: usize) void {
    std.debug.assert(std.math.isPowerOfTwo(square_size));

    allocator.free(image[0 .. square_size * square_size]);
}
