export default class PCM {
    clock: number;
    output: Float64Array;
    outputRate: number;

    process(samples: number): void {
        this.output[0] = samples;
    }

    writeRegister(offset: number, data: number): void {
        this.clock = offset;
        this.outputRate = data;
    }

    constructor(clock: number, sampleRate: number) {
        this.clock = clock;
        this.output = new Float64Array(sampleRate);
        this.outputRate = sampleRate;
    }
}