import Pako from "./pako";

interface GD3Tags {
    trackNameEn: string;
    trackNameJp: string;
    gameNameEn: string;
    gameNameJp: string;
    systemNameEn: string;
    systemNameJp: string;
    trackAuthorEn: string;
    trackAuthorJp: string;
    releaseDate: string;
    convertedBy: string;
    notes: string;

    [key: string]: string;
}

interface IArrayBuffer extends ArrayBuffer {
    [key: number]: number;
}

export default class VGM {
    data: DataView;
    version: number;
    eofOffset: number;
    gd3Offset: number;
    totalSamples: number;
    loopOffset: number;
    loopSamples: number;
    rate: number;
    ym2151Clock: number;
    ym2151Multiplier: number;
    vgmDataOffset: number;
    ay8910Clock: number;
    ay8910Type: number;
    ay8910Flags: number;
    ay8910Multiplier: number;
    volumeModifier: number;
    loopBase: number;
    loopModifier: number;
    okim6258Clock: number;
    okim6258Flags: number;
    okim6258Multiplier: number;
    k051649Clock: number;
    k051649Multiplier: number;
    extraHeaderOffset: number;
    gd3Version: number;
    gd3Length: number;
    gd3Tags: GD3Tags;

    constructor(file: ArrayBuffer) {
        let data = new DataView(file);

        // Detect if there is a zlib header then unpack .vgz file
        if (data.getUint8(0) == 0x1F && data.getUint8(1) == 0x8B) {
            const inflated = Pako.inflate(new Uint8Array(file));
            const buffer = new ArrayBuffer(inflated.length) as IArrayBuffer;
            const ui8buf = new Uint8Array(buffer);
            inflated.map((byte, i) => ui8buf[i] = byte);
            data = new DataView(buffer);
        }

        if (data.getUint8(0) != "V".charCodeAt(0) ||
            data.getUint8(1) != "g".charCodeAt(0) ||
            data.getUint8(2) != "m".charCodeAt(0) ||
            data.getUint8(3) != " ".charCodeAt(0)) {
            throw "Invalid VGM ident!";
        }

        this.version = data.getUint32(0x08, true);
        if (this.version < 0x150) throw "Only VGM 1.50+ files supported!";

        this.eofOffset = data.getUint32(0x04, true);
        this.gd3Offset = data.getUint32(0x14, true);
        this.totalSamples = data.getUint32(0x18, true);
        this.loopOffset = data.getUint32(0x1C, true);
        this.loopSamples = data.getUint32(0x20, true);
        this.rate = data.getUint32(0x24, true);
        this.ym2151Clock = data.getUint32(0x30, true);
        this.ym2151Multiplier = this.ym2151Clock ? 1 : 0;
        this.vgmDataOffset = data.getUint32(0x34, true);
        this.ay8910Clock = this.version >= 0x151 ? data.getUint32(0x74, true) : 0;
        this.ay8910Type = this.version >= 0x151 ? data.getUint8(0x78) : 0;
        this.ay8910Flags = this.version >= 0x151 ? data.getUint8(0x79) : 0;
        this.ay8910Multiplier = this.ay8910Clock ? 1 : 0;
        this.volumeModifier = this.version >= 0x160 ? data.getUint8(0x7C) : 0;
        this.loopBase = this.version >= 0x160 ? data.getUint8(0x7E) : 0;
        this.loopModifier = this.version >= 0x151 ? data.getUint8(0x7F) : 0;
        this.okim6258Clock = this.version >= 0x161 ? data.getUint32(0x90, true) : 0;
        this.okim6258Flags = this.version >= 0x161 ? data.getUint8(0x94) : 0;
        this.okim6258Multiplier = this.okim6258Clock ? 1 : 0;
        this.k051649Clock = this.version >= 0x161 ? data.getUint32(0x9C, true) : 0;
        this.k051649Multiplier = this.k051649Clock ? 1 : 0;
        this.extraHeaderOffset = this.version >= 0x170 ? data.getUint32(0xBC, true) : 0;

        // If bit 31 is set to 1, clear the bit from the clock and enable dual-chip support
        if (this.ym2151Clock & 0x40000000) {
            this.ym2151Clock &= 0xBFFFFFFF;
            this.ym2151Multiplier = 2;
        }
        if (this.ay8910Clock & 0x40000000) {
            this.ay8910Clock &= 0xBFFFFFFF;
            this.ay8910Multiplier = 2;
        }
        if (this.okim6258Clock & 0x40000000) {
            this.okim6258Clock &= 0xBFFFFFFF;
            this.okim6258Multiplier = 2;
        }
        if (this.k051649Clock & 0x40000000) {
            this.k051649Clock &= 0xBFFFFFFF;
            this.k051649Multiplier = 2;
        }

        this.gd3Version = 0;
        this.gd3Length = 0;
        this.gd3Tags = {
            trackNameEn: "",
            trackNameJp: "",
            gameNameEn: "",
            gameNameJp: "",
            systemNameEn: "",
            systemNameJp: "",
            trackAuthorEn: "",
            trackAuthorJp: "",
            releaseDate: "",
            convertedBy: "",
            notes: ""
        };

        if (this.gd3Offset) {
            // Pad the relative gd3Offset by its own location in the file
            const offset = this.gd3Offset + 0x14;

            if (data.getUint8(offset + 0) != "G".charCodeAt(0) ||
                data.getUint8(offset + 1) != "d".charCodeAt(0) ||
                data.getUint8(offset + 2) != "3".charCodeAt(0) ||
                data.getUint8(offset + 3) != " ".charCodeAt(0)) {
                throw "Invalid GD3 ident!";
            }

            this.gd3Version = data.getUint32(offset + 4, true);
            this.gd3Length = data.getUint32(offset + 8, true);

            const tags = Object.keys(this.gd3Tags);
            for (let i = 0, name = 0; i < this.gd3Length; i += 2) {
                const char = data.getUint16(offset + 12 + i, true);

                if (char == 0) name++;
                else this.gd3Tags[tags[name]] += String.fromCharCode(char);
            }
        }

        this.data = data;
    }
}
