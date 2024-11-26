const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "example",
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
            .cpu_features_add = std.Target.wasm.featureSet(&[_]std.Target.wasm.Feature{
                // .atomics,
                .bulk_memory,
                .exception_handling,
                .extended_const,
                // .multimemory,
                .multivalue,
                .mutable_globals,
                .nontrapping_fptoint,
                .reference_types,
                .relaxed_simd,
                .sign_ext,
                .simd128,
                // .tail_call,
            }),
        }),

        .optimize = optimize,
    });

    exe.entry = .disabled;
    exe.rdynamic = true;

    exe.stack_size = std.wasm.page_size * 2;
    exe.initial_memory = std.wasm.page_size * 64 * 64;
    exe.max_memory = std.wasm.page_size * 1024 * 64;

    const bin_dir = std.Build.InstallDir.bin;

    b.default_step.dependOn(&b.addInstallDirectory(.{
        .source_dir = b.path("static"),
        .install_dir = bin_dir,
        .install_subdir = "",
    }).step);

    b.installArtifact(exe);

    // --------------------------------------------------------

    const check_exe = b.addExecutable(.{
        .name = "example",
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
            .cpu_features_add = std.Target.wasm.featureSet(&[_]std.Target.wasm.Feature{
                // .atomics,
                .bulk_memory,
                .exception_handling,
                .extended_const,
                // .multimemory,
                .multivalue,
                .mutable_globals,
                .nontrapping_fptoint,
                .reference_types,
                .relaxed_simd,
                .sign_ext,
                .simd128,
                // .tail_call,
            }),
        }),

        .optimize = optimize,
    });

    check_exe.entry = .disabled;
    check_exe.rdynamic = true;

    check_exe.stack_size = std.wasm.page_size * 16;
    check_exe.initial_memory = std.wasm.page_size * 1024;
    check_exe.max_memory = std.wasm.page_size * 1024 * 64;

    const check_step = b.step("check", "check compilation");
    check_step.dependOn(&check_exe.step);
}
