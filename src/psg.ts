const DECIMATE_FACTOR = 8;
const FIR_SIZE = 192;
const DC_FILTER_SIZE = 1024;

interface Interpolator {
    c: Float64Array;
    y: Float64Array;
}

interface DCFilter {
    sum: number;
    delay: Float64Array;
}

class ToneChannel {
    tonePeriod: number;
    toneCounter: number;
    tone: number;
    tOff: number;
    nOff: number;
    eOn: number;
    volume: number;

    constructor() {
        this.toneCounter = 0;
        this.tonePeriod = 0;
        this.tone = 0;
        this.tOff = 0;
        this.nOff = 0;
        this.eOn = 0;
        this.volume = 0;
    }
}

export default class PSG {
    channels: Array<ToneChannel>;
    registers: Uint8Array;
    noisePeriod: number;
    noiseCounter: number;
    noise: number;
    envelopes: Array<Array<Function>>;
    envelopeCounter: number;
    envelopePeriod: number;
    envelopeShape: number;
    envelopeSegment: number;
    envelope: number;
    dacTable: Float64Array;
    step: number;
    x: number;
    interpolatorOutput: Interpolator;
    firOutput: Float64Array;
    firIndex: number;
    dcOutput: DCFilter;
    dcIndex: number;
    output: Float64Array;

    updateTone(index: number): number {
        const ch = this.channels[index];
        if (++ch.toneCounter >= ch.tonePeriod) {
            ch.toneCounter = 0;
            ch.tone ^= 1;
        }
        return ch.tone;
    }

    updateNoise(): number {
        if (++this.noiseCounter >= (this.noisePeriod << 1)) {
            this.noiseCounter = 0;
            const bit0x3 = ((this.noise ^ (this.noise >> 3)) & 1);
            this.noise = (this.noise >> 1) | (bit0x3 << 16);
        }
        return this.noise & 1;
    }

    slideUp(ic: PSG): void {
        if (++ic.envelope > 31) {
            ic.envelopeSegment ^= 1;
            ic.resetSegment();
        }
    }

    slideDown(ic: PSG): void {
        if (--ic.envelope < 0) {
            ic.envelopeSegment ^= 1;
            ic.resetSegment();
        }
    }

    holdTop(): void {
    }

    holdBottom(): void {
    }

    resetSegment(): void {
        const env = this.envelopes[this.envelopeShape][this.envelopeSegment];
        this.envelope = (env == this.slideDown || env == this.holdTop) ? 31 : 0;
    }

    updateEnvelope(): number {
        if (++this.envelopeCounter >= this.envelopePeriod) {
            this.envelopeCounter = 0;
            this.envelopes[this.envelopeShape][this.envelopeSegment](this);
        }
        return this.envelope;
    }

    updateMixer(sample: number): void {
        let out: number;
        const noise = this.updateNoise();
        const envelope = this.updateEnvelope();
        this.output[sample] = 0;
        for (let i = 0; i < this.channels.length; i++) {
            out = (this.updateTone(i) | this.channels[i].tOff) & (noise | this.channels[i].nOff);
            out *= this.channels[i].eOn ? envelope : this.channels[i].volume * 2 + 1;
            this.output[sample] += this.dacTable[out];
        }
    }

    setTone(index: number, period: number): void {
        period &= 0xfff;
        this.channels[index].tonePeriod = (period == 0 ? 1 : 0) | period;
    }

    setNoise(period: number): void {
        this.noisePeriod = period & 0x1f;
    }

    setMixer(index: number, tOff: number, nOff: number, eOn: number): void {
        this.channels[index].tOff = tOff & 1;
        this.channels[index].nOff = nOff & 1;
        this.channels[index].eOn = eOn;
    }

    setVolume(index: number, volume: number): void {
        this.channels[index].volume = volume & 0xf;
    }

    setEnvelope(period: number): void {
        period &= 0xffff;
        this.envelopePeriod = (period == 0 ? 1 : 0) | period;
    }

    setEnvelopeShape(shape: number): void {
        this.envelopeShape = shape & 0xf;
        this.envelopeCounter = 0;
        this.envelopeSegment = 0;
        this.resetSegment();
    }

    decimate(x: Float64Array): number {
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
        for (let i = 0; i < DECIMATE_FACTOR; i++) {
            x[FIR_SIZE - DECIMATE_FACTOR + i] = x[i];
        }
        return y;
    }

    dcFilter(dc: DCFilter, index: number, x: number): number {
        dc.sum += -dc.delay[index] + x;
        dc.delay[index] = x;
        return x - dc.sum / DC_FILTER_SIZE;
    }

    process(samples: number): void {
        for (let sample = 0; sample < samples; sample++) {
            let y1: number;

            const cOutput = this.interpolatorOutput.c;
            const yOutput = this.interpolatorOutput.y;

            const firOffset = FIR_SIZE - this.firIndex * DECIMATE_FACTOR;
            const firOutput = this.firOutput.subarray(firOffset);

            this.firIndex = (this.firIndex + 1) % (FIR_SIZE / DECIMATE_FACTOR - 1);

            for (let i = DECIMATE_FACTOR - 1; i >= 0; i--) {
                this.x += this.step;
                if (this.x >= 1) {
                    this.x--;

                    yOutput[0] = yOutput[1];
                    yOutput[1] = yOutput[2];
                    yOutput[2] = yOutput[3];

                    this.updateMixer(sample);

                    yOutput[3] = this.output[sample];

                    y1 = yOutput[2] - yOutput[0];
                    cOutput[0] = 0.5 * yOutput[1] + 0.25 * (yOutput[0] + yOutput[2]);
                    cOutput[1] = 0.5 * y1;
                    cOutput[2] = 0.25 * (yOutput[3] - yOutput[1] - y1);
                }
                firOutput[i] = (cOutput[2] * this.x + cOutput[1]) * this.x + cOutput[0];
            }

            this.output[sample] = this.decimate(firOutput);
            this.output[sample] = this.dcFilter(this.dcOutput, this.dcIndex, this.output[sample]);
            this.dcIndex = (this.dcIndex + 1) & (DC_FILTER_SIZE - 1);
        }
    }

    writeRegister(offset: number, data: number): void {
        this.registers[offset] = data;
        this.setTone(0, (this.registers[1] << 8) | this.registers[0]);
        this.setTone(1, (this.registers[3] << 8) | this.registers[2]);
        this.setTone(2, (this.registers[5] << 8) | this.registers[4]);
        this.setNoise(this.registers[6]);
        this.setMixer(0, this.registers[7] & 1, (this.registers[7] >> 3) & 1, this.registers[8] >> 4);
        this.setMixer(1, (this.registers[7] >> 1) & 1, (this.registers[7] >> 4) & 1, this.registers[9] >> 4);
        this.setMixer(2, (this.registers[7] >> 2) & 1, (this.registers[7] >> 5) & 1, this.registers[10] >> 4);
        this.setVolume(0, this.registers[8] & 0xf);
        this.setVolume(1, this.registers[9] & 0xf);
        this.setVolume(2, this.registers[10] & 0xf);
        this.setEnvelope((this.registers[12] << 8) | this.registers[11]);
        if (this.registers[13] != 0xff) this.setEnvelopeShape(this.registers[13]);
    }

    constructor(clockRate: number, sampleRate: number) {
        this.channels = [new ToneChannel(), new ToneChannel(), new ToneChannel()];
        this.registers = new Uint8Array(14);

        this.noisePeriod = 0;
        this.noiseCounter = 0;
        this.noise = 1;

        this.envelopes = [
            [this.slideDown, this.holdBottom],
            [this.slideDown, this.holdBottom],
            [this.slideDown, this.holdBottom],
            [this.slideDown, this.holdBottom],

            [this.slideUp, this.holdBottom],
            [this.slideUp, this.holdBottom],
            [this.slideUp, this.holdBottom],
            [this.slideUp, this.holdBottom],

            [this.slideDown, this.slideDown],
            [this.slideDown, this.holdBottom],
            [this.slideDown, this.slideUp],
            [this.slideDown, this.holdTop],

            [this.slideUp, this.slideUp],
            [this.slideUp, this.holdTop],
            [this.slideUp, this.slideDown],
            [this.slideUp, this.holdBottom]
        ];
        this.envelopeCounter = 0;
        this.envelopePeriod = 0;
        this.envelopeShape = 0;
        this.envelopeSegment = 0;
        this.envelope = 0;
        this.setEnvelope(1);

        // YM2149 DAC table
        this.dacTable = new Float64Array([
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
        ]);

        this.step = clockRate / (sampleRate * 8 * DECIMATE_FACTOR);
        this.x = 0.0;

        this.output = new Float64Array(sampleRate);

        this.interpolatorOutput = {
            c: new Float64Array(4),
            y: new Float64Array(4)
        };

        this.dcOutput = {
            sum: 0.0,
            delay: new Float64Array(DC_FILTER_SIZE)
        };
        this.dcIndex = 0;

        this.firOutput = new Float64Array(FIR_SIZE * 2);
        this.firIndex = 0;

        for (let i = 0; i < this.channels.length; i++) {
            this.setTone(i, 1);
        }
    }
}
