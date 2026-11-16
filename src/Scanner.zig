const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const Io = std.Io;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.Scanner);

const Scanner = @This();

src: []const u8,
tokens: ArrayList(Token),
start: usize = 0,
current: usize = 0,

pub const Token = struct {
    src: []const u8,
    kind: Kind,
    position: usize,

    pub const Kind = enum {
        lparen,
        rparen,
        lbracket,
        rbracket,
        key,
        tag,
        string,
        integer,
        eof,
    };

    pub fn format(self: Token, w: *Io.Writer) !void {
        try w.print("[{d}] {s} {any}", .{ self.position, self.src, self.kind });
    }
};

/// Caller is responsible for deinitting the arena afterwards
pub fn init(arena: Allocator, src: []const u8) !*Scanner {
    const scanner = try arena.create(Scanner);
    scanner.* = .{
        .src = src,
        .tokens = try .initCapacity(arena, 128),
    };
    return scanner;
}

pub fn scan(self: *Scanner, arena: Allocator) !void {
    while (self.advance()) |char| {
        _ = switch (char) {
            '(' => self.emitToken(arena, .lparen),
            ')' => self.emitToken(arena, .rparen),
            '[' => self.emitToken(arena, .lbracket),
            ']' => self.emitToken(arena, .rbracket),
            '\'', '"' => self.scanString(arena, char),
            '0'...'9' => self.scanInteger(arena),
            'a'...'z' => self.scanTag(arena),
            ':' => self.scanKey(arena),
            // skip whitespace:
            ' ', '\t', '\r', '\n' => {},
            else => error.UnexpectedChar,
        } catch |err| {
            // TODO: Return some sort of error value instead of printing,
            // to make testing possible.
            const start = self.posToLineColumn(self.start);
            const end = self.posToLineColumn(self.current - 1);
            log.err("{any} at L{d}:{d}-L{d}:{d}", .{
                err,
                start.line,
                start.column,
                end.line,
                end.column,
            });
            log.err("offending part: >>{s}<<", .{self.src[self.start..self.current]});
            for (self.tokens.items) |tok| {
                log.err("tok: {f}", .{tok});
            }
            return err;
        };

        self.start = self.current;
    }

    try self.emitToken(arena, .eof);
}

fn emitToken(self: *Scanner, arena: Allocator, kind: Token.Kind) !void {
    const src = self.src[self.start..self.current];
    try self.tokens.append(arena, .{
        .src = src,
        .kind = kind,
        .position = self.start,
    });
}

fn scanString(self: *Scanner, arena: Allocator, delimiter: u8) !void {
    while (self.advance()) |char| {
        if (char == delimiter) {
            try self.emitToken(arena, .string);
            return;
        }
    }
    return error.UnclosedString;
}

fn scanKey(self: *Scanner, arena: Allocator) !void {
    loop: while (self.peek()) |char| switch (char) {
        'a'...'z', '0'...'9', '-' => self.consume(),
        else => break :loop,
    };
    if (self.current - self.start < 2) {
        return error.EmptyAttributeKey;
    }
    try self.emitToken(arena, .key);
}

fn scanInteger(self: *Scanner, arena: Allocator) !void {
    loop: while (self.peek()) |char| switch (char) {
        '0'...'9' => self.consume(),
        else => break :loop,
    };
    try self.emitToken(arena, .integer);
}

fn scanTag(self: *Scanner, arena: Allocator) !void {
    loop: while (self.peek()) |char| switch (char) {
        '0'...'9', 'a'...'z', '-' => self.consume(),
        else => break :loop,
    };
    try self.emitToken(arena, .tag);
}

fn isAtEnd(self: *Scanner) bool {
    return self.current >= self.src.len;
}

fn peek(self: *Scanner) ?u8 {
    return if (self.isAtEnd()) null else self.src[self.current];
}

fn consume(self: *Scanner) void {
    self.current += 1;
}

fn advance(self: *Scanner) ?u8 {
    if (self.isAtEnd()) return null;

    const char = self.src[self.current];
    self.current += 1;
    return char;
}

fn posToLineColumn(self: *Scanner, pos: usize) struct { line: usize, column: usize } {
    var line: usize = 1;
    var column: usize = 1;
    for (self.src[0..pos]) |c| {
        if (c == '\n') {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }

    return .{ .line = line, .column = column };
}

test Scanner {
    const t = std.testing;

    t.log_level = .info;
    var arena_impl = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    var scanner: *Scanner = try .init(arena,
        \\(doctype)
        \\(html
        \\  [:lang 'en']
        \\  (head
        \\    (meta [:charset "utf-8"])
        \\    (title "Home"))
        \\  (body
        \\    (h1 "This is my home.")
        \\    "free text"))
    );
    try scanner.scan(arena);

    const expected = [_]Token{
        .{ .kind = .lparen, .src = "(", .position = 0 },
        .{ .kind = .tag, .src = "doctype", .position = 1 },
        .{ .kind = .rparen, .src = ")", .position = 8 },
        .{ .kind = .lparen, .src = "(", .position = 10 },
        .{ .kind = .tag, .src = "html", .position = 11 },
        .{ .kind = .lbracket, .src = "[", .position = 18 },
        .{ .kind = .key, .src = ":lang", .position = 19 },
        .{ .kind = .string, .src = "\'en\'", .position = 25 },
        .{ .kind = .rbracket, .src = "]", .position = 29 },
        .{ .kind = .lparen, .src = "(", .position = 33 },
        .{ .kind = .tag, .src = "head", .position = 34 },
        .{ .kind = .lparen, .src = "(", .position = 43 },
        .{ .kind = .tag, .src = "meta", .position = 44 },
        .{ .kind = .lbracket, .src = "[", .position = 49 },
        .{ .kind = .key, .src = ":charset", .position = 50 },
        .{ .kind = .string, .src = "\"utf-8\"", .position = 59 },
        .{ .kind = .rbracket, .src = "]", .position = 66 },
        .{ .kind = .rparen, .src = ")", .position = 67 },
        .{ .kind = .lparen, .src = "(", .position = 73 },
        .{ .kind = .tag, .src = "title", .position = 74 },
        .{ .kind = .string, .src = "\"Home\"", .position = 80 },
        .{ .kind = .rparen, .src = ")", .position = 86 },
        .{ .kind = .rparen, .src = ")", .position = 87 },
        .{ .kind = .lparen, .src = "(", .position = 91 },
        .{ .kind = .tag, .src = "body", .position = 92 },
        .{ .kind = .lparen, .src = "(", .position = 101 },
        .{ .kind = .tag, .src = "h1", .position = 102 },
        .{ .kind = .string, .src = "\"This is my home.\"", .position = 105 },
        .{ .kind = .rparen, .src = ")", .position = 123 },
        .{ .kind = .string, .src = "\"free text\"", .position = 129 },
        .{ .kind = .rparen, .src = ")", .position = 140 },
        .{ .kind = .rparen, .src = ")", .position = 141 },
        .{ .kind = .eof, .src = "", .position = 142 },
    };
    t.expectEqualDeep(&expected, scanner.tokens.items) catch |err| {
        for (scanner.tokens.items) |tok| {
            const kind = @tagName(tok.kind);
            std.log.err(
                ">> .{{  .kind = .{s}, .src = \"{s}\", .position = {d}  }}",
                .{ kind, tok.src, tok.position },
            );
        }
        return err;
    };
}
