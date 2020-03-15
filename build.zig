const std = @import("std");
const builtin = std.builtin;
const mem = std.mem;
const path = std.fs.path;
const Builder = std.build.Builder;
const CrossTarget = std.zig.CrossTarget;
const LibExeObjStep = std.build.LibExeObjStep;
const Target = std.build.Target;

pub fn build(b: *Builder) void {
    const arch = @tagName(builtin.cpu.arch);
    const os = @tagName(builtin.os.tag);
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{
        .whitelist = &[_]Target{
            .{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
                .abi = .musl,
            },
            .{
                .cpu_arch = .aarch64,
                .os_tag = .linux,
                .abi = .musleabi,
            },
            .{
                .cpu_arch = .x86_64,
                .os_tag = .windows,
                .abi = .msvc,
            },
        },
    });

    const cFlags = &[_][]const u8{"-std=c99"};
    const exe = b.addExecutable("opma", "src/main.zig");
    exe.setOutputDir("out");
    exe.setBuildMode(mode);
    exe.setTarget(target);
    exe.linkLibC();
    addCFiles("libz", b, exe, cFlags, &[_][]const u8{
        "adler32.c",
        "crc32.c",
        "inffast.c",
        "inflate.c",
        "inftrees.c",
        "zutil.c",
    });
    exe.linkSystemLibrary("soundio");
    const includePath = path.join(
        b.allocator, &[_][]const u8{"/usr", "include"}
    ) catch unreachable;
    exe.addIncludeDir(includePath);
    exe.install();
}

fn addCFiles(
    name: []const u8,
    b: *Builder,
    exe: *LibExeObjStep,
    cFlags: [][]const u8,
    files: [][]const u8
) void {
    const includePath = path.join(
        b.allocator, &[_][]const u8{"lib", name}
    ) catch unreachable;
    exe.addIncludeDir(includePath);

    for (files) |srcFile| {
        const srcPath = path.join(
            b.allocator, &[_][]const u8{"lib", name, srcFile}
        ) catch unreachable;
        exe.addCSourceFile(srcPath, cFlags);
    }
}
