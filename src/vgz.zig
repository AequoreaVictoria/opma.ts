const std = @import("std");
const fs = std.fs;
const gzipStream = std.compress.gzip.gzipStream;
const Allocator = std.mem.Allocator;
const File = std.fs.File;

pub fn openAndInflate(heap: *Allocator, file_name: []u8) ![]u8 {
    var path_buf = [_]u8{0} ** 4096;
    var file_path = try fs.realpath(file_name, &path_buf);
    const file = try fs.openFileAbsolute(file_path, .{
        .read = true,
        .write = false,
        .lock_nonblocking = false,
    });
    defer file.close();

    const file_size = try file.getEndPos();
    if (file_size == 0) return error.FileEmpty;

    // Return file it if it is uncompressed.
    const file_reader = file.reader();
    const byte0 = try file_reader.readByte();
    const byte1 = try file_reader.readByte();
    if (!(byte0 == 0x1F and byte1 == 0x8B)) {
        return try file_reader.readAllAlloc(heap, file_size);
    }
    try file.seekTo(0);

    var gzip = try gzipStream(heap, file_reader);
    defer gzip.deinit();

    return try gzip.reader().readAllAlloc(heap, std.math.maxInt(usize));
}
