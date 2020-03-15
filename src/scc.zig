const std = @import("std");
const math = std.math;
const panic = std.debug.panic;
const print = std.debug.warn;

const VOICES = 5;
const FREQ_BITS = 16;
const DEF_GAIN = 8;
const AMP_FACTOR = 256;
const AMP_LOOKUP = VOICES * AMP_FACTOR;
const AMP_SIZE = (AMP_LOOKUP * 2) + 1;

pub const Chip = struct {
    voice: [VOICES]Channel,
    ampTable: [AMP_SIZE]i16,
    output: f64,
    const Self = @This();

    pub fn init(clock: u32, sampleRate: u32) Self {
        var chip = Chip {
            .voice = [_]Channel {
                Channel {
                    .period = 0,
                    .counter = 0,
                    .waveform = [_]i8{0} ** 32,
                    .volume = 0,
                    .mute = 0,
                    .output = 0,
                    .clock = 0,
                    .rate = 0,
                }
            } ** VOICES,
            .ampTable = [_]i16{0} ** AMP_SIZE,
            .output = 0.0,
        };

        var channel: usize = 0;
        const channelClock = clock & 0x7FFFFFFF;
        const channelRate = channelClock / 16;
        while (channel < VOICES) : (channel += 1) {
            chip.voice[channel].clock = channelClock;
            chip.voice[channel].rate = channelRate;
        }

        var i: u32 = 0;
        while (i < AMP_LOOKUP) : (i += 1) {
            var value = (AMP_LOOKUP - i) * DEF_GAIN * 16 / VOICES;
            if (value > 32767) value = 32767;
            const negativeValue = math.negateCast(@intCast(i16, value))
                catch |err| panic("ERROR: {}", .{err});
            chip.ampTable[i] = negativeValue;
        }
        i = 0;
        while (i < (AMP_LOOKUP + 1)) : (i += 1) {
            var value = i * DEF_GAIN * 16 / VOICES;
            if (value > 32767) value = 32767;
            chip.ampTable[AMP_LOOKUP + i] = @intCast(i16, value);
        }

        return chip;
    }

    pub fn writeRegister(s: *Self, port:u8, register: u8, data: u8) void {
        switch (port) {
            // SCC mode waveform write
            0 => {
                if (port >= 0x60) {
                    // Channel 4 and 5 share RAM
                    s.voice[3].setWaveform(register, data);
                    s.voice[4].setWaveform(register, data);
                } else {
                    s.voice[register >> 5].setWaveform(register, data);
                }
            },
            1 => s.voice[register >> 1].setFrequency(register, data),
            2 => s.voice[register & 0x7].setVolume(data),
            3 => {
                var d = data;
                var channel: u3  = 0;
                while (channel < VOICES) : (channel += 1) {
                    s.voice[channel].setMute(d);
                    d >>= 1;
                }
            },
            // SCC-I mode waveform write
            4 => s.voice[register >> 5].setWaveform(register, data),
            5 => {}, // Test register not implemented
            else => unreachable
        }
    }

    pub fn process(s: *Self) void {
        var mixer: i32 = 0;
        var channel: usize = 0;

        while (channel < VOICES) : (channel += 1) {
            s.voice[channel].update();
            mixer += s.voice[channel].output;
        }

        const tone = s.ampTable[@intCast(usize, AMP_LOOKUP + mixer)];
        s.output = @intToFloat(f64, tone);
    }
};

const Channel = struct {
    period: u12,
    counter: u64,
    waveform: [32]i8,
    volume: u4,
    mute: u1,
    output: i32,
    clock: u32,
    rate: u32,
    const Self = @This();

    fn setWaveform(s: *Self, register: u8, data: u8) void {
        const address = @intCast(usize, register & 0x1F);
        s.waveform[address] = @intCast(i8, data);
    }

    fn setFrequency(s: *Self, register: u8, data: u8) void {
        const d = @intCast(u12, data);
        if ((register & 1) != 0) {
            s.period = (s.period & 0x0FF) | ((d << 8) & 0xF00);
        } else {
            s.period = (s.period & 0xF00) | (d << 0);
        }
        s.counter &= 0xFFFF0000; // Behaviour according to openMSX
    }

    fn setVolume(s: *Self, data: u8) void {
        s.volume = @intCast(u4, data & 0xF);
    }

    fn setMute(s: *Self, data: u8) void {
        s.mute = @intCast(u1, data & 1);
    }

    fn update(s: *Self) void {
        if (s.period < 9) return; // Channel is halted for period < 9

        const volume = s.volume * s.mute;

        // Amuse source:  Cab suggests this method gives greater resolution
        // Sean Young 20010417: the formula is really: f = clock/(16*(f+1))
        const clock = @intCast(i64, s.clock);
        const period = @intToFloat(f64, s.period);
        const rate = @intToFloat(f64, s.rate);

        const clockShifted = @intToFloat(f64, clock * (1 << FREQ_BITS));
        const rateShifted = ((period + 1) * 16 * (rate / 32) + 0.5);
        const step = @floatToInt(u32, clockShifted / rateShifted);

        s.counter += step;
        const address = (s.counter >> FREQ_BITS) & 0x1F;
        s.output = (s.waveform[address] * @intCast(i32, volume)) >> 3;
    }
};
