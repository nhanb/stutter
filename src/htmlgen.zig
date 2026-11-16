const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const Io = std.Io;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const Parser = @import("./Parser.zig");
const Expression = Parser.Expression;

pub const Formatting = union(enum) {
    minified: void,
    pretty: struct {
        indent_level: usize = 0,
    },

    fn indent(self: Formatting) Formatting {
        return switch (self) {
            .minified => .minified,
            .pretty => |pp| .{
                .pretty = .{ .indent_level = pp.indent_level + 1 },
            },
        };
    }
};

pub fn writeHtml(
    arena: Allocator,
    w: *Io.Writer,
    src: []const u8,
    formatting: Formatting,
) !void {
    var parser: Parser = try .init(arena, src);
    try parser.parse(arena);
    for (parser.expressions) |expr| {
        try writeExpression(arena, w, expr, formatting);
    }
    switch (formatting) {
        .pretty => try w.writeByte('\n'),
        else => {},
    }
}

// TODO: escape
fn writeExpression(
    arena: Allocator,
    w: *Io.Writer,
    expr: Expression,
    formatting: Formatting,
) !void {
    switch (expr.kind) {
        .integer => |int| try writeIndented(formatting, w, int),
        .string => |str| try writeIndented(formatting, w, str),
        .list => |list| {
            if (mem.eql(u8, list.tag, "doctype")) {
                try writeIndented(formatting, w, "<!DOCTYPE html>\n");
                return;
            }
            // opening & attributes
            try printIndented(formatting, w, "<{s}", .{list.tag});
            for (list.attributes) |attr| {
                try w.print(" {s}=\"{s}\"", .{ attr.key, attr.val });
            }
            try w.writeAll(">");

            if (VoidTag.isVoid(list.tag)) return;

            // children
            for (list.children, 0..) |child, i| {
                switch (formatting) {
                    .pretty => try w.writeAll("\n"),
                    .minified => {
                        // Put space between "terminal" values i.e. integer &
                        // string, otherwise let tags hump each other.
                        const kind = child.kind;
                        if (i > 0 and (kind == .integer or kind == .string)) {
                            const prev = list.children[i - 1];
                            if (prev.kind == .integer or prev.kind == .string) {
                                try w.writeAll(" ");
                            }
                        }
                    },
                }
                try writeExpression(
                    arena,
                    w,
                    child,
                    formatting.indent(),
                );
            }

            // closing
            switch (formatting) {
                .pretty => try w.writeAll("\n"),
                .minified => {},
            }
            try printIndented(formatting, w, "</{s}>", .{list.tag});
        },
    }
}

pub const VoidTag = enum {
    doctype,
    area,
    base,
    br,
    col,
    embed,
    hr,
    img,
    input,
    link,
    meta,
    source,
    track,
    wbr,

    pub fn isVoid(name: []const u8) bool {
        return std.meta.stringToEnum(VoidTag, name) != null;
    }
};

fn printIndented(formatting: Formatting, w: *Io.Writer, comptime format: []const u8, args: anytype) !void {
    switch (formatting) {
        .pretty => |pp| {
            for (0..pp.indent_level) |_| {
                try w.writeAll("  ");
            }
        },
        .minified => {},
    }
    try w.print(format, args);
}

fn writeIndented(formatting: Formatting, w: *Io.Writer, bytes: []const u8) !void {
    switch (formatting) {
        .pretty => |pp| {
            for (0..pp.indent_level) |_| {
                try w.writeAll("  ");
            }
        },
        .minified => {},
    }
    try w.writeAll(bytes);
}

test "htmlgen" {
    const t = std.testing;
    t.log_level = .info;

    var arena_impl = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const input = try Io.Dir.cwd().readFileAlloc(
        t.io,
        "src/htmlgen_test_input.txt",
        arena,
        .unlimited,
    );

    var pretty_w = Io.Writer.Allocating.init(arena);
    try writeHtml(arena, &pretty_w.writer, input, .{ .pretty = .{} });
    try t.expectEqualSlices(u8,
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\  <head>
        \\    <meta charset="utf-8">
        \\    <title>
        \\      Home
        \\    </title>
        \\  </head>
        \\  <body>
        \\    <h1 class="foo" id="bar">
        \\      This is my home.
        \\    </h1>
        \\    free text
        \\    more free text
        \\  </body>
        \\</html>
        \\
    , pretty_w.written());

    var minified_w = Io.Writer.Allocating.init(arena);
    try writeHtml(arena, &minified_w.writer, input, .minified);
    try t.expectEqualSlices(u8,
        \\<!DOCTYPE html>
        \\<html lang="en"><head><meta charset="utf-8"><title>Home</title></head><body><h1 class="foo" id="bar">This is my home.</h1>free text more free text</body></html>
    , minified_w.written());
    // TODO: the minifier could do better.
    // See https://j9t.github.io/html-minifier-next/
}
