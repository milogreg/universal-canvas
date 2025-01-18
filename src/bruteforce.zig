const std = @import("std");
const render = @import("render.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var prng = std.Random.DefaultPrng.init(123);
    const random = prng.random();

    const remaining_colors_map = try allocator.alloc(bool, 1 << 24);
    defer allocator.free(remaining_colors_map);

    const remaining_colors = try allocator.alloc(u24, 1 << 24);
    defer allocator.free(remaining_colors);

    @memset(remaining_colors_map, true);

    // @memset(remaining_colors_map[100..], false);

    // random.shuffle(bool, remaining_colors_map);

    const next_remaining_colors_map = try allocator.alloc(bool, 1 << 24);
    defer allocator.free(next_remaining_colors_map);

    const next_remaining_colors = try allocator.alloc(u24, 1 << 24);
    defer allocator.free(next_remaining_colors);

    var possible_splitters = std.ArrayList([10]u8).init(allocator);
    defer possible_splitters.deinit();

    var splitters: [10]u8 = undefined;

    // var max_count: usize = 0;

    // for (0..1 << 24) |i| {
    //     remaining_colors[i] = @intCast(i);
    // }
    // random.shuffle(u24, remaining_colors);

    // for (0..100000000000) |i| {
    //     _ = i; // autofix
    //     fillSplitters(&splitters, random);

    //     // std.mem.writeInt(u80, &splitters, i, .little);

    //     const target_color: [3]u8 = @splat(128);
    //     _ = target_color; // autofix

    //     // splitters[6..9].* = target_color;

    //     // splitters = render.splitterApplyColorSaltInverse(splitters, target_color);

    //     var count: usize = 0;

    //     for (remaining_colors[0..100]) |color_int| {
    //         var color: [3]u8 = undefined;
    //         std.mem.writeInt(u24, &color, @intCast(color_int), .little);

    //         // if (@as(u24, @bitCast(render.splitColor(color, splitters)[2])) == @as(u24, @bitCast(target_color))) {
    //         //     // std.debug.print("{any:<3}\n", .{splitters});
    //         //     // try possible_splitters.append(splitters);

    //         //     count += 1;
    //         // }

    //         const new_color_int = @as(u24, @bitCast(render.splitColor(color, splitters)[2]));
    //         const old_dist = distFromCenter(&.{@intCast(color_int)});

    //         const new_dist = distFromCenter(&.{new_color_int});

    //         if (new_dist <= old_dist) {
    //             count += 1;
    //         } else {
    //             break;
    //         }

    //         // if (@as(u24, @bitCast(render.splitColor(color, splitters)[2])) >= color_int) {
    //         //     // std.debug.print("{any:<3}\n", .{splitters});
    //         //     // try possible_splitters.append(splitters);

    //         //     count += 1;
    //         // } else {
    //         //     // break;
    //         // }
    //     }

    //     if (count > max_count) {
    //         std.debug.print("count: {}\n", .{count});
    //         max_count = count;

    //         var full_count: usize = 0;

    //         for (remaining_colors[0..100]) |color_int| {
    //             var color: [3]u8 = undefined;
    //             std.mem.writeInt(u24, &color, @intCast(color_int), .little);

    //             const new_color_int = @as(u24, @bitCast(render.splitColor(color, splitters)[2]));
    //             const old_dist = distFromCenter(&.{@intCast(color_int)});

    //             const new_dist = distFromCenter(&.{new_color_int});

    //             if (new_dist <= old_dist) {
    //                 full_count += 1;
    //             }
    //         }
    //         std.debug.print("full_count: {}\n", .{full_count});
    //     }
    // }

    //    std.debug.print("len: {}\n", .{possible_splitters.items.len});

    // if (true) return;

    var total: usize = 0;

    var num_iters: usize = 0;

    {
        for (remaining_colors_map, 0..) |has_color, i| {
            if (has_color) {
                remaining_colors[total] = @intCast(i);
                total += 1;
            }
        }

        @memset(next_remaining_colors_map, false);
    }

    var result_splitters = std.ArrayList([10]u8).init(allocator);
    defer result_splitters.deinit();

    var current_digit: u2 = 2;

    while (total > 1) {
        random.shuffle(u24, remaining_colors[0..total]);

        if (total < 10) {
            for (remaining_colors[0..total]) |color_int| {
                var color: [3]u8 = undefined;
                std.mem.writeInt(u24, &color, color_int, .little);
                std.debug.print("{any}\n", .{color});
            }
        }

        var count: usize = 0;

        fillSplitters(&splitters, random);

        var best_splitters: [10]u8 = splitters;
        var best_count: usize = 0;
        var best_dist_from_center: usize = std.math.maxInt(usize);
        _ = &best_dist_from_center; // autofix
        // var best_possible_children: usize = 0;

        var timer = try std.time.Timer.start();

        while ((timer.read() < 1000 * std.time.ns_per_ms) and best_count < 1000000000) {
            for (0..1) |_| {
                // var best_splitters_inner: [10]u8 = splitters;
                // var best_quality: usize = 0;
                // for (0..10) |_| {
                //     fillSplitters(&splitters, random);
                //     const quality = approximateQuality(splitters, remaining_colors, 2, random);
                //     if (quality > best_quality) {
                //         best_quality = quality;
                //         best_splitters_inner = splitters;
                //     }
                // }

                // splitters = best_splitters_inner;

                // splitters = possible_splitters.items[num_iters % possible_splitters.items.len];

                // while (true) {
                //     num_iters += 1;

                //     fillSplitters(&splitters, random);

                //     const target_color: [3]u8 = @splat(128);

                //     splitters[6..9].* = target_color;

                //     splitters = render.splitterApplyColorSaltInverse(splitters, target_color);

                //     if (@as(u24, @bitCast(render.splitColor(target_color, splitters)[current_digit])) == @as(u24, @bitCast(target_color))) {
                //         break;
                //     }
                // }

                fillSplitters(&splitters, random);
                num_iters += 1;

                // if (total <= 1000) {
                //     var best_count_inner: usize = 0;
                //     var best_splitters_inner: [10]u8 = splitters;

                //     for (0..1000000) |_| {
                //         fillSplitters(&splitters, random);

                //         var count_inner: usize = 0;
                //         for (remaining_colors[0..total]) |color_int| {
                //             var color: [3]u8 = undefined;
                //             std.mem.writeInt(u24, &color, color_int, .little);

                //             const new_color_int = @as(u24, @bitCast(render.splitColor(color, splitters)[current_digit]));
                //             const old_dist = distFromCenter(&.{@intCast(color_int)});

                //             const new_dist = distFromCenter(&.{new_color_int});

                //             if (new_dist <= old_dist) {
                //                 count_inner += 1;
                //             }
                //         }

                //         if (count_inner > best_count_inner) {
                //             best_count_inner = count_inner;
                //             best_splitters_inner = splitters;
                //         }
                //     }

                //     splitters = best_splitters_inner;
                // }

                // var count_signed: isize = 0;

                // for (remaining_colors[0..@min(1000, total)]) |color_int| {
                //     var color: [3]u8 = undefined;
                //     std.mem.writeInt(u24, &color, color_int, .little);

                //     const new_color = render.splitColor(color, splitters)[current_digit];

                //     const new_color_int = @as(u24, @bitCast(new_color));
                //     _ = new_color_int; // autofix
                //     // const old_dist = distFromCenter(&.{@intCast(color_int)});

                //     var old_dist: usize = 0;
                //     old_dist = @max(old_dist, @abs(@as(isize, color[0]) - @as(isize, color[1])));
                //     old_dist = @max(old_dist, @abs(@as(isize, color[0]) - @as(isize, color[2])));
                //     old_dist = @max(old_dist, @abs(@as(isize, color[1]) - @as(isize, color[2])));

                //     // const new_dist = distFromCenter(&.{new_color_int});

                //     count_signed += @intCast(old_dist);

                //     var new_dist: usize = 0;
                //     new_dist = @max(new_dist, @abs(@as(isize, new_color[0]) - @as(isize, new_color[1])));
                //     new_dist = @max(new_dist, @abs(@as(isize, new_color[0]) - @as(isize, new_color[2])));
                //     new_dist = @max(new_dist, @abs(@as(isize, new_color[1]) - @as(isize, new_color[2])));

                //     count_signed -= @intCast(new_dist);

                //     // if (new_dist <= old_dist) {
                //     //     count += 1;
                //     // } else {
                //     //     // break;
                //     // }
                // }

                // if (count_signed < 0) {
                //     continue;
                // }

                // count = @intCast(@max(0, count_signed));

                // num_iters += 1;

                // fillSplitters(&splitters, random);

                count = refineCount(splitters, remaining_colors[0..total], next_remaining_colors_map, next_remaining_colors, current_digit);

                // const dist_from_center = distFromCenter(next_remaining_colors[0 .. total - count]);

                // if (dist_from_center < best_dist_from_center) {
                //     best_count = count;
                //     best_splitters = splitters;
                //     best_dist_from_center = dist_from_center;
                // }

                // if (count > best_count) {
                //     best_count = count;
                //     best_splitters = splitters;
                // }

                if (count >= best_count) {
                    const dist_from_center = distFromCenter(next_remaining_colors[0 .. total - count]) / (total - count);

                    if (count > best_count or dist_from_center < best_dist_from_center) {
                        best_count = count;
                        best_splitters = splitters;
                        best_dist_from_center = dist_from_center;
                    }
                }

                // if (count >= best_count) {
                //     const possible_children = averagePossibleChildren(next_remaining_colors[0 .. total - count]);

                //     if (count > best_count or possible_children > best_possible_children) {
                //         best_count = count;
                //         best_splitters = splitters;
                //         best_possible_children = possible_children;
                //     }
                // }

                // const possible_children = averagePossibleChildren(next_remaining_colors[0 .. total - count]);

                // if (possible_children > best_possible_children) {
                //     best_count = count;
                //     best_splitters = splitters;
                //     best_possible_children = possible_children;
                // }
            }
        }

        splitters = best_splitters;

        try result_splitters.append(splitters);

        // count = refineCountOld(splitters, remaining_colors_map, next_remaining_colors_map, 2);
        // @memcpy(remaining_colors_map, next_remaining_colors_map);

        count = refineCount(splitters, remaining_colors[0..total], next_remaining_colors_map, next_remaining_colors, current_digit);

        if (current_digit > 1) {
            current_digit -= 1;
        } else {
            current_digit = 2;
        }

        total -= count;

        @memcpy(remaining_colors, next_remaining_colors);

        std.debug.print("{d:<10} {any:<3} {d}\n", .{ total, splitters, num_iters });
    }

    for (result_splitters.items) |result_splitter| {
        std.debug.print("{any:<3}\n", .{result_splitter});
    }

    std.debug.print("splitter count: {}\n", .{result_splitters.items.len});

    var final_color: [3]u8 = undefined;
    std.mem.writeInt(u24, &final_color, remaining_colors[0], .little);

    std.debug.print("final color: {any}\n", .{final_color});

    std.debug.print("final color possible children: {any}\n", .{numPossibleChildren(final_color)});

    std.debug.print("iters: {}\n", .{num_iters});

    const cwd = std.fs.cwd();

    const file_data = try allocator.alloc(u8, result_splitters.items.len * 10);
    defer allocator.free(file_data);

    for (result_splitters.items, 0..) |result_splitter, i| {
        file_data[i * 10 ..][0..10].* = result_splitter;
    }

    try cwd.writeFile(.{
        .data = file_data,
        .sub_path = "magic_splitters",
    });

    // var max_count: usize = 0;

    // for (0..1000000) |_| {
    //     fillSplitters(&splitters, random);
    //     const count = numToTarget(splitters, remaining_colors, @splat(128), 2);
    //     // if (count > max_count) {
    //         max_count = count;
    //         std.debug.print("{d:<10} {any:<3}\n", .{ count, splitters });
    //     // }
    // }
}

fn fillSplitters(splitters: *[10]u8, random: std.Random) void {
    random.bytes(splitters);
    splitters[9] &= 0b111111;
}

fn distFromCenter(remaining_colors: []const u24) usize {
    var total_dist: usize = 0;
    for (remaining_colors) |color_int| {
        var color: [3]u8 = undefined;
        std.mem.writeInt(u24, &color, color_int, .little);

        var max_dist: usize = 0;

        for (&color) |color_component| {
            max_dist = @max(max_dist, @abs(@as(isize, color_component) - 128));
            // total_dist += @abs(@as(isize, color_component) - 128);
        }

        total_dist += max_dist;

        // for (&color) |color_component| {
        //     total_dist = @max(total_dist, @abs(@as(isize, color_component) - 128));
        //     // total_dist += @abs(@as(isize, color_component) - 128);
        // }
    }

    return total_dist;
}

fn averagePossibleChildren(remaining_colors: []const u24) usize {
    var sum: u128 = undefined;

    for (remaining_colors) |color_int| {
        var color: [3]u8 = undefined;
        std.mem.writeInt(u24, &color, color_int, .little);

        sum += numPossibleChildren(color);
    }

    sum /= remaining_colors.len;

    return @intCast(sum);
}

fn numPossibleChildren(color: [3]u8) usize {
    var totals: [3]usize = undefined;

    for (0..3) |i| {
        var sum_min: usize = color[i];
        sum_min *= 4;
        sum_min -|= 1;

        var sum_max: usize = color[i];
        sum_max *= 4;
        sum_max += 2;
        sum_max = @min(sum_max, 255 * 4);

        const child_min = sum_min -| 255 * 3;
        const child_max = @min(255, sum_max);

        totals[i] = child_max - child_min + 1;
    }

    var total: usize = 1;
    for (&totals) |subtotal| {
        total *= subtotal;
    }

    return total;
}

fn approximateQuality(splitters: [10]u8, remaining_colors: []const u24, digit: u2, random: std.Random) usize {
    var count: usize = 0;

    var first_color: [3]u8 = undefined;
    var has_first = false;

    for (0..100) |_| {
        const idx = random.intRangeLessThan(usize, 0, remaining_colors.len);

        const color_int = remaining_colors[idx];

        var color: [3]u8 = undefined;

        std.mem.writeInt(u24, &color, color_int, .little);

        var split_color: [3]u8 = color;

        for (0..1) |_| {
            split_color = render.splitColor(color, splitters)[digit];
        }

        if (!has_first) {
            first_color = split_color;
            has_first = true;
        }

        count += 1;

        if (@as(u24, @bitCast(split_color)) != @as(u24, @bitCast(first_color))) {
            return count;
        }
    }

    return count;
}

fn approximateQualityOld(splitters: [10]u8, remaining_colors: []const bool, digit: u2) usize {
    var count: usize = 0;

    var first_color: [3]u8 = undefined;
    var has_first = false;

    for (remaining_colors, 0..) |has_color, i| {
        if (has_color) {
            count += 1;
            const color_int: u24 = @intCast(i);
            var color: [3]u8 = undefined;

            std.mem.writeInt(u24, &color, color_int, .little);

            var split_color: [3]u8 = color;

            for (0..1) |_| {
                split_color = render.splitColor(color, splitters)[digit];
            }

            if (!has_first) {
                first_color = split_color;
                has_first = true;
            }

            if (@as(u24, @bitCast(split_color)) != @as(u24, @bitCast(first_color))) {
                return count;
            }
        }
    }

    return count;
}

fn refineCount(splitters: [10]u8, remaining_colors: []const u24, next_remaining_colors_map: []bool, next_remaining_colors: []u24, digit: u2) usize {
    const starting_count: usize = remaining_colors.len;

    var ending_count: usize = 0;

    for (remaining_colors) |color_int| {
        var color: [3]u8 = undefined;

        std.mem.writeInt(u24, &color, color_int, .little);

        var split_color: [3]u8 = color;

        for (0..1) |_| {
            split_color = render.splitColor(color, splitters)[digit];
        }

        const split_color_int = std.mem.readInt(u24, &split_color, .little);

        if (!next_remaining_colors_map[split_color_int]) {
            next_remaining_colors_map[split_color_int] = true;
            next_remaining_colors[ending_count] = split_color_int;
            ending_count += 1;
        }
    }

    for (next_remaining_colors[0..ending_count]) |color| {
        next_remaining_colors_map[color] = false;
    }

    return starting_count - ending_count;
}

fn refineCountOld(splitters: [10]u8, remaining_colors: []const bool, next_remaining_colors: []bool, digit: u2) usize {
    var starting_count: usize = 0;
    for (remaining_colors) |has_color| {
        starting_count += @intFromBool(has_color);
    }

    @memset(next_remaining_colors, false);

    for (remaining_colors, 0..) |has_color, i| {
        if (has_color) {
            const color_int: u24 = @intCast(i);
            var color: [3]u8 = undefined;

            std.mem.writeInt(u24, &color, color_int, .little);

            var split_color: [3]u8 = color;

            for (0..10) |_| {
                split_color = render.splitColor(color, splitters)[digit];
            }

            const split_color_int = std.mem.readInt(u24, &split_color, .little);
            next_remaining_colors[split_color_int] = true;
        }
    }

    var ending_count: usize = 0;
    for (next_remaining_colors) |has_color| {
        ending_count += @intFromBool(has_color);
    }

    return starting_count - ending_count;
}

fn numToTarget(splitters: [10]u8, remaining_colors: []const bool, target: [3]u8, digit: u2) usize {
    var count: usize = 0;

    for (remaining_colors, 0..) |has_color, i| {
        if (has_color) {
            const color_int: u24 = @intCast(i);
            var color: [3]u8 = undefined;

            std.mem.writeInt(u24, &color, color_int, .little);

            const split_color = render.splitColor(color, splitters)[digit];
            if (@as(u24, @bitCast(split_color)) == @as(u24, @bitCast(target))) {
                count += 1;
            }
        }
    }

    return count;
}
