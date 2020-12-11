const std = @import("std");
const unicode = std.unicode;
const Allocator = std.mem.Allocator;
const bitview = @import("bitview.zig");

const GD3Utf8 = struct {
    trackNameEn: []u8,
    trackNameJp: []u8,
    gameNameEn: []u8,
    gameNameJp: []u8,
    systemNameEn: []u8,
    systemNameJp: []u8,
    trackAuthorEn: []u8,
    trackAuthorJp: []u8,
    releaseDate: []u8,
    convertedBy: []u8,
    notes: []u8
};

pub const VGM = struct {
    version: u32,
    eofOffset: u32,
    gd3Offset: u32,
    totalSamples: u32,
    loopOffset: u32,
    loopSamples: u32,
    rate: u32,
    ym2151Clock: u32,
    ym2151Multiplier: u8,
    vgmDataOffset: u32,
    ay8910Clock: u32,
    ay8910Type: u8,
    ay8910Flags: u8,
    ay8910Multiplier: u8,
    volumeModifier: u8,
    loopBase: u8,
    loopModifier: u8,
    okim6258Clock: u32,
    okim6258Flags: u8,
    okim6258Multiplier: u8,
    k051649Clock: u32,
    k051649Multiplier: u8,
    extraHeaderOffset: u32,
    gd3Version: u32,
    gd3Length: u32,
    gd3Tags: GD3Utf8,
    data: []u8,

    const Self = @This();

    pub fn free(self: *const Self, heap: *Allocator) void {
        var tags = self.*.gd3Tags;
        heap.free(tags.trackNameEn);
        heap.free(tags.trackNameJp);
        heap.free(tags.gameNameEn);
        heap.free(tags.gameNameJp);
        heap.free(tags.systemNameEn);
        heap.free(tags.systemNameJp);
        heap.free(tags.trackAuthorEn);
        heap.free(tags.trackAuthorJp);
        heap.free(tags.releaseDate);
        heap.free(tags.convertedBy);
        heap.free(tags.notes);
        heap.free(self.*.data);
    }

    pub fn init(heap: *Allocator, file: *const []u8) !Self {
        var vgm = file.*;

        if (vgm[0] != 'V' or
            vgm[1] != 'g' or
            vgm[2] != 'm' or
            vgm[3] != ' ')
            return error.vgmInvalidIdent;

        const version = bitview.read(u32, vgm, 0x08);
        if (version < 0x150) return error.vgmInvalidVersion;

        const gd3Offset = bitview.read(u32, vgm, 0x14);
        var gd3Version: u32 = undefined;
        var gd3Length: u32 = undefined;
        var gd3Tags: GD3Utf8 = undefined;
        if (gd3Offset == 0) {
            const empty_data = &[1:0]u8{0};
            const empty = empty_data[0..0];
            gd3Version = 0;
            gd3Length = 0;
            gd3Tags = GD3Utf8 {
                .trackNameEn = empty,
                .trackNameJp = empty,
                .gameNameEn = empty,
                .gameNameJp = empty,
                .systemNameEn = empty,
                .systemNameJp = empty,
                .trackAuthorEn = empty,
                .trackAuthorJp = empty,
                .releaseDate = empty,
                .convertedBy = empty,
                .notes = empty
            };
        } else {
            // Pad the relative gd3Offset by its own location in the vgm
            const offset = gd3Offset + 0x14;

            if (vgm[offset + 0] != 'G' or
                vgm[offset + 1] != 'd' or
                vgm[offset + 2] != '3' or
                vgm[offset + 3] != ' ')
                return error.vgmInvalidGd3Ident;

            gd3Version = bitview.read(u32, vgm, offset + 4);
            gd3Length = bitview.read(u32, vgm, offset + 8);

            const tags = enum(u8) {
                trackNameEn,
                trackNameJp,
                gameNameEn,
                gameNameJp,
                systemNameEn,
                systemNameJp,
                trackAuthorEn,
                trackAuthorJp,
                releaseDate,
                convertedBy,
                notes
            };

            var trackNameEnLen: u32 = 0;
            var trackNameJpLen: u32 = 0;
            var gameNameEnLen: u32 = 0;
            var gameNameJpLen: u32 = 0;
            var systemNameEnLen: u32 = 0;
            var systemNameJpLen: u32 = 0;
            var trackAuthorEnLen: u32 = 0;
            var trackAuthorJpLen: u32 = 0;
            var releaseDateLen: u32 = 0;
            var convertedByLen: u32 = 0;
            var notesLen: u32 = 0;

            var tag: u8 = 0;
            var i: u32 = 0;
            while (i < gd3Length) {
                const char = bitview.read(u16, vgm, offset + 12 + i);
                switch (@intToEnum(tags, tag)) {
                    .trackNameEn => trackNameEnLen += 1,
                    .trackNameJp => trackNameJpLen += 1,
                    .gameNameEn => gameNameEnLen += 1,
                    .gameNameJp => gameNameJpLen += 1,
                    .systemNameEn => systemNameEnLen += 1,
                    .systemNameJp => systemNameJpLen += 1,
                    .trackAuthorEn => trackAuthorEnLen += 1,
                    .trackAuthorJp => trackAuthorJpLen += 1,
                    .releaseDate => releaseDateLen += 1,
                    .convertedBy => convertedByLen += 1,
                    .notes => notesLen += 1
                }
                if (char == 0) tag += 1;
                i += 2;
            }

            const trackNameEn = try heap.alloc(u16, trackNameEnLen);
            defer heap.free(trackNameEn);
            const trackNameJp = try heap.alloc(u16, trackNameJpLen);
            defer heap.free(trackNameJp);
            const gameNameEn = try heap.alloc(u16, gameNameEnLen);
            defer heap.free(gameNameEn);
            const gameNameJp = try heap.alloc(u16, gameNameJpLen);
            defer heap.free(gameNameJp);
            const systemNameEn = try heap.alloc(u16, systemNameEnLen);
            defer heap.free(systemNameEn);
            const systemNameJp = try heap.alloc(u16, systemNameJpLen);
            defer heap.free(systemNameJp);
            const trackAuthorEn = try heap.alloc(u16, trackAuthorEnLen);
            defer heap.free(trackAuthorEn);
            const trackAuthorJp = try heap.alloc(u16, trackAuthorJpLen);
            defer heap.free(trackAuthorJp);
            const releaseDate = try heap.alloc(u16, releaseDateLen);
            defer heap.free(releaseDate);
            const convertedBy = try heap.alloc(u16, convertedByLen);
            defer heap.free(convertedBy);
            const notes = try heap.alloc(u16, notesLen);
            defer heap.free(notes);

            tag = 0;
            i = 0;
            var pos: u32 = 0;
            while (i < gd3Length) {
                const char = bitview.read(u16, vgm, offset + 12 + i);
                switch (@intToEnum(tags, tag)) {
                    .trackNameEn => trackNameEn[pos] = char,
                    .trackNameJp => trackNameJp[pos] = char,
                    .gameNameEn => gameNameEn[pos] = char,
                    .gameNameJp => gameNameJp[pos] = char,
                    .systemNameEn => systemNameEn[pos] = char,
                    .systemNameJp => systemNameJp[pos] = char,
                    .trackAuthorEn => trackAuthorEn[pos] = char,
                    .trackAuthorJp => trackAuthorJp[pos] = char,
                    .releaseDate => releaseDate[pos] = char,
                    .convertedBy => convertedBy[pos] = char,
                    .notes => notes[pos] = char
                }
                if (char == 0) {
                    tag += 1;
                    pos = 0;
                } else pos += 1;
                i += 2;
            }

            gd3Tags = GD3Utf8 {
                .trackNameEn = try unicode.utf16leToUtf8Alloc(heap, trackNameEn),
                .trackNameJp = try unicode.utf16leToUtf8Alloc(heap, trackNameJp),
                .gameNameEn = try unicode.utf16leToUtf8Alloc(heap, gameNameEn),
                .gameNameJp = try unicode.utf16leToUtf8Alloc(heap, gameNameJp),
                .systemNameEn = try unicode.utf16leToUtf8Alloc(heap, systemNameEn),
                .systemNameJp = try unicode.utf16leToUtf8Alloc(heap, systemNameJp),
                .trackAuthorEn = try unicode.utf16leToUtf8Alloc(heap, trackAuthorEn),
                .trackAuthorJp = try unicode.utf16leToUtf8Alloc(heap, trackAuthorJp),
                .releaseDate = try unicode.utf16leToUtf8Alloc(heap, releaseDate),
                .convertedBy = try unicode.utf16leToUtf8Alloc(heap, convertedBy),
                .notes = try unicode.utf16leToUtf8Alloc(heap, notes)
            };
        }

        var ym2151Clock = bitview.read(u32, vgm, 0x30);
        var ay8910Clock = if (version >= 0x151) bitview.read(u32, vgm, 0x74) else 0;
        var okim6258Clock = if (version >= 0x161) bitview.read(u32, vgm, 0x90) else 0;
        var k051649Clock = if (version >= 0x161) bitview.read(u32, vgm, 0x9C) else 0;
        var data = VGM {
            .version = version,
            .eofOffset = bitview.read(u32, vgm, 0x04),
            .gd3Offset = gd3Offset,
            .totalSamples = bitview.read(u32, vgm, 0x18),
            .loopOffset = bitview.read(u32, vgm, 0x1C),
            .loopSamples = bitview.read(u32, vgm, 0x20),
            .rate = bitview.read(u32, vgm, 0x24),
            .ym2151Clock = ym2151Clock,
            .ym2151Multiplier = if (ym2151Clock > 0) 1 else 0,
            .vgmDataOffset = bitview.read(u32, vgm, 0x34),
            .ay8910Clock = ay8910Clock,
            .ay8910Type = if (ay8910Clock > 0) vgm[0x78] else 0,
            .ay8910Flags = if (ay8910Clock > 0) vgm[0x79] else 0,
            .ay8910Multiplier = if (ay8910Clock > 0) 1 else 0,
            .volumeModifier = if (version >= 0x160) vgm[0x7C] else 0,
            .loopBase = if (version >= 0x160) vgm[0x7E] else 0,
            .loopModifier = if (version >= 0x151) vgm[0x7F] else 0,
            .okim6258Clock = okim6258Clock,
            .okim6258Flags = if (okim6258Clock > 0) vgm[0x94] else 0,
            .okim6258Multiplier = if (okim6258Clock > 0) 1 else 0,
            .k051649Clock = k051649Clock,
            .k051649Multiplier = if (k051649Clock > 0) 1 else 0,
            .extraHeaderOffset = if (version >= 0x170) bitview.read(u32, vgm, 0xBC) else 0,
            .gd3Version = gd3Version,
            .gd3Length = gd3Length,
            .gd3Tags = gd3Tags,
            .data = vgm
        };

        // If bit 31 is set to 1, clear the bit from the clock and enable dual-chip support
        if (ym2151Clock & 0x40000000 > 0) {
            data.ym2151Clock &= 0xBFFFFFFF;
            data.ym2151Multiplier = 2;
        }
        if (ay8910Clock & 0x40000000 > 0) {
            data.ay8910Clock &= 0xBFFFFFFF;
            data.ay8910Multiplier = 2;
        }
        if (okim6258Clock & 0x40000000 > 0) {
            data.okim6258Clock &= 0xBFFFFFFF;
            data.okim6258Multiplier = 2;
        }
        if (k051649Clock & 0x40000000 > 0) {
            data.k051649Clock &= 0xBFFFFFFF;
            data.k051649Multiplier = 2;
        }

        return data;
    }
};
