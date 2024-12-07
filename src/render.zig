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

            this.output_colors[y][x] = this.states[this.output_colors_idx].color;

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

const CommandState = packed struct {
    command: Command,
    tag: CommandEnum,

    const CommandEnum = enum(u8) {
        set_position,
        set_linear_position,
        ignore_after,
        no_op,
    };

    const Command = packed union {
        set_position: SetPosition,
        set_linear_position: SetLinearPosition,
        // set_activation_digit: SetActivationDigit,
        ignore_after: IgnoreAfter,

        no_op: NoOp,

        const None = packed struct {
            const Result = void;
        };

        const SetPosition = packed struct {
            length_state: LengthState,

            const Result = usize;

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

            pub fn encodePadded(writer: DigitWriter, result: Result, min_digits: usize) !void {
                try writer.write(0);
                try LengthState.encodePadded(writer, result, min_digits - @min(min_digits, 1));
            }
        };

        const SetLinearPosition = packed struct {
            length_state: LengthState,

            const Result = usize;

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

            pub fn encodePadded(writer: DigitWriter, result: Result, min_digits: usize) !void {
                try writer.write(1);
                try LengthState.encodePadded(writer, result, min_digits - @min(min_digits, 1));
            }
        };

        const SetActivationDigit = packed struct {
            digit: u2,
            terminated: bool,

            pub const init: SetActivationDigit = .{
                .digit = 0,
                .terminated = false,
            };

            const Result = u2;

            pub fn getResult(this: SetActivationDigit) Result {
                return this.digit;
            }

            pub fn step(this: SetActivationDigit, reader_state: *const SelfConsumingReaderState, digit: u2) ?SetActivationDigit {
                _ = reader_state; // autofix
                if (this.terminated) {
                    return null;
                }
                return .{
                    .digit = digit,
                    .terminated = true,
                };
            }

            pub fn encode(writer: DigitWriter, result: Result) !void {
                try writer.write(2);
                try writer.write(result);
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
                wait_count: usize,
                ignore_count: usize,
            };

            pub fn getResult(this: IgnoreAfter) Result {
                return .{
                    .wait_count = this.length_state.value(),
                    .ignore_count = this.ignore_count,
                };
            }

            pub fn step(this: IgnoreAfter, reader_state: *const SelfConsumingReaderState, digit: u2) ?IgnoreAfter {
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
                try LengthState.encode(writer, result.ignore_count);
                try LengthState.encode(writer, result.wait_count);
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
            length: usize,

            const length_bits = @typeInfo(usize).int.bits;

            pub const init: LengthState = .{
                .length = 0,
            };

            pub fn terminated(this: LengthState) bool {
                return this.length >> (length_bits - 1) == 1;
            }

            pub fn value(this: LengthState) usize {
                return this.length & ((1 << length_bits - 1) - 1);
            }

            pub fn step(this: LengthState, digit: u2, modulo: usize) LengthState {
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

            pub fn encode(writer: DigitWriter, num: usize) !void {
                var power: usize = 1;
                while (power <= num) {
                    power *= 3;
                }
                power /= 3;

                var temp: usize = num;
                while (power > 0) {
                    try writer.write(@intCast((num / power) % 3));
                    temp /= 3;
                    power /= 3;
                }

                try writer.write(3);
            }

            pub fn encodePadded(writer: DigitWriter, num: usize, min_digits: usize) !void {
                var digits_required: usize = 1;
                {
                    var power: usize = 1;
                    while (power <= num) {
                        power *= 3;
                    }
                    power /= 3;

                    var temp: usize = num;
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
                    var power: usize = 1;
                    while (power <= num) {
                        power *= 3;
                    }
                    power /= 3;

                    var temp: usize = num;
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
    position: usize,
    offset: usize,
    offset_pow: usize,

    position_start: usize,

    digit_count: usize,
    color: Color,

    command: CommandState,

    ignore_wait_count: usize,
    ignore_count: usize,

    linear_position: ?usize,

    pub fn init(digit_count: usize, color: Color) SelfConsumingReaderState {
        var res: SelfConsumingReaderState = .{
            .position = 0,
            .offset = 0,
            .offset_pow = 1,

            .position_start = 0,

            .digit_count = digit_count,
            .color = color,

            .command = undefined,

            .ignore_wait_count = 0,
            .ignore_count = 0,

            .linear_position = null,
        };

        res.command = CommandState.newCommand(&res, 0);
        return res;
    }

    fn setDigitIdx(this: *SelfConsumingReaderState, digit_idx: usize) void {
        var pow: usize = 1;
        var sum: usize = 0;
        while (sum <= digit_idx) {
            sum += pow * EncodedChunk.digits_per_chunk;
            pow *= 4;
        }

        pow /= 4;
        sum -= pow * EncodedChunk.digits_per_chunk;

        this.position = digit_idx - sum;
        this.offset = sum;
        this.offset_pow = pow;
    }

    fn iterateNoColor(noalias this: *const SelfConsumingReaderState, selector_digit: u2, digits: VirtualDigitArray, noalias next: *SelfConsumingReaderState) void {
        std.debug.assert(this.digit_count > 0);

        const modulo = this.digit_count - this.position_start;

        std.debug.assert(this.position + this.offset < modulo);

        const next_position = this.position * 4 + (@as(usize, selector_digit) * EncodedChunk.digits_per_chunk);

        const next_offset = this.offset + this.offset_pow * EncodedChunk.digits_per_chunk;
        if (next_position + next_offset >= modulo) {
            const next_digit_idx = clampWrap(next_position + next_offset, modulo);
            next.setDigitIdx(next_digit_idx);
        } else {
            next.position = next_position;
            next.offset = next_offset;
            next.offset_pow = this.offset_pow * 4;
        }

        next.digit_count = this.digit_count + 1;

        const command_result = this.command.step(this, selector_digit);

        next.command = command_result.next;

        next.position_start = this.position_start;

        next.linear_position = null;

        if (this.linear_position) |linear_position| {
            const next_linear_position = linear_position + 1 + EncodedChunk.digits_per_chunk;
            if (digits.get(linear_position) == selector_digit and next_linear_position < this.digit_count) {
                next.linear_position = next_linear_position;
            }
        }

        if (this.ignore_count > 0 and this.ignore_wait_count == 0) {
            next.ignore_count = this.ignore_count - 1;
        } else {
            next.ignore_count = this.ignore_count;
        }

        if (this.ignore_wait_count > 0) {
            next.ignore_wait_count = this.ignore_wait_count - 1;
        } else {
            next.ignore_wait_count = 0;
        }

        switch (command_result.result) {
            .none, .no_op => {},

            .set_position => |set_position| {
                if (selector_digit == 0) {
                    next.position_start = this.digit_count - 1 - set_position;

                    next.position = 0;
                    next.offset = 0;
                    next.offset_pow = 1;
                }
            },
            .set_linear_position => |set_linear_position| {
                if (selector_digit == 0) {
                    next.linear_position = this.digit_count - 1 - set_linear_position;
                }
            },
            // .set_activation_digit => |set_activation_digit| {
            //     next.activation_digit = set_activation_digit;
            // },
            .ignore_after => |ignore_after| {
                next.ignore_count = ignore_after.ignore_count;
                next.ignore_wait_count = ignore_after.wait_count;
            },
        }
    }

    fn iterateNoColorMutate(this: *SelfConsumingReaderState, selector_digit: u2, digits: VirtualDigitArray) void {
        std.debug.assert(this.digit_count > 0);

        const modulo = this.digit_count - this.position_start;

        std.debug.assert(this.position + this.offset < modulo);

        const next_position = this.position * 4 + (@as(usize, selector_digit) * EncodedChunk.digits_per_chunk);

        const next_offset = this.offset + this.offset_pow * EncodedChunk.digits_per_chunk;
        if (next_position + next_offset >= modulo) {
            const next_digit_idx = clampWrap(next_position + next_offset, modulo);
            this.setDigitIdx(next_digit_idx);
        } else {
            this.position = next_position;
            this.offset = next_offset;
            this.offset_pow = this.offset_pow * 4;
        }

        const command_result = this.command.step(this, selector_digit);
        this.command = command_result.next;

        if (this.linear_position) |linear_position| {
            const next_linear_position = linear_position + 1 + EncodedChunk.digits_per_chunk;
            if (digits.get(linear_position) == selector_digit and next_linear_position < this.digit_count) {
                this.linear_position = next_linear_position;
            } else {
                this.linear_position = null;
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
                    this.offset = 0;
                    this.offset_pow = 1;
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
                this.ignore_count = ignore_after.ignore_count;
                this.ignore_wait_count = ignore_after.wait_count;
            },
        }
        this.digit_count += 1;
    }

    fn iterateAllNoColor(noalias this: *const SelfConsumingReaderState, digits: VirtualDigitArray, noalias res: *[4]SelfConsumingReaderState) void {
        std.debug.assert(this.digit_count > 0);

        for (res) |*next| {
            next.digit_count = this.digit_count + 1;

            next.position_start = this.position_start;
            next.linear_position = null;

            if (this.ignore_count > 0 and this.ignore_wait_count == 0) {
                next.ignore_count = this.ignore_count - 1;
            } else {
                next.ignore_count = this.ignore_count;
            }

            if (this.ignore_wait_count > 0) {
                next.ignore_wait_count = this.ignore_wait_count - 1;
            } else {
                next.ignore_wait_count = 0;
            }
        }

        const modulo = this.digit_count - this.position_start;

        std.debug.assert(this.position + this.offset < modulo);

        const next_offset = this.offset + this.offset_pow * EncodedChunk.digits_per_chunk;

        for (res, 0..) |*next, selector_digit_usize| {
            const next_position = this.position * 4 + (selector_digit_usize * EncodedChunk.digits_per_chunk);

            if (next_position + next_offset >= modulo) {
                const next_digit_idx = clampWrap(next_position + next_offset, modulo);
                next.setDigitIdx(next_digit_idx);
            } else {
                next.position = next_position;
                next.offset = next_offset;
                next.offset_pow = this.offset_pow * 4;
            }

            const selector_digit: u2 = @intCast(selector_digit_usize);

            if (this.linear_position) |linear_position| {
                const next_linear_position = linear_position + 1 + EncodedChunk.digits_per_chunk;
                if (digits.get(linear_position) == selector_digit and next_linear_position < this.digit_count) {
                    next.linear_position = next_linear_position;
                }
            }

            const command_result = this.command.step(this, selector_digit);

            next.command = command_result.next;

            switch (command_result.result) {
                .none, .no_op => {},

                .set_position => |set_position| {
                    if (selector_digit == 0) {
                        next.position_start = this.digit_count - 1 - set_position;

                        next.position = 0;
                        next.offset = 0;
                        next.offset_pow = 1;
                    }
                },
                .set_linear_position => |set_linear_position| {
                    if (selector_digit == 0) {
                        next.linear_position = this.digit_count - 1 - set_linear_position;
                    }
                },
                .ignore_after => |ignore_after| {
                    next.ignore_count = ignore_after.ignore_count;
                    next.ignore_wait_count = ignore_after.wait_count;
                },
            }
        }
    }

    pub fn iterate(this: *const SelfConsumingReaderState, selector_digit: u2, digits: VirtualDigitArray, res: *SelfConsumingReaderState) void {
        if (this.digit_count == 0) {
            res.* = this.*;
            res.digit_count = 1;

            return;
        }

        iterateNoColor(this, selector_digit, digits, res);

        res.color = this.getChildColors(digits)[selector_digit];
    }

    pub fn iterateAll(this: *const SelfConsumingReaderState, digits: VirtualDigitArray, res: *[4]SelfConsumingReaderState) void {
        if (this.digit_count == 0) {
            res.* = @splat(this.*);
            for (res) |*res_val| {
                res_val.digit_count = 1;
            }

            return;
        }

        this.iterateAllNoColor(digits, res);

        const child_colors = this.getChildColors(digits);
        // const child_colors: [4]Color = @splat(this.color);

        for (res, &child_colors) |*res_val, child_color| {
            res_val.color = child_color;
        }
    }

    pub fn getChildColors(this: *const SelfConsumingReaderState, digits: VirtualDigitArray) [4]Color {
        if (this.digit_count == 0) {
            const default: [4]Color = @splat(this.color);
            return default;
        }

        var digit_idx = this.position + this.offset + this.position_start;

        std.debug.assert(digit_idx < this.digit_count);

        if (this.linear_position) |linear_position| {
            digit_idx = clampWrapIncrement(linear_position, this.digit_count);
        }

        {
            const encoded_chunk = EncodedChunk.fromDigits(digits, &digit_idx, this.position_start, this.digit_count);

            const splitters = encoded_chunk.splitters;

            return splitColor(this.color, splitters);
        }
    }
};

pub const StateTree = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayListUnmanaged(Node),
    root_idx: usize,

    pub const Node = struct {
        digits: std.ArrayListUnmanaged(u2),
        states: std.ArrayListUnmanaged(SelfConsumingReaderState),
        children: [4]?usize,

        pub fn init(allocator: std.mem.Allocator, digit_count: usize) std.mem.Allocator.Error!Node {
            var res: Node = .{
                .digits = try std.ArrayListUnmanaged(u2).initCapacity(allocator, digit_count),
                .states = try std.ArrayListUnmanaged(SelfConsumingReaderState).initCapacity(allocator, digit_count + 1),

                .children = @splat(null),
            };

            try res.digits.resize(allocator, digit_count);
            try res.states.resize(allocator, digit_count + 1);

            return res;
        }

        pub fn deinit(this: *Node, allocator: std.mem.Allocator) void {
            this.digits.deinit(allocator);
            this.states.deinit(allocator);
        }

        pub fn anyChildren(this: Node) bool {
            for (this.children) |child| {
                if (child != null) {
                    return true;
                }
            }
            return false;
        }
    };

    pub const VirtualNode = struct {
        idx: usize,
        sub_idx: usize,
        digit: u2,
        state: SelfConsumingReaderState,

        pub fn init(state_tree: StateTree) VirtualNode {
            return .{
                .idx = state_tree.root_idx,
                .sub_idx = 0,
                .digit = 0,
                .state = state_tree.nodes.items[state_tree.root_idx].states.items[0],
            };
        }

        pub fn iterate(this: VirtualNode, state_tree: *StateTree, digit: u2, digits: VirtualDigitArray) std.mem.Allocator.Error!VirtualNode {
            const node = state_tree.nodes.items[this.idx];

            if (this.sub_idx == node.states.items.len - 1) {
                if (node.anyChildren()) {
                    const child_idx = if (node.children[digit]) |idx| idx else blk: {
                        const new_node = try Node.init(state_tree.allocator, 0);
                        new_node.states.items[0] = this.state.iterate(digit, digits);

                        try state_tree.nodes.append(state_tree.allocator, new_node);

                        const idx = state_tree.nodes.items.len - 1;

                        state_tree.nodes.items[this.idx].children[digit] = idx;

                        break :blk idx;
                    };

                    const child_node = state_tree.nodes.items[child_idx];

                    return .{
                        .idx = child_idx,
                        .sub_idx = 0,
                        .digit = digit,
                        .state = child_node.states.items[0],
                    };
                } else {
                    try state_tree.nodes.items[this.idx].digits.resize(state_tree.allocator, this.sub_idx + 1);
                    try state_tree.nodes.items[this.idx].states.resize(state_tree.allocator, this.sub_idx + 2);

                    state_tree.nodes.items[this.idx].digits.items[this.sub_idx] = digit;

                    const new_state = this.state.iterate(digit, digits);
                    state_tree.nodes.items[this.idx].states.items[this.sub_idx + 1] = new_state;

                    return .{
                        .idx = this.idx,
                        .sub_idx = this.sub_idx + 1,
                        .digit = digit,
                        .state = new_state,
                    };
                }
            }

            const split_digit = node.digits.items[this.sub_idx];

            if (split_digit != digit) {
                var split_node = try Node.init(state_tree.allocator, node.digits.items.len - this.sub_idx - 1);
                @memcpy(split_node.digits.items, node.digits.items[this.sub_idx + 1 ..]);
                @memcpy(split_node.states.items, node.states.items[this.sub_idx + 1 ..]);
                split_node.children = node.children;

                try state_tree.nodes.append(state_tree.allocator, split_node);
                const split_idx = state_tree.nodes.items.len - 1;

                const new_node = try Node.init(state_tree.allocator, 0);
                new_node.states.items[0] = this.state.iterate(digit, digits);

                try state_tree.nodes.append(state_tree.allocator, new_node);
                const new_idx = state_tree.nodes.items.len - 1;

                // state_tree.nodes.items[this.idx].digits.shrinkAndFree(state_tree.allocator, this.sub_idx);
                // state_tree.nodes.items[this.idx].states.shrinkAndFree(state_tree.allocator, this.sub_idx + 1);

                try state_tree.nodes.items[this.idx].digits.resize(state_tree.allocator, this.sub_idx);
                try state_tree.nodes.items[this.idx].states.resize(state_tree.allocator, this.sub_idx + 1);

                state_tree.nodes.items[this.idx].children = @splat(null);
                state_tree.nodes.items[this.idx].children[split_digit] = split_idx;
                state_tree.nodes.items[this.idx].children[digit] = new_idx;

                return .{
                    .idx = new_idx,
                    .sub_idx = 0,
                    .digit = digit,
                    .state = new_node.states.items[0],
                };
            }

            return .{
                .idx = this.idx,
                .sub_idx = this.sub_idx + 1,
                .digit = digit,
                .state = node.states.items[this.sub_idx + 1],
            };
        }
    };

    pub fn init(allocator: std.mem.Allocator, root_color: Color) std.mem.Allocator.Error!StateTree {
        var nodes = try std.ArrayListUnmanaged(Node).initCapacity(allocator, 1);

        var root_node = try Node.init(allocator, 0);
        root_node.states.items[0] = SelfConsumingReaderState.init(0, root_color);

        try nodes.append(allocator, root_node);

        return .{
            .allocator = allocator,
            .nodes = nodes,
            .root_idx = 0,
        };
    }

    pub fn deinit(this: *StateTree) void {
        for (this.nodes.items) |*node| {
            node.deinit(this.allocator);
        }
        this.nodes.deinit(this.allocator);
    }

    pub fn traverseFromRoot(this: *StateTree, path: VirtualDigitArray, digit_count: usize) !SelfConsumingReaderState {
        var virtual_node = VirtualNode.init(this.*);

        for (0..digit_count) |digit_idx| {
            const digit = path.get(digit_idx);

            virtual_node = try virtual_node.iterate(this, digit, path);
        }

        return virtual_node.state;
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

fn clampWrap(val: anytype, max: anytype) @TypeOf(val) {
    // return val % max;

    if (val >= max) {
        // return 0;
        return val % max;
    } else {
        return val;
    }
}

const EncodedChunk = struct {
    splitters: [3 * 3 + 1]u8,

    const digits_per_chunk = (3 * 3) * 4 + 3;

    const dummy_zero = std.mem.zeroes(EncodedChunk);

    pub fn fromDigits(digits: VirtualDigitArray, idx: *usize, position_start: usize, digit_count: usize) EncodedChunk {
        var res: EncodedChunk = undefined;

        res.splitters[0..9].* = getArrayFromDigits(digits, 3 * 3, u8, idx, position_start, digit_count);

        const last_splitter: [1]u6 = getArrayFromDigits(digits, 1, u6, idx, position_start, digit_count);
        res.splitters[9] = last_splitter[0];

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
    defer {
        // bad practice, remove later
        for (chunks) |chunk| {
            if (chunk.len != colors.len) {
                allocator.free(chunk);
            }
        }
    }

    const altered_colors = try allocator.alloc(Color, colors.len);
    @memcpy(altered_colors, colors);

    chunks[0] = altered_colors;
    for (chunks[1..], 0..) |*chunk, i| {
        const prev_chunk = chunks[i];
        chunk.* = try averageColors(allocator, prev_chunk);
    }

    defer for (chunks) |chunk| {
        allocator.free(chunk);
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
    const padding_count = std.math.log2(digits.length) + 5;

    // TODO calculate actual minimum for this value
    const base_3_max_digits = 20;

    // TODO calculate actual minimum for this value
    const starting_zero_splitters = 16;

    const core_command_digits_count = base_3_max_digits + (starting_zero_splitters + 1) + base_3_max_digits;

    const ignore_count = std.math.log2(square_size) - 1;
    const ignore_wait_count = core_command_digits_count + 1;

    var dummy_ignore_digits = std.ArrayList(u2).init(allocator);
    defer dummy_ignore_digits.deinit();

    var dummy_ignore_list_writer: ArrayListDigitWriter = .{ .list = &dummy_ignore_digits };
    const dummy_ignore_writer = dummy_ignore_list_writer.writer();

    try CommandState.Command.IgnoreAfter.encode(dummy_ignore_writer, .{
        .ignore_count = ignore_count,
        .wait_count = ignore_wait_count,
    });

    const starting_command_digits_count = dummy_ignore_digits.items.len + padding_count;

    var color_find_digits = std.ArrayList(u2).init(allocator);
    defer color_find_digits.deinit();

    var color_find_list_writer: ArrayListDigitWriter = .{ .list = &color_find_digits };
    const color_find_writer = color_find_list_writer.writer();

    for (0..starting_zero_splitters) |_| {
        try color_find_digits.append(0);
        // for (0..EncodedChunk.digits_per_chunk) |_| {
        //     try color_find_digits.append(0);
        // }

        for (0..EncodedChunk.digits_per_chunk) |i| {
            const splitter_digit_idx = i / 4;
            const splitter_digit_offset = i % 4;

            const digit = (zero_splitters[splitter_digit_idx] >> @intCast(splitter_digit_offset * 2)) & 0b11;

            try color_find_digits.append(@intCast(digit));
        }

        // for (&zero_splitters) |zero_splitter| {
        //     for (0..4) |i| {
        //         try color_find_digits.append(@intCast((zero_splitter >> @intCast(((i) * 2))) & 0b11));
        //     }
        // }
    }

    var seek_and_set_position_digits = std.ArrayList(u2).init(allocator);
    defer seek_and_set_position_digits.deinit();

    var seek_and_set_position_list_writer: ArrayListDigitWriter = .{ .list = &seek_and_set_position_digits };
    const seek_and_set_position_writer = seek_and_set_position_list_writer.writer();

    try CommandState.Command.SetPosition.encodePadded(
        seek_and_set_position_writer,
        digits.length + starting_command_digits_count + core_command_digits_count - 1,
        base_3_max_digits,
    );

    try seek_and_set_position_digits.append(3);

    {
        try encodeColorSearch(
            color_find_writer,
            seek_and_set_position_digits.items,
            .{
                .r = 0,
                .g = 0,
                .b = 0,
                .a = 255,
            },
            chunks[0][0],
        );
    }

    const padded_digits = try DigitArray.init(allocator, digits.length * 2);
    defer padded_digits.deinit(allocator);

    {
        var padded_digit_idx: usize = 0;

        for (color_find_digits.items) |digit| {
            padded_digits.set(padded_digit_idx, digit);
            padded_digit_idx += 1;
        }

        for (0..digits.length) |i| {
            padded_digits.set(padded_digit_idx, digits.get(i));
            padded_digit_idx += 1;
        }

        for (digits.length..padded_digits.length) |i| {
            padded_digits.set(i, 3);
            padded_digit_idx += 1;
        }
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
        .ignore_count = ignore_count,
        .wait_count = ignore_wait_count,
    });

    var set_linear_position_digits = std.ArrayList(u2).init(allocator);
    defer set_linear_position_digits.deinit();

    var set_linear_position_list_writer: ArrayListDigitWriter = .{ .list = &set_linear_position_digits };
    const set_linear_position_writer = set_linear_position_list_writer.writer();

    try CommandState.Command.SetLinearPosition.encodePadded(
        set_linear_position_writer,
        color_find_digits.items.len + digits.length + starting_command_digits.items.len + set_linear_position_end_idx - 1,
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

    var color_budget: [3]usize = undefined;

    for (&color_budget, &current_color) |*color_budget_component, color_component| {
        color_budget_component.* = @as(usize, color_component) * 4;
    }

    var target_colors_arr: [4][3]u8 = undefined;

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

    // jsPrint("pd: {} {}", .{ target_colors[target_color_digit], target_color_arg });

    try encodeColorSearch(writer, digit_path[1..], target_colors[target_color_digit], target_color_arg);
}

// const splitter_salt = blk: {
//     var splitter_salt_digits: [3 * 4]u2 = undefined;

//     for (&splitter_salt_digits, 0..) |*digit, i| {
//         digit.* = @truncate(i + 3);
//     }

//     var base_salt: [3]u8 = undefined;

//     for (&base_salt, 0..) |*salt, i| {
//         salt.* = 0;
//         for (0..4) |j| {
//             salt.* |= @as(u8, splitter_salt_digits[i * 4 + j]) << @intCast(j * 2);
//         }
//     }

//     break :blk (base_salt ** 3) ++ [_]u8{50};
// };

const splitter_salt: [10]u8 = ([_]u8{ 0b11001111, 0b11011110, 0b01011110 } ** 3) ++ [_]u8{0};

// const splitter_salt = blk: {
//     var splitter_salt_init: [10]u8 = undefined;
//     _ = &splitter_salt_init; // autofix
//     var prng = std.Random.DefaultPrng.init(1322);
//     const random = prng.random();

//     for (&splitter_salt_init) |*salt| {
//         salt.* = random.int(u8);
//     }

//     break :blk splitter_salt_init;

//     // var bit_indices: [8]u3 = undefined;
//     // for (&bit_indices, 0..) |*idx, i| {
//     //     idx.* = i;
//     // }

//     // @setEvalBranchQuota(100000);

//     // random.shuffle(u3, &bit_indices);

//     // for (bit_indices[0..1]) |bit_idx| {
//     //     base_salt |= @as(u8, 1) << bit_idx;
//     // }

//     // var base_salt: [3]u8 = undefined;

//     // random.bytes(&base_salt);

//     // break :blk (base_salt ** 2) ++ [_]u8{ 100, 100, 100 } ++ [_]u8{0};
// };

const zero_splitters = blk: {
    var zero_splitters_init: [10]u8 = @splat(0);

    zero_splitters_init = splitterRandomizeInverse(zero_splitters_init);

    break :blk zero_splitters_init;
};

fn splitterRandomize(splitters: [10]u8) [10]u8 {
    var res_splitters = splitters;
    _ = &res_splitters;

    for (&res_splitters, &splitter_salt) |*splitter, salt| {
        splitter.* ^= salt;
    }

    res_splitters[0..9].* = std.simd.rotateElementsLeft(res_splitters[0..9].*, 4);

    for (&res_splitters, &splitter_salt) |*splitter, salt| {
        splitter.* ^= salt;
    }

    return res_splitters;
}

fn splitterRandomizeInverse(splitters: [10]u8) [10]u8 {
    var res_splitters = splitters;
    _ = &res_splitters;

    for (&res_splitters, &splitter_salt) |*splitter, salt| {
        splitter.* ^= salt;
    }

    res_splitters[0..9].* = std.simd.rotateElementsRight(res_splitters[0..9].*, 4);

    for (&res_splitters, &splitter_salt) |*splitter, salt| {
        splitter.* ^= salt;
    }

    return res_splitters;
}

fn splitColor(color_arg: Color, splitters_arg: [10]u8) [4]Color {
    var splitters = splitters_arg;

    splitters = splitterRandomize(splitters);

    const is_zero = std.mem.indexOfNone(u8, &splitters, &.{0}) == null;

    const color = colorToArr(color_arg);

    var total_color_modifiers_flat = splitters[3 * 3 + 0];

    total_color_modifiers_flat = total_color_modifiers_flat % (4 * 4 * 4);

    var total_color_modifiers: [3]usize = undefined;
    {
        var temp = total_color_modifiers_flat;
        for (&total_color_modifiers) |*color_modifier| {
            color_modifier.* = temp % 4;
            temp /= 4;
        }
    }

    var total_color: [3]usize = undefined;
    for (&total_color, &color, &total_color_modifiers) |*total_color_component, color_component, color_modifier| {
        const color_modifier_sub: usize = if (color_modifier < 1) 1 else 0;

        const color_modifier_add: usize = if (color_modifier > 0) color_modifier - 1 else 0;

        total_color_component.* = @min(255 * 4, @as(usize, color_component) * 4 + color_modifier_add);

        total_color_component.* = total_color_component.* - @min(total_color_component.*, color_modifier_sub);
    }

    var res_colors: [4][3]u8 = undefined;

    var in_alt_path = false;

    in_alt_path = is_zero;

    outer: for (&total_color, 0..) |total_color_component, i| {
        var sum: usize = 0;

        var splitter_code: u32 = 0;

        for (splitters[i * 3 .. (i + 1) * 3]) |splitter| {
            splitter_code <<= 8;
            splitter_code |= splitter;
        }

        var total_range: u32 = (1 << 24) - 1;

        for (0..3) |j| {
            const remaining = total_color_component - @min(total_color_component, sum);

            const min = sum + (remaining - @min(remaining, 255 * (3 - j)));
            const max = @min(total_color_component, sum + 255);

            const range = max - min;

            total_range /= range + 1;

            const point_in_range = (splitter_code % (range + 1));
            splitter_code /= range + 1;

            const res_color_component = (min - sum) + point_in_range;
            res_colors[j][i] = @intCast(res_color_component);

            sum += res_color_component;
        }

        // if (splitter_code != 0) {
        //     in_alt_path = true;
        //     break :outer;
        // }

        if ((total_range != 0 and splitter_code != total_range - 1)) {
            in_alt_path = true;
            break :outer;
        }

        // if (total_range != 0 and splitter_code != 1 and !is_zero) {
        //     in_alt_path = true;
        //     break :outer;
        // }

        res_colors[3][i] = @intCast(total_color_component - sum);
    }

    if (in_alt_path) {
        for (0..3) |i| {
            var splitter_code: u32 = 0;

            for (splitters[i * 3 .. (i + 1) * 3]) |splitter| {
                splitter_code <<= 8;
                splitter_code |= splitter;
            }

            splitter_code = xorshift32(splitter_code);

            const extra_code = xorshift32(splitter_code);

            const color_component = color[i];

            // min for color_component less than: 110
            // max for color_component less than: 146
            const base = if (color_component < 128) @as(usize, color_component) + 1 else 256 - @as(usize, color_component);

            var target: usize = 0;
            var diffs: [4]u8 = undefined;

            for (0..4) |j| {
                if (is_zero) {
                    if (color_component < 128) {
                        const diff: u8 = @intCast(if (j == 0) base - 1 else 0);

                        splitter_code /= base;

                        diffs[j] = diff;
                        target += diff;
                    } else {
                        const diff: u8 = @intCast(if (j == 0) 0 else base - 1);

                        splitter_code /= base;

                        diffs[j] = diff;
                        target += diff;
                    }
                } else {
                    const diff: u8 = @intCast(splitter_code % base);

                    splitter_code /= base;

                    diffs[j] = diff;
                    target += diff;
                }
            }

            if (color_component < 128) {
                if (is_zero) {
                    // target = target - @min(target, 1);
                } else {
                    target = @min(255, target + 2);

                    // target += 2;
                }

                // target = @min(255 * 4, target + 2);
            } else {
                if (target < 255) {
                    target += 1;
                }

                // target += 1;
            }

            const min_diff: u8 = @intCast(target / 4);
            const excess_diff = target % 4;

            var excess_idx: usize = extra_code % 4;

            if (is_zero) {
                if (color_component < 128) {
                    excess_idx = 3;
                } else {
                    excess_idx = 0;
                }
            }

            if (color_component < 128) {
                for (0..4) |j| {
                    res_colors[j][i] = color_component - diffs[j] + min_diff;

                    if (excess_idx < excess_diff) {
                        res_colors[j][i] += 1;
                    }
                    excess_idx = (excess_idx + 1) % 4;
                }
            } else {
                for (0..4) |j| {
                    res_colors[j][i] = color_component + diffs[j] - min_diff;

                    if (excess_idx < excess_diff) {
                        res_colors[j][i] -= 1;
                    }
                    excess_idx = (excess_idx + 1) % 4;
                }
            }
        }
    }

    var res: [4]Color = undefined;
    for (&res, res_colors) |*res_color, res_color_arr| {
        res_color.* = arrToColor(res_color_arr);
    }

    return res;
}

fn getSplitters(parent_color: Color, child_colors: [4]Color) [10]u8 {
    const color = colorToArr(parent_color);

    var splitters: [10]u8 = undefined;

    var res_colors: [4][3]u8 = undefined;
    for (&res_colors, &child_colors) |*res_color, child_color| {
        res_color.* = colorToArr(child_color);
    }

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

    for (&total_color, 0..) |total_color_component, i| {
        var sum: usize = 0;

        var splitter_code: u32 = 0;

        var points_in_range: [3]u8 = undefined;
        var ranges: [3]u8 = undefined;

        for (0..3) |j| {
            const remaining = total_color_component - @min(total_color_component, sum);

            const min = sum + (remaining - @min(remaining, 255 * (3 - j)));
            const max = @min(total_color_component, sum + 255);

            const range = max - min;
            ranges[j] = @intCast(range);

            const res_color_component = res_colors[j][i];

            // const point_in_range = res_color_component + sum - min;

            const point_in_range = res_color_component - (min - (@min(min, sum)));

            points_in_range[j] = @intCast(point_in_range);

            sum += (min - sum) + point_in_range;
        }

        var total_range: u32 = (1 << 24) - 1;

        for (&ranges) |range| {
            total_range /= @as(u32, range) + 1;
        }

        splitter_code = if (total_range == 0) 0 else total_range - 1;

        // splitter_code = @min(total_range, 1);

        splitter_code *= @as(u32, ranges[2]) + 1;

        splitter_code += points_in_range[2];

        splitter_code *= @as(u32, ranges[1]) + 1;

        splitter_code += points_in_range[1];

        splitter_code *= @as(u32, ranges[0]) + 1;

        splitter_code += points_in_range[0];

        for (splitters[i * 3 .. (i + 1) * 3], 0..) |*splitter, j| {
            splitter.* = @intCast((splitter_code >> @intCast((2 - j) * 8)) & 0xFF);
        }
    }

    const is_zero = std.mem.indexOfNone(u8, &splitters, &.{0}) == null;
    std.debug.assert(!is_zero);

    // const tester = splitColor(parent_color, splitters);

    // if (!std.mem.eql(Color, child_colors[0..], tester[0..])) {
    //     jsPrint("{any} ", .{color});
    //     jsPrint("{any} ", .{total_color});
    //     jsPrint("{any} ", .{splitters});
    //     jsPrint("{any} ", .{child_colors});
    //     jsPrint("{any} ", .{tester});
    //     jsPrint(" ", .{});
    // }

    splitters = splitterRandomizeInverse(splitters);

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
