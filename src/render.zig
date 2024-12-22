const std = @import("std");

pub const Color = packed struct(u32) {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

extern fn printString(ptr: [*]const u8, len: usize) void;
extern fn getTime() f64;

fn jsPrint(comptime fmt: []const u8, args: anytype) void {
    const allocator = std.heap.page_allocator;
    const to_print = std.fmt.allocPrint(allocator, fmt, args) catch @panic("OOM");
    defer allocator.free(to_print);
    printString(to_print.ptr, to_print.len);
}

pub const FillIterationState = struct {
    layer: usize,
    max_layer: usize,
    idx: usize,
    digits: DigitArray,
    states: []SelfConsumingReaderState,

    output_colors_idx: usize,
    output_colors: [][]Color,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, square_size: usize, digits: DigitArray, initial_state: SelfConsumingReaderState, output_colors: [][]Color) std.mem.Allocator.Error!FillIterationState {
        std.debug.assert(std.math.isPowerOfTwo(square_size));
        std.debug.assert(square_size == output_colors.len);

        const res: FillIterationState = .{
            .layer = 0,
            .max_layer = std.math.log2(square_size),
            .idx = 0,
            .digits = digits,
            .states = try allocator.alloc(SelfConsumingReaderState, square_size * square_size),
            .output_colors = try allocator.alloc([]Color, square_size),
            .output_colors_idx = 0,
            .allocator = allocator,
        };

        @memcpy(res.output_colors, output_colors);

        res.states[0] = initial_state;

        return res;
    }

    pub fn deinit(this: FillIterationState) void {
        this.allocator.free(this.states);
        this.allocator.free(this.output_colors);
    }

    pub fn reset(this: *FillIterationState, square_size: usize, digits: DigitArray, initial_state: SelfConsumingReaderState, output_colors: [][]Color) std.mem.Allocator.Error!void {
        std.debug.assert(std.math.isPowerOfTwo(square_size));
        std.debug.assert(square_size == output_colors.len);

        if (square_size > this.output_colors.len) {
            this.states = try this.allocator.realloc(this.states, square_size * square_size);

            this.output_colors = try this.allocator.realloc(this.output_colors, square_size);
        }

        @memcpy(this.output_colors[0..square_size], output_colors);

        const prev_square_size = @as(usize, 1) << @intCast(this.max_layer);

        if (square_size != prev_square_size) {
            this.max_layer = std.math.log2(square_size);
        }

        this.layer = 0;
        this.idx = 0;
        this.digits = digits;
        this.states[0] = initial_state;

        this.output_colors_idx = 0;
    }

    pub fn iterate(this: *FillIterationState, iteration_count: usize) bool {
        if (this.layer == this.max_layer) {
            return this.iterateFillColors(iteration_count);
        }

        const square_area = @as(usize, 1) << @intCast(this.layer * 2);

        const square_mask = (@as(usize, 1) << @intCast(this.layer)) - 1;

        for (0..iteration_count) |iteration| {
            const small_x = this.idx & square_mask;
            const small_y = this.idx >> @intCast(this.layer);

            const big_x = small_x << @intCast(this.max_layer - this.layer);
            const big_y = small_y << @intCast(this.max_layer - this.layer);

            const big_idx = (big_y << @intCast(this.max_layer)) | big_x;

            const virtual_digits = VirtualDigitArray.fromDigitArray(this.digits, big_x, big_y, this.max_layer);

            var new_states: [4]SelfConsumingReaderState = undefined;

            this.states[big_idx].iterateAll(virtual_digits, &new_states);

            // for (&new_states, 0..) |*new_state, i| {
            //     this.states[big_idx].iterate(@intCast(i), virtual_digits, new_state);
            // }

            for (&new_states, 0..) |new_state, i| {
                const child_small_x = (small_x << 1) | (i & 1);
                const child_small_y = (small_y << 1) | (i >> 1);

                const child_big_x = child_small_x << @intCast(this.max_layer - this.layer - 1);
                const child_big_y = child_small_y << @intCast(this.max_layer - this.layer - 1);

                const child_big_idx = (child_big_y << @intCast(this.max_layer)) | child_big_x;

                this.states[child_big_idx] = new_state;
            }

            this.idx += 1;
            if (this.idx == square_area) {
                this.idx = 0;
                this.layer += 1;
                return this.iterate(iteration_count - iteration - 1);
            }
        }

        return true;
    }

    fn iterateFillColors(this: *FillIterationState, iteration_count: usize) bool {
        const square_area = @as(usize, 1) << @intCast(this.max_layer * 2);

        const square_mask = (@as(usize, 1) << @intCast(this.max_layer)) - 1;

        // const small_square_size = @as(usize, 1) << @intCast(this.max_layer);

        // const square_size_mult = square_size / small_square_size;
        // _ = square_size_mult; // autofix

        for (0..iteration_count * 100) |_| {
            if (this.output_colors_idx == square_area) {
                return false;
            }

            const x = this.output_colors_idx & square_mask;
            const y = this.output_colors_idx >> @intCast(this.max_layer);

            // const small_x = x / square_size_mult;
            // const small_y = y / square_size_mult;

            this.output_colors[y][x] = arrToColor(this.states[this.output_colors_idx].color);

            this.output_colors_idx += 1;
        }

        return true;
    }
};

pub fn childIndices(parent_x: usize, parent_y: usize, parent_square_size: usize) [4]usize {
    const child_square_size = parent_square_size * 2;

    return .{
        parent_y * 2 * child_square_size + parent_x * 2,
        parent_y * 2 * child_square_size + parent_x * 2 + 1,
        (parent_y * 2 + 1) * child_square_size + parent_x * 2,
        (parent_y * 2 + 1) * child_square_size + parent_x * 2 + 1,
    };
}

pub fn childIndices2(parent_x: usize, parent_y: usize, parent_square_size: usize) [4]usize {
    const parent_idx = parent_y * parent_square_size + parent_x;
    var indices: [4]usize = undefined;
    for (&indices, 0..) |*idx, i| {
        idx.* = parent_idx * 4 + i;
    }

    return indices;
}

pub fn stateFromDigits(root_state: SelfConsumingReaderState, digits: DigitArray, digit_count: usize) SelfConsumingReaderState {
    var states: [2]SelfConsumingReaderState = undefined;

    var prev_state = &states[0];
    var next_state = &states[1];

    prev_state.* = root_state;

    for (0..digit_count) |i| {
        const digit = digits.get(i);
        prev_state.iterate(digit, VirtualDigitArray.fromDigitArray(digits, 0, 0, 0), next_state);

        const temp = prev_state;
        prev_state = next_state;
        next_state = temp;
    }

    return prev_state.*;
}

const DigitWriter = struct {
    ptr: *anyopaque,

    vtable: Vtable,

    const Vtable = struct {
        write: *const fn (ptr: *anyopaque, digit: u2) anyerror!void,
    };

    pub fn write(this: DigitWriter, digit: u2) !void {
        try this.vtable.write(this.ptr, digit);
    }
};

const ArrayListDigitWriter = struct {
    list: *std.ArrayList(u2),

    // pub fn init(list:*std.ArrayList(u2)) ArrayListDigitWriter {
    //     retunr .{
    //         .list = list,
    //     }
    // }

    pub fn writer(this: *ArrayListDigitWriter) DigitWriter {
        return .{ .ptr = this, .vtable = .{
            .write = write,
        } };
    }

    pub fn write(ptr: *anyopaque, digit: u2) std.mem.Allocator.Error!void {
        const this: *ArrayListDigitWriter = @alignCast(@ptrCast(ptr));

        try this.list.append(digit);
    }
};

const CommandStateEfficient = struct {
    idx: Size,
    ignore_count: IgnoreSize,
    tag: CommandEnum,

    const CommandEnum = enum(u8) {
        set_position = 0,
        set_linear_position = 1,
        ignore_after = 2,
        no_op = 3,
    };

    const Size = SelfConsumingReaderState.Size;
    const IgnoreSize = SelfConsumingReaderState.IgnoreSize;

    const size_bits = @typeInfo(Size).int.bits;
    const ignore_size_bits = @typeInfo(IgnoreSize).int.bits;

    fn idxTerminated(this: CommandStateEfficient) bool {
        return this.idx >> (size_bits - 1) == 1;
    }

    fn ignoreCountTerminated(this: CommandStateEfficient) bool {
        return this.ignore_count >> (ignore_size_bits - 1) == 1;
    }

    pub fn getIdx(this: CommandStateEfficient) Size {
        return this.idx & ((1 << size_bits - 1) - 1);
    }

    pub fn getIgnoreCount(this: CommandStateEfficient) IgnoreSize {
        return this.ignore_count & ((1 << ignore_size_bits - 1) - 1);
    }

    pub fn step(this: CommandStateEfficient, reader_state: *const SelfConsumingReaderState, digit: u2) CommandStateEfficient {
        var res = this;

        if (!this.idxTerminated()) {
            if (digit == 3) {
                res.idx |= @as(Size, 1) << (size_bits - 1);
            } else {
                const with_digit = this.idx * 3 + digit;

                if (with_digit < reader_state.digit_count + 2) {
                    res.idx = with_digit;
                }
            }
        } else if (!this.ignoreCountTerminated()) {
            if (digit == 3) {
                res.ignore_count |= @as(IgnoreSize, 1) << (ignore_size_bits - 1);
            } else {
                const with_digit = @as(Size, this.ignore_count) * 3 + digit;

                if (with_digit < std.math.log2(reader_state.digit_count)) {
                    res.ignore_count = @intCast(with_digit);
                }
            }
        }

        return res;
    }

    fn stepBranchless(this: CommandStateEfficient, reader_state: *const SelfConsumingReaderState, digit: u2) CommandStateEfficient {
        const idx_terminated = @intFromBool(this.idxTerminated());
        const ignore_count_terminated = @intFromBool(this.ignoreCountTerminated());

        const digit_is_3 = @intFromBool(digit == 3);

        var res: CommandStateEfficient = this;

        var idx_with_digit = res.idx;
        idx_with_digit *%= 3;
        idx_with_digit +%= digit;

        const idx_overflow = @intFromBool(idx_with_digit >= reader_state.digit_count + 2);

        if ((~idx_terminated) & (~digit_is_3) & (~idx_overflow) == 1) {
            res.idx = idx_with_digit;
        }

        var res_ignore_count: Size = res.ignore_count;

        var ignore_count_with_digit = res_ignore_count;
        ignore_count_with_digit *%= 3;
        ignore_count_with_digit +%= digit;

        const ignore_count_overflow = @intFromBool(ignore_count_with_digit >= std.math.log2(reader_state.digit_count + 1));

        if (idx_terminated & (~ignore_count_terminated) & (~digit_is_3) & (~ignore_count_overflow) == 1) {
            res_ignore_count = ignore_count_with_digit;
        }

        res.ignore_count = @intCast(res_ignore_count);

        if (digit_is_3 == 1) {
            res.idx |= @as(Size, 1) << (size_bits - 1);
        }

        if (idx_terminated & digit_is_3 == 1) {
            res.ignore_count |= @as(IgnoreSize, 1) << (ignore_size_bits - 1);
        }

        return res;
    }

    pub fn resultReady(this: CommandStateEfficient, reader_state: *const SelfConsumingReaderState) bool {
        if (reader_state.ignore_count > 0 and reader_state.ignore_wait_count == 0) {
            return false;
        }

        return switch (this.tag) {
            .set_position => this.idxTerminated(),
            .set_linear_position => this.idxTerminated(),
            .ignore_after => this.idxTerminated() and this.ignoreCountTerminated(),
            .no_op => true,
        };
    }

    fn resultReadyBranchless(this: CommandStateEfficient, reader_state: *const SelfConsumingReaderState) bool {
        const idx_terminated = @intFromBool(this.idxTerminated());
        const ignore_count_terminated = @intFromBool(this.ignoreCountTerminated());

        var res: u1 = 0;
        res |= @intFromBool(this.tag == .ignore_after);
        res &= idx_terminated;
        res &= ignore_count_terminated;

        res |= @intFromBool(@intFromEnum(this.tag) < 2);
        res &= idx_terminated;

        res |= @intFromBool(this.tag == .no_op);

        res &= @intFromBool(reader_state.ignore_count == 0) | @intFromBool(reader_state.ignore_wait_count > 0);

        return res == 1;
    }

    pub const initials: [4]CommandStateEfficient = blk: {
        var initials_init: [4]CommandStateEfficient = undefined;
        for (&initials_init, 0..) |*initial, i| {
            const digit: u2 = i;
            initial.* = .{
                .idx = 0,
                .ignore_count = 0,
                .tag = switch (digit) {
                    0 => .set_position,

                    1 => .set_linear_position,

                    2 => .ignore_after,

                    3 => .no_op,
                },
            };
        }
        break :blk initials_init;
    };
};

const CommandState = packed struct {
    command: Command,
    tag: CommandEnum,

    const Size = SelfConsumingReaderState.Size;

    const CommandEnum = enum(u8) {
        set_position,
        set_linear_position,
        ignore_after,
        no_op,
    };

    const Command = packed union {
        set_position: SetPosition,
        set_linear_position: SetLinearPosition,
        ignore_after: IgnoreAfter,

        no_op: NoOp,

        const None = packed struct {
            const Result = void;
        };

        const SetPosition = packed struct {
            length_state: LengthState,

            const Result = Size;

            pub const init: SetPosition = .{
                .length_state = LengthState.init,
            };

            pub fn getResult(this: SetPosition) Result {
                return this.length_state.value();
            }

            pub fn step(this: SetPosition, reader_state: *const SelfConsumingReaderState, digit: u2) ?SetPosition {
                if (this.length_state.terminated()) {
                    return null;
                }

                return .{
                    .length_state = this.length_state.step(digit, reader_state.digit_count + 2),
                };
            }

            pub fn encode(writer: DigitWriter, result: Result) !void {
                try writer.write(0);
                try LengthState.encode(writer, result);
            }

            pub fn encodePadded(writer: DigitWriter, result: Result, min_digits: Size) !void {
                try writer.write(0);
                try LengthState.encodePadded(writer, result, min_digits - @min(min_digits, 1));
            }
        };

        const SetLinearPosition = packed struct {
            length_state: LengthState,

            const Result = Size;

            pub const init: SetLinearPosition = .{
                .length_state = LengthState.init,
            };

            pub fn getResult(this: SetLinearPosition) Result {
                return this.length_state.value();
            }

            pub fn step(this: SetLinearPosition, reader_state: *const SelfConsumingReaderState, digit: u2) ?SetLinearPosition {
                if (this.length_state.terminated()) {
                    return null;
                }

                return .{
                    .length_state = this.length_state.step(digit, reader_state.digit_count + 2),
                };
            }

            pub fn encode(writer: DigitWriter, result: Result) !void {
                try writer.write(1);
                try LengthState.encode(writer, result);
            }

            pub fn encodePadded(writer: DigitWriter, result: Result, min_digits: Size) !void {
                try writer.write(1);
                try LengthState.encodePadded(writer, result, min_digits - @min(min_digits, 1));
            }
        };

        const IgnoreAfter = packed struct {
            length_state: LengthState,
            ignore_count: u8,

            pub const init: IgnoreAfter = .{
                .length_state = LengthState.init,
                .ignore_count = 0xFF,
            };

            const Result = struct {
                wait_count: Size,
                ignore_count: Size,
            };

            pub fn getResult(this: IgnoreAfter) Result {
                return .{
                    .wait_count = this.length_state.value(),
                    .ignore_count = this.ignore_count,
                };
            }

            pub fn step(this: IgnoreAfter, reader_state: *const SelfConsumingReaderState, digit: u2) ?IgnoreAfter {
                if (true) @compileError("Don't use this");

                if (this.length_state.terminated() and this.ignore_count != 0xFF) {
                    return null;
                }

                if (this.ignore_count != 0xFF) {
                    return .{
                        .length_state = this.length_state.step(digit, reader_state.digit_count),
                        .ignore_count = this.ignore_count,
                    };
                }

                if (this.length_state.terminated()) {
                    return .{
                        .length_state = LengthState.init.step(digit, reader_state.digit_count),
                        .ignore_count = @intCast(this.length_state.value()),
                    };
                }

                return .{
                    .length_state = this.length_state.step(digit, std.math.log2(reader_state.digit_count)),
                    .ignore_count = 0xFF,
                };
            }

            pub fn encode(writer: DigitWriter, result: Result) !void {
                try writer.write(2);
                try LengthState.encode(writer, result.wait_count);
                try LengthState.encode(writer, result.ignore_count);
            }
        };

        const NoOp = packed struct {
            const Result = void;

            pub const init: NoOp = .{};

            pub fn getResult(this: NoOp) Result {
                _ = this; // autofix
                return {};
            }

            pub fn step(this: NoOp, reader_state: *const SelfConsumingReaderState, digit: u2) ?NoOp {
                _ = this; // autofix
                _ = reader_state; // autofix
                _ = digit; // autofix
                return null;
            }

            pub fn encode(writer: DigitWriter, result: Result) !void {
                _ = result; // autofix
                try writer.write(3);
            }
        };

        const LengthState = packed struct {
            length: Size,

            const length_bits = @typeInfo(Size).int.bits;

            pub const init: LengthState = .{
                .length = 0,
            };

            pub fn terminated(this: LengthState) bool {
                return this.length >> (length_bits - 1) == 1;
            }

            pub fn value(this: LengthState) Size {
                return this.length & ((1 << length_bits - 1) - 1);
            }

            pub fn step(this: LengthState, digit: u2, modulo: Size) LengthState {
                if (this.terminated()) {
                    return this;
                }

                if (digit == 3) {
                    return .{
                        .length = this.length | (1 << (length_bits - 1)),
                    };
                }

                return .{
                    .length = @intCast((this.length * 3 + digit) % modulo),
                };
            }

            pub fn encode(writer: DigitWriter, num: Size) !void {
                var power: Size = 1;
                while (power <= num) {
                    power *= 3;
                }
                power /= 3;

                var temp: Size = num;
                while (power > 0) {
                    try writer.write(@intCast((num / power) % 3));
                    temp /= 3;
                    power /= 3;
                }

                try writer.write(3);
            }

            pub fn encodePadded(writer: DigitWriter, num: Size, min_digits: Size) !void {
                var digits_required: Size = 1;
                {
                    var power: Size = 1;
                    while (power <= num) {
                        power *= 3;
                    }
                    power /= 3;

                    var temp: Size = num;
                    while (power > 0) {
                        digits_required += 1;
                        temp /= 3;
                        power /= 3;
                    }
                }

                if (digits_required < min_digits) {
                    for (min_digits - digits_required) |_| {
                        try writer.write(0);
                    }
                }

                {
                    var power: Size = 1;
                    while (power <= num) {
                        power *= 3;
                    }
                    power /= 3;

                    var temp: Size = num;
                    while (power > 0) {
                        try writer.write(@intCast((num / power) % 3));
                        temp /= 3;
                        power /= 3;
                    }
                }

                try writer.write(3);
            }
        };

        pub fn getResult(this: Command, tag: CommandEnum) CommandResult {
            return switch (tag) {
                .set_position => .{
                    .set_position = this.set_position.getResult(),
                },
                .set_linear_position => .{
                    .set_linear_position = this.set_linear_position.getResult(),
                },
                .ignore_after => .{
                    .ignore_after = this.ignore_after.getResult(),
                },
                .no_op => .{
                    .no_op = this.no_op.getResult(),
                },
            };
        }

        // pub fn encodeStallDigits(writer: DigitWriter, stall_count: usize) !void {
        //     std.debug.assert(stall_count > 1);

        //     try SetPosition.encodePadded(writer, 0, stall_count);
        // }
    };

    const CommandResult = union(enum) {
        none,
        set_position: Command.SetPosition.Result,
        set_linear_position: Command.SetLinearPosition.Result,
        ignore_after: Command.IgnoreAfter.Result,
        no_op: Command.NoOp.Result,
    };

    const CommandStateResult = struct {
        next: CommandState,
        result: CommandResult,
    };

    pub fn step(this: CommandState, reader_state: *const SelfConsumingReaderState, digit: u2) CommandStateResult {
        switch (this.tag) {
            .set_position => {
                const next_command_opt = this.command.set_position.step(reader_state, digit);

                if (next_command_opt) |next_command| {
                    return .{
                        .next = .{
                            .command = .{
                                .set_position = next_command,
                            },
                            .tag = this.tag,
                        },
                        .result = .none,
                    };
                }

                return .{
                    .next = newCommand(reader_state, digit),
                    .result = if (reader_state.ignore_count > 0 and reader_state.ignore_wait_count == 0) .none else this.command.getResult(this.tag),
                };
            },
            .set_linear_position => {
                const next_command_opt = this.command.set_linear_position.step(reader_state, digit);

                if (next_command_opt) |next_command| {
                    return .{
                        .next = .{
                            .command = .{
                                .set_linear_position = next_command,
                            },
                            .tag = this.tag,
                        },
                        .result = .none,
                    };
                }

                return .{
                    .next = newCommand(reader_state, digit),
                    .result = if (reader_state.ignore_count > 0 and reader_state.ignore_wait_count == 0) .none else this.command.getResult(this.tag),
                };
            },
            .ignore_after => {
                const next_command_opt = this.command.ignore_after.step(reader_state, digit);

                if (next_command_opt) |next_command| {
                    return .{
                        .next = .{
                            .command = .{
                                .ignore_after = next_command,
                            },
                            .tag = this.tag,
                        },
                        .result = .none,
                    };
                }

                return .{
                    .next = newCommand(reader_state, digit),
                    .result = if (reader_state.ignore_count > 0 and reader_state.ignore_wait_count == 0) .none else this.command.getResult(this.tag),
                };
            },
            .no_op => {
                const next_command_opt = this.command.no_op.step(reader_state, digit);

                if (next_command_opt) |next_command| {
                    return .{
                        .next = .{
                            .command = .{
                                .no_op = next_command,
                            },
                            .tag = this.tag,
                        },
                        .result = .none,
                    };
                }

                return .{
                    .next = newCommand(reader_state, digit),
                    .result = if (reader_state.ignore_count > 0 and reader_state.ignore_wait_count == 0) .none else this.command.getResult(this.tag),
                };
            },
        }

        // return blk: {
        //     const next_command_opt = this.command.step(reader_state, digit);

        //     if (next_command_opt) |next_command| {
        //         break :blk .{
        //             .next = .{
        //                 .command = next_command,
        //             },
        //             .result = .none,
        //         };
        //     }

        //     break :blk .{
        //         .next = newCommand(reader_state, digit),
        //         .result = if (reader_state.ignore_count > 0 and reader_state.ignore_wait_count == 0) .none else this.command.getResult(),
        //     };
        // };
    }

    pub fn newCommand(reader_state: *const SelfConsumingReaderState, digit: u2) CommandState {
        _ = reader_state; // autofix
        return .{
            .command = switch (digit) {
                0 => .{
                    .set_position = Command.SetPosition.init,
                },
                1 => .{
                    .set_linear_position = Command.SetLinearPosition.init,
                },
                2 => .{
                    .ignore_after = Command.IgnoreAfter.init,
                },
                3 => .{
                    .no_op = Command.NoOp.init,
                },
            },
            .tag = switch (digit) {
                0 => .set_position,

                1 => .set_linear_position,

                2 => .ignore_after,

                3 => .no_op,
            },
        };
    }
};

pub const SelfConsumingReaderState = struct {
    position: Size,

    position_start: Size,

    digit_count: Size,

    ignore_wait_count: Size,

    linear_position: Size,

    command: CommandStateEfficient,

    position_layer: LayerSize,
    ignore_count: IgnoreSize,

    color: @Vector(3, u8),

    // color: [3]u8,

    const Size = u32;

    // const LayerSize = std.math.IntFittingRange(0, (@typeInfo(Size).int.bits - 1) / 2);

    // const IgnoreSize = std.math.Log2Int(Size);

    const LayerSize = std.math.ByteAlignedInt(std.math.IntFittingRange(0, (@typeInfo(Size).int.bits - 1) / 2));

    const IgnoreSize = std.math.ByteAlignedInt(std.math.Log2Int(Size));

    const ShiftSize = std.math.Log2Int(Size);

    const null_linear_position = std.math.maxInt(Size);

    pub fn init(digit_count: Size, color: Color) SelfConsumingReaderState {
        // @compileLog(@bitSizeOf(SelfConsumingReaderState));
        // @compileLog(@sizeOf(SelfConsumingReaderState));
        // @compileLog(@offsetOf(SelfConsumingReaderState, "position"), @bitOffsetOf(SelfConsumingReaderState, "position"));

        return .{
            .position = 0,

            .position_layer = 0,

            .position_start = 0,

            .digit_count = digit_count,
            .color = colorToArr(color),

            .command = CommandStateEfficient.initials[0],

            .ignore_wait_count = 0,
            .ignore_count = 0,

            .linear_position = null_linear_position,
        };
    }

    fn setDigitIdx(this: *SelfConsumingReaderState, digit_idx: Size) void {

        // var sum: usize = 0;
        // var layer: usize = 0;
        // while (sum <= digit_idx) {
        //     layer += 1;
        //     sum = offsetFromLayer(layer);
        // }

        // layer -= 1;
        // sum = offsetFromLayer(layer);

        // this.position = digit_idx - sum;
        // this.position_layer = layer;

        const adjusted_digit_idx = (digit_idx) / EncodedChunk.digits_per_chunk;

        comptime var mask: Size = 0;
        const mask_bits: ShiftSize = @typeInfo(Size).int.bits - 1;
        inline for (0..mask_bits) |i| {
            if (i & 1 == (~@typeInfo(Size).int.bits) & 1) {
                mask |= 1 << i;
            }
        }

        var layer: LayerSize = 0;
        while (adjusted_digit_idx >= mask >> (mask_bits - @as(ShiftSize, @intCast(layer)) * 2)) {
            layer += 1;
        }

        layer -= 1;

        this.position = digit_idx - offsetFromLayer(layer);
        this.position_layer = layer;
    }

    fn layerUnderDigitIdx(digit_idx: Size) LayerSize {
        const adjusted_digit_idx = (digit_idx) / EncodedChunk.digits_per_chunk;

        comptime var mask: Size = 0;
        const mask_bits: ShiftSize = @typeInfo(Size).int.bits - 1;
        inline for (0..mask_bits) |i| {
            if (i & 1 == (~@typeInfo(Size).int.bits) & 1) {
                mask |= 1 << i;
            }
        }

        inline for (1..mask_bits / 2) |i| {
            if (adjusted_digit_idx < mask >> (mask_bits - i * 2)) {
                return i - 1;
            }
        }

        unreachable;
    }

    fn offsetFromLayer(layer: LayerSize) Size {
        //     var pow: usize = 1;
        //     var sum: usize = 0;

        //     for (layer) |_| {
        //         sum += pow * EncodedChunk.digits_per_chunk;
        //         pow *= 4;
        //     }

        //     return sum;

        comptime var mask: Size = 0;
        const mask_bits: ShiftSize = @typeInfo(Size).int.bits - 1;
        inline for (0..mask_bits) |i| {
            if (i & 1 == (~@typeInfo(Size).int.bits) & 1) {
                mask |= 1 << i;
            }
        }

        var sum = mask >> (mask_bits - @as(ShiftSize, @intCast(layer)) * 2);

        sum *= EncodedChunk.digits_per_chunk;

        return sum;
    }

    fn iterateNoColor(noalias this: *const SelfConsumingReaderState, selector_digit: u2, digits: VirtualDigitArray, noalias next: *SelfConsumingReaderState) void {
        std.debug.assert(this.digit_count > 0);

        next.linear_position = null_linear_position;

        if (this.linear_position != null_linear_position) {
            const next_linear_position = this.linear_position + 1 + EncodedChunk.digits_per_chunk;
            if (next_linear_position < this.digit_count and digits.get(this.linear_position) == selector_digit) {
                next.linear_position = next_linear_position;
            }
        }

        const modulo = this.digit_count - this.position_start;

        std.debug.assert(this.position + offsetFromLayer(this.position_layer) < modulo);

        const next_position = this.position * 4 + (@as(Size, selector_digit) * EncodedChunk.digits_per_chunk);
        const next_offset = offsetFromLayer(this.position_layer + 1);

        // const overflow_digit_idx = lcgInRange(next_position + next_offset , modulo);

        // const overflow_layer = layerUnderDigitIdx(overflow_digit_idx);
        // const overflow_position = overflow_digit_idx - offsetFromLayer(overflow_layer);

        // const will_overflow = next_position + next_offset >= modulo;

        // next.position_start = this.position_start;
        // next.position = if (will_overflow) overflow_position else next_position;
        // next.position_layer = if (will_overflow) overflow_layer else this.position_layer + 1;

        const will_overflow = next_position + next_offset >= modulo;

        next.position_start = if (will_overflow and this.position_start == 0)
            this.digit_count
        else if (will_overflow and this.position_start > 0)
            this.position_start - 1
        else
            this.position_start;

        next.position = if (will_overflow) 0 else next_position;
        next.position_layer = if (will_overflow) 0 else this.position_layer + 1;

        const ignore_waiting = @intFromBool(this.ignore_wait_count > 0);
        const has_ignore = @intFromBool(this.ignore_count > 0);

        next.ignore_wait_count = this.ignore_wait_count - ignore_waiting;
        next.ignore_count = this.ignore_count - ((~ignore_waiting) & has_ignore);

        if (this.command.resultReady(this)) {
            const idx = this.command.getIdx();
            const ignore_count = this.command.getIgnoreCount();
            const tag = this.command.tag;

            const set_position = @intFromBool(tag == .set_position) & @intFromBool(selector_digit == 0);
            const set_linear_position = @intFromBool(tag == .set_linear_position) & @intFromBool(selector_digit == 0);
            const ignore_after = @intFromBool(tag == .ignore_after);

            std.debug.assert(this.command.tag == .no_op or this.digit_count >= idx + 1);

            const relative_idx = this.digit_count -% 1 -% idx;

            if (set_position == 1) {
                next.position_start = relative_idx;
                next.position = 0;
                next.position_layer = 0;
            }

            if (set_linear_position == 1) {
                next.linear_position = relative_idx;
            }

            if (ignore_after == 1) {
                next.ignore_count = ignore_count;
                next.ignore_wait_count = idx;
            }

            next.command = CommandStateEfficient.initials[selector_digit];
        } else {
            next.command = this.command.step(this, selector_digit);
        }

        // if (this.command.resultReady(this)) {
        //     switch (this.command.tag) {
        //         .no_op => {},

        //         .set_position => {
        //             const set_position = this.command.getIdx();

        //             if (selector_digit == 0) {
        //                 next.position_start = this.digit_count - 1 - set_position;

        //                 next.position = 0;
        //                 next.position_layer = 0;
        //             }
        //         },
        //         .set_linear_position => {
        //             const set_linear_position = this.command.getIdx();

        //             if (selector_digit == 0) {
        //                 next.linear_position = this.digit_count - 1 - set_linear_position;
        //             }
        //         },
        //         .ignore_after => {
        //             next.ignore_count = @intCast(this.command.getIgnoreCount());
        //             next.ignore_wait_count = this.command.getIdx();
        //         },
        //     }

        //     next.command = CommandStateEfficient.initials[selector_digit];
        // } else {
        //     next.command = this.command.step(this, selector_digit);
        // }

        next.digit_count = this.digit_count + 1;
    }

    fn iterateNoColorMutate(this: *SelfConsumingReaderState, selector_digit: u2, digits: VirtualDigitArray) void {
        if (true) {
            const next: SelfConsumingReaderState = undefined;
            this.iterateNoColor(selector_digit, digits, &next);
            this.* = next;
            return;
        }

        std.debug.assert(this.digit_count > 0);

        const modulo = this.digit_count - this.position_start;

        std.debug.assert(this.position + offsetFromLayer(this.position_layer) < modulo);

        const next_position = this.position * 4 + (@as(Size, selector_digit) * EncodedChunk.digits_per_chunk);

        const next_offset = offsetFromLayer(this.position_layer + 1);

        if (next_position + next_offset >= modulo) {
            const next_digit_idx = lcgInRange(next_position + next_offset, modulo);
            // const next_digit_idx = clampWrap(next_position + next_offset, modulo);
            this.setDigitIdx(next_digit_idx);
        } else {
            this.position = next_position;
            this.position_layer = this.position_layer + 1;
        }

        const command_result = this.command.step(this, selector_digit);
        this.command = command_result.next;

        if (this.linear_position != null_linear_position) {
            const next_linear_position = this.linear_position + 1 + EncodedChunk.digits_per_chunk;
            if (digits.get(this.linear_position) == selector_digit and next_linear_position < this.digit_count) {
                this.linear_position = next_linear_position;
            } else {
                this.linear_position = null_linear_position;
            }
        }

        if (this.ignore_count > 0 and this.ignore_wait_count == 0) {
            this.ignore_count -= 1;
        }

        if (this.ignore_wait_count > 0) {
            this.ignore_wait_count -= 1;
        }

        switch (command_result.result) {
            .none, .no_op => {},

            .set_position => |set_position| {
                if (selector_digit == 0) {
                    this.position_start = this.digit_count - 1 - set_position;

                    this.position = 0;
                    this.position_layer = 0;
                }
            },
            .set_linear_position => |set_linear_position| {
                if (selector_digit == 0) {
                    this.linear_position = this.digit_count - 1 - set_linear_position;
                }
            },
            // .set_activation_digit => |set_activation_digit| {
            //     next.activation_digit = set_activation_digit;
            // },
            .ignore_after => |ignore_after| {
                this.ignore_count = @intCast(ignore_after.ignore_count);
                this.ignore_wait_count = ignore_after.wait_count;
            },
        }
        this.digit_count += 1;
    }

    pub fn iterateAllNoColor(noalias this: *const SelfConsumingReaderState, digits: VirtualDigitArray, noalias res: *[4]SelfConsumingReaderState) void {
        if (true) {
            for (0..4) |i| {
                this.iterateNoColor(@intCast(i), digits, &res[i]);
            }

            return;
        }

        std.debug.assert(this.digit_count > 0);

        for (res) |*next| {
            next.digit_count = this.digit_count + 1;

            next.position_start = this.position_start;
            next.linear_position = null_linear_position;

            next.ignore_count = this.ignore_count - @intFromBool(this.ignore_count > 0 and this.ignore_wait_count == 0);

            next.ignore_wait_count = this.ignore_wait_count -| @intFromBool(this.ignore_wait_count > 0);
        }

        const modulo = this.digit_count - this.position_start;

        std.debug.assert(this.position + offsetFromLayer(this.position_layer) < modulo);

        const next_offset = offsetFromLayer(this.position_layer + 1);

        for (res, 0..) |*next, selector_digit_usize| {
            const selector_digit: u2 = @intCast(selector_digit_usize);

            const next_position = this.position * 4 + (@as(Size, selector_digit) * EncodedChunk.digits_per_chunk);

            if (next_position + next_offset >= modulo) {
                const next_digit_idx = lcgInRange(next_position + next_offset, modulo);
                // const next_digit_idx = clampWrap(next_position + next_offset, modulo);
                next.setDigitIdx(next_digit_idx);
            } else {
                next.position = next_position;
                next.position_layer = this.position_layer + 1;
            }

            const command_result = this.command.step(this, selector_digit);

            next.command = command_result.next;

            if (this.linear_position != null_linear_position) {
                const next_linear_position = this.linear_position + 1 + EncodedChunk.digits_per_chunk;
                if (digits.get(this.linear_position) == selector_digit and next_linear_position < this.digit_count) {
                    next.linear_position = next_linear_position;
                }
            }

            switch (command_result.result) {
                .none, .no_op => {},

                .set_position => |set_position| {
                    if (selector_digit == 0) {
                        next.position_start = this.digit_count - 1 - set_position;

                        next.position = 0;
                        next.position_layer = 0;
                    }
                },
                .set_linear_position => |set_linear_position| {
                    if (selector_digit == 0) {
                        next.linear_position = this.digit_count - 1 - set_linear_position;
                    }
                },
                .ignore_after => |ignore_after| {
                    next.ignore_count = @intCast(ignore_after.ignore_count);
                    next.ignore_wait_count = ignore_after.wait_count;
                },
            }
        }
    }

    pub fn iterate(noalias this: *const SelfConsumingReaderState, selector_digit: u2, digits: VirtualDigitArray, noalias res: *SelfConsumingReaderState) void {
        if (this.digit_count == 0) {
            @branchHint(.unlikely);
            res.* = this.*;
            res.digit_count = 1;

            return;
        }

        this.iterateNoColor(selector_digit, digits, res);

        res.color = this.getChildColors(digits)[selector_digit];
    }

    pub fn iterateMutate(noalias this: *SelfConsumingReaderState, selector_digit: u2, digits: VirtualDigitArray) void {
        if (this.digit_count == 0) {
            @branchHint(.unlikely);
            this.digit_count = 1;

            return;
        }

        this.color = this.getChildColors(digits)[selector_digit];

        this.iterateNoColorMutate(selector_digit, digits);
    }

    pub fn iterateAll(this: *const SelfConsumingReaderState, digits: VirtualDigitArray, res: *[4]SelfConsumingReaderState) void {
        if (this.digit_count == 0) {
            @branchHint(.unlikely);
            res.* = @splat(this.*);
            for (res) |*res_val| {
                res_val.digit_count = 1;
            }

            return;
        }

        this.iterateAllNoColor(digits, res);

        const child_colors = this.getChildColors(digits);

        for (res, &child_colors) |*res_val, child_color| {
            res_val.color = child_color;
        }
    }

    pub fn getChildColors(this: *const SelfConsumingReaderState, digits: VirtualDigitArray) [4][3]u8 {
        if (this.digit_count == 0) {
            const default: [4][3]u8 = @splat(this.color);
            return default;
        }

        const offset = offsetFromLayer(this.position_layer);

        var digit_idx = this.position + offset + this.position_start;

        std.debug.assert(digit_idx < this.digit_count);

        if (this.linear_position != null_linear_position) {
            digit_idx = clampWrapIncrement(this.linear_position, this.digit_count);
        }

        {
            const encoded_chunk = EncodedChunk.fromDigits(digits, digit_idx, this.position_start, this.digit_count);

            const splitters = encoded_chunk.splitters;

            return splitColor(this.color, splitters);
        }
    }
};

pub const StateStems = struct {
    quadrant_digits: [4]DigitArray,
    quadrant_digit_backers: [4]std.ArrayListUnmanaged(DigitArray.Backer),
    quadrant_digit_stem_matches: [4][4]usize,

    stem_initialized: std.DynamicBitSetUnmanaged,
    stem_digits: DigitArray,
    stem_digit_backers: std.ArrayListUnmanaged(DigitArray.Backer),

    stems_states: std.MultiArrayList(StemState),

    allocator: std.mem.Allocator,

    initial_state: SelfConsumingReaderState,

    pub const Node = struct {
        initialized: [4]bool,

        digits: [4]u2,
    };

    pub const StemState = union(enum) {
        uninitialized,
        state: SelfConsumingReaderState,
    };

    // fn getNode(this: StateStems, idx: usize) Node {
    //     const adjusted_idx = idx * 4;
    //     var res: Node = undefined;

    //     for (0..4, adjusted_idx..) |i, j| {
    //         res.initialized[i] = this.stem_initialized.isSet(j);
    //         res.digits[i] = this.stem_digits.get(j);
    //     }

    //     return res;
    // }

    // fn setNode(this: *StateStems, idx: usize, node: Node) void {
    //     const adjusted_idx = idx * 4;

    //     for (0..4, adjusted_idx..) |i, j| {
    //         this.stem_initialized.setValue(j, node.initialized[i]);
    //         this.stem_digits.set(j, node.digits[i]);
    //     }
    // }

    fn stemsLength(this: StateStems) usize {
        return this.stem_digits.length / 4;
    }

    fn resizeStems(this: *StateStems, new_len: usize) std.mem.Allocator.Error!void {
        const new_len_adjusted = new_len * 4;

        try this.stem_initialized.resize(this.allocator, new_len_adjusted, false);

        const new_backers_len = DigitArray.backersNeeded(new_len_adjusted);
        try this.stem_digit_backers.resize(this.allocator, new_backers_len);

        this.stem_digits.digit_backers = this.stem_digit_backers.items;
        this.stem_digits.length = new_len_adjusted;
    }

    fn shrinkStems(this: *StateStems, new_len: usize) void {
        const new_len_adjusted = new_len * 4;

        const new_backers_len = DigitArray.backersNeeded(new_len_adjusted);
        this.stem_digit_backers.shrinkRetainingCapacity(new_backers_len);

        this.stem_digits.digit_backers = this.stem_digit_backers.items;
        this.stem_digits.length = new_len_adjusted;
    }

    const digits_per_state = 16;

    pub fn init(allocator: std.mem.Allocator, root_color: Color) std.mem.Allocator.Error!StateStems {
        var quadrant_digit_backers: [4]std.ArrayListUnmanaged(DigitArray.Backer) = undefined;
        for (&quadrant_digit_backers) |*digit_backers| {
            digit_backers.* = try std.ArrayListUnmanaged(DigitArray.Backer).initCapacity(allocator, 1);
        }

        var quadrant_digits: [4]DigitArray = undefined;
        for (&quadrant_digits, &quadrant_digit_backers) |*digits, digit_backers| {
            digits.* = .{
                .digit_backers = digit_backers.items,
                .length = 0,
            };
        }

        const stems_states: std.MultiArrayList(StemState) = .{};

        const initial_state = SelfConsumingReaderState.init(0, root_color);

        const stem_initialized = try std.DynamicBitSetUnmanaged.initEmpty(allocator, 0);

        const stem_digit_backers = try std.ArrayListUnmanaged(DigitArray.Backer).initCapacity(allocator, 1);

        const stems_digits: DigitArray = .{
            .digit_backers = stem_digit_backers.items,
            .length = 0,
        };

        var res: StateStems = .{
            .quadrant_digits = quadrant_digits,
            .quadrant_digit_backers = quadrant_digit_backers,
            .quadrant_digit_stem_matches = @splat(@splat(0)),

            .stem_initialized = stem_initialized,
            .stem_digits = stems_digits,
            .stem_digit_backers = stem_digit_backers,
            .stems_states = stems_states,
            .allocator = allocator,
            .initial_state = initial_state,
        };

        try res.resizeStems(1);

        for (0..4) |i| {
            res.stem_digits.set(i, @intCast(i));
            res.stem_initialized.set(i);
        }

        return res;
    }

    pub fn deinit(this: *StateStems) void {
        for (&this.quadrant_digit_backers) |*digit_backers| {
            digit_backers.deinit(this.allocator);
        }

        this.stem_initialized.deinit(this.allocator);
        this.stem_digit_backers.deinit(this.allocator);
        this.stems_states.deinit(this.allocator);
    }

    pub fn appendDigit(this: *StateStems, quadrant: usize, digit: u2) std.mem.Allocator.Error!void {
        const prev_length = this.quadrant_digits[quadrant].length;

        const new_backers_len = DigitArray.backersNeeded(prev_length + 1);
        try this.quadrant_digit_backers[quadrant].resize(this.allocator, new_backers_len);

        this.quadrant_digits[quadrant].digit_backers = this.quadrant_digit_backers[quadrant].items;
        this.quadrant_digits[quadrant].length = prev_length + 1;

        this.quadrant_digits[quadrant].set(prev_length, digit);
    }

    pub fn removeDigit(this: *StateStems, quadrant: usize) void {
        const prev_length = this.quadrant_digits[quadrant].length;

        const new_backers_len = DigitArray.backersNeeded(prev_length - 1);
        this.quadrant_digit_backers[quadrant].shrinkRetainingCapacity(new_backers_len);

        this.quadrant_digits[quadrant].digit_backers = this.quadrant_digit_backers[quadrant].items;
        this.quadrant_digits[quadrant].length = prev_length - 1;

        for (&this.quadrant_digit_stem_matches[quadrant]) |*matches| {
            matches.* = @min(matches.*, this.quadrant_digits[quadrant].length);
        }
    }

    pub fn clearDigits(this: *StateStems) void {
        for (0..4) |i| {
            this.quadrant_digit_backers[i].shrinkRetainingCapacity(0);
            this.quadrant_digits[i].digit_backers = this.quadrant_digit_backers[i].items;
            this.quadrant_digits[i].length = 0;
            this.quadrant_digit_stem_matches[i] = @splat(0);
        }
    }

    pub fn incrementX(this: *StateStems, quadrant: usize) void {
        const digits = this.quadrant_digits[quadrant];

        var i: usize = digits.length - 1;
        while (true) {
            const digit = digits.get(i);
            if (digit & 0b01 == 0b01) {
                digits.set(i, digit & 0b10);
            } else {
                digits.set(i, digit | 0b01);
                break;
            }

            i -= 1;
        }

        for (&this.quadrant_digit_stem_matches[quadrant]) |*matches| {
            matches.* = @min(matches.*, i);
        }
    }

    pub fn incrementY(this: *StateStems, quadrant: usize) void {
        const digits = this.quadrant_digits[quadrant];

        var i: usize = digits.length - 1;
        while (true) {
            const digit = digits.get(i);
            if (digit & 0b10 == 0b10) {
                digits.set(i, digit & 0b01);
            } else {
                digits.set(i, digit | 0b10);
                break;
            }

            i -= 1;
        }

        for (&this.quadrant_digit_stem_matches[quadrant]) |*matches| {
            matches.* = @min(matches.*, i);
        }
    }

    pub fn decrementX(this: *StateStems, quadrant: usize) void {
        const digits = this.quadrant_digits[quadrant];

        var i: usize = digits.length - 1;
        while (true) {
            const digit = digits.get(i);
            if (digit & 0b01 == 0b00) {
                digits.set(i, digit | 0b01);
            } else {
                digits.set(i, digit & 0b10);
                break;
            }

            i -= 1;
        }

        for (&this.quadrant_digit_stem_matches[quadrant]) |*matches| {
            matches.* = @min(matches.*, i);
        }
    }

    pub fn decrementY(this: *StateStems, quadrant: usize) void {
        const digits = this.quadrant_digits[quadrant];

        var i: usize = digits.length - 1;
        while (true) {
            const digit = digits.get(i);
            if (digit & 0b10 == 0b00) {
                digits.set(i, digit | 0b10);
            } else {
                digits.set(i, digit & 0b01);
                break;
            }

            i -= 1;
        }

        for (&this.quadrant_digit_stem_matches[quadrant]) |*matches| {
            matches.* = @min(matches.*, i);
        }
    }

    pub fn trim(this: *StateStems, new_length: usize) void {
        if (new_length < this.stemsLength()) {
            this.shrinkStems(new_length);
        }

        const new_states_length = new_length / digits_per_state;
        const new_states_length_adjusted = new_states_length * 4;

        if (new_states_length_adjusted < this.stems_states.len) {
            this.stems_states.shrinkRetainingCapacity(new_states_length_adjusted);
        }
    }

    // Assumes adjusted_idx is a multiple of 4.
    fn get4Initialized(this: StateStems, adjusted_idx: usize) @Vector(4, u1) {
        const ShiftInt = std.DynamicBitSetUnmanaged.ShiftInt;

        const shift: ShiftInt = @truncate(adjusted_idx);

        const mask_idx = adjusted_idx >> @bitSizeOf(ShiftInt);

        return @bitCast(@as(u4, @truncate(this.stem_initialized.masks[mask_idx] >> shift)));
    }

    fn swapAdjacentBitsAt(val: u8, comptime idx: comptime_int) u8 {
        if (idx & 1 == 0) {
            const all_swapped = ((val & 0b10101010) >> 1) | ((val & 0b01010101) << 1);

            const shift = idx;

            const mask = @as(u8, 0b11) << shift;
            const mask_inv = ~mask;

            return (val & mask_inv) | (all_swapped & mask);
        }

        const all_swapped = ((((val << 1) & 0b10101010) >> 1) | (((val << 1) & 0b01010101) << 1)) >> 1;

        const shift = idx;

        const mask = @as(u8, 0b11) << shift;
        const mask_inv = ~mask;

        return (val & mask_inv) | (all_swapped & mask);
    }

    pub fn stateAt(this: *StateStems, quadrant: usize, position: usize) std.mem.Allocator.Error!SelfConsumingReaderState {
        const path = VirtualDigitArray.fromDigitArray(this.quadrant_digits[quadrant], 0, 0, 0);
        const digit_count = position + 1;

        // const start_time = getTime();
        // defer {
        //     const end_time = getTime();

        //     jsPrint("state stems traverse time: {d} ms", .{end_time - start_time});
        // }

        var in_path: u8 = 0;

        var starting_digit_idx: usize = 0;
        for (this.quadrant_digit_stem_matches[quadrant]) |matches| {
            starting_digit_idx = @max(starting_digit_idx, matches);
        }

        for (this.quadrant_digit_stem_matches[quadrant], 0..) |matches, i| {
            if (matches >= starting_digit_idx) {
                in_path |= @as(u8, 1) << @intCast(i);
            }
        }

        // jsPrint("starting_digit_idx: {} digit_count: {}", .{ starting_digit_idx, digit_count });

        for (starting_digit_idx..digit_count) |digit_idx| {
            for (&this.quadrant_digit_stem_matches[quadrant], 0..) |*matches, i| {
                if (((in_path >> @intCast(i)) & 1) == 1) {
                    matches.* = @max(matches.*, digit_idx);
                }
            }

            const digit = path.get(digit_idx);

            if (this.stemsLength() == digit_idx) {
                var in_path_bool: [4]bool = undefined;
                for (0..4) |i| {
                    in_path_bool[i] = ((in_path >> @intCast(i)) & 1) == 1;
                }

                return try this.overwriteStem(quadrant, digit_count, digit_idx, in_path_bool);
            }

            const adjusted_digit_idx = digit_idx * 4;

            const current_digits: u8 = blk: {
                std.debug.assert(DigitArray.digits_per_backer % 4 == 0);

                const backer = this.stem_digits.digit_backers[adjusted_digit_idx / DigitArray.digits_per_backer];

                const shift = (adjusted_digit_idx % (DigitArray.digits_per_backer)) * 2;

                const backer_vec: @Vector(4, u2) = @bitCast(@as(u8, @truncate(backer >> @intCast(shift))));

                const current_digits_bools = backer_vec == @as(@Vector(4, u2), @splat(digit));

                const current_digits_u4: u4 = @bitCast(current_digits_bools);

                break :blk current_digits_u4;
            };

            // var test_current_digits: u8 = 0;
            // for (0..4, adjusted_digit_idx..) |i, j| {
            //     test_current_digits |= @as(u8, @intFromBool(this.stem_digits.get(j) == digit)) << @intCast(i);
            // }
            // std.debug.assert(test_current_digits == current_digits);

            const current_initialized: u8 = blk: {
                const ShiftInt = std.DynamicBitSetUnmanaged.ShiftInt;

                const shift: ShiftInt = @truncate(adjusted_digit_idx);

                const mask_idx = adjusted_digit_idx >> @bitSizeOf(ShiftInt);

                break :blk @intCast((this.stem_initialized.masks[mask_idx] >> shift) & 0b1111);
            };

            // for (0..4, adjusted_digit_idx..) |i, j| {
            //     std.debug.assert(current_initialized[i] == @intFromBool(this.stem_initialized.isSet(j)));
            // }

            const next_in_path = in_path & current_digits & current_initialized;

            if (next_in_path == 0) {
                var in_path_bool: [4]bool = undefined;
                for (0..4) |i| {
                    in_path_bool[i] = ((in_path >> @intCast(i)) & 1) == 1;
                }

                return try this.overwriteStem(quadrant, digit_count, digit_idx, in_path_bool);
            }

            in_path = next_in_path;
        }

        for (0..4) |i| {
            if (((in_path >> @intCast(i)) & 1) == 1) {
                return try this.getState(digit_count - 1, i, path);
            }
        }
        unreachable;
    }

    fn overwriteStem(this: *StateStems, quadrant: usize, digit_count: usize, initial_digit_idx: usize, in_path: [4]bool) std.mem.Allocator.Error!SelfConsumingReaderState {
        const path = VirtualDigitArray.fromDigitArray(this.quadrant_digits[quadrant], 0, 0, 0);

        var overwrite_idx: usize = for (0..4) |i| {
            if (in_path[i]) {
                break i;
            }
        } else unreachable;

        this.quadrant_digit_stem_matches[quadrant][overwrite_idx] = digit_count;
        for (0..4) |i| {
            if (i != quadrant) {
                this.quadrant_digit_stem_matches[i][overwrite_idx] = @min(this.quadrant_digit_stem_matches[i][overwrite_idx], initial_digit_idx);
            }
        }

        if (initial_digit_idx < this.stemsLength()) {
            const initial_digit_idx_adjusted = initial_digit_idx * 4;

            overwrite_idx = for (0..4, initial_digit_idx_adjusted..) |i, j| {
                if (in_path[i] and !this.stem_initialized.isSet(j)) {
                    break i;
                }
            } else overwrite_idx;
        }

        // jsPrint("len recalc: {}", .{digit_count - initial_digit_idx});

        for (initial_digit_idx..digit_count) |digit_idx| {
            const digit = path.get(digit_idx);

            if (this.stemsLength() == digit_idx) {
                for (0..4) |i| {
                    this.invalidateState(digit_idx, i);
                }

                try this.resizeStems(this.stemsLength() + 1);

                const new_node_idx_adjusted = (this.stemsLength() - 1) * 4;

                for (new_node_idx_adjusted..new_node_idx_adjusted + 4) |i| {
                    this.stem_initialized.unset(i);
                }
            }

            this.invalidateState(digit_idx, overwrite_idx);

            const adjusted_digit_idx = digit_idx * 4;

            this.stem_initialized.set(adjusted_digit_idx + overwrite_idx);
            this.stem_digits.set(adjusted_digit_idx + overwrite_idx, digit);
        }

        for (digit_count..this.stemsLength()) |i| {
            const adjusted_i = i * 4;

            this.stem_initialized.unset(adjusted_i + overwrite_idx);

            this.invalidateState(i, overwrite_idx);
        }

        return try this.getState(digit_count - 1, overwrite_idx, path);
    }

    fn invalidateState(this: *StateStems, digit_idx: usize, stem_idx: usize) void {
        const idx_divided = digit_idx / digits_per_state;

        const idx_adjusted = idx_divided * 4 + stem_idx;

        if (this.stems_states.len <= idx_adjusted) {
            return;
        }

        this.stems_states.set(idx_adjusted, .uninitialized);
    }

    fn getState(this: *StateStems, digit_idx: usize, stem_idx: usize, digits: VirtualDigitArray) std.mem.Allocator.Error!SelfConsumingReaderState {
        const idx_adjusted = (digit_idx / digits_per_state) * 4 + stem_idx;

        if (this.stems_states.len <= idx_adjusted) {
            for ((idx_adjusted + 1) - this.stems_states.len) |_| {
                try this.stems_states.append(this.allocator, .uninitialized);
            }
        }

        const state_idx_target = (digit_idx / digits_per_state) * 4 + stem_idx;

        var state_idx = state_idx_target;

        while (state_idx > 3 and this.stems_states.get(state_idx) == .uninitialized) {
            state_idx -= 4;
        }

        // jsPrint("state recalc: {}", .{(digit_idx + 1) - ((state_idx / 4) * digits_per_state + 1)});

        var state: SelfConsumingReaderState = undefined;

        if (state_idx < 4) {
            this.initial_state.iterate(@intCast(this.stem_digits.get(0 + stem_idx)), digits, &state);
        } else {
            state = this.stems_states.get(state_idx).state;
        }

        for ((state_idx / 4) * digits_per_state + 1..digit_idx + 1) |idx| {
            if ((idx - 1) % digits_per_state == 0) {
                this.stems_states.set((idx / digits_per_state) * 4 + stem_idx, .{
                    .state = state,
                });
            }

            const adjusted_idx = idx * 4;

            var next_state: SelfConsumingReaderState = undefined;
            state.iterate(this.stem_digits.get(adjusted_idx + stem_idx), digits, &next_state);
            state = next_state;
        }

        if (digit_idx % digits_per_state == 0) {
            this.stems_states.set((digit_idx / digits_per_state) * 4 + stem_idx, .{
                .state = state,
            });
        }

        return state;
    }
};

pub const DigitArrayManaged = struct {
    array: DigitArray,
    digit_backers: std.ArrayList(DigitArray.Backer),

    pub fn init(allocator: std.mem.Allocator, digit_count: usize) std.mem.Allocator.Error!DigitArrayManaged {
        var res: DigitArrayManaged = undefined;

        res.digit_backers = std.ArrayList(DigitArray.Backer).init(allocator);
        try res.digit_backers.resize(DigitArray.backersNeeded(digit_count));

        res.array = .{
            .digit_backers = res.digit_backers.items,
            .length = digit_count,
        };

        return res;
    }

    pub fn deinit(this: DigitArrayManaged) void {
        this.digit_backers.deinit();
    }

    pub fn resize(this: *DigitArrayManaged, new_digit_count: usize) std.mem.Allocator.Error!void {
        try this.digit_backers.resize(DigitArray.backersNeeded(new_digit_count));
        this.array = .{
            .digit_backers = this.digit_backers.items,
            .length = new_digit_count,
        };
    }

    pub fn copy(this: *DigitArrayManaged, other: DigitArray) std.mem.Allocator.Error!void {
        try this.digit_backers.resize(other.digit_backers.len);
        @memcpy(this.digit_backers.items, other.digit_backers);

        this.array = .{
            .digit_backers = this.digit_backers.items,
            .length = other.length,
        };
    }
};

pub const VirtualDigitArray = struct {
    array: DigitArray,
    virtual_idx: usize,

    pub const zero_length = VirtualDigitArray.fromDigitArray(.{
        .digit_backers = &.{},
        .length = 0,
    }, 0, 0, 0);

    pub fn fromDigitArray(array: DigitArray, virtual_x: usize, virtual_y: usize, virtual_bits: usize) VirtualDigitArray {
        return .{
            .array = array,
            .virtual_idx = makeVirtualIdx(virtual_x, virtual_y, virtual_bits),
        };
    }

    pub fn get(this: VirtualDigitArray, idx: usize) DigitArray.Digit {
        if (idx < this.array.length) {
            return this.array.get(idx);
        }

        const virtual_selector_digit_idx = idx - this.array.length;

        return @intCast((this.virtual_idx >> @intCast((virtual_selector_digit_idx) * 2)) & 0b11);
    }
};

pub const DigitArray = struct {
    const Backer = u8;
    const backer_bits = @typeInfo(Backer).int.bits;

    const Digit = u2;
    const digit_bits = @typeInfo(Digit).int.bits;
    const digits_per_backer = backer_bits / digit_bits;

    digit_backers: []Backer,
    length: usize,

    fn backersNeeded(digit_count: usize) usize {
        return std.math.divCeil(usize, digit_count, digits_per_backer) catch unreachable;
    }

    pub fn init(allocator: std.mem.Allocator, digit_count: usize) std.mem.Allocator.Error!DigitArray {
        const res: DigitArray = .{
            .digit_backers = try allocator.alloc(Backer, backersNeeded(digit_count)),
            .length = digit_count,
        };

        return res;
    }

    pub fn initFromSlice(allocator: std.mem.Allocator, to_copy: []const u2) std.mem.Allocator.Error!DigitArray {
        const res: DigitArray = .{
            .digit_backers = try allocator.alloc(Backer, std.math.divCeil(usize, to_copy.len, digits_per_backer) catch unreachable),
            .length = to_copy.len,
        };

        for (to_copy, 0..) |digit, i| {
            res.set(i, digit);
        }

        return res;
    }

    pub fn deinit(this: DigitArray, allocator: std.mem.Allocator) void {
        allocator.free(this.digit_backers);
    }

    pub fn set(this: DigitArray, idx: usize, digit: Digit) void {
        if (Backer == Digit) {
            this.digit_backers[idx] = digit;
            return;
        }

        const backer_idx = idx / digits_per_backer;
        const bit_offset: std.math.Log2Int(Backer) = @intCast((idx % digits_per_backer) * digit_bits);

        var mask = ((@as(Backer, 1) << digit_bits) - 1);
        mask <<= bit_offset;
        mask = ~mask;

        const adder = @as(Backer, digit) << bit_offset;

        this.digit_backers[backer_idx] = (this.digit_backers[backer_idx] & mask) | adder;
    }

    pub fn get(this: DigitArray, idx: usize) Digit {
        if (Backer == Digit) {
            return this.digit_backers[idx];
        }

        const backer_idx = idx / digits_per_backer;
        const bit_offset: std.math.Log2Int(Backer) = @intCast((idx % digits_per_backer) * digit_bits);

        const mask = ((@as(Backer, 1) << digit_bits) - 1);

        const shifted = this.digit_backers[backer_idx] >> bit_offset;

        return @intCast(shifted & mask);
    }

    pub fn isMinX(this: DigitArray) bool {
        for (0..this.length) |i| {
            if (this.get(i) & 0b01 == 0b01) {
                return false;
            }
        }

        return true;
    }

    pub fn isMinY(this: DigitArray) bool {
        for (0..this.length) |i| {
            if (this.get(i) & 0b10 == 0b10) {
                return false;
            }
        }

        return true;
    }

    pub fn isMaxX(this: DigitArray) bool {
        for (0..this.length) |i| {
            if (this.get(i) & 0b01 == 0) {
                return false;
            }
        }

        return true;
    }

    pub fn isMaxY(this: DigitArray) bool {
        for (0..this.length) |i| {
            if (this.get(i) & 0b10 == 0) {
                return false;
            }
        }

        return true;
    }

    pub fn isMaxXBelow(this: DigitArray, length: usize) bool {
        for (0..length) |i| {
            if (this.get(i) & 0b01 == 0) {
                return false;
            }
        }

        return true;
    }

    pub fn isMaxYBelow(this: DigitArray, length: usize) bool {
        for (0..length) |i| {
            if (this.get(i) & 0b10 == 0) {
                return false;
            }
        }

        return true;
    }

    pub fn incrementX(this: DigitArray) void {
        var i: usize = this.length - 1;
        while (true) {
            const digit = this.get(i);
            if (digit & 0b01 == 0b01) {
                this.set(i, digit & 0b10);
            } else {
                this.set(i, digit | 0b01);
                break;
            }

            i -= 1;
        }
    }

    pub fn incrementY(this: DigitArray) void {
        var i: usize = this.length - 1;
        while (true) {
            const digit = this.get(i);
            if (digit & 0b10 == 0b10) {
                this.set(i, digit & 0b01);
            } else {
                this.set(i, digit | 0b10);
                break;
            }

            i -= 1;
        }
    }

    pub fn decrementX(this: DigitArray) void {
        var i: usize = this.length - 1;
        while (true) {
            const digit = this.get(i);
            if (digit & 0b01 == 0b00) {
                this.set(i, digit | 0b01);
            } else {
                this.set(i, digit & 0b10);
                break;
            }

            i -= 1;
        }
    }

    pub fn decrementY(this: DigitArray) void {
        var i: usize = this.length - 1;
        while (true) {
            const digit = this.get(i);
            if (digit & 0b10 == 0b00) {
                this.set(i, digit | 0b10);
            } else {
                this.set(i, digit & 0b01);
                break;
            }

            i -= 1;
        }
    }
};

fn readDigitsToBytes(
    digit_array: anytype,
    starting_idx: usize,
    min_idx: usize,
    max_idx: usize,
    comptime num_to_read: usize,
    bytes: *[std.math.divCeil(usize, num_to_read, 4) catch unreachable]u8,
) void {
    var idx = starting_idx;

    for (bytes) |*byte| {
        byte.* = 0;
        for (0..4) |i| {
            const digit: u8 = digit_array.get(idx);

            if (idx < max_idx - 1) {
                idx += 1;
            } else {
                idx = min_idx;
            }

            byte.* |= digit << @intCast(i * 2);
        }
    }

    const leftover_digits = num_to_read % 4;
    const end_mask = (1 << (leftover_digits * 2)) - 1;

    bytes[bytes.len - 1] &= end_mask;
}

pub fn getArrayFromDigits(
    digit_array: anytype,
    comptime length: usize,
    comptime T: type,
    idx: *usize,
    position_start: usize,
    digit_count: usize,
) [length]T {
    const t_bits = @typeInfo(T).int.bits;

    if (t_bits % DigitArray.digit_bits == 0) {
        return getArrayFromDigitsAligned(digit_array, length, T, idx, position_start, digit_count);
    }

    return getArrayFromDigitsMisaligned(digit_array, length, T, idx, position_start, digit_count);
}

fn getArrayFromDigitsAligned(
    digit_array: anytype,
    comptime length: usize,
    comptime T: type,
    idx: *usize,
    position_start: usize,
    digit_count: usize,
) [length]T {
    const t_bits = @typeInfo(T).int.bits;

    var res: [length]T = @splat(0);

    const digits_per_t = @divExact(t_bits, DigitArray.digit_bits);

    var digit_idx: usize = idx.*;
    defer idx.* = digit_idx;

    for (&res) |*res_val| {
        for (0..digits_per_t) |i| {
            const digit = digit_array.get(digit_idx);

            if (digit_idx < digit_count - 1) {
                digit_idx += 1;
            } else {
                digit_idx = position_start;
            }

            res_val.* |= @as(T, digit) << @intCast(i * DigitArray.digit_bits);
        }
    }

    return res;
}

fn getArrayFromDigitsMisaligned(
    digit_array: anytype,
    comptime length: usize,
    comptime T: type,
    idx: *usize,
    position_start: usize,
    digit_count: usize,
) [length]T {
    const t_bits = @typeInfo(T).int.bits;

    const res_bits = t_bits * length;

    var res: [length]T = @splat(0);

    const digits_in_res = comptime std.math.divCeil(usize, res_bits, DigitArray.digit_bits) catch unreachable;

    var digit_idx = idx.*;
    defer idx.* = digit_idx;

    outer: for (0..digits_in_res) |i| {
        const digit = digit_array.get(digit_idx);

        if (digit_idx < digit_count - 1) {
            digit_idx += 1;
        } else {
            digit_idx = position_start;
        }

        for (0..DigitArray.digit_bits) |digit_bit_idx| {
            const res_bit_idx = i * DigitArray.digit_bits + digit_bit_idx;

            const res_idx = res_bit_idx / t_bits;
            if (res_idx >= res.len) {
                break :outer;
            }

            const res_bit_offset = res_bit_idx % t_bits;

            const digit_bit: u1 = @intCast((digit >> @intCast(digit_bit_idx)) & 1);

            res[res_idx] |= @as(T, digit_bit) << @intCast(res_bit_offset);
        }
    }

    return res;
}

// Same as clampWrap(val + 1, max), but
// val must be less than max.
fn clampWrapIncrement(val: anytype, max: anytype) @TypeOf(val) {
    std.debug.assert(val < max);

    return if (val == max - 1) 0 else val + 1;
}

fn lcgInRange(seed: u32, max: u32) u32 {
    var res: u64 = lcg32(seed);
    res *= max - 1;
    res >>= 32;
    return @intCast(res);

    // var x = seed;

    // var bitmask: u32 = 1;
    // while (bitmask < max) {
    //     bitmask = (bitmask << 1) | 1; // Create a mask for the nearest power of two.
    // }

    // while (true) {
    //     x = xorshift32(x);
    //     const result = x & bitmask;

    //     if (result < max) {
    //         return result;
    //     }
    // }

    // return seed % max;

    // if (max == 1) {
    //     return 0;
    // }

    // var res = seed;

    // res >>= @intCast(@clz(max) + 1);

    // return res;
}

fn clampWrap(val: anytype, max: anytype) @TypeOf(val) {

    // if (true) return val % max;

    // std.debug.assert(val < max * 2);

    if (val >= max) {
        return 0;

        // return val & ((@as(@TypeOf(max), 1) << std.math.log2_int(@TypeOf(max), max)) - 1);

        // const jumbled = lcg32(val);
        // return @intCast((@as(u64, jumbled) * @as(u64, max - 1)) >> 32);

        // return val - max;
        // return val % max;
    } else {
        return val;
    }
}

const EncodedChunk = struct {
    splitters: [3 * 3 + 1]u8,

    const digits_per_chunk = (3 * 3) * 4 + 3;

    const dummy_zero = std.mem.zeroes(EncodedChunk);

    pub fn fromDigits(digits: VirtualDigitArray, idx: usize, position_start: usize, digit_count: usize) EncodedChunk {
        var res: EncodedChunk = undefined;

        // var running_idx = idx;
        // res.splitters[0..9].* = getArrayFromDigits(digits, 3 * 3, u8, &running_idx, position_start, digit_count);

        // const last_splitter: [1]u6 = getArrayFromDigits(digits, 1, u6, &running_idx, position_start, digit_count);
        // res.splitters[9] = last_splitter[0];

        readDigitsToBytes(digits, idx, position_start, digit_count, digits_per_chunk, &res.splitters);

        return res;
    }

    pub fn toDigits(this: EncodedChunk) [digits_per_chunk]u2 {
        var res: [digits_per_chunk]u2 = undefined;
        var res_idx: usize = 0;

        for (0..3 * 3) |i| {
            for (0..4) |k| {
                res[res_idx] = @intCast((this.splitters[i] >> @intCast((k) * 2)) & 0b11);
                res_idx += 1;
            }
        }

        for (0..3) |k| {
            res[res_idx] = @intCast((this.splitters[9] >> @intCast((k) * 2)) & 0b11);
            res_idx += 1;
        }

        std.debug.assert(res_idx == digits_per_chunk);

        return res;
    }
};

pub fn encodeColors(allocator: std.mem.Allocator, colors: []const Color) !DigitArray {
    var total_digits: usize = 0;
    var pow: usize = 1;
    while (pow < colors.len) {
        total_digits += pow * EncodedChunk.digits_per_chunk;
        pow *= 4;
    }

    const square_size = std.math.sqrt(colors.len);
    const chunk_count = std.math.log2(square_size) + 1;

    const chunks = try allocator.alloc([]const Color, chunk_count);
    defer allocator.free(chunks);

    chunks[0] = colors;
    for (chunks[1..], 0..) |*chunk, i| {
        const prev_chunk = chunks[i];
        chunk.* = try averageColors(allocator, prev_chunk);
    }

    defer for (chunks) |chunk| {
        if (chunk.len != colors.len) {
            allocator.free(chunk);
        }
    };

    std.mem.reverse([]const Color, chunks);

    const digits = try DigitArray.init(allocator, total_digits);
    @memset(digits.digit_backers, std.math.maxInt(DigitArray.Backer));

    var digit_idx: usize = 0;
    pow = 1;
    for (chunks[1..chunks.len], 0..) |chunk, i| {
        const prev_chunk = chunks[i];
        const parent_square_size = std.math.sqrt(prev_chunk.len);

        for (0..parent_square_size) |parent_y| {
            for (0..parent_square_size) |parent_x| {
                const idx_offset = makeInverseVirtualIdx(parent_x, parent_y);

                const idx = digit_idx + idx_offset;

                const child_indices = childIndices(parent_x, parent_y, parent_square_size);

                var child_colors: [4]Color = undefined;
                for (&child_colors, &child_indices) |*child_color, child_idx| {
                    child_color.* = chunk[child_idx];
                }

                const splitters = getSplitters(prev_chunk[parent_y * parent_square_size + parent_x], child_colors);

                const encoded_chunk: EncodedChunk = .{
                    .splitters = splitters,
                };

                const encoded_chunk_digits = encoded_chunk.toDigits();

                for (encoded_chunk_digits, idx * encoded_chunk_digits.len..(idx + 1) * encoded_chunk_digits.len) |digit, j| {
                    digits.set(j, digit);
                }
            }
        }

        digit_idx += pow;

        pow *= 4;
    }

    // std.debug.assert(total_digits == digit_idx * EncodedChunk.digits_per_chunk);

    // TODO calculate actual minimum for this value
    const padding_count = std.math.log2(digits.length) + 64;

    // TODO calculate actual minimum for this value
    const base_3_max_digits = 20;

    // TODO calculate actual minimum for this value
    const starting_zero_splitters = 5;

    const core_command_digits_count = base_3_max_digits + (starting_zero_splitters + 1) + base_3_max_digits;

    const ignore_count = std.math.log2(square_size) - 1;
    const ignore_wait_count = core_command_digits_count + 1;

    var dummy_ignore_digits = std.ArrayList(u2).init(allocator);
    defer dummy_ignore_digits.deinit();

    var dummy_ignore_list_writer: ArrayListDigitWriter = .{ .list = &dummy_ignore_digits };
    const dummy_ignore_writer = dummy_ignore_list_writer.writer();

    try CommandState.Command.IgnoreAfter.encode(dummy_ignore_writer, .{
        .ignore_count = @intCast(ignore_count),
        .wait_count = ignore_wait_count,
    });

    const starting_command_digits_count = dummy_ignore_digits.items.len + padding_count;

    var color_find_digits = std.ArrayList(u2).init(allocator);
    defer color_find_digits.deinit();

    var color_find_list_writer: ArrayListDigitWriter = .{ .list = &color_find_digits };
    const color_find_writer = color_find_list_writer.writer();

    for (0..starting_zero_splitters) |_| {
        try color_find_digits.append(0);

        for (0..EncodedChunk.digits_per_chunk) |i| {
            const splitter_digit_idx = i / 4;
            const splitter_digit_offset = i % 4;

            const digit = (zero_splitters[splitter_digit_idx] >> @intCast(splitter_digit_offset * 2)) & 0b11;

            try color_find_digits.append(@intCast(digit));
        }
    }

    var seek_and_set_position_digits = std.ArrayList(u2).init(allocator);
    defer seek_and_set_position_digits.deinit();

    var seek_and_set_position_list_writer: ArrayListDigitWriter = .{ .list = &seek_and_set_position_digits };
    const seek_and_set_position_writer = seek_and_set_position_list_writer.writer();

    try CommandState.Command.SetPosition.encodePadded(
        seek_and_set_position_writer,
        @intCast(digits.length + starting_command_digits_count + core_command_digits_count - 1),
        base_3_max_digits,
    );

    try seek_and_set_position_digits.append(3);

    {
        try encodeColorSearch(
            color_find_writer,
            seek_and_set_position_digits.items,
            .{
                .r = 128,
                .g = 128,
                .b = 128,
                .a = 255,
            },
            chunks[0][0],
        );
    }

    var starting_command_digits = std.ArrayList(u2).init(allocator);
    defer starting_command_digits.deinit();

    var starting_command_list_writer: ArrayListDigitWriter = .{ .list = &starting_command_digits };
    const starting_command_writer = starting_command_list_writer.writer();

    var core_command_digits = std.ArrayList(u2).init(allocator);
    defer core_command_digits.deinit();

    var core_command_list_writer: ArrayListDigitWriter = .{ .list = &core_command_digits };
    const core_command_writer = core_command_list_writer.writer();

    try starting_command_digits.appendNTimes(3, padding_count);

    const set_linear_position_idx = core_command_digits.items.len;
    try CommandState.Command.SetLinearPosition.encodePadded(core_command_writer, 0, base_3_max_digits);
    const set_linear_position_end_idx = core_command_digits.items.len;

    try core_command_digits.appendNTimes(0, starting_zero_splitters + 1);

    try core_command_digits.appendSlice(seek_and_set_position_digits.items[0 .. seek_and_set_position_digits.items.len - 1]);

    try CommandState.Command.IgnoreAfter.encode(starting_command_writer, .{
        .ignore_count = @intCast(ignore_count),
        .wait_count = ignore_wait_count,
    });

    var set_linear_position_digits = std.ArrayList(u2).init(allocator);
    defer set_linear_position_digits.deinit();

    var set_linear_position_list_writer: ArrayListDigitWriter = .{ .list = &set_linear_position_digits };
    const set_linear_position_writer = set_linear_position_list_writer.writer();

    try CommandState.Command.SetLinearPosition.encodePadded(
        set_linear_position_writer,
        @intCast(color_find_digits.items.len + digits.length + starting_command_digits.items.len + set_linear_position_end_idx - 1),
        base_3_max_digits,
    );

    @memcpy(core_command_digits.items[set_linear_position_idx..set_linear_position_end_idx], set_linear_position_digits.items);

    const digits_with_command = try DigitArray.init(
        allocator,
        color_find_digits.items.len + digits.length + starting_command_digits.items.len + core_command_digits.items.len,
    );
    var digits_with_command_idx: usize = 0;

    for (color_find_digits.items) |command_digit| {
        digits_with_command.set(digits_with_command_idx, command_digit);
        digits_with_command_idx += 1;
    }

    for (0..digits.length) |i| {
        digits_with_command.set(digits_with_command_idx, digits.get(i));
        digits_with_command_idx += 1;
    }

    for (starting_command_digits.items) |command_digit| {
        digits_with_command.set(digits_with_command_idx, command_digit);
        digits_with_command_idx += 1;
    }

    for (core_command_digits.items) |command_digit| {
        digits_with_command.set(digits_with_command_idx, command_digit);
        digits_with_command_idx += 1;
    }

    digits.deinit(allocator);

    return digits_with_command;
}

fn makeVirtualIdx(x: usize, y: usize, bit_count: usize) usize {
    if (bit_count == 0) {
        return 0;
    }

    const usize_bits = @typeInfo(usize).int.bits;
    const half_usize_bits = usize_bits / 2;
    const HalfUsize = std.meta.Int(.unsigned, half_usize_bits);
    const HalfUSizeVec = @Vector(half_usize_bits, u1);

    const parent_x_vec: HalfUSizeVec = @bitCast(@bitReverse(@as(HalfUsize, @intCast(x))) >> @intCast(half_usize_bits - bit_count));
    const parent_y_vec: HalfUSizeVec = @bitCast(@bitReverse(@as(HalfUsize, @intCast(y))) >> @intCast(half_usize_bits - bit_count));

    return @bitCast(std.simd.interlace(.{ parent_x_vec, parent_y_vec }));
}

fn makeInverseVirtualIdx(x: usize, y: usize) usize {
    const usize_bits = @typeInfo(usize).int.bits;
    const half_usize_bits = usize_bits / 2;
    const HalfUsize = std.meta.Int(.unsigned, half_usize_bits);
    const HalfUSizeVec = @Vector(half_usize_bits, u1);

    const parent_x_vec: HalfUSizeVec = @bitCast(@as(HalfUsize, @intCast(x)));
    const parent_y_vec: HalfUSizeVec = @bitCast(@as(HalfUsize, @intCast(y)));

    return @bitCast(std.simd.interlace(.{ parent_x_vec, parent_y_vec }));
}

fn averageColors(allocator: std.mem.Allocator, colors: []const Color) ![]Color {
    const averaged = try allocator.alloc(Color, colors.len / 4);

    const initial_square_size = std.math.sqrt(colors.len);
    const final_square_size = initial_square_size / 2;

    for (0..final_square_size) |averaged_y| {
        for (0..final_square_size) |averaged_x| {
            const initial_indices = childIndices(averaged_x, averaged_y, final_square_size);

            var average: SumColor = SumColor.fromColor(colors[initial_indices[0]]);
            for (initial_indices[1..]) |idx| {
                average = average.add(SumColor.fromColor(colors[idx]));
            }
            average.r += 1;
            average.g += 1;
            average.b += 1;
            average = average.divide(4);

            averaged[averaged_y * final_square_size + averaged_x] = average.toColor();
        }
    }

    return averaged;
}

fn splitterFromDigits(digits: [4]u2) usize {
    var splitter: usize = 0;
    for (&digits, 0..) |digit, i| {
        splitter |= @as(usize, digit) << @intCast(((i) * 2));
    }
    return splitter;
}

const SumColor = struct {
    r: u32,
    g: u32,
    b: u32,
    a: u32,

    pub fn fromColor(color: Color) SumColor {
        return .{
            .r = color.r,
            .g = color.g,
            .b = color.b,
            .a = color.a,
        };
    }

    pub fn toColor(this: SumColor) Color {
        return .{
            .r = @intCast(this.r),
            .g = @intCast(this.g),
            .b = @intCast(this.b),
            .a = @intCast(this.a),
        };
    }

    pub fn add(a: SumColor, b: SumColor) SumColor {
        return .{
            .r = a.r + b.r,
            .g = a.g + b.g,
            .b = a.b + b.b,
            .a = a.a + b.a,
        };
    }

    pub fn divide(this: SumColor, divisor: u32) SumColor {
        return .{
            .r = this.r / divisor,
            .g = this.g / divisor,
            .b = this.b / divisor,
            .a = this.a / divisor,
        };
    }

    pub fn multiply(this: SumColor, multiplier: u32) SumColor {
        return .{
            .r = this.r * multiplier,
            .g = this.g * multiplier,
            .b = this.b * multiplier,
            .a = this.a * multiplier,
        };
    }
};

pub fn encodeColorSearch(writer: DigitWriter, digit_path: []const u2, current_color_arg: Color, target_color_arg: Color) !void {
    if (digit_path.len == 0) {
        return;
    }

    const target_color = colorToArr(target_color_arg);

    const current_color = colorToArr(current_color_arg);

    var target_colors_arr: [4][3]u8 = undefined;

    var color_budget: [3]usize = undefined;

    for (&color_budget, &current_color) |*color_budget_component, color_component| {
        color_budget_component.* = @as(usize, color_component) * 4;
    }

    for (0..3) |i| {
        if (color_budget[i] < target_color[i]) {
            target_colors_arr[0][i] = @intCast(color_budget[i]);
        } else if ((255 * 4) - color_budget[i] < (255 - target_color[i])) {
            target_colors_arr[0][i] = @intCast(255 - ((255 * 4) - color_budget[i]));
        } else {
            target_colors_arr[0][i] = target_color[i];
        }
        color_budget[i] -= target_colors_arr[0][i];
    }

    target_colors_arr[1..].* = @splat(@splat(0));

    {
        for (0..3) |j| {
            const distribution = distributeValues(usize, 3, color_budget[j], @splat(255));
            for (&distribution, 1..4) |distribution_value, i| {
                target_colors_arr[i][j] = @intCast(distribution_value);
            }

            // var i: usize = 1;
            // while (color_budget[j] > 0 and i < 4) : (i += 1) {
            //     const space_left = 255 - target_colors_arr[i][j];

            //     const diff = @min(color_budget[j], space_left);

            //     target_colors_arr[i][j] += diff;

            //     color_budget[j] -= diff;
            // }
        }
    }

    var color_modifiers: [3]usize = @splat(1);

    for (0..3) |i| {
        if (target_color[i] > target_colors_arr[0][i]) {
            const diff = @min(target_color[i], @as(usize, target_colors_arr[0][i]) + 2);

            color_modifiers[0] = (diff - target_colors_arr[0][i]) + 1;

            target_colors_arr[0][i] = @intCast(diff);
        }
    }

    for (0..3) |i| {
        if (target_color[i] < target_colors_arr[0][i]) {
            color_modifiers[0] = 0;

            target_colors_arr[0][i] -= 1;
        }
    }

    // for (&current_color, &target_color, 0..3) |color_component, target_color_component, i| {
    //     var total_color_component = @as(u16, color_component) * 4;

    //     const total_orig = total_color_component;

    //     if (total_color_component < target_color_component) {
    //         total_color_component = @min(target_color_component, total_color_component + 2);
    //     }

    //     if (total_color_component > target_color_component) {
    //         total_color_component -= 1;
    //     }

    //     if (total_color_component <= 255 * 3 + @as(u16, target_color_component)) {
    //         target_colors_arr[0][i] = @intCast(@min(total_color_component, target_color_component));
    //     } else {
    //         target_colors_arr[0][i] = @intCast(total_color_component - 255 * 3);
    //     }

    //     total_color_component -= target_colors_arr[0][i];

    //     const altered_color_component: u8 = @intCast(total_color_component / 3);
    //     const excess = total_color_component % 3;

    //     for (0..3) |j| {
    //         target_colors_arr[j + 1][i] = altered_color_component;
    //         if (j < excess) {
    //             target_colors_arr[j + 1][i] += 1;
    //         }
    //     }

    //     var sum: u16 = 0;

    //     for (0..4) |j| {
    //         sum += target_colors_arr[j][i];
    //     }

    //     std.debug.assert(sum >= total_orig - 1 and sum <= total_orig + 2);
    // }

    const target_color_digit = digit_path[0];

    const temp = target_colors_arr[0];
    target_colors_arr[0] = target_colors_arr[target_color_digit];
    target_colors_arr[target_color_digit] = temp;

    var target_colors: [4]Color = undefined;

    for (&target_colors, &target_colors_arr) |*current_target_color, target_color_arr| {
        current_target_color.* = arrToColor(target_color_arr);
    }

    const splitters = getSplitters(current_color_arg, target_colors);
    const encoded_chunk: EncodedChunk = .{
        .splitters = splitters,
    };
    const encoded_chunk_digits = encoded_chunk.toDigits();

    try writer.write(target_color_digit);
    for (&encoded_chunk_digits) |digit| {
        try writer.write(digit);
    }

    // jsPrint("pd: {any} {any} {}", .{ target_colors_arr, target_color, target_color_digit });

    try encodeColorSearch(writer, digit_path[1..], target_colors[target_color_digit], target_color_arg);
}

const zero_splitters = blk: {
    var zero_splitters_init: [10]u8 = @splat(0);
    zero_splitters_init[0..9].* = @splat(128);
    zero_splitters_init[9] = 0b111111;

    break :blk zero_splitters_init;
};

fn hash32(x: u32) u32 {
    return x *% 1664525;
}

fn hash32Inverse(x: u32) u32 {
    return x *% 4276115653;
}

const hash72_increment = 2534895234121;

fn hash72(x: u72) u72 {
    comptime var mul: u72 = 0;
    // mul  = 18519084246547628289
    inline for (0..72 / 8) |i| {
        mul |= (0b1) << (i * 8);
    }

    const res = (x *% 12157665459056928801) +% hash72_increment;

    // const res = (x *% mul) +% hash72_increment;

    std.debug.assert(x == hash72Inverse(res));

    return res;
}

fn hash72Inverse(x: u72) u72 {
    return (x -% hash72_increment) *% 4679407515872480828385;

    // return (x -% hash72_increment) *% 4722366482869645213441;
}

fn splitterApplyColorSalt(splitters: [10]u8, color: [3]u8) [10]u8 {
    if (isZeroSplitter(splitters)) {
        return splitters;
    }

    var res: [10]u8 = undefined;
    var res_int = std.mem.readInt(u72, splitters[0..9], .little);
    res_int = res_int;

    res_int ^= std.mem.readInt(u24, &color, .little);

    res_int = hash72(res_int);

    std.mem.writeInt(u72, res[0..9], res_int, .little);
    res[9] = splitters[9];

    return res;
}

fn splitterApplyColorSaltInverse(splitters: [10]u8, color: [3]u8) [10]u8 {
    if (isZeroSplitter(splitters)) {
        return splitters;
    }

    var res: [10]u8 = undefined;
    var res_int = std.mem.readInt(u72, splitters[0..9], .little);
    res_int = res_int;

    res_int = hash72Inverse(res_int);

    res_int ^= std.mem.readInt(u24, &color, .little);

    std.mem.writeInt(u72, res[0..9], res_int, .little);
    res[9] = splitters[9];

    return res;
}

fn isZeroSplitter(splitters: [10]u8) bool {
    return splittersEqual(splitters, zero_splitters);
}

fn splittersEqual(a: [10]u8, b: [10]u8) bool {
    return @as(u80, @bitCast(a)) == @as(u80, @bitCast(b));
}

pub fn splitColor(color: [3]u8, splitters_arg: [10]u8) [4][3]u8 {
    var splitters = splitters_arg;

    splitters = splitterApplyColorSalt(splitters, color);

    const color_modifiers_flat = splitters[3 * 3];

    var total_color_bits_ored: u16 = 0;

    var res_colors: [4][3]u8 = undefined;

    for (0..3) |i| {
        const color_modifier: u2 = @truncate(color_modifiers_flat >> @intCast(i * 2));

        var total_color_component: i16 = color[i];
        total_color_component *= 4;
        total_color_component += color_modifier;
        total_color_component -= 1;

        for (0..3) |j| {
            total_color_component -= splitters[j * 3 + i];
        }

        const total_color_component_bits: u16 = @bitCast(total_color_component);

        total_color_bits_ored |= total_color_component_bits;

        res_colors[3][i] = @truncate(total_color_component_bits);

        res_colors[i] = splitters[i * 3 ..][0..3].*;
    }

    if (total_color_bits_ored >> 8 != 0) {
        if (isZeroSplitter(splitters)) {
            return splitColorZeroPath(color, splitters);
        }
        return splitColorAltPath(color, splitters);
    }

    assertValidSplit(color, res_colors);

    return res_colors;
}

// Not optimal, don't use.
fn splitColorSimd(color: [3]u8, splitters_arg: [10]u8) [4][3]u8 {
    var splitters = splitters_arg;

    splitters = splitterApplyColorSalt(splitters, color);

    const color_modifiers_flat = splitters[3 * 3];

    var total_color: @Vector(3, i16) = color;
    total_color *= @splat(4);

    var color_modifiers: @Vector(3, i16) = undefined;
    for (0..3) |i| {
        var color_modifier: i16 = ((color_modifiers_flat) >> @intCast(i * 2)) & 0b11;
        color_modifier -= 1;
        color_modifiers[i] = color_modifier;
    }

    total_color += color_modifiers;

    for (0..3) |i| {
        total_color -= splitters[i * 3 ..][0..3].*;
    }

    var total_color_bits: @Vector(3, u16) = @bitCast(total_color);
    total_color_bits >>= @splat(8);

    if (@reduce(.Or, total_color_bits) != 0) {
        if (isZeroSplitter(splitters)) {
            return splitColorZeroPath(color, splitters);
        }
        return splitColorAltPath(color, splitters);
    }

    var res_colors: [4][3]u8 = undefined;
    for (0..3) |i| {
        for (0..3) |j| {
            res_colors[j][i] = splitters[j * 3 + i];
        }

        const color_modifier: u2 = @truncate((color_modifiers_flat) >> @intCast(i * 2));

        var total_color_component = color[i];
        total_color_component *%= 4;
        total_color_component += color_modifier;
        total_color_component -%= 1;

        for (0..3) |j| {
            total_color_component -%= splitters[j * 3 + i];
        }

        res_colors[3][i] = total_color_component;
    }

    assertValidSplit(color, res_colors);

    return res_colors;
}

// Simplified reference implementation, functionally the same as splitColor.
fn splitColorSimplified(color: [3]u8, splitters_arg: [10]u8) [4][3]u8 {
    var splitters = splitters_arg;

    splitters = splitterApplyColorSalt(splitters, color);

    const color_modifiers_flat = splitters[3 * 3];

    var res_colors: [4][3]u8 = undefined;
    for (0..3) |i| {
        const color_modifier: u2 = @truncate(color_modifiers_flat >> @intCast(i * 2));

        var total_color_component: i16 = color[i];
        total_color_component *= 4;
        total_color_component += color_modifier;
        total_color_component -= 1;

        for (0..3) |j| {
            const splitter = splitters[j * 3 + i];
            total_color_component -= splitter;
            res_colors[j][i] = splitter;
        }

        if (total_color_component < 0 or total_color_component > 255) {
            if (isZeroSplitter(splitters)) {
                return splitColorZeroPath(color, splitters);
            }
            return splitColorAltPath(color, splitters);
        }

        res_colors[3][i] = @intCast(total_color_component);
    }

    assertValidSplit(color, res_colors);

    return res_colors;
}

fn splitColorZeroPath(color: [3]u8, splitters: [10]u8) [4][3]u8 {
    var res_colors: [4][3]u8 = undefined;

    for (&color, 0..3) |color_component, i| {
        var total_color_component = @as(u16, color_component) * 4;

        if (total_color_component < 128) {
            total_color_component = @min(128, total_color_component + 2);
        }

        if (total_color_component > 128) {
            total_color_component -= 1;
        }

        if (total_color_component <= 255 * 3 + 128) {
            res_colors[0][i] = @intCast(@min(total_color_component, 128));
        } else {
            res_colors[0][i] = @intCast(total_color_component - 255 * 3);
        }

        total_color_component -= res_colors[0][i];

        const altered_color_component: u8 = @intCast(total_color_component / 3);
        var target: i16 = @intCast(total_color_component % 3);

        if (true) {
            for (0..3) |j| {
                res_colors[j + 1][i] = altered_color_component;
                if (j < target) {
                    res_colors[j + 1][i] += 1;
                }
            }

            continue;
        }

        if (altered_color_component >= 128) {
            target = -target;
        }

        const splitter_code: u32 = std.mem.readInt(u24, splitters[i * 3 ..][0..3], .little);

        const base = if (altered_color_component < 128) @as(u16, altered_color_component) + 1 else 256 - @as(u16, altered_color_component);

        var diffs: [3]u8 = undefined;
        for (&diffs, 0..) |*diff, j| {
            const splitter_code_component: u8 = @truncate(splitter_code >> @intCast(j * 8));
            diff.* = @intCast((@as(u16, splitter_code_component) * @as(u16, base)) >> 8);
            target += diff.*;
        }

        const min_diff: u8 = @bitCast(@as(i8, @intCast(@divFloor(target, 3))));
        const excess_diff = @mod(target, 3);

        const extra_code = splitter_code;

        var excess_idx: usize = extra_code % 3;

        const mul: u8 = if (altered_color_component < 128) 1 else 255;
        for (0..3) |j| {
            const excess_inner: u8 = @intFromBool(excess_idx < excess_diff);

            excess_idx = (excess_idx + 1) % 3;

            res_colors[j + 1][i] = altered_color_component -% (diffs[j] *% mul) +% (min_diff *% mul) +% (excess_inner *% mul);
        }
    }

    assertValidSplit(color, res_colors);

    return res_colors;
}

fn splitColorAltPath(color: [3]u8, splitters: [10]u8) [4][3]u8 {
    if (std.simd.suggestVectorLength(u8) != null) {
        return splitColorAltPathSimd(color, splitters);
    }

    var res_colors: [4][3]u8 = undefined;

    for (0..3) |i| {
        const color_component = color[i];

        const splitter_code: u32 = std.mem.readInt(u24, splitters[i * 3 ..][0..3], .little);

        // min for color_component less than: 110
        // max for color_component less than: 146
        const base = if (color_component < 128) @as(u16, color_component) + 1 else 256 - @as(u16, color_component);

        var target: u16 = 0;
        var diffs: [4]u8 = undefined;

        for (&diffs, 0..) |*diff, j| {
            const splitter_code_component: u6 = @truncate(splitter_code >> @intCast(j * 6));
            diff.* = @intCast((@as(u16, splitter_code_component) * @as(u16, base)) >> 6);
            target += diff.*;
        }

        const extra_code = splitter_code;

        // Adds 1 to total if color_component < 128, subtracts 1 otherwise.
        target += 1;

        const min_diff: u8 = @intCast(target / 4);
        const excess_diff = target % 4;

        var excess_idx: usize = extra_code % 4;

        const mul: u8 = if (color_component < 128) 1 else 255;
        for (0..4) |j| {
            const excess: u8 = @intFromBool(excess_idx < excess_diff);

            excess_idx = (excess_idx + 1) % 4;

            res_colors[j][i] = color_component -% (diffs[j] *% mul) +% (min_diff *% mul) +% (excess *% mul);
        }
    }

    assertValidSplit(color, res_colors);

    return res_colors;
}

fn splitColorAltPathSimd(color: [3]u8, splitters: [10]u8) [4][3]u8 {
    const color_component_vec: @Vector(3, u8) = color;

    var splitter_code_vec: @Vector(3, u32) = undefined;
    for (0..3) |i| {
        splitter_code_vec[i] = std.mem.readInt(u24, splitters[i * 3 ..][0..3], .little);
    }

    var base_vec1: @Vector(3, i16) = color_component_vec;
    base_vec1 += @splat(1);

    var base_vec2: @Vector(3, i16) = @splat(256);
    base_vec2 -= color_component_vec;

    const base_vec_pred = color_component_vec < @as(@Vector(3, u8), @splat(128));

    const base_vec: @Vector(3, u16) = @intCast(@select(i16, base_vec_pred, base_vec1, base_vec2));

    // Adds 1 to total if color_component < 128, subtracts 1 otherwise.
    var target_vec: @Vector(3, u16) = @splat(1);

    var diffs_vec: [4]@Vector(3, u8) = undefined;

    for (0..4) |i| {
        var splitter_code_component_vec = splitter_code_vec;
        splitter_code_component_vec >>= @splat(@intCast(i * 6));
        splitter_code_component_vec &= @splat((1 << 6) - 1);

        var diff: @Vector(3, u16) = @intCast(splitter_code_component_vec);
        diff *= base_vec;
        diff >>= @splat(6);

        diffs_vec[i] = @intCast(diff);
        target_vec += diff;
    }

    const min_diff_vec: @Vector(3, u8) = @intCast(target_vec / @as(@Vector(3, u16), @splat(4)));
    var excess_diff_vec = target_vec;
    excess_diff_vec %= @splat(4);

    const extra_code_vec = splitter_code_vec;
    var excess_idx_vec = extra_code_vec;
    excess_idx_vec %= @splat(4);

    var res_colors: [4][3]u8 = undefined;
    for (0..4) |j| {
        const excess_vec: @Vector(3, u8) = @intFromBool(excess_idx_vec < excess_diff_vec);

        excess_idx_vec += @splat(1);
        excess_idx_vec %= @splat(4);

        const res1 = min_diff_vec -% diffs_vec[j] +% excess_vec;
        const res2 = @as(@Vector(3, u8), @splat(0)) -% res1;
        res_colors[j] = color_component_vec +% @select(u8, base_vec_pred, res1, res2);
    }

    assertValidSplit(color, res_colors);

    return res_colors;
}

fn assertValidSplit(parent_color: [3]u8, child_colors: [4][3]u8) void {
    var child_sum: [3]u16 = @splat(0);

    for (&child_sum, 0..) |*child_sum_component, i| {
        for (0..4) |j| {
            child_sum_component.* += child_colors[j][i];
        }
    }

    for (&parent_color, &child_sum) |parent_color_component, child_sum_component| {
        const average = (child_sum_component + 1) / 4;
        // if (average != parent_color_component) {
        //     jsPrint("{} {}", .{ average, parent_color_component });
        //     jsPrint("{any} {any}", .{ parent_color, child_colors });
        // }
        std.debug.assert(average == parent_color_component);
    }
}

fn getSplitters(parent_color: Color, child_colors: [4]Color) [10]u8 {
    const color = colorToArr(parent_color);

    var splitters: [10]u8 = undefined;

    var res_colors: [4][3]u8 = undefined;
    for (&res_colors, &child_colors) |*res_color, child_color| {
        res_color.* = colorToArr(child_color);
    }

    const child_colors_arr = res_colors;

    assertValidSplit(color, child_colors_arr);

    var child_total_color: [3]usize = @splat(0);
    for (&child_total_color, 0..) |*child_total_color_component, i| {
        for (0..4) |j| {
            child_total_color_component.* += res_colors[j][i];
        }
    }

    var total_color: [3]usize = undefined;
    for (&total_color, &color) |*total_color_component, color_component| {
        total_color_component.* = @as(usize, color_component) * 4;
    }

    var color_modifiers: [3]usize = undefined;
    for (&child_total_color, &total_color, &color_modifiers) |child_total_color_component, total_color_component, *color_modifier| {
        color_modifier.* = (child_total_color_component + 1) - total_color_component;
    }

    std.mem.reverse(usize, &color_modifiers);

    var color_modifiers_flat: usize = 0;
    for (&color_modifiers) |color_modifier| {
        std.debug.assert(color_modifier < 4);

        color_modifiers_flat *= 4;
        color_modifiers_flat += color_modifier;
    }

    total_color = child_total_color;

    splitters[3 * 3 + 0] = @intCast(color_modifiers_flat);

    for (0..3) |i| {
        for (splitters[i * 3 .. (i + 1) * 3], 0..) |*splitter, j| {
            splitter.* = res_colors[i][j];
        }
    }

    splitters = splitterApplyColorSaltInverse(splitters, color);

    const tester = splitColor(color, splitters);
    if (!std.mem.eql([3]u8, &child_colors_arr, &tester)) {
        // jsPrint("{any} ", .{color});
        // jsPrint("{any} ", .{total_color});
        // jsPrint("{any} ", .{splitters});
        // jsPrint("{any} ", .{child_colors_arr});
        // jsPrint("{any} ", .{tester});
        // jsPrint(" ", .{});
    }

    std.debug.assert(std.mem.eql([3]u8, &child_colors_arr, &tester));

    return splitters;
}

fn scaleToRange(num: anytype, initial_range: anytype, target_range: anytype) @TypeOf(num) {
    if (initial_range > target_range) {
        const min_slots_per_value = initial_range / target_range;
        const extra_slots = initial_range % target_range;

        const slots_without_extra = target_range - extra_slots;

        if (num / min_slots_per_value < slots_without_extra) {
            return @intCast(num / min_slots_per_value);
        }

        return @intCast(slots_without_extra / min_slots_per_value + ((num / min_slots_per_value) - slots_without_extra) / (min_slots_per_value + 1));
    }

    const min_slots_per_value = target_range / initial_range;
    const extra_slots = target_range % initial_range;

    const slots_without_extra = initial_range - extra_slots;

    if (num < slots_without_extra) {
        return @intCast(num * min_slots_per_value);
    }

    return @intCast(slots_without_extra * min_slots_per_value + (num - slots_without_extra) * (min_slots_per_value + 1));
}

fn xorshift32(x: u32) u32 {
    var res = x;
    res ^= res << 13;
    res ^= res >> 17;
    res ^= res << 5;
    return res;
}

fn lcg32(x: u32) u32 {
    var res = x;
    // res *%= 134775813;
    // res +%= 1;

    res *%= 1664525;
    res +%= 1013904223;

    return res;
}

fn lcg32Inverse(x: u32) u32 {
    var res = x;

    res -%= 1013904223;
    res *%= 4276115653;

    return res;
}

fn lcg32Vec(x: anytype) @Vector(@typeInfo(@TypeOf(x)).vector.len, u32) {
    var res: @Vector(@typeInfo(@TypeOf(x)).vector.len, u32) = x;

    res *%= @splat(1664525);
    res +%= @splat(1013904223);

    return res;
}

// This is GPT code and isn't actually a proper inverse of reverseHash64.
fn hash64(key_arg: u64) u64 {
    var key = key_arg;

    // Reversible operations to mix the bits
    key = (~key) +% (key << 21); // key = (key * 2^21) + ~key
    key = key ^ (key >> 24);
    key = (key +% (key << 3)) +% (key << 8); // key * 265
    key = key ^ (key >> 14);
    key = (key +% (key << 2)) +% (key << 4); // key * 21
    key = key ^ (key >> 28);
    key = key +% (key << 31);
    return key;
}

// This is GPT code and isn't actually a proper inverse of hash64.
fn reverseHash64(hashed_key_arg: u64) u64 {
    var hashed_key = hashed_key_arg;

    // Inverse of each operation, reversed order
    hashed_key = hashed_key -% (hashed_key << 31);
    hashed_key = hashed_key ^ (hashed_key >> 28);
    hashed_key = (hashed_key -% (hashed_key << 2)) -% (hashed_key << 4);
    hashed_key = hashed_key ^ (hashed_key >> 14);
    hashed_key = (hashed_key -% (hashed_key << 3)) -% (hashed_key << 8);
    hashed_key = hashed_key ^ (hashed_key >> 24);
    hashed_key = (~hashed_key) -% (hashed_key << 21);
    return hashed_key;
}

fn colorToArr(color: Color) [3]u8 {
    return .{
        color.r,
        color.g,
        color.b,
    };
}

fn arrToColor(arr: [3]u8) Color {
    return .{
        .r = arr[0],
        .g = arr[1],
        .b = arr[2],
        .a = 255,
    };
}

fn distributeValues(comptime T: type, comptime count: comptime_int, target: T, maximums: [count]T) [count]T {
    var x = target;

    // Array of pointers to child values and their corresponding max values
    var values: [count]T = @splat(0);

    // First pass: Distribute an even amount across each child up to its max
    const initial_share = x / count;
    for (0..count) |i| {
        // Give each child the initial share, but don't exceed its max value
        if (initial_share <= maximums[i]) {
            values[i] = @intCast(initial_share);
            x -= initial_share;
        } else {
            values[i] = maximums[i];
            x -= maximums[i];
        }
    }

    // // Second pass: Distribute the remaining x, if any, while respecting max values
    // var i: usize = 0;
    // while (x > 0 and i < 4) {
    //     const remaining_capacity = maximums[i] - values[i];
    //     const amountToGive = if (remaining_capacity < x) remaining_capacity else x;
    //     values[i] += (amountToGive);
    //     x -= amountToGive;
    //     i += 1;
    // }

    for (0..count) |i| {
        const remaining_capacity = maximums[i] - values[i];
        const amountToGive = if (remaining_capacity < x) remaining_capacity else x;
        values[i] += (amountToGive);
        x -= amountToGive;
    }

    return values;
}
