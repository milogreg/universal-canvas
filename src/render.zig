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

    pub fn encode(this: DigitWriter, num: usize) !void {
        var power: usize = 1;
        while (power <= num) {
            power *= 3;
        }
        power /= 3;

        var temp: usize = num;
        while (power > 0) {
            try this.write(@intCast((num / power) % 3));
            temp /= 3;
            power /= 3;
        }

        try this.write(3);
    }

    pub fn encodePadded(this: DigitWriter, num: usize, min_digits: usize) !void {
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
                try this.write(0);
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
                try this.write(@intCast((num / power) % 3));
                temp /= 3;
                power /= 3;
            }
        }

        try this.write(3);
    }
};

const ArrayListDigitWriter = struct {
    list: *std.ArrayList(u2),

    // pub fn init(list:*std.ArrayList(u2)) ArrayListDigitWriter {
    //     retunr .{
    //         .list = list,
    //     }
    // }

    pub fn writer(this: *const ArrayListDigitWriter) DigitWriter {
        return .{ .ptr = this.list, .vtable = .{
            .write = write,
        } };
    }

    pub fn write(ptr: *anyopaque, digit: u2) std.mem.Allocator.Error!void {
        const this: *std.ArrayList(u2) = @alignCast(@ptrCast(ptr));

        try this.append(digit);
    }
};

pub const SelfConsumingReaderState = struct {
    position_start: Size,

    position: Size,

    next_position_start: Size,

    digit_count: Size,

    color: @Vector(3, u8),

    const Size = u32;

    const LayerSize = std.math.IntFittingRange(0, (@typeInfo(Size).int.bits - 1) / 2);

    // const LayerSize = std.math.ByteAlignedInt(std.math.IntFittingRange(0, (@typeInfo(Size).int.bits - 1) / 2 ));

    const ShiftSize = std.math.Log2Int(Size);

    pub fn init(digit_count: Size, color: Color) SelfConsumingReaderState {
        // @compileLog(@bitSizeOf(SelfConsumingReaderState));
        // @compileLog(@sizeOf(SelfConsumingReaderState));
        // @compileLog(@offsetOf(SelfConsumingReaderState, "position"), @bitOffsetOf(SelfConsumingReaderState, "position"));

        return .{
            .position = 0,

            .position_start = 0,

            .digit_count = digit_count,
            .color = colorToArr(color),

            // .linear = false,
            .next_position_start = 0,
        };
    }

    fn layerUnderDigitIdxOld(digit_idx: Size) LayerSize {
        const adjusted_digit_idx = (digit_idx) / EncodedChunk.digits_per_chunk;

        comptime var mask: Size = 0;
        const mask_bits: ShiftSize = @typeInfo(Size).int.bits - 1;
        inline for (0..mask_bits) |i| {
            if (i & 1 == (~@typeInfo(Size).int.bits) & 1) {
                mask |= 1 << i;
            }
        }

        for (1..mask_bits / 2) |i| {
            if (adjusted_digit_idx < mask >> @intCast(mask_bits - i * 2)) {
                return @intCast(i - 1);
            }
        }

        unreachable;

        // var res: LayerSize = 0;

        // inline for (1..mask_bits / 2) |i| {
        //     const mask_shifted = mask >> @intCast(mask_bits - i * 2);
        //     res += @intFromBool(adjusted_digit_idx >= mask_shifted);
        // }

        // return res;
    }

    pub fn layerUnderDigitIdx(digit_idx: Size) LayerSize {
        comptime var mask: Size = 0;
        const mask_bits: ShiftSize = @typeInfo(Size).int.bits - 1;
        inline for (0..mask_bits) |i| {
            if (i & 1 == (~@typeInfo(Size).int.bits) & 1) {
                mask |= 1 << i;
            }
        }

        const scaled_zero_pos: ShiftSize = @intCast(@typeInfo(Size).int.bits - @clz(digit_idx));

        var mask_shifted = mask >> 4;
        mask_shifted >>= (mask_bits - scaled_zero_pos);

        const offset = mask_shifted * EncodedChunk.digits_per_chunk;

        var res: Size = scaled_zero_pos;
        res -|= 5;
        if (offset <= digit_idx) {
            res += 1;
        }

        res /= 2;

        // std.debug.assert(layerUnderDigitIdxOld(digit_idx) == res);
        return @intCast(res);
    }

    // pub fn layerUnderDigitIdx(digit_idx: Size) LayerSize {
    //     const adjusted_digit_idx = (digit_idx) / EncodedChunk.digits_per_chunk;

    //     comptime var mask: Size = 0;
    //     const mask_bits: ShiftSize = @typeInfo(Size).int.bits - 1;
    //     inline for (0..mask_bits) |i| {
    //         if (i & 1 == (~@typeInfo(Size).int.bits) & 1) {
    //             mask |= 1 << i;
    //         }
    //     }

    //     const first_zero_pos: ShiftSize = @intCast(@typeInfo(Size).int.bits - @clz(adjusted_digit_idx));

    //     var shift: ShiftSize = mask_bits - 1;
    //     shift -= first_zero_pos;

    //     var mask_shifted = mask;
    //     mask_shifted >>= shift;

    //     var res: Size = first_zero_pos;
    //     res += @intFromBool(adjusted_digit_idx >= mask_shifted);
    //     res /= 2;

    //     // std.debug.assert(layerUnderDigitIdxOld(digit_idx) == res);
    //     return @intCast(res);
    // }

    // pub fn absolutePosition(this: *const SelfConsumingReaderState) Size {
    //     return this.position_start + this.position + offsetFromLayer(this.position_layer);
    // }

    pub fn absolutePosition(this: *const SelfConsumingReaderState) Size {
        return this.position_start + this.position;
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

    fn valid(this: *const SelfConsumingReaderState) bool {
        return this.digit_count == 0 or this.absolutePosition() < this.digit_count;
    }

    fn iterateNoColor(noalias this: *const SelfConsumingReaderState, selector_digit: u2, digits: VirtualDigitArray, noalias next: *SelfConsumingReaderState) void {
        _ = digits; // autofix
        // if (true) return this.iterateNoColorBranchless(selector_digit, digits, next);

        std.debug.assert(this.valid());

        const layer = layerUnderDigitIdx(this.position);

        const offset = offsetFromLayer(layer);

        const next_offset = offsetFromLayer(layer + 1);

        const modulo = ((this.digit_count - this.position_start) + 1);

        const position_without_offset = this.position - offset;

        const next_position = next_offset + position_without_offset * 4 + (@as(Size, selector_digit) * EncodedChunk.digits_per_chunk);

        const will_overflow_position = next_position >= modulo;

        next.next_position_start = this.next_position_start *| 3 +| selector_digit;
        next.position_start = this.position_start;
        next.digit_count = this.digit_count + 1;
        next.position = next_position;

        if (will_overflow_position) {
            if (selector_digit == 3) {
                next.next_position_start = 0;
                if (this.next_position_start <= this.digit_count) {
                    next.position_start = this.digit_count - this.next_position_start;
                    next.position = 0;
                }
            } else if (selector_digit == (position_without_offset & 1) + 1) {
                if (position_without_offset >= EncodedChunk.digits_per_chunk) {
                    next.position = this.position - EncodedChunk.digits_per_chunk;
                } else {
                    next.position = 0;
                }
            }

            // const cond1 = (selector_digit == 3);
            // const cond2 = (this.next_position_start <= this.digit_count);
            // const cond3 = (selector_digit == ((position_without_offset) & 1) + 1);
            // const cond4 = (position_without_offset >= EncodedChunk.digits_per_chunk);

            // next.position_start = if (cond1 and cond2) this.digit_count - this.next_position_start else next.position_start;

            // next.next_position_start *= ~@intFromBool(cond1);

            // next.position = if (cond3 and cond4) this.position - EncodedChunk.digits_per_chunk else next.position;
            // next.position *= ~@intFromBool(((cond1) and (cond2)) or ((cond3) and (!cond4)));

            next.position %= modulo;
        }
    }

    fn iterateNoColorBranchless(noalias this: *const SelfConsumingReaderState, selector_digit: u2, digits: VirtualDigitArray, noalias next: *SelfConsumingReaderState) void {
        _ = digits; // autofix
        std.debug.assert(this.valid());

        next.digit_count = this.digit_count + 1;

        const layer = layerUnderDigitIdx(this.position);

        const offset = offsetFromLayer(layer);

        const next_offset = offsetFromLayer(layer + 1);

        const position_without_offset = this.position - offset;

        const next_position = next_offset + position_without_offset * 4 + (@as(Size, selector_digit) * EncodedChunk.digits_per_chunk);

        const modulo = (this.digit_count - this.position_start) + 1;

        const will_overflow_position = next_position >= modulo;

        const cond0 = @intFromBool(will_overflow_position);
        const cond1 = cond0 & @intFromBool(selector_digit == 3);
        const cond2 = cond0 & @intFromBool(this.next_position_start <= this.digit_count);
        const cond3 = cond0 & @intFromBool(selector_digit == (position_without_offset & 1) + 1);
        const cond4 = cond0 & @intFromBool(position_without_offset >= EncodedChunk.digits_per_chunk);
        const cond5 = ((cond1) & (cond2)) | ((cond3) & (~cond4));
        const cond6 = cond1 & cond2;
        const cond7 = cond3 & cond4;

        next.next_position_start = if (cond1 == 1) 0 else this.next_position_start *| 3 +| selector_digit;

        next.position_start = if (cond6 == 1) this.digit_count - this.next_position_start else this.position_start;

        next.position = next_position;
        next.position = if (cond5 == 1) 0 else next.position;
        next.position = if (cond7 == 1) this.position - EncodedChunk.digits_per_chunk else next.position;
        next.position %= modulo;
    }

    fn iterateNoColorMutate(this: *SelfConsumingReaderState, selector_digit: u2, digits: VirtualDigitArray) void {
        var next: SelfConsumingReaderState = this.*;
        this.iterateNoColor(selector_digit, digits, &next);
        this.* = next;
    }

    pub fn iterateAllNoColor(noalias this: *const SelfConsumingReaderState, digits: VirtualDigitArray, noalias res: *[4]SelfConsumingReaderState) void {
        for (0..4) |i| {
            this.iterateNoColor(@intCast(i), digits, &res[i]);
        }
    }

    pub fn iterate(noalias this: *const SelfConsumingReaderState, selector_digit: u2, digits: VirtualDigitArray, noalias res: *SelfConsumingReaderState) void {
        this.iterateNoColor(selector_digit, digits, res);
        res.color = this.getChildColors(digits)[selector_digit];
    }

    pub fn iterateMutate(noalias this: *SelfConsumingReaderState, selector_digit: u2, digits: VirtualDigitArray) void {
        this.color = this.getChildColors(digits)[selector_digit];
        this.iterateNoColorMutate(selector_digit, digits);
    }

    pub fn iterateAll(this: *const SelfConsumingReaderState, digits: VirtualDigitArray, res: *[4]SelfConsumingReaderState) void {
        this.iterateAllNoColor(digits, res);

        const child_colors = this.getChildColors(digits);

        for (res, &child_colors) |*res_val, child_color| {
            res_val.color = child_color;
        }
    }

    pub fn getChildColors(this: *const SelfConsumingReaderState, digits: VirtualDigitArray) [4][3]u8 {
        std.debug.assert(this.valid());

        const digit_idx = this.absolutePosition();

        {
            const encoded_chunk = EncodedChunk.fromDigits(digits, digit_idx, this.position_start, this.digit_count);

            const splitters = encoded_chunk.splitters;

            return splitColor(this.color, splitters);
        }
    }
};

pub const StateStems = struct {
    digits: DigitArray,
    digit_backers: std.ArrayListUnmanaged(DigitArray.Backer),

    states: std.ArrayListUnmanaged(SelfConsumingReaderState),

    allocator: std.mem.Allocator,

    initial_state: SelfConsumingReaderState,

    const digits_per_state: usize = 128;

    pub fn init(allocator: std.mem.Allocator, root_color: Color) std.mem.Allocator.Error!StateStems {
        const digit_backers = try std.ArrayListUnmanaged(DigitArray.Backer).initCapacity(allocator, 1);

        return .{
            .digits = .{
                .digit_backers = digit_backers.items,
                .length = 0,
            },
            .digit_backers = digit_backers,
            .states = try std.ArrayListUnmanaged(SelfConsumingReaderState).initCapacity(allocator, 1),
            .allocator = allocator,
            .initial_state = SelfConsumingReaderState.init(0, root_color),
        };
    }

    pub fn deinit(this: *StateStems) void {
        this.digit_backers.deinit(this.allocator);
        this.states.deinit(this.allocator);
    }

    pub fn appendDigit(this: *StateStems, digit: u2) std.mem.Allocator.Error!void {
        const prev_length = this.digits.length;

        const new_backers_len = DigitArray.backersNeeded(prev_length + 1);

        try this.digit_backers.resize(this.allocator, new_backers_len);

        this.digits.digit_backers = this.digit_backers.items;
        this.digits.length = prev_length + 1;

        this.digits.set(prev_length, digit);
    }

    pub fn removeDigit(this: *StateStems) void {
        const prev_length = this.digits.length;

        const new_backers_len = DigitArray.backersNeeded(prev_length - 1);
        this.digit_backers.shrinkRetainingCapacity(new_backers_len);

        this.digits.digit_backers = this.digit_backers.items;
        this.digits.length = prev_length - 1;

        this.states.shrinkRetainingCapacity(@min(this.states.items.len, this.digits.length / digits_per_state));
    }

    pub fn clearDigits(this: *StateStems) void {
        this.digit_backers.shrinkRetainingCapacity(0);
        this.digits.digit_backers = this.digit_backers.items;
        this.digits.length = 0;
        this.states.shrinkRetainingCapacity(0);
    }

    pub fn incrementX(this: *StateStems) void {
        const digits = this.digits;

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

        this.states.shrinkRetainingCapacity(@min(this.states.items.len, i / digits_per_state));
    }

    pub fn incrementY(this: *StateStems) void {
        const digits = this.digits;

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

        this.states.shrinkRetainingCapacity(@min(this.states.items.len, i / digits_per_state));
    }

    pub fn decrementX(this: *StateStems) void {
        const digits = this.digits;

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

        this.states.shrinkRetainingCapacity(@min(this.states.items.len, i / digits_per_state));
    }

    pub fn decrementY(this: *StateStems) void {
        const digits = this.digits;

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

        this.states.shrinkRetainingCapacity(@min(this.states.items.len, i / digits_per_state));
    }

    pub fn trim(this: *StateStems) void {
        this.digit_backers.shrinkAndFree(this.digit_backers.items.len);
        this.states.shrinkAndFree(this.states.items.len);
    }

    pub fn endingState(this: *StateStems) std.mem.Allocator.Error!SelfConsumingReaderState {
        var states: [2]SelfConsumingReaderState = undefined;
        states[0] = if (this.states.items.len == 0) this.initial_state else this.states.items[this.states.items.len - 1];

        var current_state = &states[0];
        var next_state = &states[1];

        const start_idx = this.states.items.len * digits_per_state;

        for (start_idx..this.digits.length) |i| {
            const digit = this.digits.get(i);

            current_state.iterate(digit, VirtualDigitArray.fromDigitArray(this.digits, 0, 0, 0), next_state);

            const temp = current_state;
            current_state = next_state;
            next_state = temp;

            if ((i + 1) % digits_per_state == 0) {
                try this.states.append(this.allocator, current_state.*);
            }
        }

        return current_state.*;
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
        } else {
            const virtual_selector_digit_idx = idx - this.array.length;

            return @intCast((this.virtual_idx >> @intCast((virtual_selector_digit_idx) * 2)) & 0b11);
        }

        // const virtual_selector_digit_idx = idx - this.array.length;

        // const nonvirtual_digit = this.array.get(idx);

        // const virtual_digit: DigitArray.Digit = @intCast((this.virtual_idx >> @intCast((virtual_selector_digit_idx) * 2)) & 0b11);
        // return if (idx < this.array.length) nonvirtual_digit else virtual_digit;
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

fn readDigitsToBytesSimple(
    digit_array: anytype,
    starting_idx: usize,
    max_idx: usize,
    comptime num_to_read: usize,
    bytes: *[std.math.divCeil(usize, num_to_read, 4) catch unreachable]u8,
) void {
    bytes.* = @splat(0);

    const num_to_actually_read = @min(num_to_read, max_idx - starting_idx);

    for (0..num_to_actually_read) |i| {
        const digit: u8 = digit_array.get(starting_idx + i);
        bytes[i / 4] |= digit << @intCast((i % 4) * 2);
    }
}

fn readDigitsToBytes(
    digit_array: anytype,
    starting_idx: usize,
    max_idx: usize,
    comptime num_to_read: usize,
    bytes: *[std.math.divCeil(usize, num_to_read, 4) catch unreachable]u8,
) void {
    if (@TypeOf(digit_array) != VirtualDigitArray or DigitArray.Backer != u8) {
        return readDigitsToBytesSimple(digit_array, starting_idx, max_idx, num_to_read, bytes);
    }

    const num_to_actually_read = @min(num_to_read, max_idx - starting_idx);

    const num_bytes_to_read = std.math.divCeil(usize, num_to_actually_read, 4) catch unreachable;

    if (num_to_actually_read > 0 and digit_array.array.length / 4 > (starting_idx / 4) + bytes.len + 1) {
        var res: std.meta.Int(.unsigned, (bytes.len + 1) * 8) = undefined;
        const starting_idx_offset = starting_idx % 4;

        res = std.mem.readInt(@TypeOf(res), digit_array.array.digit_backers[starting_idx / 4 ..][0 .. bytes.len + 1], .little);

        const shift = ((4 - (num_to_actually_read % 4)) % 4) * 2;

        const shift_big = (bytes.len - num_bytes_to_read + 1) * 8 + shift;

        res <<= @intCast(shift_big - starting_idx_offset * 2);
        res >>= @intCast(shift_big);

        std.mem.writeInt(std.meta.Int(.unsigned, bytes.len * 8), bytes, @truncate(res), .little);

        // bytes[num_bytes_to_read - 1] <<= @intCast(shift);
        // bytes[num_bytes_to_read - 1] >>= @intCast(shift);
    } else {
        bytes.* = @splat(0);
        for (0..num_to_actually_read) |i| {
            const digit: u8 = digit_array.get(starting_idx + i);
            bytes[i / 4] |= digit << @intCast((i % 4) * 2);
        }
    }

    // var starting_bytes = bytes.*;
    // readDigitsToBytesSimple(digit_array, starting_idx, max_idx, num_to_read, &starting_bytes);

    // if (!std.mem.eql(u8, &starting_bytes, bytes)) {
    //     jsPrint("{} {} {}", .{ starting_idx, max_idx, num_to_read });
    //     jsPrint("{any}", .{starting_bytes});
    //     jsPrint("{any}", .{bytes});
    // }

    // std.debug.assert(std.mem.eql(u8, &starting_bytes, bytes));
}

const EncodedChunk = struct {
    splitters: [3 * 3 + 1]u8,

    const digits_per_chunk = (3 * 3) * 4 + 3;

    const dummy_zero = std.mem.zeroes(EncodedChunk);

    pub fn fromDigits(digits: VirtualDigitArray, idx: usize, position_start: usize, digit_count: usize) EncodedChunk {
        _ = position_start; // autofix
        var res: EncodedChunk = undefined;

        // if (digit_count == 0) {
        //     return .{
        //         .splitters = @splat(0),
        //     };
        // }

        // var running_idx = idx;
        // res.splitters[0..9].* = getArrayFromDigits(digits, 3 * 3, u8, &running_idx, position_start, digit_count);

        // const last_splitter: [1]u6 = getArrayFromDigits(digits, 1, u6, &running_idx, position_start, digit_count);
        // res.splitters[9] = last_splitter[0];

        readDigitsToBytes(digits, idx, digit_count, digits_per_chunk, &res.splitters);

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

    // TODO calculate actual minimum for this value
    const padding_count = 20;

    // TODO calculate actual minimum for this value
    const base_3_max_digits = 30;
    _ = base_3_max_digits; // autofix

    // // TODO calculate actual minimum for this value
    // const starting_zero_splitters = 5;

    const zero_splitters_layer = chunks.len;

    const absolute_final_position = 0;

    var digit_list = std.ArrayList(u2).init(allocator);
    defer digit_list.deinit();

    for (0..digits.length) |i| {
        try digit_list.append(digits.get(i));
    }

    const average_color = colorToArr(chunks[0][0]);

    const zero_splitter_offset = SelfConsumingReaderState.offsetFromLayer(@intCast(zero_splitters_layer - 1));

    const absolute_zero_splitter_position = digit_list.items.len - absolute_final_position - zero_splitter_offset;

    // const safe_digit_count = (@as(usize, 1) << @intCast((zero_splitters_layer - 1) * 2)) * 39;

    // std.debug.assert(zero_splitter_count * 39 <= safe_digit_count);

    // jsPrint("xx: {}", .{safe_digit_count / 39});
    // jsPrint("yy: {}", .{digit_list.items.len});
    // jsPrint("zz: {}", .{absolute_zero_splitter_position});

    var final_position_digits = std.ArrayList(u2).init(allocator);
    defer final_position_digits.deinit();

    const magic_splitters = @embedFile("magic_splitters");

    const zero_splitter_count = magic_splitters.len / 10;

    const neutral_count = 1 - (zero_splitter_count % 2);

    {
        var test_digit: u2 = 2;
        for (0..zero_splitter_count) |_| {
            test_digit ^= 0b11;
        }

        for (0..1 + neutral_count) |_| {
            try final_position_digits.append(test_digit);
            test_digit ^= 0b11;
        }
    }

    var final_search_digits = std.ArrayList(u2).init(allocator);
    defer final_search_digits.deinit();

    const final_position_digit_writer = @as(ArrayListDigitWriter, .{ .list = &final_search_digits }).writer();

    try encodeColorSearch(
        final_position_digit_writer,
        final_position_digits.items,

        arrToColor(.{ 128, 128, 128 }),

        arrToColor(average_color),
    );

    for (0..final_search_digits.items.len / EncodedChunk.digits_per_chunk) |i| {
        const inverse_idx = final_search_digits.items.len / EncodedChunk.digits_per_chunk - 1 - i;

        try digit_list.appendSlice(final_search_digits.items[inverse_idx * EncodedChunk.digits_per_chunk ..][0..EncodedChunk.digits_per_chunk]);
    }

    for (0..zero_splitter_count) |j| {
        for (0..EncodedChunk.digits_per_chunk) |i| {
            try digit_list.append(@truncate(magic_splitters[(zero_splitter_count - j - 1) * 10 ..][i / 4] >> @intCast((i % 4) * 2)));
        }
    }

    for (0..padding_count) |_| {
        try digit_list.append(3);
    }

    var running_state: SelfConsumingReaderState = .{
        .position = 0,
        .position_start = @intCast(digit_list.items.len - 1),
        .next_position_start = 0,
        .digit_count = @intCast(digit_list.items.len),

        .color = undefined,
    };

    var zero_splitter_position_digits = std.ArrayList(u2).init(allocator);
    defer zero_splitter_position_digits.deinit();

    while (true) {
        const num_to_encode_zero_splitter_position = zero_splitter_position_digits.items.len + 1;

        const relative_zero_splitter_position = running_state.digit_count + num_to_encode_zero_splitter_position - absolute_zero_splitter_position - 1;

        {
            var min_len: usize = 0;
            var current = relative_zero_splitter_position;
            while (current > 0) {
                current /= 3;
                min_len += 1;
            }

            if (min_len > zero_splitter_position_digits.items.len) {
                try zero_splitter_position_digits.resize(min_len);

                continue;
            }
        }

        encodeBase3(relative_zero_splitter_position, zero_splitter_position_digits.items);

        var tester_state = running_state;

        for (zero_splitter_position_digits.items) |digit| {
            tester_state.iterateNoColorMutate(digit, undefined);
        }

        tester_state.iterateNoColorMutate(3, undefined);

        if (tester_state.absolutePosition() == absolute_zero_splitter_position) {
            for (zero_splitter_position_digits.items) |digit| {
                try digit_list.append(digit);
            }

            try digit_list.append(3);

            running_state = tester_state;

            break;
        }

        _ = try zero_splitter_position_digits.addOne();
    }

    const ending_splitter_length = (zero_splitter_count + final_position_digits.items.len) - 1;

    const ending_splitter_length_digits = try allocator.alloc(u2, zero_splitters_layer - 1);
    encodeBase4(ending_splitter_length, ending_splitter_length_digits);

    for (ending_splitter_length_digits) |digit| {
        running_state.iterateNoColorMutate(digit, undefined);
        try digit_list.append(digit);
    }

    var current_digit: u2 = 2;

    for (0..zero_splitter_count) |_| {
        running_state.iterateNoColorMutate(current_digit, undefined);
        try digit_list.append(current_digit);

        current_digit ^= 0b11;
    }

    for (final_position_digits.items) |digit| {
        running_state.iterateNoColorMutate(digit, undefined);
        try digit_list.append(digit);
    }

    const digits_with_command = try DigitArray.init(
        allocator,
        digit_list.items.len,
    );
    var digits_with_command_idx: usize = 0;

    for (digit_list.items) |command_digit| {
        digits_with_command.set(digits_with_command_idx, command_digit);
        digits_with_command_idx += 1;
    }

    std.debug.assert(digits_with_command_idx == digits_with_command.length);

    digits.deinit(allocator);

    return digits_with_command;
}

fn encodeBase3(to_encode: usize, digits: []u2) void {
    var current = to_encode;
    var i: usize = digits.len;
    while (i > 0) {
        i -= 1;
        digits[i] = @intCast(current % 3);
        current /= 3;
    }
}

fn encodeBase4(to_encode: usize, digits: []u2) void {
    var current = to_encode;
    var i: usize = digits.len;
    while (i > 0) {
        i -= 1;
        digits[i] = @intCast(current % 4);
        current /= 4;
    }
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

    for (&encoded_chunk_digits) |digit| {
        try writer.write(digit);
    }
    // try writer.write(target_color_digit);

    // jsPrint("pd: {any} {any} {}", .{ target_colors_arr, target_color, target_color_digit });

    try encodeColorSearch(writer, digit_path[1..], target_colors[target_color_digit], target_color_arg);
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
    var res: [10]u8 = undefined;
    var res_int = std.mem.readInt(u72, splitters[0..9], .little);

    res_int ^= std.mem.readInt(u24, &color, .little);

    res_int = hash72(res_int);

    std.mem.writeInt(u72, res[0..9], res_int, .little);
    res[9] = splitters[9];

    return res;
}

pub fn splitterApplyColorSaltInverse(splitters: [10]u8, color: [3]u8) [10]u8 {
    var res: [10]u8 = undefined;
    var res_int = std.mem.readInt(u72, splitters[0..9], .little);

    res_int = hash72Inverse(res_int);

    res_int ^= std.mem.readInt(u24, &color, .little);

    std.mem.writeInt(u72, res[0..9], res_int, .little);
    res[9] = splitters[9];

    return res;
}

fn splittersEqual(a: [10]u8, b: [10]u8) bool {
    return @as(u80, @bitCast(a)) == @as(u80, @bitCast(b));
}

pub fn inAltPath(color: [3]u8, splitters_arg: [10]u8) bool {
    var splitters = splitters_arg;

    // splitters = splitterApplyColorSalt(splitters, color);

    splitters = splitters;

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

    return total_color_bits_ored >> 8 != 0;
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
            return splitColorAltPath(color, splitters);
        }

        res_colors[3][i] = @intCast(total_color_component);
    }

    assertValidSplit(color, res_colors);

    return res_colors;
}

fn splitColorAltPath(color: [3]u8, splitters: [10]u8) [4][3]u8 {
    if (std.simd.suggestVectorLength(u8) != null) {
        return splitColorAltPathSimd(color, splitters);
    }

    const all_components_code: u32 = std.mem.readInt(u24, splitters[0..3], .little);

    var res_colors: [4][3]u8 = undefined;

    for (0..3) |i| {
        const color_component = color[i];

        const component_code: u32 = std.mem.readInt(u16, splitters[3 + i * 2 ..][0..2], .little);

        const base = @as(u16, color_component) + 1;

        const base_min: u16 = @max(@as(i16, color_component) * 2 - 255, 0);

        var target: u16 = 0;
        var diffs: [4]u8 = undefined;

        for (&diffs, 0..) |*diff, j| {
            const splitter_code_component: u7 =
                @intCast(((all_components_code >> @intCast(j * 6)) & 0b111111) +
                (((component_code >> @intCast(j * 4)) & 0b1111) << 2));

            diff.* = @intCast(base_min + ((@as(u16, splitter_code_component) * @as(u16, base - base_min)) >> 7));
            target += diff.*;
        }

        if (color_component < 128) {
            target += 1;
        } else {
            target -= 1;
        }

        const min_diff: u8 = @intCast(target / 4);
        const excess_diff = target % 4;

        var excess_idx: usize = (splitters[9] >> @intCast(i * 2)) % 4;

        for (0..4) |j| {
            const excess: u8 = @intFromBool(excess_idx < excess_diff);

            excess_idx = (excess_idx + 1) % 4;

            res_colors[j][i] = color_component - diffs[j] + min_diff + excess;
        }
    }

    assertValidSplit(color, res_colors);

    return res_colors;
}

fn splitColorAltPathSimd(color: [3]u8, splitters: [10]u8) [4][3]u8 {
    var res_colors: [4][3]u8 = undefined;

    const color_component_vec: @Vector(3, u32) = color;

    var base_min_vec = color_component_vec;
    base_min_vec *= @splat(2);
    base_min_vec -|= @splat(255);

    const all_components_code: u32 = std.mem.readInt(u24, splitters[0..3], .little);

    var target_vec_signed =
        @select(
            i32,
            color_component_vec < @as(@Vector(3, u8), @splat(128)),
            @as(@Vector(3, i32), @splat(1)),
            @as(@Vector(3, i32), @splat(-1)),
        );

    //var target_vec_signed:@Vector(3, i32) = @intFromBool(color_component_vec < @as(@Vector(3, u8), @splat(128)));
    //target_vec_signed *= @splat(2);
    //target_vec_signed -= @splat(1);

    var diffs: [4]@Vector(3, u8) = undefined;

    const component_code_vec: @Vector(3, u32) = if (@import("builtin").cpu.arch.endian() == .little)
        @as(@Vector(3, u16), @bitCast(splitters[3..][0..6].*))
    else
        @byteSwap(@as(@Vector(3, u16), @bitCast(splitters[3..][0..6].*)));

    for (0..4) |i| {
        var splitter_code_component_vec = component_code_vec;

        splitter_code_component_vec >>= @splat(@intCast(i * 4));
        splitter_code_component_vec &= @splat(0b1111);
        splitter_code_component_vec <<= @splat(2);

        splitter_code_component_vec += @splat((all_components_code >> @intCast(i * 6)) & 0b111111);

        var diff: @Vector(3, u32) = @intCast(splitter_code_component_vec);

        var diff_mul: @Vector(3, u32) = color_component_vec;
        diff_mul += @splat(1);
        diff_mul -= base_min_vec;

        diff *= diff_mul;
        diff >>= @splat(7);
        diff += base_min_vec;

        diffs[i] = @intCast(diff);

        target_vec_signed += @intCast(diff);
    }

    const target_vec: @Vector(3, u32) = @intCast(target_vec_signed);

    var min_diff_vec = target_vec;
    min_diff_vec /= @splat(4);

    var excess_diff_vec = target_vec;
    excess_diff_vec %= @splat(4);

    var excess_idx_vec: @Vector(3, u32) = @splat(splitters[9]);
    excess_idx_vec >>= .{ 0, 2, 4 };

    for (0..4) |i| {
        excess_idx_vec %= @splat(4);
        const excess_vec = @intFromBool(excess_idx_vec < excess_diff_vec);
        excess_idx_vec += @splat(1);

        const diff = diffs[i];

        var res_color = color_component_vec;
        res_color -= diff;
        res_color += min_diff_vec;
        res_color += excess_vec;

        res_colors[i] = @as(@Vector(3, u8), @intCast(res_color));
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
