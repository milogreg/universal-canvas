const std = @import("std");
const render = @import("render.zig");

const Color = render.Color;

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

// pub const Encoding = struct {
//     root_color: Color,
//     digits: []u2,

//     const digits_per_color = 9 * 5;

//     pub fn init(allocator: std.mem.Allocator, colors: []const Color) !Encoding {
//         const square_size = std.math.sqrt(colors.len);
//         const chunk_count = std.math.log2(square_size) + 1;

//         const chunks = try allocator.alloc([]const Color, chunk_count);
//         defer allocator.free(chunks);
//         defer {
//             // bad practice, remove later
//             for (chunks) |chunk| {
//                 if (chunk.len != colors.len) {
//                     allocator.free(chunk);
//                 }
//             }
//         }

//         chunks[0] = colors;
//         for (chunks[1..], 0..) |*chunk, i| {
//             const prev_chunk = chunks[i];
//             chunk.* = try averageColors(allocator, prev_chunk);
//         }

//         std.mem.reverse([]const Color, chunks);

//         var digit_count: usize = 0;
//         for (chunks[1..]) |chunk| {
//             digit_count += chunk.len * digits_per_color;
//         }

//         const digits = try allocator.alloc(u2, digit_count);
//         var digit_idx: usize = 0;
//         for (chunks[1..], 0..) |chunk, i| {
//             const prev_chunk = chunks[i];
//             const parent_square_size = std.math.sqrt(prev_chunk.len);
//             const child_square_size = parent_square_size * 2;
//             _ = child_square_size; // autofix
//             for (0..parent_square_size) |parent_y| {
//                 for (0..parent_square_size) |parent_x| {
//                     const child_indices = childIndices(parent_x, parent_y, parent_square_size);

//                     var child_colors: [4]Color = undefined;
//                     for (&child_colors, child_indices) |*child_color, child_idx| {
//                         child_color.* = chunk[child_idx];
//                     }

//                     const splitters = getSplitters(prev_chunk[parent_y * parent_square_size + parent_x], child_colors);

//                     var splitter_digits: [9 * 5]u2 = undefined;

//                     for (splitters, 0..) |color_splitters, j| {
//                         for (color_splitters, 0..) |splitter, k| {
//                             const current_splitter_digits = digitsFromSplitter(splitter);
//                             splitter_digits[(j * 3 + k) * 5 ..][0..5].* = current_splitter_digits;
//                         }
//                     }

//                     digits[digit_idx..][0..splitter_digits.len].* = splitter_digits;
//                     digit_idx += splitter_digits.len;
//                 }
//             }
//         }

//         return .{
//             .root_color = chunks[0][0],
//             .digits = digits,
//         };
//     }

//     pub fn deinit(this: *Encoding, allocator: std.mem.Allocator) void {
//         allocator.free(this.digits);
//     }

//     pub fn decode(this: Encoding, allocator: std.mem.Allocator, target_square_size: usize) ![]Color {
//         var colors = try allocator.alloc(Color, 1);
//         colors[0] = this.root_color;

//         var digit_idx: usize = 0;
//         while (std.math.sqrt(colors.len) < target_square_size) {
//             const parent_square_size = std.math.sqrt(colors.len);
//             const child_square_size = parent_square_size * 2;

//             const child_colors = try allocator.alloc(Color, child_square_size * child_square_size);

//             for (0..parent_square_size) |parent_y| {
//                 for (0..parent_square_size) |parent_x| {
//                     const child_indices = childIndices(parent_x, parent_y, parent_square_size);
//                     var splitters: [3][3]usize = undefined;
//                     for (0..3) |i| {
//                         for (0..3) |j| {
//                             var splitter_digits: [5]u2 = undefined;
//                             for (&splitter_digits) |*splitter_digit| {
//                                 splitter_digit.* = this.digits[digit_idx];

//                                 digit_idx = (digit_idx + 1) % this.digits.len;
//                             }

//                             splitters[i][j] = splitterFromDigits(splitter_digits);

//                             // splitters[i][j] = splitterFromDigits(this.digits[digit_idx..][0..5].*);
//                             // digit_idx += 5;
//                         }
//                     }

//                     const parent_color = colors[parent_y * parent_square_size + parent_x];
//                     const current_child_colors = splitColor(parent_color, splitters);

//                     for (&current_child_colors, &child_indices) |child_color, child_idx| {
//                         child_colors[child_idx] = child_color;
//                     }
//                 }
//             }

//             const old_colors = colors;
//             colors = child_colors;
//             allocator.free(old_colors);
//         }

//         return colors;
//     }

//     fn averageColors(allocator: std.mem.Allocator, colors: []const Color) ![]Color {
//         const averaged = try allocator.alloc(Color, colors.len / 4);

//         const initial_square_size = std.math.sqrt(colors.len);
//         const final_square_size = initial_square_size / 2;

//         for (0..final_square_size) |averaged_y| {
//             for (0..final_square_size) |averaged_x| {
//                 const initial_indices = childIndices(averaged_x, averaged_y, final_square_size);

//                 var average: SumColor = SumColor.fromColor(colors[initial_indices[0]]);
//                 for (initial_indices[1..]) |idx| {
//                     average = average.add(SumColor.fromColor(colors[idx]));
//                 }
//                 average = average.divide(4);

//                 // const average = SumColor.fromColor(colors[averaged_y * 2 * initial_square_size + averaged_x * 2])
//                 //     .add(SumColor.fromColor(colors[averaged_y * 2 * initial_square_size + averaged_x * 2 + 1]))
//                 //     .add(SumColor.fromColor(colors[(averaged_y * 2 + 1) * initial_square_size + averaged_x * 2]))
//                 //     .add(SumColor.fromColor(colors[(averaged_y * 2 + 1) * initial_square_size + averaged_x * 2 + 1]))
//                 //     .divide(4)
//                 //     .toColor();

//                 averaged[averaged_y * final_square_size + averaged_x] = average.toColor();
//             }
//         }

//         return averaged;
//     }

//     fn childIndices(parent_x: usize, parent_y: usize, parent_square_size: usize) [4]usize {
//         const child_square_size = parent_square_size * 2;

//         return .{
//             parent_y * 2 * child_square_size + parent_x * 2,
//             parent_y * 2 * child_square_size + parent_x * 2 + 1,
//             (parent_y * 2 + 1) * child_square_size + parent_x * 2,
//             (parent_y * 2 + 1) * child_square_size + parent_x * 2 + 1,
//         };
//     }

//     fn getSplitters(parent_color: Color, child_colors: [4]Color) [3][3]usize {
//         const parent_totals = SumColor.fromColor(parent_color).multiply(4);
//         _ = parent_totals; // autofix

//         const r_splitters = [_]usize{
//             @as(usize, child_colors[0].r),
//             @as(usize, child_colors[0].r) + @as(usize, child_colors[1].r),
//             @as(usize, child_colors[0].r) + @as(usize, child_colors[1].r) + @as(usize, child_colors[2].r),
//         };

//         const g_splitters = [_]usize{
//             @as(usize, child_colors[0].g),
//             @as(usize, child_colors[0].g) + @as(usize, child_colors[1].g),
//             @as(usize, child_colors[0].g) + @as(usize, child_colors[1].g) + @as(usize, child_colors[2].g),
//         };

//         const b_splitters = [_]usize{
//             @as(usize, child_colors[0].b),
//             @as(usize, child_colors[0].b) + @as(usize, child_colors[1].b),
//             @as(usize, child_colors[0].b) + @as(usize, child_colors[1].b) + @as(usize, child_colors[2].b),
//         };

//         return .{ r_splitters, g_splitters, b_splitters };
//     }

//     fn digitsFromSplitter(splitter: usize) [5]u2 {
//         var digits: [5]u2 = undefined;
//         for (&digits, 1..) |*digit, i| {
//             digit.* = @truncate(splitter >> @intCast((digits.len - i) * 2));
//         }
//         return digits;
//     }

//     fn splitterFromDigits(digits: [5]u2) usize {
//         var splitter: usize = 0;
//         for (&digits, 1..) |digit, i| {
//             splitter |= @as(usize, digit) << @intCast((digits.len - i) * 2);
//         }
//         return splitter;
//     }

//     fn splitColor(color: Color, splitters: [3][3]usize) [4]Color {
//         const parent_totals = SumColor.fromColor(color).multiply(4);

//         var r_splitters = splitters[0];
//         var g_splitters = splitters[1];
//         var b_splitters = splitters[2];

//         for (&r_splitters) |*split| {
//             split.* = (split.*) % (parent_totals.r + 1);
//         }
//         for (&g_splitters) |*split| {
//             split.* = (split.*) % (parent_totals.g + 1);
//         }
//         for (&b_splitters) |*split| {
//             split.* = (split.*) % (parent_totals.b + 1);
//         }

//         std.mem.sort(usize, &r_splitters, {}, std.sort.asc(usize));
//         std.mem.sort(usize, &g_splitters, {}, std.sort.asc(usize));
//         std.mem.sort(usize, &b_splitters, {}, std.sort.asc(usize));

//         var r_values: [4]u8 = undefined;
//         r_values[0] = @intCast(std.math.clamp(r_splitters[0], 0, 255));
//         r_values[1] = @intCast(std.math.clamp(r_splitters[1] - r_splitters[0], 0, 255));
//         r_values[2] = @intCast(std.math.clamp(r_splitters[2] - r_splitters[1], 0, 255));
//         r_values[3] = @intCast(std.math.clamp(parent_totals.r - r_splitters[2], 0, 255));

//         var g_values: [4]u8 = undefined;
//         g_values[0] = @intCast(std.math.clamp(g_splitters[0], 0, 255));
//         g_values[1] = @intCast(std.math.clamp(g_splitters[1] - g_splitters[0], 0, 255));
//         g_values[2] = @intCast(std.math.clamp(g_splitters[2] - g_splitters[1], 0, 255));
//         g_values[3] = @intCast(std.math.clamp(parent_totals.g - g_splitters[2], 0, 255));

//         var b_values: [4]u8 = undefined;
//         b_values[0] = @intCast(std.math.clamp(b_splitters[0], 0, 255));
//         b_values[1] = @intCast(std.math.clamp(b_splitters[1] - b_splitters[0], 0, 255));
//         b_values[2] = @intCast(std.math.clamp(b_splitters[2] - b_splitters[1], 0, 255));
//         b_values[3] = @intCast(std.math.clamp(parent_totals.b - b_splitters[2], 0, 255));

//         {
//             var current_r_total: usize = 0;
//             for (r_values) |value| {
//                 current_r_total += value;
//             }
//             var i: usize = 0;

//             while (current_r_total < parent_totals.r) {
//                 if (r_values[i] < 255) {
//                     r_values[i] += 1;
//                     current_r_total += 1;
//                 }
//                 i = (i + 1) % 4;
//             }
//         }

//         {
//             var current_g_total: usize = 0;
//             for (g_values) |value| {
//                 current_g_total += value;
//             }
//             var i: usize = 1;

//             while (current_g_total < parent_totals.g) {
//                 if (g_values[i] < 255) {
//                     g_values[i] += 1;
//                     current_g_total += 1;
//                 }
//                 i = (i + 1) % 4;
//             }
//         }

//         {
//             var current_b_total: usize = 0;
//             for (b_values) |value| {
//                 current_b_total += value;
//             }
//             var i: usize = 2;

//             while (current_b_total < parent_totals.b) {
//                 if (b_values[i] < 255) {
//                     b_values[i] += 1;
//                     current_b_total += 1;
//                 }
//                 i = (i + 1) % 4;
//             }
//         }

//         var child_colors: [4]Color = undefined;
//         for (&child_colors, &r_values, &g_values, &b_values) |*child_color, r, g, b| {
//             child_color.* = .{
//                 .r = r,
//                 .g = g,
//                 .b = b,
//                 .a = 255,
//             };
//         }

//         return child_colors;
//     }
// };

pub const Encoding = struct {
    root_color: Color,
    digits: []u2,

    const digits_per_color = (3 * 8);

    pub fn init(allocator: std.mem.Allocator, colors: []const Color) !Encoding {
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

        chunks[0] = colors;
        for (chunks[1..], 0..) |*chunk, i| {
            const prev_chunk = chunks[i];
            chunk.* = try averageColors(allocator, prev_chunk);
        }

        std.mem.reverse([]const Color, chunks);

        var digit_count: usize = 0;
        for (chunks[1..]) |chunk| {
            digit_count += chunk.len * digits_per_color;
        }

        const digits = try allocator.alloc(u2, digit_count);
        @memset(digits, 3);

        var digit_idx: usize = 0;
        for (chunks[1..], 0..) |chunk, i| {
            const prev_chunk = chunks[i];
            const parent_square_size = std.math.sqrt(prev_chunk.len);
            const child_square_size = parent_square_size * 2;
            _ = child_square_size; // autofix
            for (0..parent_square_size) |parent_y| {
                for (0..parent_square_size) |parent_x| {
                    const child_indices = childIndices(parent_x, parent_y, parent_square_size);

                    var child_colors: [4]Color = undefined;
                    for (&child_colors, &child_indices) |*child_color, child_idx| {
                        child_color.* = chunk[child_idx];
                    }

                    const splitters = getSplitters(prev_chunk[parent_y * parent_square_size + parent_x], child_colors);

                    var splitter_digits: [(3 * 4) * 8]u2 = undefined;

                    for (splitters, 0..) |color_splitters, j| {
                        for (color_splitters, 0..) |splitter, k| {
                            const current_splitter_digits = digitsFromSplitter(splitter);

                            splitter_digits[(j * 4 + k) * 8 ..][0..8].* = current_splitter_digits;
                        }
                    }

                    // for (splitters, 0..) |color_splitters, j| {
                    //     for (color_splitters, 0..) |splitter, k| {
                    //         const current_splitter_digits = digitsFromSplitter(splitter);

                    //         // for (current_splitter_digits, 0..) |splitter_digit, l| {
                    //         //     splitter_digits[(k * 3 + j) + 8 * l] = splitter_digit;
                    //         // }
                    //         for (current_splitter_digits, 0..) |splitter_digit, l| {
                    //             splitter_digits[(j * 4 + k) + 8 * l] = splitter_digit;
                    //         }
                    //     }
                    // }

                    // std.mem.reverse(u2, &splitter_digits);

                    // for (&child_indices, 0..) |child_idx, j| {
                    //     digits[digit_idx + child_idx * digits_per_color ..][0..digits_per_color].* = splitter_digits[j * digits_per_color ..][0..digits_per_color].*;
                    // }

                    digits[digit_idx..][0..splitter_digits.len].* = splitter_digits;
                    digit_idx += splitter_digits.len;
                }
            }

            // digit_idx += chunk.len * digits_per_color;
        }

        std.debug.assert(digit_count == digit_idx);

        return .{
            .root_color = chunks[0][0],
            .digits = digits,
        };
    }

    pub fn deinit(this: *Encoding, allocator: std.mem.Allocator) void {
        allocator.free(this.digits);
    }

    pub fn decode(this: Encoding, allocator: std.mem.Allocator, target_square_size: usize) ![]Color {
        var colors = try allocator.alloc(Color, 1);
        colors[0] = this.root_color;

        var digit_idx: usize = 0;
        while (std.math.sqrt(colors.len) < target_square_size) {
            const parent_square_size = std.math.sqrt(colors.len);
            const child_square_size = parent_square_size * 2;

            const child_colors = try allocator.alloc(Color, child_square_size * child_square_size);

            for (0..parent_square_size) |parent_y| {
                for (0..parent_square_size) |parent_x| {
                    const child_indices = childIndices(parent_x, parent_y, parent_square_size);
                    var splitters: [3][4]usize = undefined;
                    for (0..3) |i| {
                        for (0..4) |j| {
                            var splitter_digits: [8]u2 = undefined;
                            for (&splitter_digits) |*splitter_digit| {
                                splitter_digit.* = this.digits[digit_idx];

                                digit_idx = (digit_idx + 1) % this.digits.len;
                            }

                            splitters[i][j] = splitterFromDigits(splitter_digits);

                            // splitters[i][j] = splitterFromDigits(this.digits[digit_idx..][0..4].*);
                            // digit_idx += 4;
                        }
                    }

                    const parent_color = colors[parent_y * parent_square_size + parent_x];
                    const current_child_colors = splitColor(parent_color, splitters);

                    for (&current_child_colors, &child_indices) |child_color, child_idx| {
                        child_colors[child_idx] = child_color;
                    }
                }
            }

            const old_colors = colors;
            colors = child_colors;
            allocator.free(old_colors);
        }

        return colors;
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
                average = average.divide(4);

                // const average = SumColor.fromColor(colors[averaged_y * 2 * initial_square_size + averaged_x * 2])
                //     .add(SumColor.fromColor(colors[averaged_y * 2 * initial_square_size + averaged_x * 2 + 1]))
                //     .add(SumColor.fromColor(colors[(averaged_y * 2 + 1) * initial_square_size + averaged_x * 2]))
                //     .add(SumColor.fromColor(colors[(averaged_y * 2 + 1) * initial_square_size + averaged_x * 2 + 1]))
                //     .divide(4)
                //     .toColor();

                averaged[averaged_y * final_square_size + averaged_x] = average.toColor();
            }
        }

        return averaged;
    }

    fn childIndices(parent_x: usize, parent_y: usize, parent_square_size: usize) [4]usize {
        const child_square_size = parent_square_size * 2;

        return .{
            parent_y * 2 * child_square_size + parent_x * 2,
            parent_y * 2 * child_square_size + parent_x * 2 + 1,
            (parent_y * 2 + 1) * child_square_size + parent_x * 2,
            (parent_y * 2 + 1) * child_square_size + parent_x * 2 + 1,
        };
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

    fn getSplitters(parent_color: Color, child_colors: [4]Color) [3][4]usize {
        var splitter_colors = child_colors;

        var splitter_average = SumColor.fromColor(splitter_colors[0]);
        splitter_average = splitter_average.add(SumColor.fromColor(splitter_colors[1]));
        splitter_average = splitter_average.add(SumColor.fromColor(splitter_colors[2]));
        splitter_average = splitter_average.add(SumColor.fromColor(splitter_colors[3]));
        splitter_average = splitter_average.divide(4);

        const scales: [3]usize = .{
            if (splitter_average.r != 0)
                (@as(usize, parent_color.r) * 256) / splitter_average.r
            else
                (if (parent_color.r == 0) 256 else 0),

            if (splitter_average.g != 0)
                (@as(usize, parent_color.g) * 256) / splitter_average.g
            else
                (if (parent_color.g == 0) 256 else 0),

            if (splitter_average.b != 0)
                (@as(usize, parent_color.b) * 256) / splitter_average.b
            else
                (if (parent_color.b == 0) 256 else 0),
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

        var res_splitters: [3][4]usize = undefined;

        for (&res_colors, 0..) |res_color, i| {
            res_splitters[0][i] = res_color.r;
            res_splitters[1][i] = res_color.g;
            res_splitters[2][i] = res_color.b;
        }

        // const target_total = SumColor.fromColor(parent_color).multiply(4);
        // var current_total = SumColor.fromColor(res_colors[0]);
        // for (res_colors[1..]) |child_color| {
        //     current_total = current_total.add(SumColor.fromColor(child_color));
        // }

        // {
        //     var i: usize = 0;
        //     while (current_total.r < target_total.r) : (i = (i + 1) % 4) {
        //         if (res_splitters[0][i] < 255) {
        //             res_splitters[0][i] += 1;
        //             current_total.r += 1;
        //         }
        //     }
        // }

        // {
        //     var i: usize = 0;
        //     while (current_total.g < target_total.g) : (i = (i + 1) % 4) {
        //         if (res_splitters[1][i] < 255) {
        //             res_splitters[1][i] += 1;
        //             current_total.g += 1;
        //         }
        //     }
        // }

        // {
        //     var i: usize = 0;
        //     while (current_total.b < target_total.b) : (i = (i + 1) % 4) {
        //         if (res_splitters[2][i] < 255) {
        //             res_splitters[2][i] += 1;
        //             current_total.b += 1;
        //         }
        //     }
        // }

        return res_splitters;
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
};

test "Encoding init and deinit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // const colors = &[_]Color{
    //     Color{ .r = 10, .g = 20, .b = 30, .a = 255 },
    //     Color{ .r = 50, .g = 60, .b = 70, .a = 255 },
    //     Color{ .r = 90, .g = 100, .b = 110, .a = 255 },
    //     Color{ .r = 130, .g = 140, .b = 150, .a = 255 },
    // };

    const square_size = 64;

    var max_diff: u8 = 0;

    for (0..1) |i| {
        const colors = try allocator.alloc(Color, square_size * square_size);
        defer allocator.free(colors);
        var prng = std.Random.DefaultPrng.init(i);
        const random = prng.random();
        _ = random; // autofix

        for (colors, 0..) |*color, j| {
            _ = j; // autofix
            // color.* = .{
            //     .r = random.int(u8),
            //     .g = random.int(u8),
            //     .b = random.int(u8),
            //     .a = 255,
            // };

            const x = i % square_size;
            const y = i / square_size;

            const radius = square_size / 2;
            const center_x = square_size / 2;
            const center_y = square_size / 2;

            const dx = @as(isize, @intCast(x)) - @as(isize, @intCast(center_x));
            const dy = @as(isize, @intCast(y)) - @as(isize, @intCast(center_y));
            const distance_squared = dx * dx + dy * dy;

            color.* = .{
                .r = if (distance_squared <= radius * radius) 0 else 255,
                // .r = if (((y) & 1) == 0) 127 else 255,
                // .r = if (y >= square_size / 4) 0 else 255,
                .g = 0,
                .b = 0,
                .a = 255,
            };
        }

        var encoding = try Encoding.init(allocator, colors);
        defer encoding.deinit(allocator);

        const decoded_colors = try encoding.decode(allocator, std.math.sqrt(colors.len));
        defer allocator.free(decoded_colors);

        for (decoded_colors, colors) |decoded, original| {
            const orig_max = max_diff;
            _ = orig_max; // autofix

            if (decoded.r > original.r) {
                max_diff = @max(max_diff, decoded.r - original.r);
            } else {
                max_diff = @max(max_diff, original.r - decoded.r);
            }

            if (decoded.g > original.g) {
                max_diff = @max(max_diff, decoded.g - original.g);
            } else {
                max_diff = @max(max_diff, original.g - decoded.g);
            }

            if (decoded.b > original.b) {
                max_diff = @max(max_diff, decoded.b - original.b);
            } else {
                max_diff = @max(max_diff, original.b - decoded.b);
            }

            if (decoded != original) {
                std.debug.print("{d:3} {d:3}\n", .{ decoded.r, original.r });
                std.debug.print("{d:3} {d:3}\n", .{ decoded.g, original.g });
                std.debug.print("{d:3} {d:3}\n", .{ decoded.b, original.b });
                std.debug.print("\n", .{});
            }
        }

        // std.debug.print("{any}\n", .{decoded_colors});

        // std.debug.print("{}\n", .{encoding});

        const concat_digits = try allocator.alloc(u2, encoding.digits.len + 1);
        defer allocator.free(concat_digits);
        @memcpy(concat_digits[0..encoding.digits.len], encoding.digits);
        concat_digits[concat_digits.len - 1] = 3;

        //   var junk: usize = 0;

        // const test_colors = try render.refineColorWithDigits(allocator, @bitCast(encoding.root_color), &junk, concat_digits);

        // std.debug.print("{any}\n", .{test_colors});
    }

    std.debug.print("max_diff: {}\n", .{max_diff});
}
