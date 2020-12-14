# OPMA
> A fictional sound chip implemented in Zig.

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

## Chips & Credits
The emulation of these components is based upon prior work:

* [YM2149][5] is based on [Ayumi][14].
* [Konami SCC][7] is based on [MAME][15].
* [YM2151][6] is based on [FMGen][16].
* OKIM6258 is based on [MAME][15].

## Compiling
You will need the [Zig][17] compiler installed.

This has not been tested outside of Linux yet!

``` Shell
$ zig build -Drelease-fast=true
```

## Usage
```

 Usage: opma [-write] [-loop <count>] "<filepath>" [... "<filepathN>"]

   -write: Write the output to disk as a 16-bit 44.1Khz .wav file.
       (aliases: --write, -w, --w)

   -loop: Loop the song <count> times before exiting. (Default: 3)
       (aliases: --loop, -l, --l)

   <filepath>: Path to a .vgm/.vgz file. Can specify multiple files.

```

## License
All code unique to the project has been released under a [0BSD][19] license.
This means that all of it may be used without any further action on your
part, not even a copyright line. Enjoy!

However, as the sound generation code is based upon open source releases of
arcade and computer emulators, those specific files are licensed the same way
as their point of origin. See [LICENSE.md][20] for more information, which
also contains the licensing information for the contents of `lib/`.

In order of preference: Only [ISC][21], [MIT][22] and [3BSD][23] (or lower!!)
licensed libraries will be considered for inclusion in this project. This means
at worst you must reproduce the relevant contents of [LICENSE.md][20] somewhere
for the code you're reusing and you may be restricted from using the names of
copyright holders for the purposes of marketing. Not very hard.


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
[17]: https://ziglang.org/
[19]: https://opensource.org/licenses/0BSD
[20]: https://github.com/AequoreaVictoria/opma/blob/master/LICENSE.md
[21]: https://opensource.org/licenses/ISC
[22]: https://opensource.org/licenses/MIT
[23]: https://opensource.org/licenses/BSD-3-Clause
