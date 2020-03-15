const std = @import("std");
const fmt = std.fmt;
const heap = std.heap.c_allocator;
const mem = std.mem;
const print = std.debug.warn;
const process = std.process;
const player = @import("player.zig");

fn die() void {
    print("{}", .{
        \\
        \\ Usage: opma [-write] [-loop <count>] "<filepath>" [... "<filepathN>"]
        \\
        \\   -write: Write the output to disk as a 16-bit 44.1Khz .wav file.
        \\       (aliases: --write, -w, --w)
        \\
        \\   -loop: Loop the song <count> times before exiting. (Default: 3)
        \\       (aliases: --loop, -l, --l)
        \\
        \\   <filepath>: Path to a .vgm/.vgz file. Can specify multiple files.
        \\
    });
    process.exit(1);
}

pub fn main() !void {
    const args = try process.argsAlloc(heap);
    defer process.argsFree(heap, args);
    if (args.len == 1) die();

    var writeFile: bool = false;
    var loopCount: ?u32 = null;
    var files = try heap.alloc([]u8, args.len - 1);
    defer heap.free(files);

    var i: u32 = 1;
    var f: u32 = 0;
    while (i < args.len) {
        if (
            mem.eql(u8, args[i], "-write") or
            mem.eql(u8, args[i], "-w") or
            mem.eql(u8, args[i], "--write") or
            mem.eql(u8, args[i], "--w")
        ) {
            if (writeFile) {
                print("\nERROR: -write specified more than once!\n", .{});
                die();
            }
            writeFile = true;
            i += 1;
        } else if (
            mem.eql(u8, args[i], "-loop") or
            mem.eql(u8, args[i], "-l") or
            mem.eql(u8, args[i], "--loop") or
            mem.eql(u8, args[i], "--l")
        ) {
            if (loopCount != null) {
                print("\nERROR: -loop specified more than once!\n", .{});
                die();
            }
            if ((i + 1) > args.len) {
                print("\nERROR: -loop was not given an argument!\n", .{});
                die();
            }
            loopCount = try fmt.parseUnsigned(u32, args[i + 1], 10);
            i += 2;
        } else if (args[i][0] == '-') {
            print("\nERROR: -command unknown!\n", .{});
            die();
        } else {
            files[f] = args[i];
            f += 1;
            i += 1;
        }
    }

    if (loopCount == null) loopCount = 3;
    var fileList = files[0..f]; // We overallocated due to -loop and -write.

    if (loopCount) |count| {
        try player.start(heap, fileList, writeFile, count);
    } else unreachable;
}
