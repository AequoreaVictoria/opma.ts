import PSG from "./psg";
import SCC from "./scc";
import OPM from "./opm";
import PCM from "./pcm";
import VGM from "./vgm";

const BUFFER_SIZE = 4096;
const MASTER_RATE = 44100;

interface State {
    loopCount: number,
    currentLoop: number,
    vgmPosition: number,
    remainingWait: number,
    sampleRate: number
}

interface Chips {
    PSG: PSG,
    SCC: SCC,
    OPM: OPM,
    PCM: PCM
}

function runCommand(ic: Chips, vgm: VGM, state: State): number {
    const command = vgm.data.getUint8(state.vgmPosition);
    let wait = 0;

    if (command == 0xA0) {
        // PSG write
        const register = vgm.data.getUint8(state.vgmPosition + 1);
        const data = vgm.data.getUint8(state.vgmPosition + 2);
        ic.PSG.writeRegister(register, data);
        state.vgmPosition += 3;
    } else if (command == 0xD2) {
        // SSC write
        const port = vgm.data.getUint8(state.vgmPosition + 1);
        const register = vgm.data.getUint8(state.vgmPosition + 2);
        const data = vgm.data.getUint8(state.vgmPosition + 3);
        ic.SCC.writeRegister((port << 1) | 0x00, register);
        ic.SCC.writeRegister((port << 1) | 0x01, data);
        state.vgmPosition += 4;
    } else if (command == 0x54) {
        // OPM write
        const register = vgm.data.getUint8(state.vgmPosition + 1);
        const data = vgm.data.getUint8(state.vgmPosition + 2);
        ic.OPM.writeRegister(0x00, register);
        ic.OPM.writeRegister(0x01, data);
        state.vgmPosition += 3;
    } else if (command == 0xB7) {
        // PCM write
        const register = vgm.data.getUint8(state.vgmPosition + 1);
        const data = vgm.data.getUint8(state.vgmPosition + 2);
        ic.PCM.writeRegister(register, data);
        state.vgmPosition += 3
    } else if (command == 0x67) {
        // PCM data load
        const size = vgm.data.getUint32(state.vgmPosition + 2, true);
        // Do something to get PCM data at vgmPosition + 6...
        state.vgmPosition += 6 + size;
    } else if (command == 0x61) {
        // Wait X samples
        wait = vgm.data.getUint16(state.vgmPosition + 1, true);
        state.vgmPosition += 3;
    } else if (command == 0x62) {
        // Wait 60TH of a second
        wait = 735;
        state.vgmPosition += 1;
    } else if (command == 0x63) {
        // Wait 50TH of a second
        wait = 882;
        state.vgmPosition += 1;
    } else if (command >= 0x70 && command <= 0x7F) {
        // Wait 1 sample ... Wait 16 samples
        wait = (command & 0x0F) + 1;
        state.vgmPosition += 1;
    } else if (command == 0x66) {
        // End of data
        if (vgm.loopOffset && (state.currentLoop <= state.loopCount)) {
            state.vgmPosition = vgm.loopOffset + 0x1C;
            state.currentLoop++;
        } else wait = -1;
    } else {
        console.log(`Unknown command ${command} at ${state.vgmPosition}`);
        state.vgmPosition += 1;
    }

    return wait;
}

function getBuffer(event: AudioProcessingEvent, ic: Chips, vgm: VGM, state: State, node: ScriptProcessorNode): boolean {
    const left = event.outputBuffer.getChannelData(0);
    const right = event.outputBuffer.getChannelData(1);
    let bufPosition = 0;

    while (true) {
        let wait;
        if (state.remainingWait == 0) {
            wait = runCommand(ic, vgm, state);
            if (wait == -1) {
                // End of playback
                node.disconnect();
                return false;
            }
        } else {
            wait = state.remainingWait;
            state.remainingWait = 0;
        }

        if (wait + bufPosition >= BUFFER_SIZE) {
            state.remainingWait = (wait + bufPosition) - BUFFER_SIZE;
            wait = BUFFER_SIZE - bufPosition;
        }

        if (wait > 0) {
            if (vgm.ay8910Clock) ic.PSG.process(wait);
            if (vgm.k051649Clock) ic.SCC.process(wait);
            if (vgm.ym2151Clock) ic.OPM.process(wait);
            if (vgm.okim6258Clock) ic.PCM.process(wait);

            for (let i = 0; i < wait; i++) {
                let leftSample = 0.0;
                let rightSample = 0.0;

                if (vgm.ay8910Clock) {
                    leftSample += ic.PSG.output[i];
                    rightSample += ic.PSG.output[i];
                }
                if (vgm.k051649Clock) {
                    //leftSample += ic.SCC.output[i];
                    //rightSample += ic.SCC.output[i];
                }
                if (vgm.ym2151Clock) {
                    //leftSample += ic.OPM.output[i];
                    //rightSample += ic.OPM.output[i];
                }
                if (vgm.okim6258Clock) {
                    //leftSample += ic.OPM.output[i];
                    //rightSample += ic.OPM.output[i];
                }

                left[bufPosition + i] = leftSample;
                right[bufPosition + i] = rightSample;
            }
            bufPosition += wait;
        }

        if (bufPosition >= BUFFER_SIZE) return true;
    }
}

function Player(vgm: VGM, audioContext: AudioContext, loopCount: number) {
    if (!vgm.ay8910Clock && !vgm.k051649Clock && !vgm.ym2151Clock && !vgm.okim6258Clock)
        throw "No supported chips! Sorry, only AY8910, & K051649, YM2151 & OKIM6258 are supported!";

    if (vgm.ay8910Multiplier > 1 || vgm.k051649Multiplier > 1 || vgm.ym2151Multiplier > 1 || vgm.okim6258Multiplier > 1)
        throw "Sorry, dual chip support hasn't been implemented yet!";

    const ic: Chips = {
        PSG: new PSG(vgm.ay8910Clock, MASTER_RATE),
        SCC: new SCC(vgm.k051649Clock, MASTER_RATE),
        OPM: new OPM(vgm.ym2151Clock, MASTER_RATE),
        PCM: new PCM(vgm.okim6258Clock, MASTER_RATE)
    };

    const state: State = {
        loopCount: loopCount,
        currentLoop: 0,
        vgmPosition: 0x34 + vgm.vgmDataOffset,
        remainingWait: 0,
        sampleRate: audioContext.sampleRate
    };

    const audioNode = audioContext.createScriptProcessor(BUFFER_SIZE, 0, 2);
    audioNode.onaudioprocess = (event) => getBuffer(event, ic, vgm, state, audioNode);
    audioNode.connect(audioContext.destination);
}

export default Player;
