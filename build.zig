const std = @import("std");
const builtin = std.builtin;
const mem = std.mem;
const path = std.fs.path;
const Builder = std.build.Builder;
const CrossTarget = std.zig.CrossTarget;
const LibExeObjStep = std.build.LibExeObjStep;
const Target = std.build.Target;

pub fn build(b: *Builder) !void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const exe = b.addExecutable("opma", "src/main.zig");
    exe.setOutputDir("out");
    exe.setBuildMode(mode);
    exe.setTarget(target);

    switch (builtin.os.tag) {
        .linux => {
            const cFlags = &[_][]const u8{"-D_POSIX_SOURCE -D_REENTRANT -std=c99"};
            addCFiles("libz", b, exe, cFlags, &[_][]const u8{
                "adler32.c",
                "crc32.c",
                "inffast.c",
                "inflate.c",
                "inftrees.c",
                "zutil.c",
            });
            addCFiles("libsoundio", b, exe, cFlags, &[_][]const u8{
                "alsa.c",
                "channel_layout.c",
                "dummy.c",
                "os.c",
                "pulseaudio.c",
                "ring_buffer.c",
                "soundio.c",
                "util.c",
            });
            exe.linkSystemLibrary("asound");
            exe.linkSystemLibrary("pulse");
            exe.linkSystemLibrary("pthread");
            const config =  \\#ifndef SOUNDIO_CONFIG_H
                            \\#define SOUNDIO_CONFIG_H
                            \\#define SOUNDIO_VERSION_MAJOR 2
                            \\#define SOUNDIO_VERSION_MINOR 0
                            \\#define SOUNDIO_VERSION_PATCH 0
                            \\#define SOUNDIO_VERSION_STRING "2.0.0"
                            \\#define SOUNDIO_HAVE_PULSEAUDIO
                            \\#define SOUNDIO_HAVE_ALSA
                            \\#endif
            ;
            const file = try std.fs.cwd().createFile("lib/libsoundio/config.h", .{});
            defer file.close();
            try file.writeAll(config);
        },

        .macos => {
            const cFlags = &[_][]const u8{"-std=c99"};
            addCFiles("libz", b, exe, cFlags, &[_][]const u8{
                "adler32.c",
                "crc32.c",
                "inffast.c",
                "inflate.c",
                "inftrees.c",
                "zutil.c",
            });
            addCFiles("libsoundio", b, exe, cFlags, &[_][]const u8{
                "channel_layout.c",
                "coreaudio.c",
                "dummy.c",
                "os.c",
                "ring_buffer.c",
                "soundio.c",
                "util.c",
            });
            exe.linkSystemLibrary("coreaudio");
            const config =  \\#ifndef SOUNDIO_CONFIG_H
                            \\#define SOUNDIO_CONFIG_H
                            \\#define SOUNDIO_VERSION_MAJOR 2
                            \\#define SOUNDIO_VERSION_MINOR 0
                            \\#define SOUNDIO_VERSION_PATCH 0
                            \\#define SOUNDIO_VERSION_STRING "2.0.0"
                            \\#define SOUNDIO_HAVE_COREAUDIO
                            \\#endif
            ;
            const file = try std.fs.cwd().createFile("lib/libsoundio/config.h", .{});
            defer file.close();
            try file.writeAll(config);
        },

        .windows => {
            const cFlags = &[_][]const u8{"-std=c99"};
            addCFiles("libz", b, exe, cFlags, &[_][]const u8{
                "adler32.c",
                "crc32.c",
                "inffast.c",
                "inflate.c",
                "inftrees.c",
                "zutil.c",
            });
            addCFiles("libsoundio", b, exe, cFlags, &[_][]const u8{
                "channel_layout.c",
                "dummy.c",
                "os.c",
                "ring_buffer.c",
                "soundio.c",
                "util.c",
                "wasapi.c",
            });
            exe.linkSystemLibrary("wasapi");
            const config =  \\#ifndef SOUNDIO_CONFIG_H
                            \\#define SOUNDIO_CONFIG_H
                            \\#define SOUNDIO_VERSION_MAJOR 2
                            \\#define SOUNDIO_VERSION_MINOR 0
                            \\#define SOUNDIO_VERSION_PATCH 0
                            \\#define SOUNDIO_VERSION_STRING "2.0.0"
                            \\#define SOUNDIO_HAVE_WASAPI
                            \\#endif
            ;
            const file = try std.fs.cwd().createFile("lib/libsoundio/config.h", .{});
            defer file.close();
            try file.writeAll(config);
        },
        else => {
                print("{}", .{
                \\
                \\ ERROR: Only Linux, Mac and Windows currently supported!
                \\
            });
            process.exit(1);
        }
    }

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
    cFlags: []const []const u8,
    files: []const []const u8
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
