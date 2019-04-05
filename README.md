# OPMA.ts
> A TypeScript library for a fictional sound chip

The OPMA is a fictional sound chip inspired by the [Yamaha OPNA (YM2608)][0], a
sound chip notably used in [NEC PC-88][1] and [NEC PC-98][2] computers. It is a
preferred instrument of composer [Yuzo Koshiro][3] among other aficionados. The
OPNA features 16 channels:
 
* Six 4-operator FM synthesis channels ([YM2203/Operator Type-N][4])
* Three square/noise channels ([YM2149][5])
* One general purpose 8-bit/16Khz ADPCM channel
* Six additional ADPCM channels locked to samples from an integrated ROM.

In contrast, the OPMA provides 24 channels:
 
* Eight 4-operator FM synthesis channels ([YM2151/Operator Type-M][6])
* Three square/noise channels ([YM2149][5])
* Five 8-bit wavetable channels ([Konami SCC+][7])
* Eight general purpose 8-bit/22Khz ADPCM channels (OKIM6258)

Currently OKIM6258 is limited to a single ADPCM channel, but should be extended
to eight in the future.

This combination of channels have never been completely combined before in a
system, but some combinations do have historical precedents:

* [MSX][8]: [YM2149][5] + [Konami SCC][7]
* [Sharp X1 Turbo][10]: [YM2151][6] + [YM2149][5]
* [Sharp X68000][9]: [YM2151][6] + OKIM6258

While Yamaha has released two [MSX][8] machines featuring a [YM2149][5] and
[YM2151][6], as far as I am aware no music has been composed with a [YM2151][6]
and [Konami SCC+][7] together. The selection of the OKIM6258 was purely for
compatibility with the [Sharp X68000][9] music scene and its notable support
for eight ADPCM channels via software mixing.
 
This library currently provides a [VGM][11] player that supports any music from
computers, consoles and arcade boards that make use of the above chips. Many
tracks are currently available for download from [VGMRips.net][11]. The
[YM2149][5] is fully compatible with [AY-3-8910][5] tracks available. The
[Konami SCC+][7] compatible tracks are listed as either 'K051649' or 'K052539'.
There are many more formats for these chips out there and some even have tools
for converting them to [VGM][11] format, which was used due to pre-existing
support of these four chips.

In the future [MML][12] playback support will be provided as well. 

It is distributed as a minified ES6 module in the `dist/` directory, under an
[MIT License][13]. See `LICENSE.md` for more details.

## Chips & Credits
The emulation of these components is based upon prior work:

* [YM2149][5] is based on [Ayumi][14].
* [Konami SCC][7] is based on [MAME][15].
* [YM2151][6] is based on [FMGen][16].
* OKIM6258 is based on [MAME][15].

## Compiling
If needed, this library is built with [Node.js][17] and [Gulp][18]:

``` Shell
$ npm install
$ gulp
```

## Usage
OPMA.ts provides a `loadVGM()` constructor and a `playVGM()` function.

* `readVGM(vgm: ArrayBuffer)`

The `loadVGM()` constructor takes an ArrayBuffer and returns a parsed [VGM][11]
object.

Consult `src/vgm.ts` for all the properties provided by the [VGM][11] object.
The [VGM 1.71 Specification][19] will explain each property and is included as
`vgmspec171.txt`.

* `playVGM(vgm: VGM, context: AudioContext, loopCount: integer)`

The `playVGM()` function takes a [VGM][11] object, the AudioContext and a loop
count. It will begin playback.

## Example
This example demonstrates fetching a remote VGZ file, parsing it, displaying
its metadata, playing it and handling any errors encountered:

```html
<div id="Main">
    <h1 class="track-name"></h1>
    <h2 class="author-name"></h2>
    <h2 class="game-name"></h2>
    <h3 class="system-name"></h3>
    <h4 class="release-date"></h4>
    <h1 class="error-msg"></h1>
    <button id="Play">CLICK TO PLAY</button>
</div>
```

```javascript
import OPMA from "opma";

let audioContext;
let vgm;

function loadVGM(file) {
    fetch(file).then((response) => {
        response.arrayBuffer().then(function(buffer) {
            try {
                vgm = new OPMA.loadVGM(buffer);
                document.querySelector(".track-name").textContent = vgm.gd3Tags.trackNameEn;
                document.querySelector(".author-name").textContent = vgm.gd3Tags.trackAuthorEn;
                document.querySelector(".game-name").textContent = vgm.gd3Tags.gameNameEn;
                document.querySelector(".system-name").textContent = vgm.gd3Tags.systemNameEn;
                document.querySelector(".release-date").textContent = vgm.gd3Tags.releaseDate;
                document.querySelector(".error-msg").textContent = "";
            } catch (exception) {
                document.querySelector(".track-name").textContent = "";
                document.querySelector(".author-name").textContent = "";
                document.querySelector(".game-name").textContent = "";
                document.querySelector(".system-name").textContent = "";
                document.querySelector(".release-date").textContent = "";
                document.querySelector(".error-msg").textContent = `${file}: ${exception.message}`;
            }
        });
    });
}

loadVGM("static/poison_of_snake.vgz");

document.querySelector("#Play").addEventListener("click", function() {
    if (audioContext) audioContext.close();
    audioContext = new AudioContext();
    OPMA.playVGM(vgm, audioContext, 3);
});
```

## VGM Parser
OPMA.ts uses a minimal [VGM][11] parser that includes support for VGZ
compressed files via a stripped-down [Pako][20] library which is already
bundled. 

The parser expects an ArrayBuffer and returns a parsed object.

You may import this parser separately from OPMA.ts as either a TypeScript or
ES6 module. If you wish to use it as an ES6 module, compile the project and
copy `tmp/vgm.js` and `tmp/pako.js` into your own project. TypeScript users
will need `src/vgm.ts`, `src/pako.js` and `src/pako.ts`.

The following example for [Node.js][17] usage uses an ES6 module:

```javascript
const FS = require("fs");
import VGM from "./vgm";

const file = FS.readFileSync(process.argv[2]);
const buffer = new ArrayBuffer(file.length);
const ui8buf = new Uint8Array(buffer);
file.map((byte, i) => ui8buf[i] = byte);

const vgm = new VGM(buffer);
```

[0]: https://en.wikipedia.org/wiki/Yamaha_YM2608
[1]: https://en.wikipedia.org/wiki/PC-8800_series
[2]: https://en.wikipedia.org/wiki/PC-9800_series
[3]: https://en.wikipedia.org/wiki/Yuzo_Koshiro
[4]: https://en.wikipedia.org/wiki/Yamaha_YM2203
[5]: https://en.wikipedia.org/wiki/General_Instrument_AY-3-8910
[6]: https://en.wikipedia.org/wiki/Yamaha_YM2151
[7]: https://www.msx.org/wiki/SCC
[8]: https://en.wikipedia.org/wiki/MSX
[9]: https://en.wikipedia.org/wiki/X68000
[10]: https://en.wikipedia.org/wiki/X1_(computer)
[11]: https://vgmrips.net/
[12]: https://en.wikipedia.org/wiki/Music_Macro_Language
[13]: https://en.wikipedia.org/wiki/MIT_License
[14]: https://github.com/true-grue/ayumi
[15]: https://www.mamedev.org/
[16]: http://retropc.net/cisc/m88/download.html
[17]: https://nodejs.org/en/
[18]: https://gulpjs.com/
[19]: https://vgmrips.net/wiki/VGM_Specification
[20]: https://github.com/nodeca/pako
