const std = @import("std");
const unicode = std.unicode;
const Allocator = std.mem.Allocator;
const bitview = @import("bitview.zig");

const GD3Utf8 = struct {
    track_name_en: []u8,
    track_name_jp: []u8,
    game_name_en: []u8,
    game_name_jp: []u8,
    system_name_en: []u8,
    system_name_jp: []u8,
    track_author_en: []u8,
    track_author_jp: []u8,
    release_date: []u8,
    converted_by: []u8,
    notes: []u8
};

pub const VGM = struct {
    version: u32,
    eof_offset: u32,
    gd3_offset: u32,
    total_samples: u32,
    loop_offset: u32,
    loop_samples: u32,
    rate: u32,
    ym2151_clock: u32,
    ym2151_multiplier: u8,
    vgm_data_offset: u32,
    ay8910_clock: u32,
    ay8910_type: u8,
    ay8910_flags: u8,
    ay8910_multiplier: u8,
    volume_modifier: u8,
    loop_base: u8,
    loop_modifier: u8,
    okim6258_clock: u32,
    okim6258_flags: u8,
    okim6258_multiplier: u8,
    k051649_clock: u32,
    k051649_multiplier: u8,
    extra_header_offset: u32,
    gd3_version: u32,
    gd3_length: u32,
    gd3_tags: GD3Utf8,
    data: []u8,

    const Self = @This();

    pub fn free(self: *const Self, heap: *Allocator) void {
        var tags = self.*.gd3_tags;
        heap.free(tags.track_name_en);
        heap.free(tags.track_name_jp);
        heap.free(tags.game_name_en);
        heap.free(tags.game_name_jp);
        heap.free(tags.system_name_en);
        heap.free(tags.system_name_jp);
        heap.free(tags.track_author_en);
        heap.free(tags.track_author_jp);
        heap.free(tags.release_date);
        heap.free(tags.converted_by);
        heap.free(tags.notes);
        heap.free(self.*.data);
    }

    pub fn init(heap: *Allocator, file: *const []u8) !Self {
        var vgm = file.*;

        if (vgm[0] != 'V' or
            vgm[1] != 'g' or
            vgm[2] != 'm' or
            vgm[3] != ' ')
            return error.InvalidVGMIdent;

        const version = bitview.read(u32, vgm, 0x08);
        if (version < 0x150) return error.InvalidVGMVersion;

        const gd3_offset = bitview.read(u32, vgm, 0x14);
        var gd3_version: u32 = undefined;
        var gd3_length: u32 = undefined;
        var gd3_tags: GD3Utf8 = undefined;
        if (gd3_offset == 0) {
            const empty_data = &[1:0]u8{0};
            const empty = empty_data[0..0];
            gd3_version = 0;
            gd3_length = 0;
            gd3_tags = GD3Utf8{
                .track_name_en = empty,
                .track_name_jp = empty,
                .game_name_en = empty,
                .game_name_jp = empty,
                .system_name_en = empty,
                .system_name_jp = empty,
                .track_author_en = empty,
                .track_author_jp = empty,
                .release_date = empty,
                .converted_by = empty,
                .notes = empty,
            };
        } else {
            // Pad the relative gd3_offset by its own location in the vgm
            const offset = gd3_offset + 0x14;

            if (vgm[offset + 0] != 'G' or
                vgm[offset + 1] != 'd' or
                vgm[offset + 2] != '3' or
                vgm[offset + 3] != ' ')
                return error.InvalidGD3Ident;

            gd3_version = bitview.read(u32, vgm, offset + 4);
            gd3_length = bitview.read(u32, vgm, offset + 8);

            const tags = enum(u8) {
                track_name_en,
                track_name_jp,
                game_name_en,
                game_name_jp,
                system_name_en,
                system_name_jp,
                track_author_en,
                track_author_jp,
                release_date,
                converted_by,
                notes
            };

            var track_name_en_len: u32 = 0;
            var track_name_jp_len: u32 = 0;
            var game_name_en_len: u32 = 0;
            var game_name_jp_len: u32 = 0;
            var system_name_en_len: u32 = 0;
            var system_name_jp_len: u32 = 0;
            var track_author_en_len: u32 = 0;
            var track_author_jp_len: u32 = 0;
            var release_date_len: u32 = 0;
            var converted_by_len: u32 = 0;
            var notes_len: u32 = 0;

            var tag: u8 = 0;
            var i: u32 = 0;
            while (i < gd3_length) {
                const char = bitview.read(u16, vgm, offset + 12 + i);
                switch (@intToEnum(tags, tag)) {
                    .track_name_en => track_name_en_len += 1,
                    .track_name_jp => track_name_jp_len += 1,
                    .game_name_en => game_name_en_len += 1,
                    .game_name_jp => game_name_jp_len += 1,
                    .system_name_en => system_name_en_len += 1,
                    .system_name_jp => system_name_jp_len += 1,
                    .track_author_en => track_author_en_len += 1,
                    .track_author_jp => track_author_jp_len += 1,
                    .release_date => release_date_len += 1,
                    .converted_by => converted_by_len += 1,
                    .notes => notes_len += 1,
                }
                if (char == 0) tag += 1;
                i += 2;
            }

            const track_name_en = try heap.alloc(u16, track_name_en_len);
            defer heap.free(track_name_en);
            const track_name_jp = try heap.alloc(u16, track_name_jp_len);
            defer heap.free(track_name_jp);
            const game_name_en = try heap.alloc(u16, game_name_en_len);
            defer heap.free(game_name_en);
            const game_name_jp = try heap.alloc(u16, game_name_jp_len);
            defer heap.free(game_name_jp);
            const system_name_en = try heap.alloc(u16, system_name_en_len);
            defer heap.free(system_name_en);
            const system_name_jp = try heap.alloc(u16, system_name_jp_len);
            defer heap.free(system_name_jp);
            const track_author_en = try heap.alloc(u16, track_author_en_len);
            defer heap.free(track_author_en);
            const track_author_jp = try heap.alloc(u16, track_author_jp_len);
            defer heap.free(track_author_jp);
            const release_date = try heap.alloc(u16, release_date_len);
            defer heap.free(release_date);
            const converted_by = try heap.alloc(u16, converted_by_len);
            defer heap.free(converted_by);
            const notes = try heap.alloc(u16, notes_len);
            defer heap.free(notes);

            tag = 0;
            i = 0;
            var pos: u32 = 0;
            while (i < gd3_length) {
                const char = bitview.read(u16, vgm, offset + 12 + i);
                switch (@intToEnum(tags, tag)) {
                    .track_name_en => track_name_en[pos] = char,
                    .track_name_jp => track_name_jp[pos] = char,
                    .game_name_en => game_name_en[pos] = char,
                    .game_name_jp => game_name_jp[pos] = char,
                    .system_name_en => system_name_en[pos] = char,
                    .system_name_jp => system_name_jp[pos] = char,
                    .track_author_en => track_author_en[pos] = char,
                    .track_author_jp => track_author_jp[pos] = char,
                    .release_date => release_date[pos] = char,
                    .converted_by => converted_by[pos] = char,
                    .notes => notes[pos] = char,
                }
                if (char == 0) {
                    tag += 1;
                    pos = 0;
                } else pos += 1;
                i += 2;
            }

            gd3_tags = GD3Utf8{
                .track_name_en = try unicode.utf16leToUtf8Alloc(heap, track_name_en),
                .track_name_jp = try unicode.utf16leToUtf8Alloc(heap, track_name_jp),
                .game_name_en = try unicode.utf16leToUtf8Alloc(heap, game_name_en),
                .game_name_jp = try unicode.utf16leToUtf8Alloc(heap, game_name_jp),
                .system_name_en = try unicode.utf16leToUtf8Alloc(heap, system_name_en),
                .system_name_jp = try unicode.utf16leToUtf8Alloc(heap, system_name_jp),
                .track_author_en = try unicode.utf16leToUtf8Alloc(heap, track_author_en),
                .track_author_jp = try unicode.utf16leToUtf8Alloc(heap, track_author_jp),
                .release_date = try unicode.utf16leToUtf8Alloc(heap, release_date),
                .converted_by = try unicode.utf16leToUtf8Alloc(heap, converted_by),
                .notes = try unicode.utf16leToUtf8Alloc(heap, notes),
            };
        }

        var ym2151_clock = bitview.read(u32, vgm, 0x30);
        var ay8910_clock = if (version >= 0x151) bitview.read(u32, vgm, 0x74) else 0;
        var okim6258_clock = if (version >= 0x161) bitview.read(u32, vgm, 0x90) else 0;
        var k051649_clock = if (version >= 0x161) bitview.read(u32, vgm, 0x9C) else 0;
        var data = VGM{
            .version = version,
            .eof_offset = bitview.read(u32, vgm, 0x04),
            .gd3_offset = gd3_offset,
            .total_samples = bitview.read(u32, vgm, 0x18),
            .loop_offset = bitview.read(u32, vgm, 0x1C),
            .loop_samples = bitview.read(u32, vgm, 0x20),
            .rate = bitview.read(u32, vgm, 0x24),
            .ym2151_clock = ym2151_clock,
            .ym2151_multiplier = if (ym2151_clock > 0) 1 else 0,
            .vgm_data_offset = bitview.read(u32, vgm, 0x34),
            .ay8910_clock = ay8910_clock,
            .ay8910_type = if (ay8910_clock > 0) vgm[0x78] else 0,
            .ay8910_flags = if (ay8910_clock > 0) vgm[0x79] else 0,
            .ay8910_multiplier = if (ay8910_clock > 0) 1 else 0,
            .volume_modifier = if (version >= 0x160) vgm[0x7C] else 0,
            .loop_base = if (version >= 0x160) vgm[0x7E] else 0,
            .loop_modifier = if (version >= 0x151) vgm[0x7F] else 0,
            .okim6258_clock = okim6258_clock,
            .okim6258_flags = if (okim6258_clock > 0) vgm[0x94] else 0,
            .okim6258_multiplier = if (okim6258_clock > 0) 1 else 0,
            .k051649_clock = k051649_clock,
            .k051649_multiplier = if (k051649_clock > 0) 1 else 0,
            .extra_header_offset = if (version >= 0x170) bitview.read(u32, vgm, 0xBC) else 0,
            .gd3_version = gd3_version,
            .gd3_length = gd3_length,
            .gd3_tags = gd3_tags,
            .data = vgm,
        };

        // If bit 31 is set to 1, clear the bit from the clock and enable dual-chip support
        if (ym2151_clock & 0x40000000 > 0) {
            data.ym2151_clock &= 0xBFFFFFFF;
            data.ym2151_multiplier = 2;
        }
        if (ay8910_clock & 0x40000000 > 0) {
            data.ay8910_clock &= 0xBFFFFFFF;
            data.ay8910_multiplier = 2;
        }
        if (okim6258_clock & 0x40000000 > 0) {
            data.okim6258_clock &= 0xBFFFFFFF;
            data.okim6258_multiplier = 2;
        }
        if (k051649_clock & 0x40000000 > 0) {
            data.k051649_clock &= 0xBFFFFFFF;
            data.k051649_multiplier = 2;
        }

        return data;
    }
};
