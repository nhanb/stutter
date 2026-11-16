const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const Io = std.Io;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const Scanner = @import("./Scanner.zig");
const Token = Scanner.Token;

const Parser = @This();

const log = std.log.scoped(.Parser);
tokens: []Token,
current: usize = 0,
expressions: []Expression,
scanner: *Scanner,

pub const Expression = struct {
    position: usize,
    kind: Kind,

    pub const Kind = union(enum) {
        integer: []const u8,
        string: []const u8,
        list: struct {
            tag: []const u8,
            attributes: []const Attribute = &.{},
            children: []const Expression = &.{},
        },
    };

    pub const Attribute = struct { key: []const u8, val: []const u8 };

    pub fn format(self: *const Expression, w: *Io.Writer) !void {
        try self.prettyPrint(w, 0);
    }

    pub fn prettyPrint(self: *const Expression, w: *Io.Writer, indent: usize) !void {
        switch (self.kind) {
            .integer => |int| {
                try printIndented(w, indent, "{s}", .{int});
            },
            .string => |str| {
                try printIndented(w, indent, "{s}", .{str});
            },
            .list => |list| {
                // (html
                try printIndented(w, indent, "({s} ", .{list.tag});

                //   [:foo "1" :bar "2"]
                try w.writeAll("[");
                for (list.attributes, 0..) |attr, i| {
                    try w.print(":{s} {s}{s}", .{
                        attr.key,
                        attr.val,
                        if (i == list.attributes.len - 1) "" else " ",
                    });
                }
                try w.writeAll("]");

                // children
                for (list.children) |child| {
                    try w.writeAll("\n");
                    try child.prettyPrint(w, indent + 1);
                }
                //try printIndented(w, indent, ")", .{});
                try w.writeAll(")");
            },
        }
    }

    fn printIndented(
        w: *Io.Writer,
        indent: usize,
        comptime f: []const u8,
        args: anytype,
    ) !void {
        for (0..indent) |_| try w.writeAll("  ");
        try w.print(f, args);
    }
};

pub const ParseError = error{
    OutOfMemory,
    UnexpectedToken,
};

pub fn init(arena: Allocator, src: []const u8) !Parser {
    // TODO: decouple Scanner.scan() call from parser init
    var scanner = try Scanner.init(arena, src);
    try scanner.scan(arena);

    return .{
        .scanner = scanner,
        .tokens = scanner.tokens.items,
        .expressions = &.{},
    };
}

pub fn parse(self: *Parser, arena: Allocator) ParseError!void {
    var expressions: ArrayList(Expression) = try .initCapacity(arena, 2);
    while (self.peek().kind != .eof) {
        const list = self.parseList(arena) catch |err| {
            log.err(
                "current token: [{d}] {any}",
                .{ self.current, self.tokens[self.current] },
            );
            for (self.tokens, 0..) |tok, i| {
                const mark: u8 = if (i < self.current) 'x' else ' ';
                log.err("{d} [{c}] {f}", .{ i, mark, tok });
            }
            return err;
        };
        try expressions.append(arena, list);
    }
    // ArrayList.items is safe to use here because we don't clear the arena
    // until we're done with the whole parsed result.
    self.expressions = expressions.items;
}

pub fn parseList(self: *Parser, arena: Allocator) ParseError!Expression {
    const position = self.current;

    _ = try self.consume(.lparen);

    const tag = (try self.consume(.tag)).src;

    const attributes =
        if (self.peek().kind == .lbracket)
            try self.parseAttributes(arena)
        else
            &.{};

    var children: ArrayList(Expression) = try .initCapacity(arena, 0);
    while (self.peek().kind != .rparen) {
        const child = try self.parseExpression(arena);
        try children.append(arena, child);
    }

    _ = try self.consume(.rparen);

    const list: Expression = .{
        .position = position,
        .kind = .{
            .list = .{
                .tag = tag,
                .attributes = attributes,
                .children = children.items,
            },
        },
    };

    return list;
}

pub fn parseExpression(self: *Parser, arena: Allocator) ParseError!Expression {
    const position = self.current;

    const token = self.peek();
    switch (token.kind) {
        .lparen => return self.parseList(arena),
        .integer => return .{
            .position = position,
            .kind = .{ .integer = try self.parseLiteral() },
        },
        .string => return .{
            .position = position,
            .kind = .{ .string = try self.parseLiteral() },
        },
        else => {
            log.err("expected {any}/{any}/{any}, got {any}", .{
                .lparen, .integer, .string, token.kind,
            });
            return error.UnexpectedToken;
        },
    }
}

pub fn parseAttributes(self: *Parser, arena: Allocator) ![]Expression.Attribute {
    _ = try self.consume(.lbracket);

    var attrs: ArrayList(Expression.Attribute) = try .initCapacity(arena, 0);

    while (self.peek().kind != .rbracket) {
        const attr = try self.parseAttribute();
        try attrs.append(arena, attr);
    }

    _ = try self.consume(.rbracket);

    // ArrayList.items is safe to use here because we don't clear the arena
    // until we're done with the whole parsed result.
    return attrs.items;
}

pub fn parseAttribute(self: *Parser) !Expression.Attribute {
    const key = (try self.consume(.key)).src[":".len..];
    const val = try self.parseLiteral();
    return .{ .key = key, .val = val };
}

pub fn parseLiteral(self: *Parser) ![]const u8 {
    const token = self.peek();

    switch (token.kind) {
        .integer => {
            self.current += 1;
            return token.src;
        },
        .string => {
            self.current += 1;
            return token.src[1 .. token.src.len - 1]; // strip quotes
        },
        else => {
            return error.UnexpectedToken;
        },
    }
}

fn peek(self: *Parser) Token {
    return self.tokens[self.current];
}

fn match(self: *Parser, token_kind: Token.Kind) bool {
    if (self.peek().kind == token_kind) {
        self.current += 1;
        return true;
    }
    return false;
}

fn consume(self: *Parser, expected_kind: Token.Kind) !Token {
    const token = self.tokens[self.current];
    if (token.kind == expected_kind) {
        self.current += 1;
        return token;
    }

    log.err("expected {any}, got {any}", .{ expected_kind, token.kind });
    return error.UnexpectedToken;
}

test Parser {
    const t = std.testing;

    t.log_level = .info;
    var arena_impl = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    var parser: Parser = try .init(arena,
        \\(doctype)
        \\(html
        \\  [:lang 'en']
        \\  (head
        \\    (meta [:charset "utf-8"])
        \\    (title "Home"))
        \\  (body
        \\    (h1 [:class "foo" :id "bar"] "This is my home.")
        \\    "free text"))
    );
    try parser.parse(arena);

    const expected = [_]Expression{
        .{
            .position = 0,
            .kind = .{ .list = .{ .tag = "doctype" } },
        },
        .{
            .position = 3,
            .kind = .{
                .list = .{
                    .tag = "html",
                    .attributes = &.{
                        .{ .key = "lang", .val = "en" },
                    },
                    .children = &.{
                        .{
                            .position = 9,
                            .kind = .{
                                .list = .{
                                    .tag = "head",
                                    .children = &.{
                                        .{
                                            .position = 11,
                                            .kind = .{
                                                .list = .{
                                                    .tag = "meta",
                                                    .attributes = &.{
                                                        .{ .key = "charset", .val = "utf-8" },
                                                    },
                                                },
                                            },
                                        },
                                        .{
                                            .position = 18,
                                            .kind = .{
                                                .list = .{
                                                    .tag = "title",
                                                    .children = &.{
                                                        .{
                                                            .position = 20,
                                                            .kind = .{ .string = "Home" },
                                                        },
                                                    },
                                                },
                                            },
                                        },
                                    },
                                },
                            },
                        },
                        .{
                            .position = 23,
                            .kind = .{
                                .list = .{
                                    .tag = "body",
                                    .children = &.{
                                        .{
                                            .position = 25,
                                            .kind = .{
                                                .list = .{
                                                    .tag = "h1",
                                                    .attributes = &.{
                                                        .{ .key = "class", .val = "foo" },
                                                        .{ .key = "id", .val = "bar" },
                                                    },
                                                    .children = &.{
                                                        .{
                                                            .position = 33,
                                                            .kind = .{ .string = "This is my home." },
                                                        },
                                                    },
                                                },
                                            },
                                        },
                                        .{
                                            .position = 35,
                                            .kind = .{ .string = "free text" },
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    };
    t.expectEqualDeep(&expected, parser.expressions) catch |err| {
        for (parser.expressions) |expr| {
            std.log.err("\n{f}", .{expr});
        }
        return err;
    };
}
