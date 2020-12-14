const std = @import("std");
const panic = std.debug.panic;
const print = std.debug.warn;
const process = std.process;
const Allocator = std.mem.Allocator;
const bitview = @import("bitview.zig");
const parser = @import("vgm.zig");
const VGM = parser.VGM;
const vgz = @import("vgz.zig");
const psg = @import("psg.zig");
const scc = @import("scc.zig");
const opm = @import("opm.zig");
const pcm = @import("pcm.zig");
const sio = @cImport({
    @cInclude("soundio.h");
});

const MASTER_RATE = 44100; // Required by VGM standard

const Chips = struct {
    psg: psg.Chip,
    scc: scc.Chip,
    opm: opm.Chip,
    pcm: pcm.Chip,
};

const State = struct {
    loop_count: u32,
    current_loop: u32,
    vgm_position: u32,
    remaining_wait: u32,
    files: [][]u8,
    files_index: u32,
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

    if (state.files_index == state.files.len) {
        print("\n - FINISHED -\n", .{});
        process.exit(0);
    }

    const file = vgz.openAndInflate(heap, state.files[state.files_index])
        catch panic("ERROR: Could not inflate file!", .{});
    vgm = parser.VGM.init(heap, &file)
        catch panic("ERROR: Could not parse VGM file!", .{});

    if (vgm) |v| {
        if (!(v.ay8910_clock > 0) and
            !(v.k051649_clock > 0) and
            !(v.ym2151_clock > 0) and
            !(v.okim6258_clock > 0))
            panic("ERROR: No supported chips in file!", .{});
        if (v.ay8910_multiplier > 1 or
            v.k051649_multiplier > 1 or
            v.ym2151_multiplier > 1 or
            v.okim6258_multiplier > 1)
            panic("ERROR: No dual chip support at this time!", .{});

        ic = Chips{
            .psg = psg.Chip.init(v.ay8910_clock, MASTER_RATE),
            .scc = scc.Chip.init(v.k051649_clock, MASTER_RATE),
            .opm = opm.Chip.init(v.ym2151_clock, MASTER_RATE),
            .pcm = pcm.Chip.init(v.okim6258_clock, MASTER_RATE),
        };

        state.current_loop = 0;
        state.vgm_position = 0x34 + v.vgm_data_offset;
        state.remaining_wait = 0;
        state.files_index += 1;

        print(
            \\
            \\ {} ({}): {}
            \\ [{} - {}]
            \\
        , .{
            v.gd3_tags.game_name_en,
            v.gd3_tags.system_name_en,
            v.gd3_tags.track_name_en,
            v.gd3_tags.track_author_en,
            v.gd3_tags.release_date,
        });
    } else unreachable;
}

fn nextStep() u32 {
    if (vgm) |v| {
        var wait: u32 = 0;
        const command = v.data[state.vgm_position];
        switch (command) {
            0xA0 => { // PSG write
                const register = v.data[state.vgm_position + 1];
                const data = v.data[state.vgm_position + 2];
                ic.psg.writeRegister(register, data);
                state.vgm_position += 3;
            },
            0xD2 => { // SSC write
                const port = v.data[state.vgm_position + 1];
                const register = v.data[state.vgm_position + 2];
                const data = v.data[state.vgm_position + 3];
                ic.scc.writeRegister(port, register, data);
                state.vgm_position += 4;
            },
            0x54 => { // OPM write
                const register = v.data[state.vgm_position + 1];
                const data = v.data[state.vgm_position + 2];
                ic.opm.writeRegister(0x00, register);
                ic.opm.writeRegister(0x01, data);
                state.vgm_position += 3;
            },
            0xB7 => { // PCM write
                const register = v.data[state.vgm_position + 1];
                const data = v.data[state.vgm_position + 2];
                ic.pcm.writeRegister(register, data);
                state.vgm_position += 3;
            },
            0x67 => { // PCM data load
                const size = bitview.read(u32, v.data, state.vgm_position + 2);
                // Do something to get PCM data at vgm_position + 6...
                state.vgm_position += 6 + size;
            },
            0x61 => { // Wait X samples
                wait = bitview.read(u16, v.data, state.vgm_position + 1);
                state.vgm_position += 3;
            },
            0x62 => { // Wait 60TH of a second
                wait = 735;
                state.vgm_position += 1;
            },
            0x63 => { // Wait 50TH of a second
                wait = 882;
                state.vgm_position += 1;
            },
            0x70...0x7F => { // Wait 1 sample ... Wait 16 samples
                wait = (command & 0x0F) + 1;
                state.vgm_position += 1;
            },
            0x66 => { // End of data
                if (v.loop_offset > 0 and
                    state.loop_count > 0 and
                    state.current_loop < state.loop_count)
                {
                    state.vgm_position = v.loop_offset + 0x1C;
                    state.current_loop += 1;
                } else nextVGM();
            },
            else => state.vgm_position += 1,
        }
        return wait;
    } else unreachable;
}

pub fn writeCallback(
    maybe_out_stream: ?[*]sio.SoundIoOutStream,
    frame_count_min: c_int,
    frame_count_max: c_int,
) callconv(.C) void {
    var frames_left = frame_count_max;
    while (frames_left > 0) {
        var frame_count = frames_left;

        var areas: [*]sio.SoundIoChannelArea = undefined;
        sioErr(sio.soundio_outstream_begin_write(
            maybe_out_stream,
            @ptrCast([*]?[*]sio.SoundIoChannelArea, &areas),
            &frame_count,
        )) catch |err| panic("Error: SoundIO write failed - {}", .{@errorName(err)});

        if (frame_count == 0) break;

        var frame: c_int = 0;
        while (frame < frame_count) {
            if (state.remaining_wait == 0) state.remaining_wait = nextStep();
            if (state.remaining_wait > 0) {
                var left_sample: f64 = 0.0;
                var right_sample: f64 = 0.0;

                if (vgm) |v| {
                    if (v.ay8910_clock > 0) {
                        ic.psg.process();
                        ic.psg.removeDc();
                        left_sample += ic.psg.output;
                        right_sample += ic.psg.output;
                    }
                    if (v.k051649_clock > 0) {
                        ic.scc.process();
                        left_sample += ic.scc.output;
                        right_sample += ic.scc.output;
                    }
                    if (v.ym2151_clock > 0) {
                        ic.opm.process();
                        left_sample += ic.opm.output;
                        right_sample += ic.opm.output;
                    }
                    if (v.okim6258_clock > 0) {
                        ic.pcm.process();
                        left_sample += ic.pcm.output;
                        right_sample += ic.pcm.output;
                    }
                } else unreachable;

                // Wait until the last moment to downcast to f32.
                const left_sample_f32: f32 = @floatCast(f32, left_sample);
                const right_sample_f32: f32 = @floatCast(f32, right_sample);

                const left_channel_ptr = areas[0].ptr;
                const left_sample_ptr = &left_channel_ptr[@intCast(usize, areas[0].step * frame)];
                @ptrCast(*f32, @alignCast(@alignOf(f32), left_sample_ptr)).* = left_sample_f32;

                const right_channel_ptr = areas[1].ptr;
                const right_sample_ptr = &right_channel_ptr[@intCast(usize, areas[1].step * frame)];
                @ptrCast(*f32, @alignCast(@alignOf(f32), right_sample_ptr)).* = right_sample_f32;

                state.remaining_wait -= 1;
                frame += 1;
            }
        }

        sioErr(sio.soundio_outstream_end_write(maybe_out_stream))
            catch |err| panic("Error: SoundIO end write failed - {}", .{@errorName(err)});

        frames_left -= frame_count;
    }
}

pub fn start(alloc: *Allocator, files: [][]u8, write_file: bool, loop_count: u32) !void {
    heap = alloc;

    if (write_file) return error.FileWritingNotImplementedYet;

    const soundio = sio.soundio_create();
    defer sio.soundio_destroy(soundio);
    try sioErr(sio.soundio_connect(soundio));
    sio.soundio_flush_events(soundio);

    const device_index = sio.soundio_default_output_device_index(soundio);
    if (device_index < 0) return error.NoOutputDeviceFound;
    const device = sio.soundio_get_output_device(soundio, device_index) orelse return error.OutOfMemory;
    defer sio.soundio_device_unref(device);

    const device_name = @ptrCast(*[*:0]u8, &(device.*.name)).*;
    const device_id = @ptrCast(*u8, &(device.*.id)).*;
    const device_bit_rate = @ptrCast(*[*:0]u8, &(sio.soundio_format_string(device.*.current_format))).*;
    const device_sample_rate = device.*.sample_rate_current;
    print(
        \\
        \\ {} (id: {})
        \\ [{} @ {}Hz]
        \\
    , .{
        device_name,
        device_id,
        device_bit_rate,
        device_sample_rate,
    });

    const outstream = sio.soundio_outstream_create(device) orelse return error.OutOfMemory;
    defer sio.soundio_outstream_destroy(outstream);
    outstream.*.format = @intToEnum(sio.SoundIoFormat, sio.SoundIoFormatFloat32NE);
    outstream.*.write_callback = writeCallback;
    try sioErr(sio.soundio_outstream_open(outstream));

    const layout = outstream.*.layout;
    if (layout.channel_count != 2) return error.UseOnlyStereoChannels;
    const sample_rate = outstream.*.sample_rate;
    if (sample_rate < MASTER_RATE) return error.DownsamplingNotSupported;

    state = State{
        .loop_count = loop_count,
        .current_loop = 0,
        .vgm_position = 0,
        .remaining_wait = 0,
        .files = files,
        .files_index = 0,
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
        else => unreachable,
    }
}
