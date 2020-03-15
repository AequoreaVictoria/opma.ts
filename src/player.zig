const std = @import("std");
const panic = std.debug.panic;
const print = std.debug.warn;
const process = std.process;
const Allocator = std.mem.Allocator;
const bitview = @import("bitview.zig");
const libz = @import("libz.zig");
const parser = @import("vgm.zig");
const VGM = parser.VGM;
const psg = @import("psg.zig");
const scc = @import("scc.zig");
const opm = @import("opm.zig");
const pcm = @import("pcm.zig");
const sio = @cImport({
    @cInclude("soundio/soundio.h");
});

const MASTER_RATE = 44100; // Required by VGM standard

const Chips = struct {
    psg: psg.Chip,
    scc: scc.Chip,
    opm: opm.Chip,
    pcm: pcm.Chip,
};

const State = struct {
    loopCount: u32,
    currentLoop: u32,
    vgmPosition: u32,
    remainingWait: u32,
    files: [][]u8,
    filesIndex: u32,
};

var heap: *Allocator = undefined;
var ic: Chips = undefined;
var state: State = undefined;
var vgm: ?VGM = null;

fn nextVGM() void {
    if (vgm) |v| {
        v.free(heap);
        vgm = null;
    }

    if (state.filesIndex == state.files.len) {
        print("\n - FINISHED -\n", .{});
        process.exit(0);
    }

    const file = libz.openAndInflate(heap, state.files[state.filesIndex])
        catch panic("ERROR: Could not inflate file!", .{});
    vgm = parser.VGM.init(heap, &file)
        catch panic("ERROR: Could not parse VGM file!", .{});

    if (vgm) |v| {
        if (!(v.ay8910Clock > 0) and
            !(v.k051649Clock > 0) and
            !(v.ym2151Clock > 0) and
            !(v.okim6258Clock > 0))
            panic("ERROR: No supported chips in file!", .{});
        if (v.ay8910Multiplier > 1 or
            v.k051649Multiplier > 1 or
            v.ym2151Multiplier > 1 or
            v.okim6258Multiplier > 1)
            panic("ERROR: No dual chip support at this time!", .{});

        ic = Chips {
            .psg = psg.Chip.init(v.ay8910Clock, MASTER_RATE),
            .scc = scc.Chip.init(v.k051649Clock, MASTER_RATE),
            .opm = opm.Chip.init(v.ym2151Clock, MASTER_RATE),
            .pcm = pcm.Chip.init(v.okim6258Clock, MASTER_RATE),
        };

        state.currentLoop = 0;
        state.vgmPosition = 0x34 + v.vgmDataOffset;
        state.remainingWait = 0;
        state.filesIndex += 1;

        print(
            \\
            \\ {} ({}): {}
            \\ [{} - {}]
            \\
            , .{
               v.gd3Tags.gameNameEn,
               v.gd3Tags.systemNameEn,
               v.gd3Tags.trackNameEn,
               v.gd3Tags.trackAuthorEn,
               v.gd3Tags.releaseDate,
            });
    } else unreachable;
}

fn nextStep() u32 {
    if (vgm) |v| {
        var wait: u32 = 0;
        const command = v.data[state.vgmPosition];
        switch (command) {
            0xA0 => { // PSG write
                const register = v.data[state.vgmPosition + 1];
                const data = v.data[state.vgmPosition + 2];
                ic.psg.writeRegister(register, data);
                state.vgmPosition += 3;
            },
            0xD2 => { // SSC write
                const port = v.data[state.vgmPosition + 1];
                const register = v.data[state.vgmPosition + 2];
                const data = v.data[state.vgmPosition + 3];
                ic.scc.writeRegister(port, register, data);
                state.vgmPosition += 4;
            },
            0x54 => { // OPM write
                const register = v.data[state.vgmPosition + 1];
                const data = v.data[state.vgmPosition + 2];
                ic.opm.writeRegister(0x00, register);
                ic.opm.writeRegister(0x01, data);
                state.vgmPosition += 3;
            },
            0xB7 => { // PCM write
                const register = v.data[state.vgmPosition + 1];
                const data = v.data[state.vgmPosition + 2];
                ic.pcm.writeRegister(register, data);
                state.vgmPosition += 3;
            },
            0x67 => { // PCM data load
                const size = bitview.read(u32, v.data, state.vgmPosition + 2);
                // Do something to get PCM data at vgmPosition + 6...
                state.vgmPosition += 6 + size;
            },
            0x61 => { // Wait X samples
                wait = bitview.read(u16, v.data, state.vgmPosition + 1);
                state.vgmPosition += 3;
            },
            0x62 => { // Wait 60TH of a second
                wait = 735;
                state.vgmPosition += 1;
            },
            0x63 => { // Wait 50TH of a second
                wait = 882;
                state.vgmPosition += 1;
            },
            0x70 ... 0x7F => { // Wait 1 sample ... Wait 16 samples
                wait = (command & 0x0F) + 1;
                state.vgmPosition += 1;
            },
            0x66 => { // End of data
                if (v.loopOffset > 0
                    and state.loopCount > 0
                    and state.currentLoop < state.loopCount) {
                    state.vgmPosition = v.loopOffset + 0x1C;
                    state.currentLoop += 1;
                } else nextVGM();
            },
            else => state.vgmPosition += 1
        }
        return wait;
    } else unreachable;
}

pub fn writeCallback(
    maybeOutstream: ?[*]sio.SoundIoOutStream,
    frameCountMin: c_int,
    frameCountMax: c_int,
) callconv(.C) void {
    var framesLeft = frameCountMax;
    while (framesLeft > 0) {
        var frameCount = framesLeft;

        var areas: [*]sio.SoundIoChannelArea = undefined;
        sioErr(sio.soundio_outstream_begin_write(
            maybeOutstream,
            @ptrCast([*]?[*]sio.SoundIoChannelArea, &areas),
            &frameCount,
        )) catch |err| panic("Error: SoundIO write failed - {}", .{@errorName(err)});

        if (frameCount == 0) break;

        var frame: c_int = 0;
        while (frame < frameCount) {
            if (state.remainingWait == 0) state.remainingWait = nextStep();
            if (state.remainingWait > 0) {
                var leftSample: f64 = 0.0;
                var rightSample: f64 = 0.0;

                if (vgm) |v| {
                    if (v.ay8910Clock > 0) {
                        ic.psg.process();
                        ic.psg.removeDc();
                        leftSample += ic.psg.output;
                        rightSample += ic.psg.output;
                    }
                    if (v.k051649Clock > 0) {
                        ic.scc.process();
                        leftSample += ic.scc.output;
                        rightSample += ic.scc.output;
                    }
                    if (v.ym2151Clock > 0) {
                        ic.opm.process();
                        leftSample += ic.opm.output;
                        rightSample += ic.opm.output;
                    }
                    if (v.okim6258Clock > 0) {
                        ic.pcm.process();
                        leftSample += ic.pcm.output;
                        rightSample += ic.pcm.output;
                    }
                } else unreachable;

                // Wait until the last moment to downcast to f32.
                const leftSampleF32: f32 = @floatCast(f32, leftSample);
                const rightSampleF32: f32 = @floatCast(f32, rightSample);

                const leftChannelPtr = areas[0].ptr;
                const leftSamplePtr = &leftChannelPtr[@intCast(usize, areas[0].step * frame)];
                @ptrCast(*f32, @alignCast(@alignOf(f32), leftSamplePtr)).* = leftSampleF32;

                const rightChannelPtr = areas[1].ptr;
                const rightSamplePtr = &rightChannelPtr[@intCast(usize, areas[1].step * frame)];
                @ptrCast(*f32, @alignCast(@alignOf(f32), rightSamplePtr)).* = rightSampleF32;

                state.remainingWait -= 1;
                frame += 1;
            }
        }

        sioErr(sio.soundio_outstream_end_write(maybeOutstream))
            catch |err| panic("Error: SoundIO end write failed - {}", .{@errorName(err)});

        framesLeft -= frameCount;
    }
}

pub fn start(alloc: *Allocator, files: [][]u8, writeFile: bool, loopCount: u32) !void {
    heap = alloc;

    if (writeFile) return error.FileWritingNotImplementedYet;

    const soundio = sio.soundio_create();
    defer sio.soundio_destroy(soundio);
    try sioErr(sio.soundio_connect(soundio));
    sio.soundio_flush_events(soundio);

    const deviceIndex = sio.soundio_default_output_device_index(soundio);
    if (deviceIndex < 0) return error.NoOutputDeviceFound;
    const device = sio.soundio_get_output_device(soundio, deviceIndex)
        orelse return error.OutOfMemory;
    defer sio.soundio_device_unref(device);

    const deviceName = @ptrCast(*[*:0]u8, &(device.*.name)).*;
    const deviceID = @ptrCast(*u8, &(device.*.id)).*;
    const deviceBitRate = @ptrCast(*[*:0]u8, &(sio.soundio_format_string(device.*.current_format))).*;
    const deviceSampleRate = device.*.sample_rate_current;
    print(
        \\
        \\ {} (id: {})
        \\ [{} @ {}Hz]
        \\
        , .{
           deviceName,
           deviceID,
           deviceBitRate,
           deviceSampleRate,
        });

    const outstream = sio.soundio_outstream_create(device)
        orelse return error.OutOfMemory;
    defer sio.soundio_outstream_destroy(outstream);
    outstream.*.format = @intToEnum(sio.SoundIoFormat, sio.SoundIoFormatFloat32NE);
    outstream.*.write_callback = writeCallback;
    try sioErr(sio.soundio_outstream_open(outstream));

    const layout = outstream.*.layout;
    if (layout.channel_count != 2) return error.UseOnlyStereoChannels;
    const sampleRate = outstream.*.sample_rate;
    if (sampleRate < MASTER_RATE) return error.DownsamplingNotSupported;

    state = State {
        .loopCount = loopCount,
        .currentLoop = 0,
        .vgmPosition = 0,
        .remainingWait = 0,
        .files = files,
        .filesIndex = 0,
    };
    nextVGM();

    try sioErr(sio.soundio_outstream_start(outstream));
    while (true) sio.soundio_wait_events(soundio);
}

fn sioErr(err: c_int) !void {
    switch (@intToEnum(sio.SoundIoError, err)) {
        .None => {},
        .NoMem => return error.NoMem,
        .InitAudioBackend => return error.InitAudioBackend,
        .SystemResources => return error.SystemResources,
        .OpeningDevice => return error.OpeningDevice,
        .NoSuchDevice => return error.NoSuchDevice,
        .Invalid => return error.Invalid,
        .BackendUnavailable => return error.BackendUnavailable,
        .Streaming => return error.Streaming,
        .IncompatibleDevice => return error.IncompatibleDevice,
        .NoSuchClient => return error.NoSuchClient,
        .IncompatibleBackend => return error.IncompatibleBackend,
        .BackendDisconnected => return error.BackendDisconnected,
        .Interrupted => return error.Interrupted,
        .Underflow => return error.Underflow,
        .EncodingString => return error.EncodingString,
        else => unreachable
    }
}
