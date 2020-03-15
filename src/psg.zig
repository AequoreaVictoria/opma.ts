const DECIMATE_FACTOR = 8;
const FIR_SIZE = 192;
const DC_FILTER_SIZE = 1024;

pub const Chip = struct {
    register: [14]u16,
    tone: [3]ToneChannel,
    noise: NoiseChannel,
    envelope: Envelope,
    firFilter: FIRFilter,
    dcFilter: DCFilter,
    dacTable: [32]f64,
    step: f64,
    x: f64,
    output: f64,
    const Self = @This();

    pub fn init(clockRate: u32, sampleRate: u32) Self {
        return Self {
            .register = [_]u16{0} ** 14,
            .tone = [_]ToneChannel {
                ToneChannel {
                    .period = 1,
                    .counter = 0,
                    .tone = 0,
                    .volume = 0,
                    .tOff = 0,
                    .nOff = 0,
                    .eOn = 0,
                }
            } ** 3,
            .noise = NoiseChannel {
                .period = 0,
                .counter = 0,
                .noise = 1,
            },
            .envelope = Envelope {
                .period = 1,
                .counter = 0,
                .envelope = 0,
                .shape = 0,
                .segment = 0,
                .table = [16][2]fn(*Envelope) void {
                    [2]fn(*Envelope) void {Envelope.slideDown, Envelope.holdBottom},
                    [2]fn(*Envelope) void {Envelope.slideDown, Envelope.holdBottom},
                    [2]fn(*Envelope) void {Envelope.slideDown, Envelope.holdBottom},
                    [2]fn(*Envelope) void {Envelope.slideDown, Envelope.holdBottom},

                    [2]fn(*Envelope) void {Envelope.slideUp, Envelope.holdBottom},
                    [2]fn(*Envelope) void {Envelope.slideUp, Envelope.holdBottom},
                    [2]fn(*Envelope) void {Envelope.slideUp, Envelope.holdBottom},
                    [2]fn(*Envelope) void {Envelope.slideUp, Envelope.holdBottom},

                    [2]fn(*Envelope) void {Envelope.slideDown, Envelope.slideDown},
                    [2]fn(*Envelope) void {Envelope.slideDown, Envelope.holdBottom},
                    [2]fn(*Envelope) void {Envelope.slideDown, Envelope.slideUp},
                    [2]fn(*Envelope) void {Envelope.slideDown, Envelope.holdTop},

                    [2]fn(*Envelope) void {Envelope.slideUp, Envelope.slideUp},
                    [2]fn(*Envelope) void {Envelope.slideUp, Envelope.holdTop},
                    [2]fn(*Envelope) void {Envelope.slideUp, Envelope.slideDown},
                    [2]fn(*Envelope) void {Envelope.slideUp, Envelope.holdBottom},
                },
            },
            .firFilter = FIRFilter {
                .interpolator = FIRFilter.Interpolator {
                    .c = [_]f64{0} ** 4,
                    .y = [_]f64{0} ** 4,
                },
                .output = [_]f64{0} ** (FIR_SIZE * 2),
                .index = 0,
                .result = 0.0,
            },
            .dcFilter = DCFilter {
                .output = DCFilter.DCOutput {
                    .sum = 0.0,
                    .delay = [_]f64{0} ** DC_FILTER_SIZE,
                },
                .index = 0,
                .result = 0.0,
            },
            .dacTable = [32]f64 { // YM2149 DAC Table
                0.0, 0.0,
                0.00465400167849, 0.00772106507973,
                0.0109559777218, 0.0139620050355,
                0.0169985503929, 0.0200198367285,
                0.024368657969, 0.029694056611,
                0.0350652323186, 0.0403906309606,
                0.0485389486534, 0.0583352407111,
                0.0680552376593, 0.0777752346075,
                0.0925154497597, 0.111085679408,
                0.129747463188, 0.148485542077,
                0.17666895552, 0.211551079576,
                0.246387426566, 0.281101701381,
                0.333730067903, 0.400427252613,
                0.467383840696, 0.53443198291,
                0.635172045472, 0.75800717174,
                0.879926756695, 1.0
            },
            .step = @intToFloat(f64, clockRate) / @intToFloat(f64, (sampleRate * 8 * DECIMATE_FACTOR)),
            .x = 0.0,
            .output = 0,
        };
    }

    pub fn writeRegister(s: *Self, offset: u8, data: u8) void {
        var r = &(s.register);
        var t0 = &(s.tone[0]);
        var t1 = &(s.tone[1]);
        var t2 = &(s.tone[2]);

        r[offset] = data;

        t0.setTone((r[1] << 8) | r[0]);
        t1.setTone((r[3] << 8) | r[2]);
        t2.setTone((r[5] << 8) | r[4]);

        s.noise.setNoise(r[6]);

        t0.setMixer(r[7] & 1, (r[7] >> 3) & 1, r[8] >> 4);
        t1.setMixer((r[7] >> 1) & 1, (r[7] >> 4) & 1, r[9] >> 4);
        t2.setMixer((r[7] >> 2) & 1, (r[7] >> 5) & 1, r[10] >> 4);

        t0.setVolume(r[8] & 0xf);
        t1.setVolume(r[9] & 0xf);
        t2.setVolume(r[10] & 0xf);

        s.envelope.setEnvelope((r[12] << 8) | r[11]);
        if (r[13] != 0xff) s.envelope.setEnvelopeShape(r[13]);
    }

    pub fn process(s: *Self) void {
        var fir = &(s.firFilter);
        var c = fir.interpolator.c;
        var y = fir.interpolator.y;
        var y1: f64 = undefined;
        var output = fir.output[(FIR_SIZE - fir.index * DECIMATE_FACTOR) .. fir.output.len];
        fir.index = (fir.index + 1) % (FIR_SIZE / DECIMATE_FACTOR - 1);

        var i: usize = DECIMATE_FACTOR - 1;
        while (true) {
            s.x += s.step;
            if (s.x >= 1) {
                s.x -= 1;

                y[0] = y[1];
                y[1] = y[2];
                y[2] = y[3];

                s.noise.update();
                s.envelope.update();
                s.output = 0;

                var channel: usize = 0;
                while (channel < 3) : (channel += 1) {
                    const t = &(s.tone[channel]);
                    t.update();
                    var out = (t.tone | t.tOff) & ((s.noise.noise & 1) | t.nOff);
                    out *= if (t.eOn != 0) s.envelope.envelope else t.volume * 2 + 1;
                    s.output += s.dacTable[@intCast(usize, out)];
                }

                y[3] = s.output;
                y1 = y[2] - y[0];

                c[0] = 0.5 * y[1] + 0.25 * (y[0] + y[2]);
                c[1] = 0.5 * y1;
                c[2] = 0.25 * (y[3] - y[1] - y1);
            }
            output[i] = (c[2] * s.x + c[1]) * s.x + c[0];

            if (i == 0) break;
            i -= 1;
        }
        fir.decimate(output);
        s.output = fir.result;
    }

    pub fn removeDc(s: *Self) void {
        s.dcFilter.process(s.output);
        s.output = s.dcFilter.result;
    }
};

const ToneChannel = struct {
    period: i32,
    counter: i32,
    tone: i32,
    tOff: i32,
    nOff: i32,
    eOn: i32,
    volume: i32,
    const Self = @This();

    fn setTone(s: *Self, period: i32) void {
        const newPeriod = period & 0xfff;
        const p: i32 = if (newPeriod == 0) 1 else 0;
        s.period = p | newPeriod;
    }

    fn setMixer(s: *Self, tOff: i32, nOff: i32, eOn: i32) void {
        s.tOff = tOff & 1;
        s.nOff = nOff & 1;
        s.eOn = eOn;
    }

    fn setVolume(s: *Self, volume: i32) void {
        s.volume = volume & 0xf;
    }

    fn update(s: *Self) void {
        s.counter += 1;
        if (s.counter >= s.period) {
            s.counter = 0;
            s.tone ^= 1;
        }
    }
};

const NoiseChannel = struct {
    period: i32,
    counter: i32,
    noise: i32,
    const Self = @This();

    fn setNoise(s: *Self, period: i32) void {
        s.period = period & 0x1f;
    }

    fn update(s: *Self) void {
        s.counter += 1;
        if (s.counter >= (s.period << 1)) {
            s.counter = 0;
            const bit0x3 = ((s.noise ^ (s.noise >> 3)) & 1);
            s.noise = (s.noise >> 1) | (bit0x3 << 16);
        }
    }
};

const Envelope = struct {
    period: i32,
    counter: i32,
    envelope: i32,
    shape: i32,
    segment: i32,
    table: [16][2]fn(*Self) void,
    const Self = @This();

    fn setEnvelope(s: *Self, period: i32) void {
        const newPeriod = period & 0xffff;
        const p: i32 = if (newPeriod == 0) 1 else 0;
        s.period = p | newPeriod;
    }

    fn setEnvelopeShape(s: *Self, shape: i32) void {
        s.shape = shape & 0xf;
        s.counter = 0;
        s.segment = 0;
        resetSegment(s);
    }

    fn resetSegment(s: *Self) void {
        const envelope = s.table[@intCast(usize, s.shape)][@intCast(usize, s.segment)];
        const slideDownPtr = @ptrToInt(envelope) == @ptrToInt(slideDown);
        const holdTopPtr = @ptrToInt(envelope) == @ptrToInt(holdTop);
        s.envelope = if (slideDownPtr or holdTopPtr) 31 else 0;
    }

    fn slideUp(s: *Self) void {
        s.envelope += 1;
        if (s.envelope > 31) {
            s.segment ^= 1;
            resetSegment(s);
        }
    }

    fn slideDown(s: *Self) void {
        s.envelope -= 1;
        if (s.envelope < 0) {
            s.segment ^= 1;
            resetSegment(s);
        }
    }

    fn holdTop(s: *Self) void {}

    fn holdBottom(s: *Self) void {}

    fn update(s: *Self) void {
        s.counter += 1;
        if (s.counter >= s.period) {
            s.counter = 0;
            const envelope = s.table[@intCast(usize, s.shape)][@intCast(usize, s.segment)];
            envelope(s);
        }
    }
};

const FIRFilter = struct {
    interpolator: Interpolator,
    output: [FIR_SIZE * 2]f64,
    index: usize,
    result: f64,
    const Self = @This();

    const Interpolator = struct {
        c: [4]f64,
        y: [4]f64,
    };

    fn decimate(s: *Self, x: []f64) void {
        const y = -0.0000046183113992051936 * (x[1] + x[191]) +
            -0.00001117761640887225 * (x[2] + x[190]) +
            -0.000018610264502005432 * (x[3] + x[189]) +
            -0.000025134586135631012 * (x[4] + x[188]) +
            -0.000028494281690666197 * (x[5] + x[187]) +
            -0.000026396828793275159 * (x[6] + x[186]) +
            -0.000017094212558802156 * (x[7] + x[185]) +
            0.000023798193576966866 * (x[9] + x[183]) +
            0.000051281160242202183 * (x[10] + x[182]) +
            0.00007762197826243427 * (x[11] + x[181]) +
            0.000096759426664120416 * (x[12] + x[180]) +
            0.00010240229300393402 * (x[13] + x[179]) +
            0.000089344614218077106 * (x[14] + x[178]) +
            0.000054875700118949183 * (x[15] + x[177]) +
            -0.000069839082210680165 * (x[17] + x[175]) +
            -0.0001447966132360757 * (x[18] + x[174]) +
            -0.00021158452917708308 * (x[19] + x[173]) +
            -0.00025535069106550544 * (x[20] + x[172]) +
            -0.00026228714374322104 * (x[21] + x[171]) +
            -0.00022258805927027799 * (x[22] + x[170]) +
            -0.00013323230495695704 * (x[23] + x[169]) +
            0.00016182578767055206 * (x[25] + x[167]) +
            0.00032846175385096581 * (x[26] + x[166]) +
            0.00047045611576184863 * (x[27] + x[165]) +
            0.00055713851457530944 * (x[28] + x[164]) +
            0.00056212565121518726 * (x[29] + x[163]) +
            0.00046901918553962478 * (x[30] + x[162]) +
            0.00027624866838952986 * (x[31] + x[161]) +
            -0.00032564179486838622 * (x[33] + x[159]) +
            -0.00065182310286710388 * (x[34] + x[158]) +
            -0.00092127787309319298 * (x[35] + x[157]) +
            -0.0010772534348943575 * (x[36] + x[156]) +
            -0.0010737727700273478 * (x[37] + x[155]) +
            -0.00088556645390392634 * (x[38] + x[154]) +
            -0.00051581896090765534 * (x[39] + x[153]) +
            0.00059548767193795277 * (x[41] + x[151]) +
            0.0011803558710661009 * (x[42] + x[150]) +
            0.0016527320270369871 * (x[43] + x[149]) +
            0.0019152679330965555 * (x[44] + x[148]) +
            0.0018927324805381538 * (x[45] + x[147]) +
            0.0015481870327877937 * (x[46] + x[146]) +
            0.00089470695834941306 * (x[47] + x[145]) +
            -0.0010178225878206125 * (x[49] + x[143]) +
            -0.0020037400552054292 * (x[50] + x[142]) +
            -0.0027874356824117317 * (x[51] + x[141]) +
            -0.003210329988021943 * (x[52] + x[140]) +
            -0.0031540624117984395 * (x[53] + x[139]) +
            -0.0025657163651900345 * (x[54] + x[138]) +
            -0.0014750752642111449 * (x[55] + x[137]) +
            0.0016624165446378462 * (x[57] + x[135]) +
            0.0032591192839069179 * (x[58] + x[134]) +
            0.0045165685815867747 * (x[59] + x[133]) +
            0.0051838984346123896 * (x[60] + x[132]) +
            0.0050774264697459933 * (x[61] + x[131]) +
            0.0041192521414141585 * (x[62] + x[130]) +
            0.0023628575417966491 * (x[63] + x[129]) +
            -0.0026543507866759182 * (x[65] + x[127]) +
            -0.0051990251084333425 * (x[66] + x[126]) +
            -0.0072020238234656924 * (x[67] + x[125]) +
            -0.0082672928192007358 * (x[68] + x[124]) +
            -0.0081033739572956287 * (x[69] + x[123]) +
            -0.006583111539570221 * (x[70] + x[122]) +
            -0.0037839040415292386 * (x[71] + x[121]) +
            0.0042781252851152507 * (x[73] + x[119]) +
            0.0084176358598320178 * (x[74] + x[118]) +
            0.01172566057463055 * (x[75] + x[117]) +
            0.013550476647788672 * (x[76] + x[116]) +
            0.013388189369997496 * (x[77] + x[115]) +
            0.010979501242341259 * (x[78] + x[114]) +
            0.006381274941685413 * (x[79] + x[113]) +
            -0.007421229604153888 * (x[81] + x[111]) +
            -0.01486456304340213 * (x[82] + x[110]) +
            -0.021143584622178104 * (x[83] + x[109]) +
            -0.02504275058758609 * (x[84] + x[108]) +
            -0.025473530942547201 * (x[85] + x[107]) +
            -0.021627310017882196 * (x[86] + x[106]) +
            -0.013104323383225543 * (x[87] + x[105]) +
            0.017065133989980476 * (x[89] + x[103]) +
            0.036978919264451952 * (x[90] + x[102]) +
            0.05823318062093958 * (x[91] + x[101]) +
            0.079072012081405949 * (x[92] + x[100]) +
            0.097675998716952317 * (x[93] + x[99]) +
            0.11236045936950932 * (x[94] + x[98]) +
            0.12176343577287731 * (x[95] + x[97]) +
            0.125 * x[96];
        var i: usize = 0;
        while (i < DECIMATE_FACTOR) : (i += 1) { x[FIR_SIZE - DECIMATE_FACTOR + i] = x[i]; }
        s.result = y;
    }
};

const DCFilter = struct {
    output: DCOutput,
    index: usize,
    result: f64,
    const Self = @This();

    const DCOutput = struct {
        sum: f64,
        delay: [DC_FILTER_SIZE]f64,
    };

    fn process(s: *Self, x: f64) void {
        s.output.sum += -s.output.delay[s.index] + x;
        s.output.delay[s.index] = x;
        s.result = x - s.output.sum / DC_FILTER_SIZE;
        s.index = (s.index + 1) & (DC_FILTER_SIZE - 1);
    }
};
