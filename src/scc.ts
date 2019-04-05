const FREQ_BITS = 16;
const DEF_GAIN = 8;

class Channel {
    key: number;
    volume: number;
    counter: number;
    frequency: number;
    waveram: Array<number>;

    constructor() {
        this.key = 0;
        this.volume = 0;
        this.counter = 0;
        this.frequency = 0;
        this.waveram = new Array<number>(32);
    }
}

export default class SCC {
    voice: Array<Channel>;
    rate: number;
    clock: number;

    output: Float64Array;

    mixerTable: Int16Array;
    mixerLookup: number;

    test: number;
    currentRegister: number;

    process(samples: number): void {
        const mixerBuffer = new Int16Array(this.output.length);

        for (let channel = 0; channel < 5; channel++) {
            const frequency = this.voice[channel].frequency;

            // Channel is halted for frequency < 9
            if (frequency > 8) {
                const waveram = this.voice[channel].waveram;
                const volume = this.voice[channel].volume * this.voice[channel].key;
                let counter = this.voice[channel].counter;

                const step = ((this.clock * (1 << FREQ_BITS)) / ((frequency + 1) * 16 * (this.rate / 32)) + 0.5);

                for (let i = 0; i < samples; i++) {
                    counter += step;
                    const offset = (counter >> FREQ_BITS) & 0x1F;
                    mixerBuffer[i] += (waveram[offset] * volume) >> 3;
                }

                this.voice[channel].counter = counter;
            }
        }

        for (let i = 0; i < samples; i++) {
            mixerBuffer[i] = this.mixerTable[this.mixerLookup + mixerBuffer[i]];
            this.output[i] = mixerBuffer[i] / 32768;
        }
    }

    setWaveform(offset: number, data: number): void {
        // Is RAM read-only?
        if (this.test & 0x40 || (this.test & 0x80 && offset >= 0x60)) return;

        if (offset >= 0x60) {
            // Channel 5 shares RAM with channel 4
            this.voice[3].waveram[offset & 0x1F] = data;
            this.voice[4].waveram[offset & 0x1F] = data;
        } else this.voice[offset >> 5].waveram[offset & 0x1F] = data;
    }

    getWaveform(offset: number): number {
        // Test register bits 6/7 expose the internal counter
        if (this.test & 0xC0) {
            if (offset >= 0x60)
                offset += (this.voice[3 + (this.test >> 6 & 1)].counter >> FREQ_BITS);
            else if (this.test & 0x40)
                offset += (this.voice[offset >> 5].counter >> FREQ_BITS);
        }

        return this.voice[offset >> 5].waveram[offset & 0x1F];
    }

    setWaveformPlus(offset: number, data: number): void {
        // Is RAM read-only?
        if (this.test & 0x40) return;

        this.voice[offset >> 5].waveram[offset & 0x1F] = data;
    }

    getWaveformPlus(offset: number): number {
        // Test register bit 6 exposes the internal counter
        if (this.test & 0x40)
            offset += (this.voice[offset >> 5].counter >> FREQ_BITS);

        return this.voice[offset >> 5].waveram[offset & 0x1F];
    }

    setVolume(offset: number, data: number): void {
        this.voice[offset & 0x7].volume = data & 0xF;
    }

    setFrequency(offset: number, data: number): void {
        const channel = this.voice[offset >> 1];

        // Test register bit 5 resets the internal counter
        if (this.test & 0x20)
            channel.counter = ~0;
        else if (channel.frequency < 9)
            channel.counter |= ((1 << FREQ_BITS) - 1);

        if (offset & 1)
            channel.frequency = (channel.frequency & 0x0FF) | ((data << 8) & 0xF00);
        else
            channel.frequency = (channel.frequency & 0xF00) | (data << 0);

        // Valley Bell: Behaviour according to OpenMSX
        channel.counter &= 0xFFFF0000;
    }

    setKeyOnOff(data: number): void {
        for (let channel = 0; channel < 5; channel++) {
            this.voice[channel].key = data & 1;
            data >>= 1;
        }
    }

    setTest(data: number): void {
        this.test = data;
    }

    getTest(): number {
        // Reading the test register sets it to 0xFF
        this.setTest(0xFF);
        return 0xFF;
    }

    writeRegister(offset: number, data: number): void {
        switch (offset & 1) {
            case 0x00:
                this.currentRegister = data;
                break;
            case 0x01:
                switch (offset >> 1) {
                    case 0x00:
                        this.setWaveform(this.currentRegister, data);
                        break;
                    case 0x01:
                        this.setFrequency(this.currentRegister, data);
                        break;
                    case 0x02:
                        this.setVolume(this.currentRegister, data);
                        break;
                    case 0x03:
                        this.setKeyOnOff(data);
                        break;
                    case 0x04:
                        this.setWaveformPlus(this.currentRegister, data);
                        break;
                    case 0x05:
                        this.setTest(data);
                        break;
                }
                break;
        }
    }

    constructor(clock: number, sampleRate: number) {
        this.voice = [
            new Channel(),
            new Channel(),
            new Channel(),
            new Channel(),
            new Channel()
        ];

        this.clock = clock & 0x7FFFFFFF;
        this.rate = this.clock / 16;

        this.output = new Float64Array(sampleRate);

        this.mixerTable = new Int16Array(2561);
        this.mixerLookup = 1280;

        for (let i = 0; i < 1281; i++) {
            let val = i * DEF_GAIN * 16 / 5;
            if (val > 32768) val = 32768;
            this.mixerTable[this.mixerLookup + i] = val;
            this.mixerTable[this.mixerLookup - i] = -val;
        }

        this.currentRegister = 0;
        this.test = 0;
    }
}
