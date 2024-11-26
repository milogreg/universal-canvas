const std = @import("std");

pub const Color = packed struct(u32) {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

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

const magic_color: Color = .{
    .r = 64,
    .g = 64,
    .b = 64,
    .a = 255,
};

// const magic_color: Color = .{
//     .r = 204,
//     .g = 204,
//     .b = 5,
//     .a = 255,
// };

// const magic_color: Color = .{
//     .r = 0,
//     .g = 0,
//     .b = 0,
//     .a = 255,
// };

pub fn getPixelColor(allocator: std.mem.Allocator, x: usize, y: usize, bit_count: usize, offset_digits: []const u2) !Color {
    const x_bits = try bitsFromInt(allocator, x, bit_count);
    defer allocator.free(x_bits);
    const y_bits = try bitsFromInt(allocator, y, bit_count);
    defer allocator.free(y_bits);

    return try getPixelColorBitwiseCoordinates(
        allocator,
        x_bits,
        y_bits,
        offset_digits,
    );
}

fn bitsFromInt(allocator: std.mem.Allocator, int: anytype, bit_count: anytype) ![]u1 {
    const bits = try allocator.alloc(u1, bit_count);

    var temp = int;
    var i: usize = @intCast(bit_count);
    while (temp > 0) {
        i -= 1;
        bits[i] = @truncate(temp);
        temp >>= 1;
    }

    @memset(bits[0..i], 0);

    return bits;
}

// fn getPixelColorBitwiseCoordinates(allocator: std.mem.Allocator, x: []const u1, y: []const u1, width: usize, height: usize) !Color {
//     std.debug.assert(x.len == y.len);

//     const digit_count = x.len;

//     const digits = try allocator.alloc(u2, digit_count);
//     defer allocator.free(digits);

//     for (digits, x, y) |*digit, x_bit, y_bit| {
//         digit.* = (@as(u2, y_bit) << 1) | @as(u2, x_bit);
//     }

//     return try getPixelColorDigits(allocator, digits, width, height);
// }

fn getPixelColorBitwiseCoordinates(allocator: std.mem.Allocator, x: []const u1, y: []const u1, offset_digits: []const u2) !Color {
    std.debug.assert(x.len == y.len);

    const digit_count = x.len;

    const digits = try allocator.alloc(u2, digit_count);
    defer allocator.free(digits);

    // const prefix = comptime blk: {
    //     @setEvalBranchQuota(1000000);
    //     var prng = std.Random.DefaultPrng.init(5245);
    //     const random = prng.random();
    //     var prefix_init: [10]u2 = undefined;
    //     for (&prefix_init) |*digit| {
    //         digit.* = random.int(u1);
    //     }
    //     break :blk prefix_init;
    // };

    const prefix = offset_digits;

    const digits_with_prefix = try allocator.alloc(u2, digit_count + prefix.len);
    defer allocator.free(digits_with_prefix);
    for (digits_with_prefix[0..prefix.len], prefix[0..]) |*digit_with_prefix, prefix_digit| {
        digit_with_prefix.* = prefix_digit;
    }

    for (digits, x, y, digits_with_prefix[prefix.len .. digits.len + prefix.len]) |*digit, x_bit, y_bit, *digit_with_prefix| {
        digit.* = (@as(u2, y_bit) << 1) | @as(u2, x_bit);
        digit_with_prefix.* = (@as(u2, y_bit) << 1) | @as(u2, x_bit);
        // if (digit_with_prefix.* == 2 or digit_with_prefix.* == 3) {
        //     digit_with_prefix.* -= 2;
        // }
    }

    // digits_with_prefix[digits_with_prefix.len - 4] = 2;
    // digits_with_prefix[digits_with_prefix.len - 5] = 2;

    return try getPixelColorDigits(allocator, digits_with_prefix);
}

pub fn getCoordinateDigits(allocator: std.mem.Allocator, x: usize, y: usize, bit_count: usize, offset_digits: []const u2) ![]u2 {
    std.debug.assert(x < @as(std.math.IntFittingRange(0, 1 << 64), 1) << @intCast(bit_count));
    std.debug.assert(y < @as(std.math.IntFittingRange(0, 1 << 64), 1) << @intCast(bit_count));

    const digit_count = offset_digits.len + bit_count;

    const digits = try allocator.alloc(u2, digit_count);

    @memcpy(digits[0..offset_digits.len], offset_digits);

    for (digits[offset_digits.len..], 0..) |*digit, i| {
        const x_bit: u1 = @truncate(x >> @intCast(bit_count - 1 - i));
        const y_bit: u1 = @truncate(y >> @intCast(bit_count - 1 - i));

        // const x_bit: u1 = @truncate(x >> @intCast(i));
        // const y_bit: u1 = @truncate(y >> @intCast(i));
        digit.* = (@as(u2, y_bit) << 1) | @as(u2, x_bit);
    }

    return digits;
}

// fn getPixelColorDigits(allocator: std.mem.Allocator, digits: []const u2) !Color {
//     // {
//     //     var selected_color_idx: usize = 0;
//     //     var color_int: u32 = 0;

//     //     for (digits) |selector| {
//     //         var prng = std.Random.DefaultPrng.init(@as(usize, selector) +% selected_color_idx);
//     //         const random = prng.random();

//     //         color_int = random.int(u32);
//     //         selected_color_idx = random.int(usize);
//     //     }

//     //     var color: Color = @bitCast(color_int);
//     //     color.a = 255;
//     //     if (true) return color;
//     // }

//     if (digits.len < 2) {
//         return magic_color;
//     }

//     const first_2_idx = std.mem.indexOf(u2, digits, &.{3}) orelse return magic_color;

//     // var prev_digit = digits[0];
//     // const first_2_idx: usize = for (digits[1..], 0..) |digit, i| {
//     //     if ((digit == 2) and (prev_digit == 3)) {
//     //         break i + 1;
//     //     }
//     //     prev_digit = digit;
//     // } else {
//     //     // if (true) return .{
//     //     //     .r = @intCast((@as(usize, prev_digit) + 1) * 40),
//     //     //     .g = 0,
//     //     //     .b = 0,
//     //     //     .a = 255,
//     //     // };
//     //     return magic_color;
//     // };

//     const layers = digits.len - first_2_idx - 1;

//     if (layers > 12) {
//         return getPixelColorDigits(allocator, digits[first_2_idx + 1 ..]);
//     }

//     const selector_digits = digits[first_2_idx + 1 ..];

//     // var required_encoded_colors: usize = 0;

//     var selected_color_idx: usize = 0;

//     for (selector_digits) |selector| {
//         selected_color_idx *= 4;
//         selected_color_idx += selector;
//     }

//     if (layers > 0) {
//         selected_color_idx += std.math.pow(usize, 4, layers - 1);
//     }

//     // const size_ceil = ((@as(usize, std.math.log2_int_ceil(usize, layers + 1)) + 1) / 2) * 4;
//     // const required_encoded_colors = blk: {
//     //     var color_count: usize = 0;
//     //     var temp = size_ceil;
//     //     while (temp > 0) : (temp /= 4) {
//     //         color_count += temp;
//     //     }
//     //     break :blk color_count;
//     // };

//     // for (0..layers + 1) |layer| {
//     //     required_encoded_colors += std.math.pow(usize, 4, layer);
//     // }

//     // for (1..layers + 1) |layer| {
//     //     required_encoded_colors += 4 * layer;
//     // }

//     const digits_per_color = 1;

//     const required_encoded_colors = selected_color_idx + 1;

//     const required_encoded_digits = required_encoded_colors * digits_per_color;

//     if (first_2_idx < required_encoded_digits) {
//         // if (true) return .{
//         //     .r = @intCast(required_encoded_digits / 128),
//         //     .g = 255,
//         //     .b = 0,
//         //     .a = 255,
//         // };
//         return getPixelColorDigits(allocator, digits[first_2_idx + 1 ..]);
//         // return magic_color;
//     }

//     const colors = try allocator.alloc(Color, required_encoded_colors);
//     defer allocator.free(colors);

//     for (colors, 0..) |*color, i| {
//         color.* = .{
//             .r = 0,
//             .g = 0,
//             .b = 0,
//             .a = 255,
//         };

//         const color_bits = 24;
//         const color_bits_per_digit = color_bits / digits_per_color;

//         for (digits[i * digits_per_color .. (i + 1) * digits_per_color], 0..) |digit, j| {
//             // std.debug.assert(digit < 2);

//             const digit_adjusted: u1 = @truncate(digit);

//             var color_int: u32 = @bitCast(color.*);
//             color_int |= @as(u32, digit_adjusted) << @intCast(j * color_bits_per_digit);
//             color.* = @bitCast(color_int);
//         }
//     }

//     var test_selected_color_idx: usize = 0;
//     const max_diff = 10;
//     {
//         const diff = colorDiff(colors[0], magic_color);

//         if (diff > max_diff) {
//             return magic_color;
//         }
//     }

//     for (selector_digits) |selector| {
//         const parent = colors[test_selected_color_idx];

//         test_selected_color_idx *= 4;

//         const siblings = .{
//             colors[test_selected_color_idx],
//             colors[test_selected_color_idx + 1],
//             colors[test_selected_color_idx + 2],
//             colors[test_selected_color_idx + 3],
//         };

//         const diff = colorDiff(averageColors(&siblings), parent);

//         if (diff > max_diff) {
//             return magic_color;
//         }

//         test_selected_color_idx += selector;
//     }

//     return colors[selected_color_idx];
// }

// fn getSelfTerminatingDigits(digits: []const u2) ?[]const u2 {
//     var length: usize = 0;
//     var length_start: usize = 0;

//     while (length_start < digits.len and length_start < 64 and (digits[length_start] == 0 or digits[length_start] == 1)) : (length_start += 1) {
//         length |= @as(usize, digits[length_start]) << @intCast(length_start);
//     }

//     if (length_start == 64) {
//         return null;
//     }

//     if (length_start + length >= digits.len) {
//         return null;
//     }

//     return digits[length_start .. length_start + length];
// }

// fn getNonSelfTerminatingDigits(digits: []const u2) []const u2 {
//     const self_terminating = getSelfTerminatingDigits(digits) orelse unreachable;
//     const offset = @intFromPtr(self_terminating.ptr) - @intFromPtr(digits.ptr);

//     return digits[offset + self_terminating.len ..];
// }

fn getSelfTerminatingDigits(digits: []const u2) ?[]const u2 {
    var length: usize = 0;

    while (length < digits.len and digits[length] != 3) {
        length += 1;
    }

    if (length >= digits.len) {
        return null;
    }

    // if (length == 0) {
    //     // length = 1;
    //     return null;
    // }

    return digits[0..length];
}

fn getNonSelfTerminatingDigits(digits: []const u2) []const u2 {
    const self_terminating = getSelfTerminatingDigits(digits) orelse return &.{};

    // if (self_terminating.len + 2 >= digits.len) return &.{};

    return digits[self_terminating.len + 1 ..];
}

// fn getSelfTerminatingDigits(digits: []const u2) ?[]const u2 {
//     var length: usize = 0;

//     var xor_res: u8 = 0;
//     var prng = std.Random.DefaultPrng.init(0);
//     const random = prng.random();

//     while (length < digits.len and (digits[length] != 3 or xor_res != 255)) {
//         for (digits[length]) |_| {
//             _ = random.boolean();
//         }

//         // xor_res +%= digits[length];
//         xor_res = random.int(@TypeOf(xor_res));
//         length += 1;
//     }

//     if (length >= digits.len - 1) {
//         return null;
//     }

//     return digits[0..length];
// }

pub fn childIndices(parent_x: usize, parent_y: usize, parent_square_size: usize) [4]usize {
    const child_square_size = parent_square_size * 2;

    return .{
        parent_y * 2 * child_square_size + parent_x * 2,
        parent_y * 2 * child_square_size + parent_x * 2 + 1,
        (parent_y * 2 + 1) * child_square_size + parent_x * 2,
        (parent_y * 2 + 1) * child_square_size + parent_x * 2 + 1,
    };
}

// fn splitColor(color: Color, splitters: [3][4]usize) [4]Color {
//     var splitter_colors: [4]Color = undefined;

//     for (&splitter_colors, 0..) |*splitter_color, i| {
//         splitter_color.* = .{
//             .r = @intCast(splitters[0][i]),
//             .g = @intCast(splitters[1][i]),
//             .b = @intCast(splitters[2][i]),
//             .a = 255,
//         };
//     }

//     var splitter_average = SumColor.fromColor(splitter_colors[0]);
//     splitter_average = splitter_average.add(SumColor.fromColor(splitter_colors[1]));
//     splitter_average = splitter_average.add(SumColor.fromColor(splitter_colors[2]));
//     splitter_average = splitter_average.add(SumColor.fromColor(splitter_colors[3]));
//     splitter_average = splitter_average.divide(4);

//     const scales: [3]usize = .{
//         if (splitter_average.r != 0)
//             (@as(usize, color.r) * 256) / splitter_average.r
//         else
//             (if (color.r == 0) 256 else 0),

//         if (splitter_average.g != 0)
//             (@as(usize, color.g) * 256) / splitter_average.g
//         else
//             (if (color.g == 0) 256 else 0),

//         if (splitter_average.b != 0)
//             (@as(usize, color.b) * 256) / splitter_average.b
//         else
//             (if (color.b == 0) 256 else 0),
//     };

//     var res_colors: [4]Color = undefined;
//     for (&res_colors, &splitter_colors) |*res_color, splitter_color| {
//         res_color.* = .{
//             .r = @intCast(std.math.clamp((@as(usize, splitter_color.r) * scales[0]) / 256, 0, 255)),
//             .g = @intCast(std.math.clamp((@as(usize, splitter_color.g) * scales[1]) / 256, 0, 255)),
//             .b = @intCast(std.math.clamp((@as(usize, splitter_color.b) * scales[2]) / 256, 0, 255)),
//             .a = 255,
//         };
//     }

//     const target_total = SumColor.fromColor(color).multiply(4);
//     var current_total = SumColor.fromColor(res_colors[0]);
//     for (res_colors[1..]) |child_color| {
//         current_total = current_total.add(SumColor.fromColor(child_color));
//     }

//     {
//         var i: usize = 0;
//         while (current_total.r < target_total.r) : (i = (i + 1) % 4) {
//             if (res_colors[i].r < 255) {
//                 res_colors[i].r += 1;
//                 current_total.r += 1;
//             }
//         }
//     }

//     {
//         var i: usize = 0;
//         while (current_total.g < target_total.g) : (i = (i + 1) % 4) {
//             if (res_colors[i].g < 255) {
//                 res_colors[i].g += 1;
//                 current_total.g += 1;
//             }
//         }
//     }

//     {
//         var i: usize = 0;
//         while (current_total.b < target_total.b) : (i = (i + 1) % 4) {
//             if (res_colors[i].b < 255) {
//                 res_colors[i].b += 1;
//                 current_total.b += 1;
//             }
//         }
//     }

//     return res_colors;
// }

fn distributeValues(comptime T: type, comptime count: comptime_int, target: T, maximums: [count]T) [count]T {
    var x = target;

    // Array of pointers to child values and their corresponding max values
    var values: [4]T = @splat(0);

    // First pass: Distribute an even amount across each child up to its max
    const initial_share = x / 4;
    for (0..4) |i| {
        // Give each child the initial share, but don't exceed its max value
        if (initial_share <= maximums[i]) {
            values[i] = @intCast(initial_share);
            x -= initial_share;
        } else {
            values[i] = maximums[i];
            x -= maximums[i];
        }
    }

    // Second pass: Distribute the remaining x, if any, while respecting max values
    var i: usize = 0;
    while (x > 0 and i < 4) {
        const remaining_capacity = maximums[i] - values[i];
        const amountToGive = if (remaining_capacity < x) remaining_capacity else x;
        values[i] += (amountToGive);
        x -= amountToGive;
        i += 1;
    }

    return values;
}

fn splitColor(color: Color, splitters: [3][4]usize) [4]Color {
    var splitter_colors: [4]Color = undefined;

    for (&splitter_colors, 0..) |*splitter_color, i| {
        splitter_color.* = .{
            .r = @intCast(splitters[0][i]),
            .g = @intCast(splitters[1][i]),
            .b = @intCast(splitters[2][i]),
            .a = 255,
        };
    }

    var splitter_average = SumColor.fromColor(splitter_colors[0]);
    splitter_average = splitter_average.add(SumColor.fromColor(splitter_colors[1]));
    splitter_average = splitter_average.add(SumColor.fromColor(splitter_colors[2]));
    splitter_average = splitter_average.add(SumColor.fromColor(splitter_colors[3]));
    splitter_average = splitter_average.divide(4);

    const scales: [3]usize = .{
        if (splitter_average.r != 0)
            (@as(usize, color.r) * 256) / splitter_average.r
        else
            (if (color.r == 0) 256 else 0),

        if (splitter_average.g != 0)
            (@as(usize, color.g) * 256) / splitter_average.g
        else
            (if (color.g == 0) 256 else 0),

        if (splitter_average.b != 0)
            (@as(usize, color.b) * 256) / splitter_average.b
        else
            (if (color.b == 0) 256 else 0),
    };

    var res_colors: [4]Color = undefined;
    for (&res_colors, &splitter_colors) |*res_color, splitter_color| {
        res_color.* = .{
            .r = @intCast(std.math.clamp((@as(usize, splitter_color.r) * scales[0]) / 256, 0, 255)),
            .g = @intCast(std.math.clamp((@as(usize, splitter_color.g) * scales[1]) / 256, 0, 255)),
            .b = @intCast(std.math.clamp((@as(usize, splitter_color.b) * scales[2]) / 256, 0, 255)),
            .a = 255,
        };
    }

    const target_total = SumColor.fromColor(color).multiply(4);
    var current_total = SumColor.fromColor(res_colors[0]);
    for (res_colors[1..]) |child_color| {
        current_total = current_total.add(SumColor.fromColor(child_color));
    }

    const SumColorField = std.meta.FieldType(SumColor, .r);

    if (current_total.r < target_total.r) {
        const target = target_total.r - current_total.r;

        var max_values: [4]SumColorField = undefined;

        for (&max_values, &res_colors) |*max_value, res_color| {
            max_value.* = 255 - res_color.r;
        }

        const values = distributeValues(SumColorField, 4, target, max_values);

        for (&values, &res_colors) |value, *res_color| {
            res_color.r += @intCast(value);
        }
    }

    if (current_total.g < target_total.g) {
        const target = target_total.g - current_total.g;

        var max_values: [4]SumColorField = undefined;

        for (&max_values, &res_colors) |*max_value, res_color| {
            max_value.* = 255 - res_color.g;
        }

        const values = distributeValues(SumColorField, 4, target, max_values);

        for (&values, &res_colors) |value, *res_color| {
            res_color.g += @intCast(value);
        }
    }

    if (current_total.b < target_total.b) {
        const target = target_total.b - current_total.b;

        var max_values: [4]SumColorField = undefined;

        for (&max_values, &res_colors) |*max_value, res_color| {
            max_value.* = 255 - res_color.b;
        }

        const values = distributeValues(SumColorField, 4, target, max_values);

        for (&values, &res_colors) |value, *res_color| {
            res_color.b += @intCast(value);
        }
    }

    // {
    //     var i: usize = 0;

    //     while (current_total.r < target_total.r) : (i = (i + 1) % 4) {
    //         if (res_colors[i].r < 255) {
    //             res_colors[i].r += 1;
    //             current_total.r += 1;
    //         }
    //     }
    // }

    // {
    //     var i: usize = 0;
    //     while (current_total.g < target_total.g) : (i = (i + 1) % 4) {
    //         if (res_colors[i].g < 255) {
    //             res_colors[i].g += 1;
    //             current_total.g += 1;
    //         }
    //     }
    // }

    // {
    //     var i: usize = 0;
    //     while (current_total.b < target_total.b) : (i = (i + 1) % 4) {
    //         if (res_colors[i].b < 255) {
    //             res_colors[i].b += 1;
    //             current_total.b += 1;
    //         }
    //     }
    // }

    return res_colors;
}

fn digitsFromSplitter(splitter: usize) [8]u2 {
    var digits: [8]u2 = undefined;
    for (&digits, 1..) |*digit, i| {
        digit.* = @intCast((splitter >> @intCast((digits.len - i))) & 1);
    }
    return digits;
}

fn splitterFromDigits(digits: [8]u2) usize {
    var splitter: usize = 0;
    for (&digits, 1..) |digit, i| {
        splitter |= @as(usize, digit & 1) << @intCast((digits.len - i));
    }
    return splitter;
}

fn encodedIdxFromCoordinates(encoded_length: usize, coord_x: usize, coord_y: usize, layer: usize) usize {
    const coord_bits = layer + 1;

    var digit_buf: [64]u2 = undefined;
    const digits = digit_buf[0..coord_bits];

    for (digits, 0..) |*digit, i| {
        const x_bit: u1 = @truncate(coord_x >> @intCast(coord_bits - 1 - i));
        const y_bit: u1 = @truncate(coord_y >> @intCast(coord_bits - 1 - i));

        // const x_bit: u1 = @truncate(x >> @intCast(i));
        // const y_bit: u1 = @truncate(y >> @intCast(i));
        digit.* = (@as(u2, y_bit) << 1) | @as(u2, x_bit);
    }

    if (true) {
        return encodedIdxFromDigits(encoded_length, digits);
    }

    var encoded_idx: usize = 0;

    const digits_per_color = 3 * 8;

    var parent_square_size: usize = 1;

    for (coord_bits - 1) |_| {
        var square = parent_square_size % encoded_length;

        square = (square * parent_square_size) % encoded_length;
        square = (square * (4 * digits_per_color)) % encoded_length;

        encoded_idx = (encoded_idx + square) % encoded_length;

        parent_square_size = (parent_square_size * 2) % encoded_length;
    }

    encoded_idx = (encoded_idx + (coord_y * parent_square_size + coord_x) * (4 * digits_per_color)) % encoded_length;

    // encoded_idx = (encoded_length + encoded_idx - (4 * digits_per_color)) % encoded_length;

    // {
    //     var square_size: usize = 1;
    //     for (digits) |digit| {
    //         encoded_idx = (encoded_idx * 2) % encoded_length;
    //         encoded_idx = (encoded_idx + (digit & 1)) % encoded_length;

    //         encoded_idx = (encoded_idx + (digit >> 1) * square_size) % encoded_length;

    //         square_size = (square_size * 2) % encoded_length;
    //     }

    //     encoded_idx = (encoded_idx * digits_per_color) % encoded_length;
    // }

    return encoded_idx;
}

fn encodedIdxFromDigits(encoded_length: usize, digits: []const u2) usize {
    if (digits.len == 0) {
        return 0;
    }

    var encoded_idx: usize = 0;

    const digits_per_color = 3 * 8;

    var parent_square_size: usize = 1;

    for (digits.len) |_| {
        var square = parent_square_size % encoded_length;

        square = (square * parent_square_size) % encoded_length;
        square = (square * (4 * digits_per_color)) % encoded_length;

        encoded_idx = (encoded_idx + square) % encoded_length;

        parent_square_size = (parent_square_size * 2) % encoded_length;
    }

    var pow: usize = 1;

    var digit_idx: usize = digits.len;

    while (digit_idx > 0) {
        digit_idx -= 1;

        const digit = digits[digit_idx];

        const digit_x: usize = digit & 1;
        const digit_y: usize = (digit >> 1) & 1;

        var adder: usize = digit_x;
        adder = (adder + (digit_y * parent_square_size)) % encoded_length;
        adder = (adder * (4 * digits_per_color)) % encoded_length;
        adder = (adder * (pow)) % encoded_length;

        encoded_idx = (encoded_idx + adder) % encoded_length;

        pow = (pow * 2) % encoded_length;
    }

    // encoded_idx = (encoded_idx + (coord_y * parent_square_size + coord_x) * (4 * digits_per_color)) % encoded_length;

    // encoded_idx = (encoded_length + encoded_idx - (4 * digits_per_color)) % encoded_length;

    // {
    //     var square_size: usize = 1;
    //     for (digits) |digit| {
    //         encoded_idx = (encoded_idx * 2) % encoded_length;
    //         encoded_idx = (encoded_idx + (digit & 1)) % encoded_length;

    //         encoded_idx = (encoded_idx + (digit >> 1) * square_size) % encoded_length;

    //         square_size = (square_size * 2) % encoded_length;
    //     }

    //     encoded_idx = (encoded_idx * digits_per_color) % encoded_length;
    // }

    return encoded_idx;
}

pub fn refineColorWithDigits(allocator: std.mem.Allocator, parent_color: Color, encoded_idx_ptr: *usize, digits: []const u2) ![4]Color {
    _ = allocator; // autofix
    var encoded_idx = encoded_idx_ptr.*;
    defer encoded_idx_ptr.* = encoded_idx;

    const default_colors: [4]Color = @splat(parent_color);

    const debug_colors: [4]Color = @splat(.{
        .r = 0,
        .g = 255,
        .b = 0,
        .a = 255,
    });

    if (digits.len == 0) {
        return default_colors;
    }

    var encoded_digits = getSelfTerminatingDigits(digits) orelse return default_colors;

    var encoded_length = encoded_digits.len;

    if (encoded_length < 1) {
        return default_colors;
        // return try refineColorWithDigits(allocator, parent_color, encoded_idx_ptr, digits[1..]);
    }

    // if (digits.len > encoded_digits.len * 2) {
    //     return try refineColorWithDigits(allocator, parent_color, encoded_idx_ptr, digits[encoded_digits.len + 1 ..]);
    // }

    encoded_digits.len = encoded_digits.len;
    encoded_length = encoded_digits.len;

    const selector_digits = getNonSelfTerminatingDigits(digits);

    encoded_idx = 0;

    // const digits_per_color = (9 * 10) + 3;
    // const digits_per_color = (9 * 10) + 6;
    const digits_per_color = (3 * 8);
    _ = digits_per_color; // autofix

    // for (selector_digits[0 .. selector_digits.len - 1]) |digit| {
    //     encoded_idx = (encoded_idx * digits_per_color) % encoded_length;
    //     encoded_idx = (encoded_idx + digit) % encoded_length;
    // }
    // encoded_idx = (encoded_idx * digits_per_color) % encoded_length;

    // for (selector_digits.len - 1) |_| {
    //     encoded_idx = (encoded_idx * digits_per_color) % encoded_length;
    // }

    // 0: 4^1 * dpc
    // 1: 4^2 * dpc
    // 2: 4^3 * dpc

    // x(n + 1) = x(n) * 2

    // {
    //     var x: usize = 0;
    //     var y: usize = 0;
    //     var parent_square_size: usize = 1;
    //     var digit_idx: usize = 0;
    //     while (parent_square_size < digits.len and digit_idx < selector_digits.len) : (digit_idx += 1) {
    //         x *= 2;
    //         y *= 2;

    //         const digit = selector_digits[digit_idx];

    //         x += digit & 1;
    //         y += digit >> 1;

    //         parent_square_size *= 2;
    //     }

    //     parent_square_size /= 2;

    //     encoded_idx = (((y * parent_square_size) + x) * digits_per_color) % encoded_length;

    //     if ((((y * parent_square_size) + x) * digits_per_color) >= encoded_length) {
    //         return default_colors;
    //     }
    // }

    // {
    //     var square_size: usize = 1;
    //     for (selector_digits) |digit| {
    //         encoded_idx = (encoded_idx * 2) % encoded_length;
    //         encoded_idx = (encoded_idx + (digit & 1)) % encoded_length;

    //         encoded_idx = (encoded_idx + (digit >> 1) * square_size) % encoded_length;

    //         square_size = (square_size * 2) % encoded_length;
    //     }

    //     encoded_idx = (encoded_idx * digits_per_color) % encoded_length;
    // }

    // {
    //     var x: usize = 0;
    //     var y: usize = 0;
    //     var parent_square_size: usize = 1;
    //     var digit_idx: usize = 0;
    //     while (parent_square_size < digits.len and digit_idx < selector_digits.len) : (digit_idx += 1) {
    //         const digit = selector_digits[digit_idx];

    //         const child_indices = childIndices(x, y, parent_square_size);
    //         const child_idx = child_indices[digit];

    //         const child_square_size = parent_square_size * 2;

    //         x = child_idx % child_square_size;
    //         y = child_idx / child_square_size;

    //         parent_square_size = child_square_size;
    //     }

    //     encoded_idx = (((y * parent_square_size) + x) * digits_per_color) % encoded_length;

    //     if ((((y * parent_square_size) + x) * digits_per_color) >= encoded_length) {
    //         return default_colors;
    //     }
    // }

    encoded_idx = encodedIdxFromDigits(encoded_length, selector_digits);

    // encoded_idx = 0;

    // var adders: [3]u1 = undefined;
    // for (&adders) |*adder| {
    //     adder.* = @intFromBool(encoded_digits[encoded_idx] == 0);
    //     encoded_idx = (encoded_idx + 1) % encoded_length;
    // }

    // var adders: [3]u1 = undefined;
    // for (&adders) |*adder| {
    //     var has_adder = true;
    //     for (0..4) |_| {
    //         has_adder = has_adder and encoded_digits[encoded_idx] == 1;
    //         encoded_idx = (encoded_idx + 1) % encoded_length;
    //     }
    //     adder.* = @intFromBool(has_adder);
    // }

    // var subtractors: [3]u1 = undefined;
    // for (&subtractors) |*subtractor| {
    //     subtractor.* = @intFromBool(encoded_digits[encoded_idx] == 0);
    //     encoded_idx = (encoded_idx + 1) % encoded_length;
    // }

    // var subtractors: [3]u1 = undefined;
    // for (&subtractors) |*subtractor| {
    //     var has_subtractor = true;
    //     for (0..4) |_| {
    //         has_subtractor = has_subtractor and encoded_digits[encoded_idx] == 1;
    //         encoded_idx = (encoded_idx + 1) % encoded_length;
    //     }
    //     subtractor.* = @intFromBool(has_subtractor);
    // }

    var mutaters: [6]u1 = @splat(0);

    var splitters: [3][4]usize = undefined;
    for (0..3) |i| {
        for (0..4) |j| {
            var splitter_digits: [8]u2 = undefined;
            for (&splitter_digits) |*splitter_digit| {
                splitter_digit.* = digits[encoded_idx];

                encoded_idx = (encoded_idx + 1) % encoded_length;
            }

            splitters[i][j] = splitterFromDigits(splitter_digits);
        }
    }

    if (true) return splitColor(parent_color, splitters);

    var splits: [4 * 3]u8 = undefined;
    for (&splits, 0..) |*split, j| {
        split.* = 0;
        // for (0..8) |i| {
        //     mutaters[j % mutaters.len] ^= @intCast(digits[encoded_idx] >> 1);
        //     split.* |= @as(u8, digits[encoded_idx] & 1) << @intCast(i);
        //     encoded_idx = (encoded_idx + 1) % encoded_length;
        // }

        for (0..8) |i| {
            if (digits[encoded_idx] == 2 or digits[encoded_idx] == 3) {
                return debug_colors;
            }

            mutaters[j % mutaters.len] ^= @intCast(digits[encoded_idx] >> 1);
            split.* |= @as(u8, digits[encoded_idx] & 1) << @intCast(i);
            encoded_idx = (encoded_idx + 1) % encoded_length;
        }

        // for (0..7) |_| {
        //     split.* *%= 3;
        //     split.* +%= @as(u10, encoded_digits[encoded_idx]);

        //     encoded_idx = (encoded_idx + 1) % encoded_length;
        // }

        // var prng = std.Random.DefaultPrng.init(split.*);
        // const random = prng.random();
        // split.* = random.int(u8);

        // split.* = @bitReverse(split.*);
    }

    const adders = mutaters[0..3];
    _ = adders; // autofix
    const subtractors = mutaters[3..6];
    _ = subtractors; // autofix

    var splitter_colors: [4]Color = undefined;

    // for (&splitter_colors, 0..) |*splitter_color, i| {
    //     splitter_color.* = .{
    //         .r = @intCast(splits[i * 3 + 0]),
    //         .g = @intCast(splits[i * 3 + 1]),
    //         .b = @intCast(splits[i * 3 + 2]),
    //         .a = 255,
    //     };
    // }

    for (&splitter_colors, 0..) |*splitter_color, i| {
        splitter_color.* = .{
            .r = @intCast(splits[0 * 4 + i]),
            .g = @intCast(splits[1 * 4 + i]),
            .b = @intCast(splits[2 * 4 + i]),
            .a = 255,
        };
    }

    var splitter_average = SumColor.fromColor(splitter_colors[0]);
    splitter_average = splitter_average.add(SumColor.fromColor(splitter_colors[1]));
    splitter_average = splitter_average.add(SumColor.fromColor(splitter_colors[2]));
    splitter_average = splitter_average.add(SumColor.fromColor(splitter_colors[3]));
    splitter_average = splitter_average.divide(4);

    var parent_color_adjusted = parent_color;
    parent_color_adjusted = parent_color_adjusted;

    // if (parent_color_adjusted.r < 255) {
    //     parent_color_adjusted.r += adders[0];
    // }
    // if (parent_color_adjusted.g < 255) {
    //     parent_color_adjusted.g += adders[1];
    // }
    // if (parent_color_adjusted.b < 255) {
    //     parent_color_adjusted.b += adders[2];
    // }

    // if (parent_color_adjusted.r > 0) {
    //     parent_color_adjusted.r -= subtractors[0];
    // }
    // if (parent_color_adjusted.g > 0) {
    //     parent_color_adjusted.g -= subtractors[1];
    // }
    // if (parent_color_adjusted.b > 0) {
    //     parent_color_adjusted.b -= subtractors[2];
    // }

    const scales: [3]usize = .{
        if (splitter_average.r != 0)
            (@as(usize, parent_color_adjusted.r) * 256) / splitter_average.r
        else
            (if (parent_color_adjusted.r == 0) 256 else 0),

        if (splitter_average.g != 0)
            (@as(usize, parent_color_adjusted.g) * 256) / splitter_average.g
        else
            (if (parent_color_adjusted.g == 0) 256 else 0),

        if (splitter_average.b != 0)
            (@as(usize, parent_color_adjusted.b) * 256) / splitter_average.b
        else
            (if (parent_color_adjusted.b == 0) 256 else 0),
    };

    // const scales: [3]usize = .{
    //     if (splitter_average.r != 0)
    //         std.math.divCeil(usize, @as(usize, parent_color_adjusted.r) * 256, splitter_average.r) catch unreachable
    //     else
    //         (if (parent_color_adjusted.r == 0) 256 else 0),

    //     if (splitter_average.g != 0)
    //         std.math.divCeil(usize, @as(usize, parent_color_adjusted.g) * 256, splitter_average.g) catch unreachable
    //     else
    //         (if (parent_color_adjusted.g == 0) 256 else 0),

    //     if (splitter_average.b != 0)
    //         std.math.divCeil(usize, @as(usize, parent_color_adjusted.b) * 256, splitter_average.b) catch unreachable
    //     else
    //         (if (parent_color_adjusted.b == 0) 256 else 0),
    // };

    var res_colors: [4]Color = undefined;
    for (&res_colors, &splitter_colors) |*res_color, splitter_color| {
        res_color.* = .{
            .r = @intCast(std.math.clamp((@as(usize, splitter_color.r) * scales[0]) / 256, 0, 255)),
            .g = @intCast(std.math.clamp((@as(usize, splitter_color.g) * scales[1]) / 256, 0, 255)),
            .b = @intCast(std.math.clamp((@as(usize, splitter_color.b) * scales[2]) / 256, 0, 255)),
            .a = 255,
        };
    }

    const target_total = SumColor.fromColor(parent_color_adjusted).multiply(4);
    var current_total = SumColor.fromColor(res_colors[0]);
    for (res_colors[1..]) |color| {
        current_total = current_total.add(SumColor.fromColor(color));
    }

    {
        var i: usize = 0;
        while (current_total.r < target_total.r) : (i = (i + 1) % 4) {
            if (res_colors[i].r < 255) {
                res_colors[i].r += 1;
                current_total.r += 1;
            }
        }
    }

    {
        var i: usize = 0;
        while (current_total.g < target_total.g) : (i = (i + 1) % 4) {
            if (res_colors[i].g < 255) {
                res_colors[i].g += 1;
                current_total.g += 1;
            }
        }
    }

    {
        var i: usize = 0;
        while (current_total.b < target_total.b) : (i = (i + 1) % 4) {
            if (res_colors[i].b < 255) {
                res_colors[i].b += 1;
                current_total.b += 1;
            }
        }
    }

    return res_colors;
}

// pub fn fillColorsRecursive(allocator: std.mem.Allocator, root_color: Color, digits: []const u2, output_colors: []const []Color, target_square_size: usize) !void {
//     std.debug.assert(target_square_size > 0);

//     if (target_square_size == 1) {
//         // output_colors[0][0] = .{ .r = 0, .g = 255, .b = 0, .a = 255 };
//         output_colors[0][0] = root_color;
//         return;
//     }

//     const new_digit_slices = try allocator.alloc([]u2, 4);
//     defer allocator.free(new_digit_slices);

//     for (new_digit_slices) |*new_digit_slice| {
//         new_digit_slice.* = try allocator.alloc(u2, digits.len + 1);
//     }
//     defer {
//         for (new_digit_slices) |new_digit_slice| {
//             allocator.free(new_digit_slice);
//         }
//     }
//     for (new_digit_slices, 0..) |new_digit_slice, i| {
//         @memcpy(new_digit_slice[0 .. new_digit_slice.len - 1], digits);
//         new_digit_slice[new_digit_slice.len - 1] = @intCast(i);
//     }

//     const new_output_colors = try allocator.alloc([][]Color, 4);
//     defer allocator.free(new_output_colors);

//     for (new_output_colors) |*new_output_color| {
//         new_output_color.* = try allocator.alloc([]Color, target_square_size / 2);
//     }

//     defer {
//         for (new_output_colors) |new_output_color| {
//             allocator.free(new_output_color);
//         }
//     }

//     for (new_output_colors, 0..) |new_output_color, i| {
//         const x_bit = (i & 1);
//         const y_bit = (i >> 1) & 1;

//         for (0..target_square_size / 2) |y| {
//             const x = x_bit * (target_square_size / 2);

//             new_output_color[y] = output_colors[(y + y_bit * (target_square_size / 2))][x .. x + target_square_size / 2];
//         }

//         // switch (i) {
//         //     0...2 => {
//         //         for (0..target_square_size / 2) |y| {
//         //             new_output_color[y] = output_colors[y][0 .. target_square_size / 2];
//         //         }
//         //     },
//         //     3 => {
//         //         for (0..target_square_size / 2) |y| {
//         //             new_output_color[y] = output_colors[y + target_square_size / 2][target_square_size / 2 .. target_square_size];
//         //         }
//         //     },
//         //     else => unreachable,
//         // }
//     }

//     const encoded_digits = getSelfTerminatingDigits(digits) orelse {
//         for (new_digit_slices, new_output_colors) |new_digit_slice, new_output_color| {
//             try fillColorsRecursive(allocator, root_color, new_digit_slice, new_output_color, target_square_size / 2);
//         }

//         return;
//     };

//     // if (encoded_digits.len < 1) {
//     //     for (new_digit_slices, new_output_colors) |new_digit_slice, new_output_color| {
//     //         try fillColorsRecursive(allocator, root_color, new_digit_slice, new_output_color, target_square_size / 2);
//     //     }
//     //     return;
//     // }

//     const selector_digits = getNonSelfTerminatingDigits(digits);

//     // const starting_idx = encodedIdxFromDigits(encoded_digits.len, selector_digits);

//     try fillColorsTerminate(allocator, root_color, encoded_digits, output_colors, selector_digits);
// }

pub fn fillColorsRecursive(allocator: std.mem.Allocator, root_color: Color, digits: []const u2, output_colors: []const []Color, target_square_size: usize) std.mem.Allocator.Error!void {
    const target_square_size_bits = std.math.log2(target_square_size);

    const digits_buf = try allocator.alloc(u2, digits.len + target_square_size_bits);
    defer allocator.free(digits_buf);

    @memcpy(digits_buf[0..digits.len], digits);

    try fillColorsRecursiveHelp(
        allocator,
        root_color,
        digits_buf,
        digits.len,
        output_colors,
        target_square_size,
        getSelfTerminatingDigits(digits_buf[0..digits.len]),
    );
    // try fillColorsRecursiveHelp(allocator, root_color, digits_buf, @min(digits.len, 64), output_colors, target_square_size);
}

// fn fillColorsRecursiveHelp(allocator: std.mem.Allocator, root_color: Color, digits_buf: []u2, digit_count: usize, output_colors: []const []Color, target_square_size: usize) !void {
//     std.debug.assert(target_square_size > 0);

//     if (target_square_size == 1) {
//         // output_colors[0][0] = .{ .r = 0, .g = 255, .b = 0, .a = 255 };
//         output_colors[0][0] = root_color;
//         return;
//     }

//     const new_output_colors = try allocator.alloc([][]Color, 4);
//     defer allocator.free(new_output_colors);

//     for (new_output_colors) |*new_output_color| {
//         new_output_color.* = try allocator.alloc([]Color, target_square_size / 2);
//     }

//     defer {
//         for (new_output_colors) |new_output_color| {
//             allocator.free(new_output_color);
//         }
//     }

//     for (new_output_colors, 0..) |new_output_color, i| {
//         const x_bit = (i & 1);
//         const y_bit = (i >> 1) & 1;

//         for (0..target_square_size / 2) |y| {
//             const x = x_bit * (target_square_size / 2);

//             new_output_color[y] = output_colors[(y + y_bit * (target_square_size / 2))][x .. x + target_square_size / 2];
//         }
//     }

//     const digits = digits_buf[0..digit_count];

//     const encoded_digits = getSelfTerminatingDigits(digits) orelse {
//         const new_digit_count = digit_count + 1;
//         for (new_output_colors, 0..) |new_output_color, i| {
//             digits_buf[digit_count] = @intCast(i);

//             try fillColorsRecursiveHelp(allocator, root_color, digits_buf, new_digit_count, new_output_color, target_square_size / 2);
//         }

//         return;
//     };

//     const selector_digits = getNonSelfTerminatingDigits(digits);

//     try fillColorsTerminate(allocator, root_color, encoded_digits, output_colors, selector_digits);
// }

fn fillColorsRecursiveHelp(allocator: std.mem.Allocator, root_color: Color, digits_buf: []u2, digit_count: usize, output_colors: []const []Color, target_square_size: usize, encoded_digits_opt: ?[]const u2) !void {
    std.debug.assert(target_square_size > 0);

    if (target_square_size == 1) {
        // output_colors[0][0] = .{ .r = 0, .g = 255, .b = 0, .a = 255 };
        output_colors[0][0] = root_color;
        return;
    }

    const digits = digits_buf[0..digit_count];

    // const test_len = @min(digit_count, 64);
    // const digits = digits_buf[digit_count - test_len .. digit_count];

    const encoded_digits = encoded_digits_opt orelse {
        const new_output_colors = try allocator.alloc([][]Color, 4);
        defer allocator.free(new_output_colors);

        for (new_output_colors) |*new_output_color| {
            new_output_color.* = try allocator.alloc([]Color, target_square_size / 2);
        }

        defer {
            for (new_output_colors) |new_output_color| {
                allocator.free(new_output_color);
            }
        }

        for (new_output_colors, 0..) |new_output_color, i| {
            const x_bit = (i & 1);
            const y_bit = (i >> 1) & 1;

            for (0..target_square_size / 2) |y| {
                const x = x_bit * (target_square_size / 2);

                new_output_color[y] = output_colors[(y + y_bit * (target_square_size / 2))][x .. x + target_square_size / 2];
            }
        }

        const new_digit_count = digit_count + 1;
        for (new_output_colors, 0..) |new_output_color, i| {
            digits_buf[digit_count] = @intCast(i);

            const new_encoded_digits: ?[]const u2 = if (i == 3) digits_buf[0..digit_count] else null;

            try fillColorsRecursiveHelp(allocator, root_color, digits_buf, new_digit_count, new_output_color, target_square_size / 2, new_encoded_digits);
        }

        return;
    };

    const selector_digits = digits[@min(digits.len, encoded_digits.len + 1)..];

    try fillColorsTerminateSelfConsuming(allocator, root_color, encoded_digits, output_colors, selector_digits);
}

// fn fillColorsTerminate(allocator: std.mem.Allocator, root_color: Color, digits: []const u2, output_colors: []const []Color, selector_digits: []const u2) !void {
//     if (digits.len == 0) {
//         for (output_colors) |sub_output_colors| {
//             @memset(sub_output_colors, root_color);
//         }
//         return;
//     }

//     const target_square_size = output_colors.len;
//     std.debug.assert(std.math.isPowerOfTwo(target_square_size));

//     const digits_per_color = (3 * 8);

//     ///////////////////////////////////////////

//     const buf1: []Color = try allocator.alloc(Color, target_square_size * target_square_size);
//     defer allocator.free(buf1);

//     const buf2: []Color = try allocator.alloc(Color, target_square_size * target_square_size);
//     defer allocator.free(buf2);

//     var colors: []Color = buf1[0..1];
//     colors[0] = root_color;

//     var digit_idx: usize = 0;

//     var layer: usize = 1;

//     const layer_max = @min(14, selector_digits.len + std.math.log2(target_square_size));

//     var parent_offset_x: usize = 0;
//     var parent_offset_y: usize = 0;

//     while (layer <= layer_max) : (layer += 1) {
//         const parent_square_size_bits: std.math.Log2Int(usize) = @intCast((layer - 1) - @min(layer - 1, selector_digits.len));
//         const parent_square_size = @as(usize, 1) << parent_square_size_bits;
//         const child_square_size_bits = parent_square_size_bits + 1;
//         const child_square_size = @as(usize, 1) << child_square_size_bits;

//         const true_parent_square_size_bits: std.math.Log2Int(usize) = @intCast(layer - 1);
//         const true_parent_square_size = @as(usize, 1) << @intCast(true_parent_square_size_bits);
//         const true_child_square_size_bits: std.math.Log2Int(usize) = @intCast(layer);
//         const true_child_square_size = @as(usize, 1) << true_child_square_size_bits;
//         _ = true_child_square_size; // autofix

//         const child_colors = buf2[0 .. child_square_size * child_square_size];
//         @memset(child_colors, .{
//             .r = 255,
//             .g = 255,
//             .b = 0,
//             .a = 255,
//         });

//         var child_offset_x: usize = parent_offset_x * 2;
//         var child_offset_y: usize = parent_offset_y * 2;
//         if (layer <= selector_digits.len) {
//             const digit = selector_digits[layer - 1];
//             const digit_x: usize = digit & 1;
//             const digit_y: usize = (digit >> 1) & 1;

//             child_offset_x += digit_x;
//             child_offset_y += digit_y;
//         }

//         defer parent_offset_x = child_offset_x;
//         defer parent_offset_y = child_offset_y;

//         {
//             var digit_idx_adder = 4 * digits_per_color * parent_offset_y % digits.len;
//             digit_idx_adder = (digit_idx_adder * true_parent_square_size) % digits.len;
//             digit_idx = (digit_idx + digit_idx_adder) % digits.len;
//         }

//         const child_indices_modifiers = [_]usize{
//             0,
//             1,
//             @as(usize, 1) << true_child_square_size_bits,
//             (@as(usize, 1) << true_child_square_size_bits) | 1,
//         };

//         const child_indices_adder = (parent_offset_y << (true_child_square_size_bits + 1)) | (parent_offset_x << 1);

//         const child_indices_mask = (@as(usize, 1) << true_child_square_size_bits) - 1;
//         const child_indices_subtractor = (child_offset_y << child_square_size_bits) + child_offset_x;

//         for (0..parent_square_size) |parent_y| {
//             digit_idx = (digit_idx + 4 * digits_per_color * parent_offset_x) % digits.len;

//             for (0..parent_square_size) |parent_x| {
//                 var splitters: [3][4]usize = undefined;

//                 for (0..3) |i| {
//                     for (0..4) |j| {
//                         var splitter_digits: [8]u2 = undefined;
//                         for (&splitter_digits) |*splitter_digit| {
//                             splitter_digit.* = digits[digit_idx];

//                             digit_idx = (digit_idx + 1) % digits.len;
//                         }

//                         splitters[i][j] = splitterFromDigits(splitter_digits);
//                     }
//                 }

//                 var adjusted_child_indices: [4]?usize = undefined;
//                 {
//                     var base_idx = (parent_y << (true_child_square_size_bits + 1)) | ((parent_x) << 1);
//                     base_idx += child_indices_adder;

//                     for (&adjusted_child_indices, &child_indices_modifiers) |*adjusted_child_idx, modifier| {
//                         const temp = base_idx | modifier;
//                         var idx = (temp >> true_child_square_size_bits) << child_square_size_bits;

//                         idx += temp & child_indices_mask;

//                         adjusted_child_idx.* = if (child_indices_subtractor <= idx) idx - child_indices_subtractor else null;
//                     }
//                 }

//                 std.debug.assert(std.mem.indexOfNone(?usize, &adjusted_child_indices, &.{null}) != null);

//                 const adjusted_parent_x = parent_x;
//                 const adjusted_parent_y = parent_y;

//                 const parent_color_idx = adjusted_parent_y * parent_square_size + adjusted_parent_x;

//                 const parent_color = colors[parent_color_idx];

//                 const current_child_colors = splitColor(parent_color, splitters);

//                 for (&current_child_colors, &adjusted_child_indices) |child_color, adjusted_child_idx| {
//                     if (adjusted_child_idx) |idx| {
//                         child_colors[idx] = child_color;
//                     }
//                 }
//             }

//             {
//                 const diff = true_parent_square_size - (parent_offset_x + parent_square_size);
//                 digit_idx = (digit_idx + 4 * digits_per_color * diff) % digits.len;
//             }
//         }

//         {
//             const diff = true_parent_square_size - (parent_offset_y + parent_square_size);
//             var digit_idx_adder = 4 * digits_per_color * diff % digits.len;
//             digit_idx_adder = (digit_idx_adder * true_parent_square_size) % digits.len;
//             digit_idx = (digit_idx + digit_idx_adder) % digits.len;
//         }

//         if (layer > selector_digits.len) {
//             colors = buf1[0..child_colors.len];
//             @memcpy(colors, child_colors);
//         } else {
//             colors[0] = child_colors[0];
//         }
//     }

//     for (0..target_square_size) |y| {
//         if ((y + 1) * target_square_size <= colors.len) {
//             @memcpy(output_colors[y], colors[y * target_square_size .. (y + 1) * target_square_size]);
//         } else {
//             @memset(output_colors[y], .{
//                 .r = 0,
//                 .g = 255,
//                 .b = 255,
//                 .a = 255,
//             });
//         }
//     }
// }

fn shiftLeftModulo(comptime T: type, val: T, shift: anytype, modulo: T) T {
    var res = val;
    for (shift) |_| {
        res = (res << 1) % modulo;
    }
    return res;
}

// fn fillColorsTerminate(allocator: std.mem.Allocator, root_color: Color, digits: []const u2, output_colors: []const []Color, selector_digits: []const u2) !void {
//     if (digits.len == 0) {
//         for (output_colors) |sub_output_colors| {
//             @memset(sub_output_colors, root_color);
//         }
//         return;
//     }

//     const target_square_size = output_colors.len;
//     std.debug.assert(std.math.isPowerOfTwo(target_square_size));

//     const digits_per_color = (3 * 8);

//     ///////////////////////////////////////////

//     const buf1: []Color = try allocator.alloc(Color, target_square_size * target_square_size);
//     defer allocator.free(buf1);

//     const buf2: []Color = try allocator.alloc(Color, target_square_size * target_square_size);
//     defer allocator.free(buf2);

//     var colors: []Color = buf1[0..1];
//     colors[0] = root_color;

//     var digit_idx: usize = 0;

//     var layer: usize = 1;

//     const layer_max = @min(14, selector_digits.len + std.math.log2(target_square_size));

//     var parent_offset_x: usize = 0;
//     var parent_offset_y: usize = 0;

//     while (layer <= layer_max) : (layer += 1) {
//         const parent_square_size_bits: std.math.Log2Int(usize) = @intCast((layer - 1) - @min(layer - 1, selector_digits.len));
//         const parent_square_size = @as(usize, 1) << parent_square_size_bits;
//         const child_square_size_bits = parent_square_size_bits + 1;
//         const child_square_size = @as(usize, 1) << child_square_size_bits;

//         // const modulo:usize = (1 << 30) + 124127;

//         const modulo = digits.len * target_square_size * target_square_size;

//         const true_parent_square_size_bits = layer - 1;
//         const true_parent_square_size = shiftLeftModulo(usize, 1, true_parent_square_size_bits, modulo);
//         const true_child_square_size_bits = layer;
//         const true_child_square_size = shiftLeftModulo(usize, 1, true_child_square_size_bits, modulo);
//         _ = true_child_square_size; // autofix

//         const child_colors = buf2[0 .. child_square_size * child_square_size];
//         @memset(child_colors, .{
//             .r = 255,
//             .g = 255,
//             .b = 0,
//             .a = 255,
//         });

//         var child_offset_x: usize = (parent_offset_x * 2) % modulo;
//         var child_offset_y: usize = (parent_offset_y * 2) % modulo;
//         if (layer <= selector_digits.len) {
//             const digit = selector_digits[layer - 1];
//             const digit_x: usize = digit & 1;
//             const digit_y: usize = (digit >> 1) & 1;

//             child_offset_x = (child_offset_x + digit_x) % modulo;
//             child_offset_y = (child_offset_y + digit_y) % modulo;
//         }

//         // std.debug.assert(child_offset_x < target_square_size * target_square_size);

//         defer parent_offset_x = child_offset_x;
//         defer parent_offset_y = child_offset_y;

//         {
//             var digit_idx_adder = 4 * digits_per_color * parent_offset_y % digits.len;
//             digit_idx_adder = (digit_idx_adder * true_parent_square_size) % digits.len;
//             digit_idx = (digit_idx + digit_idx_adder) % digits.len;
//         }

//         const child_indices_modifiers = [_]usize{
//             0,
//             1,
//             shiftLeftModulo(usize, 1, true_child_square_size_bits, modulo),
//             (shiftLeftModulo(usize, 1, true_child_square_size_bits, modulo) + 1) % modulo,
//         };

//         const child_indices_adder = blk: {
//             var temp = shiftLeftModulo(usize, parent_offset_y, true_child_square_size_bits + 1, modulo);
//             temp = (temp + (parent_offset_x << 1)) % modulo;
//             break :blk temp;
//         };

//         const child_indices_modulo = shiftLeftModulo(usize, 1, true_child_square_size_bits, modulo);
//         const child_indices_subtractor = ((child_offset_y << child_square_size_bits) + child_offset_x) % modulo;

//         for (0..parent_square_size) |parent_y| {
//             digit_idx = (digit_idx + 4 * digits_per_color * parent_offset_x) % digits.len;

//             for (0..parent_square_size) |parent_x| {
//                 var splitters: [3][4]usize = undefined;

//                 for (0..3) |i| {
//                     for (0..4) |j| {
//                         var splitter_digits: [8]u2 = undefined;
//                         for (&splitter_digits) |*splitter_digit| {
//                             splitter_digit.* = digits[digit_idx];

//                             digit_idx = (digit_idx + 1) % digits.len;
//                         }

//                         splitters[i][j] = splitterFromDigits(splitter_digits);
//                     }
//                 }

//                 var adjusted_child_indices: [4]usize = undefined;
//                 {
//                     var base_idx = shiftLeftModulo(usize, parent_y, true_child_square_size_bits + 1, modulo);
//                     base_idx = (base_idx + (parent_x << 1)) % modulo;
//                     base_idx = (base_idx + child_indices_adder) % modulo;

//                     for (&adjusted_child_indices, &child_indices_modifiers) |*adjusted_child_idx, modifier| {
//                         const temp = (base_idx + modifier) % modulo;

//                         var idx = shiftLeftModulo(usize, (std.math.shr(usize, temp, true_child_square_size_bits)), child_square_size_bits, modulo);

//                         idx = (idx + (temp % child_indices_modulo)) % modulo;

//                         adjusted_child_idx.* = (child_colors.len + idx - child_indices_subtractor) % child_colors.len;
//                     }
//                 }

//                 const adjusted_parent_x = parent_x;
//                 const adjusted_parent_y = parent_y;

//                 const parent_color_idx = adjusted_parent_y * parent_square_size + adjusted_parent_x;

//                 const parent_color = colors[parent_color_idx % colors.len];

//                 const current_child_colors = splitColor(parent_color, splitters);

//                 for (&current_child_colors, &adjusted_child_indices) |child_color, adjusted_child_idx| {
//                     child_colors[adjusted_child_idx] = child_color;
//                 }
//             }

//             {
//                 const diff = (digits.len + true_parent_square_size - ((parent_offset_x + parent_square_size) % digits.len)) % digits.len;
//                 digit_idx = (digit_idx + 4 * digits_per_color * diff) % digits.len;
//             }
//         }

//         {
//             const diff = (digits.len + true_parent_square_size - ((parent_offset_y + parent_square_size) % digits.len)) % digits.len;
//             var digit_idx_adder = 4 * digits_per_color * diff % digits.len;
//             digit_idx_adder = (digit_idx_adder * true_parent_square_size) % digits.len;
//             digit_idx = (digit_idx + digit_idx_adder) % digits.len;
//         }

//         if (layer > selector_digits.len) {
//             colors = buf1[0..child_colors.len];
//             @memcpy(colors, child_colors);
//         } else {
//             colors[0] = child_colors[0];
//         }
//     }

//     for (0..target_square_size) |y| {
//         if ((y + 1) * target_square_size <= colors.len) {
//             @memcpy(output_colors[y], colors[y * target_square_size .. (y + 1) * target_square_size]);
//         } else {
//             @memset(output_colors[y], .{
//                 .r = 0,
//                 .g = 255,
//                 .b = 255,
//                 .a = 255,
//             });
//         }
//     }
// }

// fn fillColorsTerminate(allocator: std.mem.Allocator, root_color: Color, digits: []const u2, output_colors: []const []Color, selector_digits: []const u2) !void {
//     if (digits.len == 0) {
//         for (output_colors) |sub_output_colors| {
//             @memset(sub_output_colors, root_color);
//         }
//         return;
//     }

//     const target_square_size = output_colors.len;
//     std.debug.assert(std.math.isPowerOfTwo(target_square_size));

//     const digits_per_color = (3 * 8);

//     ///////////////////////////////////////////

//     const buf1: []Color = try allocator.alloc(Color, target_square_size * target_square_size);
//     defer allocator.free(buf1);

//     const buf2: []Color = try allocator.alloc(Color, target_square_size * target_square_size);
//     defer allocator.free(buf2);

//     var colors: []Color = buf1[0..1];
//     colors[0] = root_color;

//     var digit_idx: usize = 0;

//     var layer: usize = 1;

//     const layer_max = @min(14, selector_digits.len + std.math.log2(target_square_size));

//     var parent_offset_x: usize = 0;
//     var parent_offset_y: usize = 0;

//     while (layer <= layer_max) : (layer += 1) {
//         const parent_square_size_bits: std.math.Log2Int(usize) = @intCast((layer - 1) - @min(layer - 1, selector_digits.len));
//         const parent_square_size = @as(usize, 1) << parent_square_size_bits;
//         const child_square_size_bits = parent_square_size_bits + 1;
//         const child_square_size = @as(usize, 1) << child_square_size_bits;

//         const true_parent_square_size_bits: std.math.Log2Int(usize) = @intCast(layer - 1);
//         const true_parent_square_size = @as(usize, 1) << @intCast(true_parent_square_size_bits);
//         const true_child_square_size_bits: std.math.Log2Int(usize) = @intCast(layer);
//         const true_child_square_size = @as(usize, 1) << true_child_square_size_bits;
//         _ = true_child_square_size; // autofix

//         const child_colors = buf2[0 .. child_square_size * child_square_size];
//         @memset(child_colors, .{
//             .r = 255,
//             .g = 255,
//             .b = 0,
//             .a = 255,
//         });

//         var child_offset_x: usize = parent_offset_x * 2;
//         var child_offset_y: usize = parent_offset_y * 2;
//         if (layer <= selector_digits.len) {
//             const digit = selector_digits[layer - 1];
//             const digit_x: usize = digit & 1;
//             const digit_y: usize = (digit >> 1) & 1;

//             child_offset_x += digit_x;
//             child_offset_y += digit_y;
//         }

//         defer parent_offset_x = child_offset_x;
//         defer parent_offset_y = child_offset_y;

//         {
//             var digit_idx_adder = 4 * digits_per_color * parent_offset_y % digits.len;
//             digit_idx_adder = (digit_idx_adder * true_parent_square_size) % digits.len;
//             digit_idx = (digit_idx + digit_idx_adder) % digits.len;
//         }

//         const child_indices_modifiers = [_]usize{
//             0,
//             1,
//             @as(usize, 1) << true_child_square_size_bits,
//             (@as(usize, 1) << true_child_square_size_bits) | 1,
//         };

//         const child_indices_adder = (parent_offset_y << (true_child_square_size_bits + 1)) | (parent_offset_x << 1);

//         const child_indices_mask = (@as(usize, 1) << true_child_square_size_bits) - 1;
//         const child_indices_subtractor = (child_offset_y << child_square_size_bits) + child_offset_x;

//         for (0..parent_square_size) |parent_y| {
//             digit_idx = (digit_idx + 4 * digits_per_color * parent_offset_x) % digits.len;

//             for (0..parent_square_size) |parent_x| {
//                 var splitters: [3][4]usize = undefined;

//                 for (0..3) |i| {
//                     for (0..4) |j| {
//                         var splitter_digits: [8]u2 = undefined;
//                         for (&splitter_digits) |*splitter_digit| {
//                             splitter_digit.* = digits[digit_idx];

//                             digit_idx = (digit_idx + 1) % digits.len;
//                         }

//                         splitters[i][j] = splitterFromDigits(splitter_digits);
//                     }
//                 }

//                 var adjusted_child_indices: [4]?usize = undefined;
//                 {
//                     var base_idx = (parent_y << (true_child_square_size_bits + 1)) | ((parent_x) << 1);
//                     base_idx += child_indices_adder;

//                     for (&adjusted_child_indices, &child_indices_modifiers) |*adjusted_child_idx, modifier| {
//                         const temp = base_idx | modifier;
//                         var idx = (temp >> true_child_square_size_bits) << child_square_size_bits;

//                         idx += temp & child_indices_mask;

//                         adjusted_child_idx.* = if (child_indices_subtractor <= idx) idx - child_indices_subtractor else null;
//                     }
//                 }

//                 std.debug.assert(std.mem.indexOfNone(?usize, &adjusted_child_indices, &.{null}) != null);

//                 const adjusted_parent_x = parent_x;
//                 const adjusted_parent_y = parent_y;

//                 const parent_color_idx = adjusted_parent_y * parent_square_size + adjusted_parent_x;

//                 const parent_color = colors[parent_color_idx];

//                 const current_child_colors = splitColor(parent_color, splitters);

//                 for (&current_child_colors, &adjusted_child_indices) |child_color, adjusted_child_idx| {
//                     if (adjusted_child_idx) |idx| {
//                         child_colors[idx] = child_color;
//                     }
//                 }
//             }

//             {
//                 const diff = true_parent_square_size - (parent_offset_x + parent_square_size);
//                 digit_idx = (digit_idx + 4 * digits_per_color * diff) % digits.len;
//             }
//         }

//         {
//             const diff = true_parent_square_size - (parent_offset_y + parent_square_size);
//             var digit_idx_adder = 4 * digits_per_color * diff % digits.len;
//             digit_idx_adder = (digit_idx_adder * true_parent_square_size) % digits.len;
//             digit_idx = (digit_idx + digit_idx_adder) % digits.len;
//         }

//         if (layer > selector_digits.len) {
//             colors = buf1[0..child_colors.len];
//             @memcpy(colors, child_colors);
//         } else {
//             colors[0] = child_colors[0];
//         }
//     }

//     for (0..target_square_size) |y| {
//         if ((y + 1) * target_square_size <= colors.len) {
//             @memcpy(output_colors[y], colors[y * target_square_size .. (y + 1) * target_square_size]);
//         } else {
//             @memset(output_colors[y], .{
//                 .r = 0,
//                 .g = 255,
//                 .b = 255,
//                 .a = 255,
//             });
//         }
//     }
// }

fn fillColorsTerminate1(allocator: std.mem.Allocator, root_color: Color, digits: []const u2, output_colors: []const []Color, selector_digits: []const u2) !void {
    if (digits.len == 0) {
        for (output_colors) |sub_output_colors| {
            @memset(sub_output_colors, root_color);
        }
        return;
    }

    const target_square_size = output_colors.len;
    std.debug.assert(std.math.isPowerOfTwo(target_square_size));

    const digits_per_color = (3 * 8);

    ///////////////////////////////////////////

    var buf1: []Color = try allocator.alloc(Color, target_square_size * target_square_size);
    defer allocator.free(buf1);

    var buf2: []Color = try allocator.alloc(Color, target_square_size * target_square_size);
    defer allocator.free(buf2);

    var colors: []Color = buf1[0..1];
    colors[0] = root_color;

    var digit_idx: usize = 0;

    var layer: usize = 1;

    const layer_max = selector_digits.len + std.math.log2(target_square_size);

    var parent_offset_x = try std.math.big.int.Managed.init(allocator);
    defer parent_offset_x.deinit();
    try parent_offset_x.set(0);

    var parent_offset_y = try std.math.big.int.Managed.init(allocator);
    defer parent_offset_y.deinit();
    try parent_offset_y.set(0);

    var parent_offset_x_modulo: usize = 0;
    var parent_offset_y_modulo: usize = 0;

    while (layer <= layer_max) : (layer += 1) {
        const parent_square_size_bits: std.math.Log2Int(usize) = @intCast((layer - 1) - @min(layer - 1, selector_digits.len));
        const parent_square_size = @as(usize, 1) << parent_square_size_bits;
        const child_square_size_bits = parent_square_size_bits + 1;
        const child_square_size = @as(usize, 1) << child_square_size_bits;

        const true_parent_square_size_bits = layer - 1;

        var true_parent_square_size = try std.math.big.int.Managed.init(allocator);
        defer true_parent_square_size.deinit();
        try true_parent_square_size.set(1);
        try true_parent_square_size.shiftLeft(&true_parent_square_size, true_parent_square_size_bits);

        const true_child_square_size_bits = layer;

        const child_colors = buf2[0 .. child_square_size * child_square_size];

        var child_offset_x = try std.math.big.int.Managed.init(allocator);
        defer {
            var old_parent_offset_x = parent_offset_x;
            parent_offset_x = child_offset_x;
            old_parent_offset_x.deinit();
        }

        var child_offset_y = try std.math.big.int.Managed.init(allocator);
        defer {
            var old_parent_offset_y = parent_offset_y;
            parent_offset_y = child_offset_y;
            old_parent_offset_y.deinit();
        }

        try child_offset_x.shiftLeft(&parent_offset_x, 1);
        try child_offset_y.shiftLeft(&parent_offset_y, 1);

        var child_offset_x_modulo = (parent_offset_x_modulo * 2) % digits.len;
        var child_offset_y_modulo = (parent_offset_y_modulo * 2) % digits.len;
        defer {
            parent_offset_x_modulo = child_offset_x_modulo;
            parent_offset_y_modulo = child_offset_y_modulo;
        }

        if (layer <= selector_digits.len) {
            const digit = selector_digits[layer - 1];
            const digit_x: usize = digit & 1;
            const digit_y: usize = (digit >> 1) & 1;

            try child_offset_x.addScalar(&child_offset_x, digit_x);
            try child_offset_y.addScalar(&child_offset_y, digit_y);

            child_offset_x_modulo = (child_offset_x_modulo + digit_x) % digits.len;
            child_offset_y_modulo = (child_offset_y_modulo + digit_y) % digits.len;
        }

        {
            var digit_idx_adder = (4 * digits_per_color * parent_offset_y_modulo) % digits.len;
            digit_idx_adder = shiftLeftModulo(usize, digit_idx_adder, true_parent_square_size_bits, digits.len);
            digit_idx = (digit_idx + digit_idx_adder) % digits.len;
        }

        var child_indices_modifiers: [4]std.math.big.int.Managed = undefined;
        for (&child_indices_modifiers) |*child_indices_modifier| {
            child_indices_modifier.* = try std.math.big.int.Managed.init(allocator);
        }
        defer for (&child_indices_modifiers) |*child_indices_modifier| {
            // bad practice, change later (possible to call deinit on undefined)
            child_indices_modifier.deinit();
        };

        try child_indices_modifiers[0].set(0);
        try child_indices_modifiers[1].set(1);
        try child_indices_modifiers[2].shiftLeft(&child_indices_modifiers[1], true_child_square_size_bits);
        try child_indices_modifiers[3].bitOr(&child_indices_modifiers[2], &child_indices_modifiers[1]);

        var child_indices_adder = try std.math.big.int.Managed.init(allocator);
        defer child_indices_adder.deinit();
        {
            try child_indices_adder.shiftLeft(&parent_offset_y, true_child_square_size_bits + 1);

            var temp = try std.math.big.int.Managed.init(allocator);
            defer temp.deinit();
            try temp.shiftLeft(&parent_offset_x, 1);

            try child_indices_adder.bitOr(&child_indices_adder, &temp);
        }

        // const child_indices_mask = (@as(usize, 1) << true_child_square_size_bits) - 1;

        var child_indices_mask = try std.math.big.int.Managed.init(allocator);
        defer child_indices_mask.deinit();
        {
            try child_indices_mask.set(1);
            try child_indices_mask.shiftLeft(&child_indices_mask, true_child_square_size_bits);
            try child_indices_mask.saturate(&child_indices_mask, .unsigned, true_child_square_size_bits);

            // try child_indices_mask.set(1);
            // try child_indices_mask.shiftLeft(&child_indices_mask, true_child_square_size_bits);
            // try child_indices_mask.addScalar(&child_indices_mask, -1);
        }

        // const child_indices_subtractor = (child_offset_y << child_square_size_bits) + child_offset_x;

        var child_indices_subtractor = try std.math.big.int.Managed.init(allocator);
        defer child_indices_subtractor.deinit();
        {
            try child_indices_subtractor.shiftLeft(&child_offset_y, child_square_size_bits);
            try child_indices_subtractor.add(&child_indices_subtractor, &child_offset_x);
        }

        const true_parent_square_size_modulo = shiftLeftModulo(usize, 1, true_parent_square_size_bits, digits.len);

        // to be used later --------------
        var child_indices_idx = try std.math.big.int.Managed.init(allocator);
        defer child_indices_idx.deinit();

        var child_indices_temp_or = try std.math.big.int.Managed.init(allocator);
        defer child_indices_temp_or.deinit();

        var child_indices_temp_and = try std.math.big.int.Managed.init(allocator);
        defer child_indices_temp_and.deinit();

        var child_indices_temp_base = try std.math.big.int.Managed.init(allocator);
        defer child_indices_temp_base.deinit();

        var child_indices_base_idx = try std.math.big.int.Managed.init(allocator);
        defer child_indices_base_idx.deinit();

        // -------------------------------

        for (0..parent_square_size) |parent_y| {
            digit_idx = (digit_idx + 4 * digits_per_color * parent_offset_x_modulo) % digits.len;

            for (0..parent_square_size) |parent_x| {
                var splitters: [3][4]usize = undefined;

                var adders: [3]u1 = @splat(0);

                for (0..3) |i| {
                    for (0..4) |j| {
                        var splitter_digits: [8]u2 = undefined;
                        for (&splitter_digits) |*splitter_digit| {
                            splitter_digit.* = digits[digit_idx];

                            adders[i] ^= @intFromBool(digits[digit_idx] == 2);

                            digit_idx = (digit_idx + 1) % digits.len;
                        }

                        splitters[i][j] = splitterFromDigits(splitter_digits);
                    }
                }

                var adjusted_child_indices: [4]?usize = undefined;
                adjusted_child_indices = @splat(0);
                // {
                //     // var base_idx = (parent_y << (true_child_square_size_bits + 1)) | ((parent_x) << 1);
                //     // base_idx += child_indices_adder;

                //     var base_idx = try std.math.big.int.Managed.init(allocator);
                //     defer base_idx.deinit();
                //     {
                //         try base_idx.set(parent_y);
                //         try base_idx.shiftLeft(&base_idx, true_child_square_size_bits + 1);

                //         var temp = try std.math.big.int.Managed.init(allocator);
                //         defer temp.deinit();
                //         try temp.set(parent_x << 1);

                //         try base_idx.bitOr(&base_idx, &temp);

                //         try base_idx.add(&base_idx, &child_indices_adder);
                //     }

                //     for (&adjusted_child_indices, &child_indices_modifiers) |*adjusted_child_idx, *modifier| {
                //         // const temp = base_idx | modifier;

                //         var temp = try std.math.big.int.Managed.init(allocator);
                //         defer temp.deinit();
                //         try temp.bitOr(&base_idx, modifier);

                //         //   var idx = (temp >> true_child_square_size_bits) << child_square_size_bits;

                //         var idx = try std.math.big.int.Managed.init(allocator);
                //         defer idx.deinit();
                //         try idx.shiftRight(&temp, true_child_square_size_bits);
                //         try idx.shiftLeft(&idx, child_square_size_bits);

                //         // idx += temp & child_indices_mask;

                //         var temp_and = try std.math.big.int.Managed.init(allocator);
                //         defer temp_and.deinit();
                //         try temp_and.bitAnd(&temp, &child_indices_mask);

                //         try idx.add(&idx, &temp_and);

                //         // adjusted_child_idx.* = if (child_indices_subtractor <= idx) idx - child_indices_subtractor else null;

                //         const order = child_indices_subtractor.order(idx);
                //         adjusted_child_idx.* = switch (order) {
                //             .lt, .eq => blk: {
                //                 var temp_sub = try std.math.big.int.Managed.init(allocator);
                //                 defer temp_sub.deinit();

                //                 try temp_sub.sub(&idx, &child_indices_subtractor);

                //                 break :blk try temp_sub.to(usize);
                //             },
                //             else => null,
                //         };

                //         // adjusted_child_idx.* = blk: {
                //         //     var temp_sub = try std.math.big.int.Managed.init(allocator);
                //         //     defer temp_sub.deinit();

                //         //     try temp_sub.sub(&idx, &child_indices_subtractor);

                //         //     break :blk (try temp_sub.to(usize)) % child_colors.len;
                //         // };
                //     }
                // }

                {
                    // var base_idx = (parent_y << (true_child_square_size_bits + 1)) | ((parent_x) << 1);
                    // base_idx += child_indices_adder;

                    {
                        try child_indices_base_idx.set(parent_y);
                        try child_indices_base_idx.shiftLeft(&child_indices_base_idx, true_child_square_size_bits + 1);

                        try child_indices_temp_base.set(parent_x << 1);

                        try child_indices_base_idx.bitOr(&child_indices_base_idx, &child_indices_temp_base);

                        try child_indices_base_idx.add(&child_indices_base_idx, &child_indices_adder);
                    }

                    for (&adjusted_child_indices, &child_indices_modifiers) |*adjusted_child_idx, *modifier| {
                        // const temp = base_idx | modifier;

                        try child_indices_temp_or.bitOr(&child_indices_base_idx, modifier);

                        //   var idx = (temp >> true_child_square_size_bits) << child_square_size_bits;

                        try child_indices_idx.shiftRight(&child_indices_temp_or, true_child_square_size_bits);
                        try child_indices_idx.shiftLeft(&child_indices_idx, child_square_size_bits);

                        // idx += temp & child_indices_mask;

                        try child_indices_temp_and.bitAnd(&child_indices_temp_or, &child_indices_mask);

                        try child_indices_idx.add(&child_indices_idx, &child_indices_temp_and);

                        // adjusted_child_idx.* = if (child_indices_subtractor <= idx) idx - child_indices_subtractor else null;

                        const order = child_indices_subtractor.order(child_indices_idx);
                        adjusted_child_idx.* = switch (order) {
                            .lt, .eq => blk: {
                                var temp_sub = try std.math.big.int.Managed.init(allocator);
                                defer temp_sub.deinit();

                                try temp_sub.sub(&child_indices_idx, &child_indices_subtractor);

                                break :blk try temp_sub.to(usize);
                            },
                            else => null,
                        };

                        // adjusted_child_idx.* = blk: {
                        //     var temp_sub = try std.math.big.int.Managed.init(allocator);
                        //     defer temp_sub.deinit();

                        //     try temp_sub.sub(&idx, &child_indices_subtractor);

                        //     break :blk (try temp_sub.to(usize)) % child_colors.len;
                        // };
                    }
                }

                std.debug.assert(std.mem.indexOfNone(?usize, &adjusted_child_indices, &.{null}) != null);

                const parent_color_idx = parent_y * parent_square_size + parent_x;

                var parent_color = colors[parent_color_idx];
                _ = &parent_color;

                // if (parent_color.r < 255) {
                //     parent_color.r += adders[0];
                // }
                // if (parent_color.g < 255) {
                //     parent_color.g += adders[1];
                // }
                // if (parent_color.b < 255) {
                //     parent_color.b += adders[2];
                // }

                const current_child_colors = splitColor(parent_color, splitters);

                for (&current_child_colors, &adjusted_child_indices) |child_color, adjusted_child_idx| {
                    if (adjusted_child_idx) |idx| {
                        child_colors[idx] = child_color;
                    }
                }
            }

            {
                var diff = true_parent_square_size_modulo;
                diff = (diff + digits.len - parent_offset_x_modulo) % digits.len;
                diff = (diff + digits.len - (parent_square_size % digits.len)) % digits.len;

                digit_idx = (digit_idx + 4 * digits_per_color * diff) % digits.len;
            }
        }

        {
            var diff = true_parent_square_size_modulo;
            diff = (diff + digits.len - parent_offset_y_modulo) % digits.len;
            diff = (diff + digits.len - (parent_square_size % digits.len)) % digits.len;

            var digit_idx_adder = (4 * digits_per_color * diff) % digits.len;

            digit_idx_adder = @intCast(std.math.mulWide(usize, digit_idx_adder, true_parent_square_size_modulo) % digits.len);
            digit_idx = (digit_idx + digit_idx_adder) % digits.len;
        }

        if (layer > selector_digits.len) {
            // colors = buf1[0..child_colors.len];
            // @memcpy(colors, child_colors);

            const temp = buf1;
            buf1 = buf2;
            buf2 = temp;

            colors = child_colors;
        } else {
            colors[0] = child_colors[0];
        }
    }

    for (0..target_square_size) |y| {
        if ((y + 1) * target_square_size <= colors.len) {
            @memcpy(output_colors[y], colors[y * target_square_size .. (y + 1) * target_square_size]);
        } else {
            @memset(output_colors[y], .{
                .r = 0,
                .g = 255,
                .b = 255,
                .a = 255,
            });
        }
    }
}

// fn fillColorsTerminateSelfConsuming(allocator: std.mem.Allocator, root_color: Color, digits: []const u2, output_colors: []const []Color, selector_digits: []const u2) !void {
//     if (digits.len == 0) {
//         for (output_colors) |sub_output_colors| {
//             @memset(sub_output_colors, root_color);
//         }
//         return;
//     }

//     const target_square_size = output_colors.len;
//     std.debug.assert(std.math.isPowerOfTwo(target_square_size));

//     const digits_per_color = (3 * 8);

//     ///////////////////////////////////////////

//     const buf1: []Color = try allocator.alloc(Color, target_square_size * target_square_size);
//     defer allocator.free(buf1);

//     const buf2: []Color = try allocator.alloc(Color, target_square_size * target_square_size);
//     defer allocator.free(buf2);

//     var colors: []Color = buf1[0..1];
//     colors[0] = root_color;

//     var digit_idx: usize = 0;

//     var layer: usize = 1;

//     const layer_max = selector_digits.len + std.math.log2(target_square_size);

//     var parent_offset_x: usize = 0;
//     var parent_offset_y: usize = 0;

//     var digit_count = digits.len;

//     while (layer <= layer_max) : (layer += 1) {
//         const parent_square_size_bits: std.math.Log2Int(usize) = @intCast((layer - 1) - @min(layer - 1, selector_digits.len));
//         const parent_square_size = @as(usize, 1) << parent_square_size_bits;
//         const child_square_size_bits = parent_square_size_bits + 1;
//         const child_square_size = @as(usize, 1) << child_square_size_bits;

//         const true_parent_square_size_bits: usize = @intCast(layer - 1);

//         const true_parent_square_size = shiftLeftModulo(usize, 1, true_parent_square_size_bits, digit_count);

//         const child_colors = buf2[0 .. child_square_size * child_square_size];

//         // var child_offset_x: usize = (parent_offset_x * 2) % digit_count;
//         // var child_offset_y: usize = (parent_offset_y * 2) % digit_count;
//         // if (layer <= selector_digits.len) {
//         //     const digit = selector_digits[layer - 1];
//         //     const digit_x: usize = digit & 1;
//         //     const digit_y: usize = (digit >> 1) & 1;

//         //     child_offset_x = (child_offset_x + digit_x) % digit_count;
//         //     child_offset_y = (child_offset_y + digit_y) % digit_count;
//         // }

//         // defer parent_offset_x = child_offset_x;
//         // defer parent_offset_y = child_offset_y;

//         parent_offset_x = 0;
//         parent_offset_y = 0;

//         for (0..layer - 1) |i| {
//             var child_offset_x: usize = (parent_offset_x * 2) % digit_count;
//             var child_offset_y: usize = (parent_offset_y * 2) % digit_count;
//             if (i < selector_digits.len) {
//                 const digit = selector_digits[i];
//                 const digit_x: usize = digit & 1;
//                 const digit_y: usize = (digit >> 1) & 1;

//                 child_offset_x = (child_offset_x + digit_x) % digit_count;
//                 child_offset_y = (child_offset_y + digit_y) % digit_count;
//             }

//             defer parent_offset_x = child_offset_x;
//             defer parent_offset_y = child_offset_y;
//         }

//         {
//             var digit_idx_adder = (4 * digits_per_color * parent_offset_y) % digit_count;
//             digit_idx_adder = shiftLeftModulo(usize, digit_idx_adder, true_parent_square_size_bits, digit_count);
//             digit_idx = (digit_idx + digit_idx_adder) % digit_count;
//         }

//         for (0..parent_square_size) |parent_y| {
//             digit_idx = (digit_idx + 4 * digits_per_color * parent_offset_x) % digit_count;

//             for (0..parent_square_size) |parent_x| {
//                 var splitters: [3][4]usize = undefined;

//                 var adders: [3]u1 = @splat(0);

//                 var subtractors: [3]u1 = @splat(0);

//                 for (0..3) |i| {
//                     for (0..4) |j| {
//                         // std.debug.assert(parent_offset_x == 0);
//                         var splitter_digits_mul: usize = 0;
//                         var splitter_digits: [8]u2 = undefined;
//                         for (&splitter_digits) |*splitter_digit| {
//                             var digit: u2 = undefined;

//                             if (digit_idx < digits.len) {
//                                 digit = digits[digit_idx];
//                             } else if (digit_idx < digits.len + selector_digits.len) {
//                                 const selector_digit_idx = digit_idx - digits.len;
//                                 digit = selector_digits[selector_digit_idx];
//                             } else {
//                                 const virtual_selector_digit_idx = digit_idx - digits.len - selector_digits.len;

//                                 const bit_count = parent_square_size_bits;

//                                 const x_bit: u1 = @truncate((parent_x) >> @intCast(bit_count - 1 - virtual_selector_digit_idx));
//                                 const y_bit: u1 = @truncate((parent_y) >> @intCast(bit_count - 1 - virtual_selector_digit_idx));

//                                 digit = (@as(u2, y_bit) << 1) | @as(u2, x_bit);
//                             }

//                             splitter_digits_mul *= 3;
//                             splitter_digits_mul += digit;

//                             splitter_digit.* = digit & 1;

//                             digit_idx = (digit_idx + 1) % digit_count;
//                         }

//                         for (&splitter_digits, 0..) |*splitter_digit, k| {
//                             const new_splitter_digit: u2 = @truncate(splitter_digits_mul >> @intCast(k * 2));
//                             splitter_digit.* = new_splitter_digit;
//                             adders[i] ^= @intFromBool(new_splitter_digit == 2);
//                             subtractors[i] ^= @intFromBool(new_splitter_digit == 3);
//                         }

//                         splitters[i][j] = splitterFromDigits(splitter_digits);
//                     }
//                 }

//                 var parent_color = colors[parent_y * parent_square_size + parent_x];

//                 if (parent_color.r < 255) {
//                     parent_color.r += adders[0];
//                 }
//                 if (parent_color.g < 255) {
//                     parent_color.g += adders[1];
//                 }
//                 if (parent_color.b < 255) {
//                     parent_color.b += adders[2];
//                 }

//                 if (parent_color.r > 0) {
//                     parent_color.r -= subtractors[0];
//                 }
//                 if (parent_color.g > 0) {
//                     parent_color.g -= subtractors[1];
//                 }
//                 if (parent_color.b > 0) {
//                     parent_color.b -= subtractors[2];
//                 }

//                 const current_child_colors = splitColor(parent_color, splitters);

//                 const child_indices = childIndices(parent_x, parent_y, parent_square_size);

//                 for (&child_indices, &current_child_colors) |child_idx, child_color| {
//                     child_colors[child_idx] = child_color;
//                 }
//             }

//             {
//                 const diff = (digit_count + true_parent_square_size - ((parent_offset_x + parent_square_size) % digit_count)) % digit_count;
//                 digit_idx = (digit_idx + 4 * digits_per_color * diff) % digit_count;
//             }
//         }

//         {
//             var diff = true_parent_square_size;
//             diff = (diff + digit_count - parent_offset_y) % digit_count;
//             diff = (diff + digit_count - (parent_square_size % digit_count)) % digit_count;

//             var digit_idx_adder = (4 * digits_per_color * diff) % digit_count;

//             digit_idx_adder = shiftLeftModulo(usize, digit_idx_adder, true_parent_square_size_bits, digit_count);
//             digit_idx = (digit_idx + digit_idx_adder) % digit_count;
//         }

//         if (layer > selector_digits.len) {
//             colors = buf1[0..child_colors.len];
//             @memcpy(colors, child_colors);
//         } else {
//             colors[0] = child_colors[selector_digits[layer - 1]];
//         }
//         digit_count += 1;
//     }

//     for (0..target_square_size) |y| {
//         @memcpy(output_colors[y], colors[y * target_square_size .. (y + 1) * target_square_size]);
//     }
// }

fn fillColorsTerminateSelfConsuming(allocator: std.mem.Allocator, root_color: Color, digits: []const u2, output_colors: []const []Color, selector_digits: []const u2) !void {
    // if (digits.len == 0) {
    //     for (output_colors) |sub_output_colors| {
    //         @memset(sub_output_colors, root_color);
    //     }
    //     return;
    // }

    const target_square_size = output_colors.len;
    std.debug.assert(std.math.isPowerOfTwo(target_square_size));

    const digits_per_color = (3 * 8);
    _ = digits_per_color; // autofix

    ///////////////////////////////////////////

    const square_size = output_colors.len;
    const square_size_bits = std.math.log2(square_size);
    _ = square_size_bits; // autofix

    const target_size = target_square_size * target_square_size;

    var states_buf_1 = try allocator.alloc(SelfConsumingReaderState, target_size);
    defer allocator.free(states_buf_1);
    var states_buf_2 = try allocator.alloc(SelfConsumingReaderState, target_size);
    defer allocator.free(states_buf_2);

    var colors_buf_1 = try allocator.alloc(Color, target_size);
    defer allocator.free(colors_buf_1);
    var colors_buf_2 = try allocator.alloc(Color, target_size);
    defer allocator.free(colors_buf_2);

    var initial_color = root_color;
    var initial_state = SelfConsumingReaderState.init(digits.len);

    for (selector_digits) |selector_digit| {
        initial_color = initial_state.getChildColors(initial_color, digits, selector_digits, 0, 0, 0)[selector_digit];
        initial_state = initial_state.iterate(selector_digit);
    }

    var states: []SelfConsumingReaderState = states_buf_1[0..1];
    states[0] = initial_state;

    var colors: []Color = colors_buf_1[0..1];
    colors[0] = initial_color;

    var parent_square_size: usize = 1;
    var parent_square_size_bits: usize = 0;

    while (parent_square_size < output_colors.len) {
        const child_square_size = parent_square_size * 2;
        defer parent_square_size = child_square_size;

        const child_colors = colors_buf_2[0 .. child_square_size * child_square_size];
        defer {
            colors = child_colors;
            const temp = colors_buf_1;
            colors_buf_1 = colors_buf_2;
            colors_buf_2 = temp;
        }

        const child_states = states_buf_2[0 .. child_square_size * child_square_size];
        defer {
            states = child_states;
            const temp = states_buf_1;
            states_buf_1 = states_buf_2;
            states_buf_2 = temp;
        }

        for (0..parent_square_size) |parent_y| {
            for (0..parent_square_size) |parent_x| {
                const parent_idx = parent_y * parent_square_size + parent_x;

                const parent_state = states[parent_idx];
                const parent_color = colors[parent_idx];
                const child_indices = childIndices(parent_x, parent_y, parent_square_size);

                // const adjusted_selector_digits = try getCoordinateDigits(allocator, parent_x, parent_y, parent_square_size_bits, selector_digits);

                const current_child_colors = parent_state.getChildColors(parent_color, digits, selector_digits, parent_x, parent_y, parent_square_size_bits);

                for (&child_indices, &current_child_colors, 0..) |child_idx, child_color, i| {
                    const child_state = parent_state.iterate(@intCast(i));

                    child_colors[child_idx] = child_color;
                    child_states[child_idx] = child_state;
                }
            }
        }

        parent_square_size_bits += 1;
    }
    for (0..target_square_size) |y| {
        @memcpy(output_colors[y], colors[y * target_square_size .. (y + 1) * target_square_size]);
    }
}

fn fillColorsTerminateSelfConsumingRecursive(allocator: std.mem.Allocator, root_color: Color, digits: []const u2, output_colors: []const []Color, selector_digits: []const u2) !void {
    // if (digits.len == 0) {
    //     for (output_colors) |sub_output_colors| {
    //         @memset(sub_output_colors, root_color);
    //     }
    //     return;
    // }

    const target_square_size = output_colors.len;
    std.debug.assert(std.math.isPowerOfTwo(target_square_size));

    const digits_per_color = (3 * 8);
    _ = digits_per_color; // autofix

    ///////////////////////////////////////////

    const square_size = output_colors.len;
    const square_size_bits = std.math.log2(square_size);
    _ = square_size_bits; // autofix

    const target_size = target_square_size * target_square_size;

    var states_buf_1 = try allocator.alloc(SelfConsumingReaderState, target_size);
    defer allocator.free(states_buf_1);
    var states_buf_2 = try allocator.alloc(SelfConsumingReaderState, target_size);
    defer allocator.free(states_buf_2);

    var colors_buf_1 = try allocator.alloc(Color, target_size);
    defer allocator.free(colors_buf_1);
    var colors_buf_2 = try allocator.alloc(Color, target_size);
    defer allocator.free(colors_buf_2);

    var initial_color = root_color;
    var initial_state = SelfConsumingReaderState.init(digits.len);

    var num_selected: usize = 0;

    const max_selected = digits.len;

    for (selector_digits) |selector_digit| {
        if (num_selected >= max_selected) {
            break;
        }

        initial_color = initial_state.getChildColors(initial_color, digits, selector_digits, 0, 0, 0)[selector_digit];
        initial_state = initial_state.iterate(selector_digit);
        num_selected += 1;
    }

    var states: []SelfConsumingReaderState = states_buf_1[0..1];
    states[0] = initial_state;

    var colors: []Color = colors_buf_1[0..1];
    colors[0] = initial_color;

    var parent_square_size: usize = 1;
    var parent_square_size_bits: usize = 0;

    while (parent_square_size < output_colors.len) {
        if (num_selected >= max_selected) {
            break;
        }

        const child_square_size = parent_square_size * 2;
        defer parent_square_size = child_square_size;

        const child_colors = colors_buf_2[0 .. child_square_size * child_square_size];
        defer {
            colors = child_colors;
            const temp = colors_buf_1;
            colors_buf_1 = colors_buf_2;
            colors_buf_2 = temp;
        }

        const child_states = states_buf_2[0 .. child_square_size * child_square_size];
        defer {
            states = child_states;
            const temp = states_buf_1;
            states_buf_1 = states_buf_2;
            states_buf_2 = temp;
        }

        for (0..parent_square_size) |parent_y| {
            for (0..parent_square_size) |parent_x| {
                const parent_idx = parent_y * parent_square_size + parent_x;

                const parent_state = states[parent_idx];
                const parent_color = colors[parent_idx];
                const child_indices = childIndices(parent_x, parent_y, parent_square_size);

                // const adjusted_selector_digits = try getCoordinateDigits(allocator, parent_x, parent_y, parent_square_size_bits, selector_digits);

                const current_child_colors = parent_state.getChildColors(parent_color, digits, selector_digits, parent_x, parent_y, parent_square_size_bits);

                for (&child_indices, &current_child_colors, 0..) |child_idx, child_color, i| {
                    const child_state = parent_state.iterate(@intCast(i));

                    child_colors[child_idx] = child_color;
                    child_states[child_idx] = child_state;
                }
            }
        }

        parent_square_size_bits += 1;
        num_selected += 1;
    }

    if (num_selected >= max_selected) {
        const sub_square_size = (output_colors.len / parent_square_size);

        for (0..parent_square_size) |parent_x| {
            for (0..parent_square_size) |parent_y| {
                const new_output_colors = try allocator.alloc([]Color, sub_square_size);
                defer allocator.free(new_output_colors);

                const x = parent_x * sub_square_size;
                const y = parent_y * sub_square_size;

                for (new_output_colors, 0..) |*new_output_color, i| {
                    // const idx = (y + i) * sub_square_size + x;
                    new_output_color.* = output_colors[y + i][x .. x + sub_square_size];
                }

                const adjusted_selector_digits = try getCoordinateDigits(allocator, parent_x, parent_y, parent_square_size_bits, selector_digits);
                const adjusted_selector_digits_trimmed = adjusted_selector_digits[num_selected..];
                try fillColorsRecursive(allocator, colors[parent_y * parent_square_size + parent_x], adjusted_selector_digits_trimmed, new_output_colors, sub_square_size);
            }
        }
    } else {
        for (0..target_square_size) |y| {
            @memcpy(output_colors[y], colors[y * target_square_size .. (y + 1) * target_square_size]);
        }
    }
}

fn fillColorsTerminateSelfConsumingInefficient(allocator: std.mem.Allocator, root_color: Color, digits: []const u2, output_colors: []const []Color, selector_digits: []const u2) !void {
    if (digits.len == 0) {
        for (output_colors) |sub_output_colors| {
            @memset(sub_output_colors, root_color);
        }
        return;
    }

    const target_square_size = output_colors.len;
    std.debug.assert(std.math.isPowerOfTwo(target_square_size));

    const digits_per_color = (3 * 8);
    _ = digits_per_color; // autofix

    ///////////////////////////////////////////

    const square_size = output_colors.len;
    const square_size_bits = std.math.log2(square_size);

    for (0..square_size) |y| {
        for (0..square_size) |x| {
            const updated_selector_digits = try getCoordinateDigits(allocator, x, y, square_size_bits, selector_digits);
            defer allocator.free(updated_selector_digits);

            const initial_res = try fillColorsTerminateSelfConsumingInitial(allocator, root_color, digits, updated_selector_digits);
            output_colors[y][x] = initial_res.color;
        }
    }
}

fn fillColorsTerminateInefficient(allocator: std.mem.Allocator, root_color: Color, digits: []const u2, output_colors: []const []Color, selector_digits: []const u2) !void {
    if (digits.len == 0) {
        for (output_colors) |sub_output_colors| {
            @memset(sub_output_colors, root_color);
        }
        return;
    }

    const target_square_size = output_colors.len;
    std.debug.assert(std.math.isPowerOfTwo(target_square_size));

    const digits_per_color = (3 * 8);
    _ = digits_per_color; // autofix

    ///////////////////////////////////////////

    const square_size = output_colors.len;
    const square_size_bits = std.math.log2(square_size);

    for (0..square_size) |y| {
        for (0..square_size) |x| {
            const updated_selector_digits = try getCoordinateDigits(allocator, x, y, square_size_bits, selector_digits);
            defer allocator.free(updated_selector_digits);

            const initial_res = try fillColorsTerminateInitial(allocator, root_color, digits, updated_selector_digits);
            output_colors[y][x] = initial_res.color;
        }
    }
}

// fn fillColorsTerminate(allocator: std.mem.Allocator, root_color: Color, digits: []const u2, output_colors: []const []Color, selector_digits: []const u2) !void {
//     if (digits.len == 0) {
//         for (output_colors) |sub_output_colors| {
//             @memset(sub_output_colors, root_color);
//         }
//         return;
//     }

//     const target_square_size = output_colors.len;
//     std.debug.assert(std.math.isPowerOfTwo(target_square_size));

//     const digits_per_color = (3 * 8);

//     ///////////////////////////////////////////

//     const buf1: []Color = try allocator.alloc(Color, target_square_size * target_square_size);
//     defer allocator.free(buf1);

//     const buf2: []Color = try allocator.alloc(Color, target_square_size * target_square_size);
//     defer allocator.free(buf2);

//     var colors: []Color = buf1[0..1];
//     colors[0] = root_color;

//     var digit_idx: usize = 0;

//     var layer: usize = 1;

//     const layer_max = selector_digits.len + std.math.log2(target_square_size);

//     var parent_offset_x: usize = 0;
//     var parent_offset_y: usize = 0;

//     while (layer <= layer_max) : (layer += 1) {
//         const parent_square_size_bits: std.math.Log2Int(usize) = @intCast((layer - 1) - @min(layer - 1, selector_digits.len));
//         const parent_square_size = @as(usize, 1) << parent_square_size_bits;
//         const child_square_size_bits = parent_square_size_bits + 1;
//         const child_square_size = @as(usize, 1) << child_square_size_bits;

//         const true_parent_square_size_bits: usize = @intCast(layer - 1);

//         const true_parent_square_size = shiftLeftModulo(usize, 1, true_parent_square_size_bits, digits.len);

//         const child_colors = buf2[0 .. child_square_size * child_square_size];

//         var child_offset_x: usize = (parent_offset_x * 2) % digits.len;
//         var child_offset_y: usize = (parent_offset_y * 2) % digits.len;
//         if (layer <= selector_digits.len) {
//             const digit = selector_digits[layer - 1];
//             const digit_x: usize = digit & 1;
//             const digit_y: usize = (digit >> 1) & 1;

//             child_offset_x = (child_offset_x + digit_x) % digits.len;
//             child_offset_y = (child_offset_y + digit_y) % digits.len;
//         }

//         defer parent_offset_x = child_offset_x;
//         defer parent_offset_y = child_offset_y;

//         {
//             var digit_idx_adder = (4 * digits_per_color * parent_offset_y) % digits.len;
//             // digit_idx_adder = (digit_idx_adder * true_parent_square_size) % digits.len;
//             digit_idx_adder = shiftLeftModulo(usize, digit_idx_adder, true_parent_square_size_bits, digits.len);
//             digit_idx = (digit_idx + digit_idx_adder) % digits.len;
//         }

//         for (0..parent_square_size) |parent_y| {
//             digit_idx = (digit_idx + 4 * digits_per_color * parent_offset_x) % digits.len;

//             for (0..parent_square_size) |parent_x| {
//                 var splitters: [3][4]usize = undefined;

//                 // var adders: [3]u1 = @splat(0);

//                 for (0..3) |i| {
//                     for (0..4) |j| {
//                         var splitter_digits: [8]u2 = undefined;
//                         for (&splitter_digits) |*splitter_digit| {
//                             splitter_digit.* = digits[digit_idx];

//                             // adders[i] ^= @intFromBool(digits[digit_idx] == 2);

//                             digit_idx = (digit_idx + 1) % digits.len;
//                         }

//                         splitters[i][j] = splitterFromDigits(splitter_digits);
//                     }
//                 }

//                 const parent_color = colors[parent_y * parent_square_size + parent_x];

//                 // if (parent_color.r < 255) {
//                 //     parent_color.r += adders[0];
//                 // }
//                 // if (parent_color.g < 255) {
//                 //     parent_color.g += adders[1];
//                 // }
//                 // if (parent_color.b < 255) {
//                 //     parent_color.b += adders[2];
//                 // }

//                 const current_child_colors = splitColor(parent_color, splitters);

//                 const child_indices = childIndices(parent_x, parent_y, parent_square_size);

//                 for (&child_indices, &current_child_colors) |child_idx, child_color| {
//                     child_colors[child_idx] = child_color;
//                 }
//             }

//             {
//                 const diff = (digits.len + true_parent_square_size - ((parent_offset_x + parent_square_size) % digits.len)) % digits.len;
//                 digit_idx = (digit_idx + 4 * digits_per_color * diff) % digits.len;
//             }
//         }

//         {
//             var diff = true_parent_square_size;
//             diff = (diff + digits.len - parent_offset_y) % digits.len;
//             diff = (diff + digits.len - (parent_square_size % digits.len)) % digits.len;

//             var digit_idx_adder = (4 * digits_per_color * diff) % digits.len;

//             // digit_idx_adder = @intCast(std.math.mulWide(usize, digit_idx_adder, true_parent_square_size) % digits.len);
//             digit_idx_adder = shiftLeftModulo(usize, digit_idx_adder, true_parent_square_size_bits, digits.len);
//             digit_idx = (digit_idx + digit_idx_adder) % digits.len;
//         }

//         if (layer > selector_digits.len) {
//             colors = buf1[0..child_colors.len];
//             @memcpy(colors, child_colors);
//         } else {
//             colors[0] = child_colors[selector_digits[layer - 1]];
//         }
//     }

//     for (0..target_square_size) |y| {
//         @memcpy(output_colors[y], colors[y * target_square_size .. (y + 1) * target_square_size]);
//     }
// }

fn fillColorsTerminate(allocator: std.mem.Allocator, root_color: Color, digits: []const u2, output_colors: []const []Color, selector_digits: []const u2) !void {
    if (digits.len == 0) {
        for (output_colors) |sub_output_colors| {
            @memset(sub_output_colors, root_color);
        }
        return;
    }

    const target_square_size = output_colors.len;
    std.debug.assert(std.math.isPowerOfTwo(target_square_size));

    const digits_per_color = (3 * 8);

    ///////////////////////////////////////////

    const buf1: []Color = try allocator.alloc(Color, target_square_size * target_square_size);
    defer allocator.free(buf1);

    const buf2: []Color = try allocator.alloc(Color, target_square_size * target_square_size);
    defer allocator.free(buf2);

    var colors: []Color = buf1[0..1];
    colors[0] = root_color;

    var digit_idx: usize = 0;

    var layer: usize = 1;

    const layer_max = selector_digits.len + std.math.log2(target_square_size);

    var parent_offset_x: usize = 0;
    var parent_offset_y: usize = 0;

    const initial_res = try fillColorsTerminateInitial(allocator, root_color, digits, selector_digits);
    colors[0] = initial_res.color;
    parent_offset_x = initial_res.offset_x;
    parent_offset_y = initial_res.offset_y;
    digit_idx = initial_res.digit_idx;

    layer = selector_digits.len + 1;

    while (layer <= layer_max) : (layer += 1) {
        const parent_square_size_bits: std.math.Log2Int(usize) = @intCast((layer - 1) - @min(layer - 1, selector_digits.len));
        const parent_square_size = @as(usize, 1) << parent_square_size_bits;
        const child_square_size_bits = parent_square_size_bits + 1;
        const child_square_size = @as(usize, 1) << child_square_size_bits;

        const true_parent_square_size_bits: usize = @intCast(layer - 1);

        const true_parent_square_size = shiftLeftModulo(usize, 1, true_parent_square_size_bits, digits.len);

        const child_colors = buf2[0 .. child_square_size * child_square_size];

        const parent_split_colors = try allocator.alloc([4]Color, parent_square_size * parent_square_size);
        defer allocator.free(parent_split_colors);

        var child_offset_x: usize = (parent_offset_x * 2) % digits.len;
        var child_offset_y: usize = (parent_offset_y * 2) % digits.len;
        if (layer <= selector_digits.len) {
            const digit = selector_digits[layer - 1];
            const digit_x: usize = digit & 1;
            const digit_y: usize = (digit >> 1) & 1;

            child_offset_x = (child_offset_x + digit_x) % digits.len;
            child_offset_y = (child_offset_y + digit_y) % digits.len;
        }

        defer parent_offset_x = child_offset_x;
        defer parent_offset_y = child_offset_y;

        {
            var digit_idx_adder = (4 * digits_per_color * parent_offset_y) % digits.len;
            // digit_idx_adder = (digit_idx_adder * true_parent_square_size) % digits.len;
            digit_idx_adder = shiftLeftModulo(usize, digit_idx_adder, true_parent_square_size_bits, digits.len);
            digit_idx = (digit_idx + digit_idx_adder) % digits.len;
        }

        for (0..parent_square_size) |parent_y| {
            digit_idx = (digit_idx + 4 * digits_per_color * parent_offset_x) % digits.len;

            for (0..parent_square_size) |parent_x| {
                var splitters: [3][4]usize = undefined;

                // var adders: [3]u1 = @splat(0);

                for (0..3) |i| {
                    for (0..4) |j| {
                        var splitter_digits: [8]u2 = undefined;
                        for (&splitter_digits) |*splitter_digit| {
                            splitter_digit.* = digits[digit_idx];

                            // adders[i] ^= @intFromBool(digits[digit_idx] == 2);

                            digit_idx = (digit_idx + 1) % digits.len;
                        }

                        splitters[i][j] = splitterFromDigits(splitter_digits);
                    }
                }

                const parent_color = colors[parent_y * parent_square_size + parent_x];

                // if (parent_color.r < 255) {
                //     parent_color.r += adders[0];
                // }
                // if (parent_color.g < 255) {
                //     parent_color.g += adders[1];
                // }
                // if (parent_color.b < 255) {
                //     parent_color.b += adders[2];
                // }

                parent_split_colors[parent_y * parent_square_size + parent_x] = splitColor(parent_color, splitters);
            }

            {
                const diff = (digits.len + true_parent_square_size - ((parent_offset_x + parent_square_size) % digits.len)) % digits.len;
                digit_idx = (digit_idx + 4 * digits_per_color * diff) % digits.len;
            }
        }

        // for (0..child_square_size) |child_y| {
        //     for (0..child_square_size) |child_x| {
        //         const parent_x = child_x / 2;
        //         const parent_y = child_y / 2;
        //         const parent_idx = parent_y * parent_square_size + parent_x;

        //         // const parent_idx = ((child_y >> 1) << (child_square_size_bits - 1)) | (child_x >> 1); ((child_y << child_square_size_bits) | child_x) >> 1

        //         const child_sub_idx = ((child_y & 1) << 1) | (child_x & 1);
        //         child_colors[child_y * child_square_size + child_x] = parent_split_colors[parent_idx][child_sub_idx];
        //     }
        // }

        for (0..child_square_size * child_square_size) |child_idx| {
            const child_sub_idx = (((child_idx >> (child_square_size_bits - 1)) & 0b10)) | (child_idx & 1);

            const child_square_size_mask = (@as(usize, 1) << child_square_size_bits) - 1;

            const parent_idx = (((child_idx >> (child_square_size_bits + 1))) << (child_square_size_bits - 1)) |
                ((child_idx & child_square_size_mask) >> 1);

            child_colors[child_idx] = parent_split_colors[parent_idx][child_sub_idx];
        }

        {
            var diff = true_parent_square_size;
            diff = (diff + digits.len - parent_offset_y) % digits.len;
            diff = (diff + digits.len - (parent_square_size % digits.len)) % digits.len;

            var digit_idx_adder = (4 * digits_per_color * diff) % digits.len;

            // digit_idx_adder = @intCast(std.math.mulWide(usize, digit_idx_adder, true_parent_square_size) % digits.len);
            digit_idx_adder = shiftLeftModulo(usize, digit_idx_adder, true_parent_square_size_bits, digits.len);
            digit_idx = (digit_idx + digit_idx_adder) % digits.len;
        }

        if (layer > selector_digits.len) {
            colors = buf1[0..child_colors.len];
            @memcpy(colors, child_colors);
        } else {
            colors[0] = child_colors[selector_digits[layer - 1]];
        }
    }

    for (0..target_square_size) |y| {
        @memcpy(output_colors[y], colors[y * target_square_size .. (y + 1) * target_square_size]);
    }
}

const FillColorsTerminateInitialRes = struct {
    color: Color,
    offset_x: usize,
    offset_y: usize,
    digit_idx: usize,
};

fn fillColorsTerminateInitial(allocator: std.mem.Allocator, root_color: Color, digits: []const u2, selector_digits: []const u2) !FillColorsTerminateInitialRes {
    _ = allocator; // autofix
    if (digits.len == 0 or selector_digits.len == 0) {
        return .{
            .color = root_color,
            .offset_x = 0,
            .offset_y = 0,
            .digit_idx = 0,
        };
    }

    const digits_per_color = (3 * 8);

    var parent_color = root_color;

    var digit_idx: usize = 0;

    var layer: usize = 1;

    const layer_max = selector_digits.len;

    var parent_offset_x: usize = 0;
    var parent_offset_y: usize = 0;

    while (layer <= layer_max) : (layer += 1) {
        const true_parent_square_size_bits: usize = @intCast(layer - 1);

        const true_parent_square_size = shiftLeftModulo(usize, 1, true_parent_square_size_bits, digits.len);

        const selector_digit = selector_digits[layer - 1];

        var child_offset_x: usize = (parent_offset_x * 2) % digits.len;
        var child_offset_y: usize = (parent_offset_y * 2) % digits.len;
        if (layer <= selector_digits.len) {
            const digit = selector_digits[layer - 1];
            const digit_x: usize = digit & 1;
            const digit_y: usize = (digit >> 1) & 1;

            child_offset_x = (child_offset_x + digit_x) % digits.len;
            child_offset_y = (child_offset_y + digit_y) % digits.len;
        }

        defer parent_offset_x = child_offset_x;
        defer parent_offset_y = child_offset_y;

        {
            var digit_idx_adder = (4 * digits_per_color * parent_offset_y) % digits.len;
            digit_idx_adder = shiftLeftModulo(usize, digit_idx_adder, true_parent_square_size_bits, digits.len);
            digit_idx = (digit_idx + digit_idx_adder) % digits.len;
        }

        digit_idx = (digit_idx + 4 * digits_per_color * parent_offset_x) % digits.len;

        {
            var splitters: [3][4]usize = undefined;

            // var adders: [3]u1 = @splat(0);

            for (0..3) |i| {
                for (0..4) |j| {
                    var splitter_digits: [8]u2 = undefined;
                    for (&splitter_digits) |*splitter_digit| {
                        splitter_digit.* = digits[digit_idx];

                        // adders[i] ^= @intFromBool(digits[digit_idx] == 2);

                        digit_idx = (digit_idx + 1) % digits.len;
                    }

                    splitters[i][j] = splitterFromDigits(splitter_digits);
                }
            }

            // if (parent_color.r < 255) {
            //     parent_color.r += adders[0];
            // }
            // if (parent_color.g < 255) {
            //     parent_color.g += adders[1];
            // }
            // if (parent_color.b < 255) {
            //     parent_color.b += adders[2];
            // }

            const current_child_colors = splitColor(parent_color, splitters);

            parent_color = current_child_colors[selector_digit];
        }

        {
            const diff = (digits.len + true_parent_square_size - ((parent_offset_x + 1) % digits.len)) % digits.len;
            digit_idx = (digit_idx + 4 * digits_per_color * diff) % digits.len;
        }

        {
            var diff = true_parent_square_size;
            diff = (diff + digits.len - parent_offset_y) % digits.len;
            diff = (diff + digits.len - 1) % digits.len;

            var digit_idx_adder = (4 * digits_per_color * diff) % digits.len;

            // digit_idx_adder = @intCast(std.math.mulWide(usize, digit_idx_adder, true_parent_square_size) % digits.len);
            digit_idx_adder = shiftLeftModulo(usize, digit_idx_adder, true_parent_square_size_bits, digits.len);
            digit_idx = (digit_idx + digit_idx_adder) % digits.len;
        }
    }

    return .{
        .color = parent_color,
        .offset_x = parent_offset_x,
        .offset_y = parent_offset_y,
        .digit_idx = digit_idx,
    };
}

const FillColorsTerminateSelfConsumingInitialRes = struct {
    color: Color,
};

fn fillColorsTerminateSelfConsumingInitial(allocator: std.mem.Allocator, root_color: Color, digits: []const u2, selector_digits: []const u2) !FillColorsTerminateSelfConsumingInitialRes {
    _ = allocator; // autofix
    if (digits.len == 0 or selector_digits.len == 0) {
        return .{
            .color = root_color,
        };
    }

    var parent_color = root_color;

    var state = SelfConsumingReaderState.init(digits.len);

    for (selector_digits) |selector_digit| {
        parent_color = state.getChildColors(parent_color, digits, selector_digits)[selector_digit];
        state = state.iterate(selector_digit);
    }

    return .{
        .color = parent_color,
    };
}

const SelfConsumingReaderState = struct {
    position: usize,
    offset: usize,
    offset_pow: usize,
    layer: usize,
    digit_count: usize,

    const digits_per_color = (3 * 8);

    pub fn init(digit_count: usize) SelfConsumingReaderState {
        return .{
            .position = 0,
            .offset = 0,
            .offset_pow = 1,
            .layer = 1,
            .digit_count = digit_count,
        };
    }

    pub fn iterate(this: SelfConsumingReaderState, selector_digit: u2) SelfConsumingReaderState {
        if (this.digit_count == 0) {
            var new = this;
            new.digit_count = 1;
            return new;
        }

        var next: SelfConsumingReaderState = undefined;

        const modulo = ((this.digit_count + (digits_per_color * 4) - 1) / (digits_per_color * 4));

        const square_size = (@as(usize, 1) << @intCast(this.layer));

        {
            var position_x = this.position % (square_size / 2);
            var position_y = this.position / (square_size / 2);
            position_x *= 2;
            position_x += selector_digit & 1;
            position_y *= 2;
            position_y += selector_digit >> 1;

            next.position = (position_y * square_size + position_x) % modulo;

            // var prng = std.Random.DefaultPrng.init(next.position);
            // const random = prng.random();
            // next.position = random.intRangeLessThan(usize, 0, modulo);
        }

        const next_offset = this.offset + this.offset_pow;
        if (next_offset >= modulo) {
            next.layer = 1;
            next.offset = 0;
            next.offset_pow = 1;
        } else {
            next.layer = this.layer + 1;
            next.offset = next_offset;
            next.offset_pow = this.offset_pow * 4;
        }
        next.digit_count = this.digit_count + 1;

        return next;
    }

    pub fn getChildColors(this: SelfConsumingReaderState, parent_color: Color, digits: []const u2, selector_digits: []const u2, parent_x: usize, parent_y: usize, parent_square_size_bits: usize) [4]Color {
        if (this.digit_count == 0) {
            const default: [4]Color = @splat(parent_color);
            return default;
        }

        var digit_idx = ((this.position + this.offset) * digits_per_color * 4) % this.digit_count;

        {
            var splitters: [3][4]usize = undefined;

            var adders: [3]u1 = @splat(0);
            var subtractors: [3]u1 = @splat(0);

            for (0..3) |i| {
                for (0..4) |j| {
                    var splitter_digits: [8]u2 = undefined;
                    for (&splitter_digits) |*splitter_digit| {
                        var digit: u2 = undefined;

                        // if (digit_idx < digits.len) {
                        //     digit = digits[digit_idx];
                        // } else {
                        //     const selector_digit_idx = digit_idx - digits.len;
                        //     digit = selector_digits[selector_digit_idx];
                        // }

                        if (digit_idx < digits.len) {
                            digit = digits[digit_idx];
                        } else if (digit_idx < digits.len + selector_digits.len) {
                            const selector_digit_idx = digit_idx - digits.len;
                            digit = selector_digits[selector_digit_idx];
                        } else {
                            const virtual_selector_digit_idx = digit_idx - digits.len - selector_digits.len;

                            const bit_count = parent_square_size_bits;

                            const x_bit: u1 = @truncate((parent_x) >> @intCast(bit_count - 1 - virtual_selector_digit_idx));
                            const y_bit: u1 = @truncate((parent_y) >> @intCast(bit_count - 1 - virtual_selector_digit_idx));

                            digit = (@as(u2, y_bit) << 1) | @as(u2, x_bit);
                            // var buf: [1000]u8 = undefined;
                            // var fba = std.heap.FixedBufferAllocator.init(&buf);

                            // const virtual_digits = getCoordinateDigits(fba.allocator(), parent_x, parent_y, parent_square_size_bits, &.{}) catch unreachable;
                            // digit = virtual_digits[virtual_selector_digit_idx];
                        }

                        adders[i] ^= @intFromBool(digit == 2);
                        subtractors[i] ^= @intFromBool(digit == 3);

                        splitter_digit.* = digit;

                        // adders[i] ^= @intFromBool(digits[digit_idx] == 2);

                        digit_idx = (digit_idx + 1) % this.digit_count;
                    }

                    splitters[i][j] = splitterFromDigits(splitter_digits);
                }
            }

            // var seed: u64 = 0;
            // for (0..3) |i| {
            //     for (0..4) |j| {
            //         seed ^= splitters[i][j] << @intCast(j * 2);
            //     }
            // }
            // var prng = std.Random.DefaultPrng.init(seed);
            // const random = prng.random();
            // for (0..3) |i| {
            //     for (0..4) |j| {
            //         splitters[i][j] = random.int(u8);
            //     }
            // }

            ///////////////////////////////////////////

            // for (0..3) |i| {
            //     for (0..4) |j| {
            //         // std.debug.assert(parent_offset_x == 0);
            //         var splitter_digits_mul: usize = 0;
            //         var splitter_digits: [8]u2 = undefined;
            //         for (&splitter_digits) |*splitter_digit| {
            //             var digit: u2 = undefined;

            //             if (digit_idx < digits.len) {
            //                 digit = digits[digit_idx];
            //             } else if (digit_idx < digits.len + selector_digits.len) {
            //                 const selector_digit_idx = digit_idx - digits.len;
            //                 digit = selector_digits[selector_digit_idx];
            //             } else {
            //                 const virtual_selector_digit_idx = digit_idx - digits.len - selector_digits.len;

            //                 const bit_count = parent_square_size_bits;

            //                 const x_bit: u1 = @truncate((parent_x) >> @intCast(bit_count - 1 - virtual_selector_digit_idx));
            //                 const y_bit: u1 = @truncate((parent_y) >> @intCast(bit_count - 1 - virtual_selector_digit_idx));

            //                 digit = (@as(u2, y_bit) << 1) | @as(u2, x_bit);
            //             }

            //             splitter_digits_mul *= 3;
            //             splitter_digits_mul += digit;

            //             splitter_digit.* = digit & 1;

            //             digit_idx = (digit_idx + 1) % this.digit_count;
            //         }

            //         for (&splitter_digits, 0..) |*splitter_digit, k| {
            //             const new_splitter_digit: u2 = @truncate(splitter_digits_mul >> @intCast(k * 2));
            //             splitter_digit.* = new_splitter_digit;
            //             adders[i] ^= @intFromBool(new_splitter_digit == 2);
            //             subtractors[i] ^= @intFromBool(new_splitter_digit == 3);
            //         }

            //         splitters[i][j] = splitterFromDigits(splitter_digits);
            //     }
            // }

            var parent_color_adjusted = parent_color;

            if (parent_color_adjusted.r < 255) {
                parent_color_adjusted.r += adders[0];
            }
            if (parent_color_adjusted.g < 255) {
                parent_color_adjusted.g += adders[1];
            }
            if (parent_color_adjusted.b < 255) {
                parent_color_adjusted.b += adders[2];
            }

            if (parent_color_adjusted.r > 0) {
                parent_color_adjusted.r -= subtractors[0];
            }
            if (parent_color_adjusted.g > 0) {
                parent_color_adjusted.g -= subtractors[1];
            }
            if (parent_color_adjusted.b > 0) {
                parent_color_adjusted.b -= subtractors[2];
            }

            // if (parent_color_adjusted.r == 0) {
            //     parent_color_adjusted.r += adders[0];
            // }
            // if (parent_color_adjusted.g == 0) {
            //     parent_color_adjusted.g += adders[1];
            // }
            // if (parent_color_adjusted.b == 0) {
            //     parent_color_adjusted.b += adders[2];
            // }

            // if (parent_color_adjusted.r == 255) {
            //     parent_color_adjusted.r -= subtractors[0];
            // }
            // if (parent_color_adjusted.g == 255) {
            //     parent_color_adjusted.g -= subtractors[1];
            // }
            // if (parent_color_adjusted.b == 255) {
            //     parent_color_adjusted.b -= subtractors[2];
            // }

            return splitColor(parent_color_adjusted, splitters);
        }
    }

    // pub fn getChildColors(this: SelfConsumingReaderState, parent_color: Color, digits: []const u2, selector_digits: []const u2, parent_x: usize, parent_y: usize, parent_square_size_bits: usize) [4]Color {
    //     if (digits.len == 0) {
    //         const default: [4]Color = @splat(parent_color);
    //         return default;
    //     }

    //     var digit_idx = ((this.position + this.offset) * digits_per_color * 4) % this.digit_count;

    //     {
    //         var splitters: [3][4]usize = undefined;

    //         for (0..3) |i| {
    //             for (0..4) |j| {
    //                 var splitter_digits: [8]u2 = undefined;
    //                 for (&splitter_digits) |*splitter_digit| {
    //                     var digit: u2 = undefined;

    //                     if (digit_idx < digits.len) {
    //                         digit = digits[digit_idx];
    //                     } else if (digit_idx < digits.len + selector_digits.len) {
    //                         const selector_digit_idx = digit_idx - digits.len;
    //                         digit = selector_digits[selector_digit_idx];
    //                     } else {
    //                         const virtual_selector_digit_idx = digit_idx - digits.len - selector_digits.len;

    //                         const bit_count = parent_square_size_bits;

    //                         const x_bit: u1 = @truncate((parent_x) >> @intCast(bit_count - 1 - virtual_selector_digit_idx));
    //                         const y_bit: u1 = @truncate((parent_y) >> @intCast(bit_count - 1 - virtual_selector_digit_idx));

    //                         digit = (@as(u2, y_bit) << 1) | @as(u2, x_bit);
    //                     }

    //                     splitter_digit.* = digit;

    //                     digit_idx = (digit_idx + 1) % this.digit_count;
    //                 }

    //                 splitters[i][j] = splitterFromDigits(splitter_digits);
    //             }
    //         }

    //         return splitColor(parent_color, splitters);
    //     }
    // }
};

fn getChildColorsSelfConsuming(allocator: std.mem.Allocator, parent_color: Color, digit_count: usize, reader_position: usize, reader_layer: usize, digits: []const u2, selector_digits: []const u2) ![4]Color {
    _ = allocator; // autofix
    if (digits.len == 0 or selector_digits.len == 0) {
        const default: [4]Color = @splat(parent_color);
        return default;
    }

    const digits_per_color = (3 * 8);

    var reader_offset: usize = 0;
    {
        var pow: usize = 1;

        for (reader_layer - 1) |_| {
            reader_offset = (reader_offset + pow);
            pow = (pow * 4);
        }
    }

    const reader_modulo = ((digit_count + (digits_per_color * 4) - 1) / (digits_per_color * 4));

    if (reader_offset >= reader_modulo) {
        reader_offset = 0;
    }

    var digit_idx = ((reader_position + reader_offset) * digits_per_color * 4) % digit_count;

    {
        var splitters: [3][4]usize = undefined;

        // var adders: [3]u1 = @splat(0);

        for (0..3) |i| {
            for (0..4) |j| {
                var splitter_digits: [8]u2 = undefined;
                for (&splitter_digits) |*splitter_digit| {
                    var digit: u2 = undefined;

                    if (digit_idx < digits.len) {
                        digit = digits[digit_idx];
                    } else {
                        const selector_digit_idx = digit_idx - digits.len;
                        digit = selector_digits[selector_digit_idx];
                    }
                    splitter_digit.* = digit;

                    // adders[i] ^= @intFromBool(digits[digit_idx] == 2);

                    digit_idx = (digit_idx + 1) % digit_count;
                }

                splitters[i][j] = splitterFromDigits(splitter_digits);
            }
        }

        // if (parent_color.r < 255) {
        //     parent_color.r += adders[0];
        // }
        // if (parent_color.g < 255) {
        //     parent_color.g += adders[1];
        // }
        // if (parent_color.b < 255) {
        //     parent_color.b += adders[2];
        // }

        return splitColor(parent_color, splitters);
    }
}

pub fn incrementDigitsX(digits: []u2) void {
    var i: usize = digits.len - 1;
    while (true) {
        if (digits[i] & 0b01 == 0b01) {
            digits[i] &= 0b10;
        } else {
            digits[i] |= 0b01;
            break;
        }

        i -= 1;
    }
}

pub fn incrementDigitsY(digits: []u2) void {
    var i: usize = digits.len - 1;
    while (true) {
        if (digits[i] & 0b10 == 0b10) {
            digits[i] &= 0b01;
        } else {
            digits[i] |= 0b10;
            break;
        }

        i -= 1;
    }
}

pub fn decrementDigitsX(digits: []u2) void {
    var i: usize = digits.len - 1;
    while (true) {
        if (digits[i] & 0b01 == 0b00) {
            digits[i] |= 0b01;
        } else {
            digits[i] &= 0b10;
            break;
        }

        i -= 1;
    }
}

pub fn decrementDigitsY(digits: []u2) void {
    var i: usize = digits.len - 1;
    while (true) {
        if (digits[i] & 0b10 == 0b00) {
            digits[i] |= 0b10;
        } else {
            digits[i] &= 0b01;
            break;
        }

        i -= 1;
    }
}

pub fn fillColorsAtLocation(allocator: std.mem.Allocator, buffer: []Color, root_color: Color, digits: []const u2, output_colors: []Color, target_square_size: usize) !void {
    std.debug.assert(std.math.isPowerOfTwo(target_square_size));

    if (digits.len == 0) {
        @memset(output_colors, root_color);
        return;
    }

    // var encoded_digits = getSelfTerminatingDigits(digits) orelse {
    //     @memset(output_colors, root_color);
    //     return;
    // };

    var encoded_digits = digits;

    var encoded_length = encoded_digits.len;

    if (encoded_length < 1) {
        @memset(output_colors, root_color);
        return;
    }

    encoded_digits.len = encoded_digits.len;
    encoded_length = encoded_digits.len;

    var selector_digits = getNonSelfTerminatingDigits(digits);

    // const target_bit_count = std.math.log2(target_square_size);

    const digits_per_color = (3 * 8);
    _ = digits_per_color; // autofix

    ///////////////////////////////////////////

    const buf1: []Color = buffer[0 .. target_square_size * target_square_size];

    const buf2 = buffer[target_square_size * target_square_size ..];

    var initial_parent_color = root_color;
    initial_parent_color = initial_parent_color;
    // for (selector_digits, 0..) |selector_digit, k| {
    //     var splitters: [3][4]usize = undefined;
    //     var digit_idx = encodedIdxFromDigits(encoded_digits.len, selector_digits[0 .. k + 1]);

    //     for (0..3) |i| {
    //         for (0..4) |j| {
    //             var splitter_digits: [8]u2 = undefined;
    //             for (&splitter_digits) |*splitter_digit| {
    //                 splitter_digit.* = encoded_digits[digit_idx];

    //                 digit_idx = (digit_idx + 1) % encoded_digits.len;
    //             }

    //             splitters[i][j] = splitterFromDigits(splitter_digits);
    //         }
    //     }

    //     const current_child_colors = splitColor(initial_parent_color, splitters);
    //     initial_parent_color = current_child_colors[selector_digit];
    // }

    var colors: []Color = buf1[0..1];
    colors[0] = initial_parent_color;

    var digit_idx: usize = 0;

    var parent_square_size: usize = 1;

    var layer: usize = 0;

    while (std.math.sqrt(colors.len) < target_square_size) : (layer += 1) {
        const child_square_size = parent_square_size * 2;

        const child_colors = buf2[0 .. child_square_size * child_square_size];

        for (0..parent_square_size) |parent_y| {
            for (0..parent_square_size) |parent_x| {
                const parent_color = colors[parent_y * parent_square_size + parent_x];

                const child_indices = childIndices(parent_x, parent_y, parent_square_size);
                var splitters: [3][4]usize = undefined;

                const coord_digits = try getCoordinateDigits(allocator, parent_x, parent_y, layer + 1, digits);
                defer allocator.free(coord_digits);

                encoded_digits = getSelfTerminatingDigits(coord_digits) orelse {
                    for (&child_indices) |child_idx| {
                        child_colors[child_idx] = parent_color;
                    }
                    continue;
                };

                selector_digits = getNonSelfTerminatingDigits(coord_digits);
                if (selector_digits.len == 0) {
                    for (&child_indices) |child_idx| {
                        child_colors[child_idx] = parent_color;
                    }
                    continue;
                }

                // digit_idx = encodedIdxFromCoordinates(encoded_digits.len, parent_x, parent_y, layer);
                digit_idx = encodedIdxFromDigits(encoded_digits.len, selector_digits);

                for (0..3) |i| {
                    for (0..4) |j| {
                        var splitter_digits: [8]u2 = undefined;
                        for (&splitter_digits) |*splitter_digit| {
                            splitter_digit.* = encoded_digits[digit_idx];

                            digit_idx = (digit_idx + 1) % encoded_digits.len;
                        }

                        splitters[i][j] = splitterFromDigits(splitter_digits);

                        // splitters[i][j] = splitterFromDigits(this.digits[digit_idx..][0..4].*);
                        // digit_idx += 4;
                    }
                }

                const current_child_colors = splitColor(parent_color, splitters);

                for (&current_child_colors, &child_indices) |child_color, child_idx| {
                    child_colors[child_idx] = child_color;
                }
            }
        }

        colors = buf1[0..child_colors.len];
        @memcpy(colors, child_colors);

        parent_square_size = child_square_size;
    }

    @memcpy(output_colors, colors);
}

fn getPixelColorDigits(allocator: std.mem.Allocator, digits: []const u2) !Color {
    if (digits.len == 0) {
        return magic_color;
    }

    // var encoded_length: usize = 0;
    // while (encoded_length < digits.len and digits[encoded_length] == 3) {
    //     encoded_length += 1;
    // }

    // var encoded_true_length: usize = 0;
    // while (encoded_length < digits.len and digits[encoded_length] != 3) {
    //     encoded_true_length += 1;
    //     encoded_length += 1;
    // }

    // // const encoded_length = std.mem.indexOfAny(u2, digits, &.{3}) orelse return magic_color;
    // if (encoded_length >= digits.len - 1) {
    //     return magic_color;
    // }

    const encoded_digits = getSelfTerminatingDigits(digits) orelse return magic_color;

    const encoded_length = encoded_digits.len;

    if (encoded_length < 1) {
        return try getPixelColorDigits(allocator, digits[1..]);
    }

    const selector_digits = getNonSelfTerminatingDigits(digits);

    // if (encoded_true_length < 1) {
    //     return try getPixelColorDigits(allocator, digits[encoded_length..]);
    // }

    var encoded_idx: usize = 0;

    const digits_per_color = (9 * 10) + 3;

    for (selector_digits[0 .. selector_digits.len - 1]) |digit| {
        encoded_idx = (encoded_idx * digits_per_color) % encoded_length;
        encoded_idx = (encoded_idx + digit) % encoded_length;
    }
    encoded_idx = (encoded_idx * digits_per_color) % encoded_length;

    // if (digits.len - encoded_length > 3) {
    for (digits.len - encoded_length - 2) |_| {
        encoded_idx = (encoded_idx * digits_per_color) % encoded_length;
    }
    // }

    // var splits: [9]u10 = undefined;
    // for (&splits) |*split| {
    //     for (0..5) |i| {
    //         split.* |= @as(u10, digits[encoded_idx]) << @intCast(i * 2);
    //         encoded_idx = (encoded_idx + 1) % encoded_length;
    //     }
    // }

    var splits: [9]u10 = undefined;
    for (&splits) |*split| {
        split.* = 0;

        // for (0..7) |i| {
        //     _ = i; // autofix

        //     split.* *%= 3;
        //     split.* +%= @as(u10, digits[encoded_idx]);

        //     // split.* |= @as(u10, digits[encoded_idx] & 1) << @intCast(i);
        //     encoded_idx = (encoded_idx + 1) % encoded_length;
        // }

        for (0..10) |i| {
            split.* |= @as(u10, digits[encoded_idx] & 1) << @intCast(i);
            encoded_idx = (encoded_idx + 1) % encoded_length;
        }

        // var prng = std.Random.DefaultPrng.init(split.*);
        // const random = prng.random();
        // split.* = random.int(u10);
    }

    var add_extras: [3]u1 = undefined;
    var sub_extras: [3]u1 = undefined;

    for (&add_extras, &sub_extras) |*add_extra, *sub_extra| {
        if (digits[encoded_idx] == 0) {
            add_extra.* = 1;
            sub_extra.* = 0;
        } else if (digits[encoded_idx] != 0) {
            add_extra.* = 0;
            sub_extra.* = 1;
        }
        encoded_idx = (encoded_idx + 1) % encoded_length;
    }

    const parent_color = try getPixelColorDigits(allocator, digits[0 .. digits.len - 1]);

    const r_splits = splits[0..3];
    const g_splits = splits[3..6];
    const b_splits = splits[6..9];

    var r_total = @as(u10, parent_color.r) * 4;

    // if (r_total == 0) {
    //     r_total += 1;
    // }
    // if (r_total == 255 * 4) {
    //     r_total -= 1;
    // }
    if (r_total < 255 * 4) {
        r_total += add_extras[1];
    }
    if (r_total > 0) {
        r_total -= sub_extras[0];
    }

    var g_total = @as(u10, parent_color.g) * 4;

    // if (g_total == 0) {
    //     g_total += 1;
    // }
    // if (g_total == 255 * 4) {
    //     g_total -= 1;
    // }
    if (g_total < 255 * 4) {
        g_total += add_extras[1];
    }
    if (g_total > 0) {
        g_total -= sub_extras[1];
    }

    var b_total = @as(u10, parent_color.b) * 4;

    // if (b_total == 0) {
    //     b_total += 1;
    // }
    // if (b_total == 255 * 4) {
    //     b_total -= 1;
    // }
    if (b_total < 255 * 4) {
        b_total += add_extras[2];
    }
    if (b_total > 0) {
        b_total -= sub_extras[2];
    }

    for (r_splits) |*split| {
        split.* = (split.*) % (r_total + 1);
    }

    for (g_splits) |*split| {
        split.* = (split.*) % (g_total + 1);
    }

    for (b_splits) |*split| {
        split.* = (split.*) % (b_total + 1);
    }

    std.mem.sort(u10, r_splits, {}, std.sort.asc(u10));
    std.mem.sort(u10, g_splits, {}, std.sort.asc(u10));
    std.mem.sort(u10, b_splits, {}, std.sort.asc(u10));

    var r_values: [4]u8 = undefined;
    r_values[0] = @intCast(std.math.clamp(r_splits[0], 0, 255));
    r_values[1] = @intCast(std.math.clamp(r_splits[1] - r_splits[0], 0, 255));
    r_values[2] = @intCast(std.math.clamp(r_splits[2] - r_splits[1], 0, 255));
    r_values[3] = @intCast(std.math.clamp(r_total - r_splits[2], 0, 255));

    var g_values: [4]u8 = undefined;
    g_values[0] = @intCast(std.math.clamp(g_splits[0], 0, 255));
    g_values[1] = @intCast(std.math.clamp(g_splits[1] - g_splits[0], 0, 255));
    g_values[2] = @intCast(std.math.clamp(g_splits[2] - g_splits[1], 0, 255));
    g_values[3] = @intCast(std.math.clamp(g_total - g_splits[2], 0, 255));

    var b_values: [4]u8 = undefined;
    b_values[0] = @intCast(std.math.clamp(b_splits[0], 0, 255));
    b_values[1] = @intCast(std.math.clamp(b_splits[1] - b_splits[0], 0, 255));
    b_values[2] = @intCast(std.math.clamp(b_splits[2] - b_splits[1], 0, 255));
    b_values[3] = @intCast(std.math.clamp(b_total - b_splits[2], 0, 255));

    {
        var current_r_total: u10 = 0;
        for (r_values) |value| {
            current_r_total += value;
        }
        var i: usize = 0;

        while (current_r_total < r_total) {
            const additional_r = 255 - r_values[i];
            r_values[i] += additional_r;
            current_r_total += additional_r;
            i = (i + 1) % 4;
        }
    }

    {
        var current_g_total: u10 = 0;
        for (g_values) |value| {
            current_g_total += value;
        }
        var i: usize = 1;
        while (current_g_total < g_total) {
            const additional_g = 255 - g_values[i];
            g_values[i] += additional_g;
            current_g_total += additional_g;
            i = (i + 1) % 4;
        }
    }

    {
        var current_b_total: u10 = 0;
        for (b_values) |value| {
            current_b_total += value;
        }
        var i: usize = 2;
        while (current_b_total < b_total) {
            const additional_b = 255 - b_values[i];
            b_values[i] += additional_b;
            current_b_total += additional_b;
            i = (i + 1) % 4;
        }
    }

    const last_digit = digits[digits.len - 1];

    return .{
        .r = r_values[last_digit],
        .g = g_values[last_digit],
        .b = b_values[last_digit],
        .a = 255,
    };
}

fn testPanic() noreturn {
    @panic("");
}

fn colorDiff(a: Color, b: Color) usize {
    var diff: usize = 0;
    const Signed = std.meta.Int(.signed, 16);
    diff += @abs(@as(Signed, a.r) - @as(Signed, b.r));
    diff += @abs(@as(Signed, a.g) - @as(Signed, b.g));
    diff += @abs(@as(Signed, a.b) - @as(Signed, b.b));
    return diff;
}

fn averageColors(colors: []const Color) Color {
    var res_r: usize = 0;
    var res_g: usize = 0;
    var res_b: usize = 0;

    for (colors) |color| {
        res_r += color.r;
        res_g += color.g;
        res_b += color.b;
    }

    res_r /= colors.len;
    res_g /= colors.len;
    res_b /= colors.len;

    return .{
        .r = @intCast(res_r),
        .g = @intCast(res_g),
        .b = @intCast(res_b),
        .a = 255,
    };
}

fn encodeColorsAsDigits(allocator: std.mem.Allocator, colors: []const Color) ![]u2 {
    var temp = colors.len;
    var digit_count: usize = 0;
    while (temp > 0) : (temp /= 4) {
        digit_count += temp * 24;
    }

    const digits = try allocator.alloc(u2, digit_count);

    temp = colors.len;

    var i: usize = digits.len;

    var sub_colors = try allocator.alloc(Color, colors.len);
    defer allocator.free(sub_colors);
    @memcpy(sub_colors, colors);

    while (temp > 0) : (temp /= 4) {
        const sub_digit_count = temp * 24;

        // std.debug.print("{} {}\n", .{ i, sub_digit_count });

        for (sub_colors, 0..) |sub_color, j| {
            for (i - sub_digit_count + j * 24..i - sub_digit_count + (j + 1) * 24, 0..) |k, shift| {
                const color_int: u32 = @bitCast(sub_color);
                digits[k] = @intCast((color_int >> @intCast(shift)) & 1);
            }
        }

        i -= sub_digit_count;

        if (i > 0) {
            const new_sub_colors = try allocator.alloc(Color, temp / 4);
            for (new_sub_colors, 0..) |*sub_color, j| {
                sub_color.* = averageColors(sub_colors[j * 4 .. ((j + 1) * 4)]);
            }
            allocator.free(sub_colors);
            sub_colors = new_sub_colors;
        }
    }

    return digits;
}

// test "pixels" {
//     const allocator = std.testing.allocator;

//     const width: usize = 512;
//     const height: usize = 512;

//     const x: usize = 0b001110111;
//     _ = x; // autofix
//     const y: usize = 0b101010011;
//     _ = y; // autofix

//     // const color = try getPixelColor(allocator, x, y, width, height);

//     // const digits = ([_]u2{ 0, 1, 1, 1, 0, 0, 0, 1, 1, 0, 0, 1 } ** 10) ++
//     //     [_]u2{2} ++
//     //     [_]u2{3};

//     var digits = try encodeColorsAsDigits(allocator, &.{
//         .{
//             .r = 123,
//             .g = 43,
//             .b = 42,
//             .a = 255,
//         },
//         .{
//             .r = 23,
//             .g = 143,
//             .b = 42,
//             .a = 255,
//         },
//         .{
//             .r = 0,
//             .g = 43,
//             .b = 0,
//             .a = 255,
//         },
//         .{
//             .r = 123,
//             .g = 255,
//             .b = 255,
//             .a = 255,
//         },
//     });
//     defer allocator.free(digits);

//     const prev_digit_len = digits.len;

//     digits = try allocator.realloc(digits, digits.len + 3);

//     digits[prev_digit_len] = 2;
//     digits[prev_digit_len + 1] = 2;
//     digits[prev_digit_len + 2] = 2;
//     // digits[prev_digit_len + 1] = 3;

//     const color = try getPixelColorDigits(allocator, digits, width, height);

//     std.debug.print("digits: {any}\n", .{digits});

//     std.debug.print("color: {}\n", .{color});
// }
