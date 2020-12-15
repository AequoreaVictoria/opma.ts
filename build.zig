const std = @import("std");
const Mode = std.builtin.Mode;

pub fn build(b: *std.build.Builder) !void {
    // workaround for windows not having Visual Studio installed.
    const target = if (std.builtin.os.tag != .windows)
        b.standardTargetOptions(.{ .default_target = std.zig.CrossTarget{} })
    else
        b.standardTargetOptions(.{ .default_target = std.zig.CrossTarget{ .abi = .gnu } });
    const mode = b.standardReleaseOptions();

    const jack = false;
    const pulseaudio = target.isLinux();
    const alsa = target.isLinux();
    const coreaudio = target.isDarwin();
    const wasapi = target.isWindows();

    const libsoundio = blk: {
        const root = "./lib/libsoundio";

        const lib = b.addStaticLibrary("soundio", null);
        lib.setBuildMode(mode);
        lib.setTarget(target);

        const cflags = [_][]const u8{
            "-std=c11",
            "-fvisibility=hidden",
            "-Wall",
            "-Werror=strict-prototypes",
            "-Werror=old-style-definition",
            "-Werror=missing-prototypes",
            "-Wno-missing-braces",
        };

        var sources = [_][]const u8{
            root ++ "/soundio.c",
            root ++ "/util.c",
            root ++ "/os.c",
            root ++ "/dummy.c",
            root ++ "/channel_layout.c",
            root ++ "/ring_buffer.c",
        };
        for (sources) |src| lib.addCSourceFile(src, &cflags);

        lib.defineCMacro("_REENTRANT");
        lib.defineCMacro("_POSIX_C_SOURCE=200809L");
        lib.defineCMacro("SOUNDIO_VERSION_MAJOR=2");
        lib.defineCMacro("SOUNDIO_VERSION_MINOR=0");
        lib.defineCMacro("SOUNDIO_VERSION_PATCH=0");
        lib.defineCMacro("SOUNDIO_VERSION_STRING=\"2.0.0\"");

        if (jack) {
            lib.addCSourceFile(root ++ "/jack.c", &cflags);
            lib.defineCMacro("SOUNDIO_HAVE_JACK");
            lib.linkSystemLibrary("jack");
        }
        if (pulseaudio) {
            lib.addCSourceFile(root ++ "/pulseaudio.c", &cflags);
            lib.defineCMacro("SOUNDIO_HAVE_PULSEAUDIO");
            lib.linkSystemLibrary("libpulse");
        }
        if (alsa) {
            lib.addCSourceFile(root ++ "/alsa.c", &cflags);
            lib.defineCMacro("SOUNDIO_HAVE_ALSA");
            lib.linkSystemLibrary("alsa");
        }
        if (coreaudio) {
            lib.addCSourceFile(root ++ "/coreaudio.c", &cflags);
            lib.defineCMacro("SOUNDIO_HAVE_COREAUDIO");
            lib.linkSystemLibrary("CoreAudio");
            lib.linkSystemLibrary("Audiotoolbox");
        }
        if (wasapi) {
            lib.addCSourceFile(root ++ "/wasapi.c", &cflags);
            lib.defineCMacro("SOUNDIO_HAVE_WASAPI");
            // lib.linkSystemLibrary("");
        }

        lib.linkLibC();
        lib.linkSystemLibrary("m");
        lib.addIncludeDir(root);

        if (lib.build_mode == Mode.ReleaseSmall or lib.build_mode == Mode.ReleaseFast) lib.strip = true;
        lib.single_threaded = true;

        break :blk lib;
    };

    {
        const exe = b.addExecutable("opma", "src/main.zig");
        exe.setTarget(target);
        exe.setBuildMode(mode);
        exe.setOutputDir("out");

        exe.linkLibC();
        exe.linkSystemLibrary("m");
        if (jack) exe.linkSystemLibrary("jack");
        if (pulseaudio) exe.linkSystemLibrary("libpulse");
        if (alsa) exe.linkSystemLibrary("alsa");
        if (coreaudio) {
            exe.linkSystemLibrary("CoreAudio");
            exe.linkSystemLibrary("Audiotoolbox");
        }
        if (wasapi) {
            exe.linkSystemLibrary("uuid");
            exe.linkSystemLibrary("ole32");
        }
        exe.linkLibrary(libsoundio);
        exe.addIncludeDir("./lib/libsoundio");

        if (exe.build_mode == Mode.ReleaseSmall or exe.build_mode == Mode.ReleaseFast) exe.strip = true;
        exe.single_threaded = true;

        exe.install();
    }
}
