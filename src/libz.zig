const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const File = std.fs.File;

const libz = @cImport({
    @cInclude("zlib.h");
    @cInclude("inftrees.h");
    @cInclude("inflate.h");
});

pub fn openAndInflate(heap: *Allocator, fileName: []u8) ![]u8 {
    var pathBuf = [_]u8{0} ** 4096;
    var filePath = try fs.realpath(fileName, &pathBuf);
    const file = try fs.openFileAbsolute(filePath, .{
        .read = true,
        .write = false,
        .always_blocking = false
    });
    defer file.close();

    // Create the input buffer, returning it if it is uncompressed
    const inSize = try file.getEndPos();
    if (inSize == 0) return error.fileEmpty;
    var in = try heap.alloc(u8, inSize);
    const read = try file.read(in);
    if (!(in[0] == 0x1F and in[1] == 0x8B)) return in;
    const inPtr = @ptrCast(*[*c]u8, &in);

    // Create an output buffer using the size information in the gzip data
    const b4 = @intCast(u32, in[inSize - 4]);
    const b3 = @intCast(u32, in[inSize - 3]);
    const b2 = @intCast(u32, in[inSize - 2]);
    const b1 = @intCast(u32, in[inSize - 1]);
    const outSize = (b1 << 24) | (b2 << 16) + (b3 << 8) + b4;
    var out = try heap.alloc(u8, outSize);
    const outPtr = @ptrCast(*[*c]u8, &out);

    // A fully initialized state and stream ready to handle gzip files
    var empty = libz.code {.op = 0, .bits = 0, .val = 0};
    var state = libz.inflate_state {
        .mode = libz.inflate_mode.HEAD,
        .last = 0,
        .wrap = 2,
        .havedict = 0,
        .flags = 0,
        .dmax = 32768,
        .check = 0,
        .total = 0,
        .head = null,
        .wbits = 15,
        .wsize = 0,
        .whave = 0,
        .wnext = 0,
        .window = null,
        .hold = 0,
        .bits = 0,
        .length = 0,
        .offset = 0,
        .extra = 0,
        .lencode = &empty,
        .distcode = &empty,
        .lenbits = 0,
        .distbits = 0,
        .ncode = 0,
        .nlen = 0,
        .ndist = 0,
        .have = 0,
        .next = &empty,
        .lens = [_]c_ushort{0} ** 320,
        .work = [_]c_ushort{0} ** 288,
        .codes = [_]libz.code {
            libz.code {.op = 0, .bits = 0, .val = 0}
        } ** libz.ENOUGH,
        .sane = 1,
        .back = -1,
        .was = 0,
    };
    var stream = libz.z_stream {
        .next_in = inPtr.*,
        .avail_in = @intCast(c_uint, inSize),
        .total_in = 0,
        .next_out = outPtr.*,
        .avail_out = @intCast(c_uint, outSize),
        .total_out = 0,
        .msg = null,
        .state = &state,
        .zalloc = null,
        .zfree = null,
        .opaque = null,
        .data_type = libz.Z_BINARY,
        .adler = 0,
        .reserved = 0,
    };

    const err = libz.inflate(&stream, libz.Z_FINISH);
    if (err != libz.Z_STREAM_END) {
        switch (err) {
            libz.Z_STREAM_ERROR => return error.Z_STREAM_ERROR,
            libz.Z_NEED_DICT => return error.Z_NEED_DICT,
            libz.Z_DATA_ERROR => return error.Z_DATA_ERROR,
            libz.Z_MEM_ERROR => return error.Z_MEM_ERROR,
            libz.Z_BUF_ERROR => return error.Z_BUF_ERROR,
            else => unreachable
        }
    }

    heap.free(in);
    return out;
}
