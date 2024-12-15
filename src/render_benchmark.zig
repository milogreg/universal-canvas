const std = @import("std");
const render = @import("render.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const encode_colors_time = try benchmarkEncodeColors(allocator);
    std.debug.print("encode colors time: {d} ms\n", .{@as(f128, @floatFromInt(encode_colors_time)) / 1000000.0});

    const deep_zoom_time = try benchmarkDeepZoom(allocator);
    std.debug.print("deep zoom time: {d} ms\n", .{@as(f128, @floatFromInt(deep_zoom_time)) / 1000000.0});

    const fill_iteration_time = try benchmarkFillIteration(allocator);
    std.debug.print("fill iteration time: {d} ms\n", .{@as(f128, @floatFromInt(fill_iteration_time)) / 1000000.0});

    const state_iterate_all_time = try benchmarkStateIterateAll(allocator);
    std.debug.print("state iterate all time: {d} ms\n", .{@as(f128, @floatFromInt(state_iterate_all_time)) / 1000000.0});

    const split_color_time = try benchmarkSplitColor(allocator);
    std.debug.print("split color time: {d} ms\n", .{@as(f128, @floatFromInt(split_color_time)) / 1000000.0});
}

fn benchmarkEncodeColors(allocator: std.mem.Allocator) !u64 {
    const square_size = 1024;

    const colors = try allocator.alloc(render.Color, square_size * square_size);
    defer allocator.free(colors);

    var prng = std.Random.DefaultPrng.init(123);
    const random = prng.random();

    for (colors) |*color| {
        color.* = @bitCast(random.int(u32));
        color.a = 255;
    }

    var timer = try std.time.Timer.start();

    const digits = try render.encodeColors(allocator, colors);
    defer digits.deinit(allocator);

    return timer.read();
}

fn benchmarkDeepZoom(allocator: std.mem.Allocator) !u64 {
    const square_size = 1024;

    const colors = try allocator.alloc(render.Color, square_size * square_size);
    defer allocator.free(colors);

    var prng = std.Random.DefaultPrng.init(123);
    const random = prng.random();

    for (colors) |*color| {
        color.* = @bitCast(random.int(u32));
        color.a = 255;
    }

    const digits = try render.encodeColors(allocator, colors);
    defer digits.deinit(allocator);

    const root_color: render.Color = .{
        .r = 60,
        .g = 60,
        .b = 60,
        .a = 255,
    };

    var states: [2]render.SelfConsumingReaderState = undefined;
    states[0] = render.SelfConsumingReaderState.init(0, root_color);

    var current_state = &states[0];
    var next_state = &states[1];

    var timer = try std.time.Timer.start();

    for (0..digits.length) |i| {
        const digit = digits.get(i);

        current_state.iterate(digit, render.VirtualDigitArray.fromDigitArray(digits, 0, 0, 0), next_state);

        const temp = current_state;
        current_state = next_state;
        next_state = temp;
    }

    return timer.read();
}

fn benchmarkStateIterateAll(allocator: std.mem.Allocator) !u64 {
    const state_count = 1398101;

    const digits = try render.DigitArray.init(allocator, 1000000);
    defer digits.deinit(allocator);

    var prng = std.Random.DefaultPrng.init(123);
    const random = prng.random();

    for (0..digits.length) |i| {
        digits.set(i, random.int(u2));
    }

    const input_states = try allocator.alloc(render.SelfConsumingReaderState, state_count);
    defer allocator.free(input_states);

    const root_color: render.Color = .{
        .r = 60,
        .g = 60,
        .b = 60,
        .a = 255,
    };

    var states: [2]render.SelfConsumingReaderState = undefined;
    states[0] = render.SelfConsumingReaderState.init(0, root_color);

    var current_state = &states[0];
    var next_state = &states[1];

    for (0..digits.length - 1) |i| {
        const digit = digits.get(i);

        current_state.iterate(digit, render.VirtualDigitArray.fromDigitArray(digits, 0, 0, 0), next_state);

        const temp = current_state;
        current_state = next_state;
        next_state = temp;
    }

    @memset(input_states, current_state.*);

    const output_states = try allocator.alloc(render.SelfConsumingReaderState, state_count * 4);
    defer allocator.free(output_states);

    var timer = try std.time.Timer.start();

    for (input_states, 0..) |*state, i| {
        state.iterateAll(render.VirtualDigitArray.fromDigitArray(digits, 0, 0, 0), output_states[i * 4 ..][0..4]);
    }

    return timer.read();
}

fn benchmarkFillIteration(allocator: std.mem.Allocator) !u64 {
    const square_size = 2048;

    const colors = try allocator.alloc(render.Color, square_size * square_size);
    defer allocator.free(colors);

    const digits = try render.DigitArray.init(allocator, 1000000);
    defer digits.deinit(allocator);

    var prng = std.Random.DefaultPrng.init(123);
    const random = prng.random();

    for (0..digits.length) |i| {
        digits.set(i, random.int(u2));
    }

    const root_color: render.Color = .{
        .r = 60,
        .g = 60,
        .b = 60,
        .a = 255,
    };

    var states: [2]render.SelfConsumingReaderState = undefined;
    states[0] = render.SelfConsumingReaderState.init(0, root_color);

    var current_state = &states[0];
    var next_state = &states[1];

    for (0..digits.length) |i| {
        const digit = digits.get(i);

        current_state.iterate(digit, render.VirtualDigitArray.fromDigitArray(digits, 0, 0, 0), next_state);

        const temp = current_state;
        current_state = next_state;
        next_state = temp;
    }

    const output_colors = try allocator.alloc([]render.Color, square_size);
    defer allocator.free(output_colors);

    for (output_colors, 0..) |*output_colors_layer, i| {
        output_colors_layer.* = colors[i * square_size .. (i + 1) * square_size];
    }

    var iteration_state = try render.FillIterationState.init(allocator, square_size, digits, current_state.*, output_colors);
    defer iteration_state.deinit();

    var timer = try std.time.Timer.start();

    _ = iteration_state.iterate(1000000000);

    return timer.read();
}

fn benchmarkSplitColor(allocator: std.mem.Allocator) !u64 {
    const color_count = 1398101 * 10;

    const colors = try allocator.alloc(render.Color, color_count);
    defer allocator.free(colors);

    const splitters = try allocator.alloc([10]u8, color_count);
    defer allocator.free(splitters);

    var prng = std.Random.DefaultPrng.init(123);
    const random = prng.random();

    for (colors, splitters) |*color, *splitter| {
        color.* = @bitCast(random.int(u32));
        color.a = 255;

        random.bytes(splitter);
    }

    const split_colors = try allocator.alloc([4]render.Color, color_count);
    defer allocator.free(split_colors);

    var timer = try std.time.Timer.start();

    var accum: u32 = 0;

    for (colors, splitters, split_colors) |color, splitter, *split_color| {
        _ = split_color; // autofix

        // split_color.* = render.splitColor(color, splitter);

        const split = render.splitColor(color, splitter);
        for (0..4) |i| {
            accum ^= @bitCast(split[i]);
        }
    }

    std.mem.doNotOptimizeAway(accum);

    return timer.read();
}
