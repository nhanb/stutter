const std = @import("std");
const Io = std.Io;

const stutter = @import("stutter");

pub fn main(init: std.process.Init) !void {
    // This is appropriate for anything that lives as long as the process.
    const arena: std.mem.Allocator = init.arena.allocator();

    // Accessing command line arguments:
    const args = try init.minimal.args.toSlice(arena);
    for (args) |arg| {
        std.log.info("arg: {s}", .{arg});
    }

    // In order to do I/O operations need an `Io` instance.
    const io = init.io;

    var stdin_buf: [1024]u8 = undefined;
    var stdin_reader = Io.File.stdin().reader(io, &stdin_buf);
    const stutter_src = try stdin_reader.interface.allocRemaining(arena, .unlimited);

    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    try stutter.writeHtml(arena, stdout_writer, stutter_src, .{ .pretty = .{} });

    try stdout_writer.flush(); // Don't forget to flush!
}
