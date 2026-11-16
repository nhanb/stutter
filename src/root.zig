const htmlgen = @import("./htmlgen.zig");

pub const writeHtml = htmlgen.writeHtml;
pub const Formatting = htmlgen.Formatting;

test "all" {
    _ = .{
        @import("./Scanner.zig"),
        @import("./Parser.zig"),
        @import("./htmlgen.zig"),
    };
}
