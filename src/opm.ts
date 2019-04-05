export default class OPM {
    clock: number;
    outputLeft: Float64Array;
    outputRight: Float64Array;
    outputRate: number;

    process(samples: number): void {
        this.outputLeft[0] = samples;
        this.outputRight[0] = samples;
    }

    writeRegister(offset: number, data: number): void {
        this.clock = offset;
        this.outputRate = data;
    }

    constructor(clock: number, sampleRate: number) {
        this.clock = clock;
        this.outputLeft = new Float64Array(sampleRate);
        this.outputRight = new Float64Array(sampleRate);
        this.outputRate = sampleRate;
    }
}