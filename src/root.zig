const std = @import("std");

/// maximum bitwidth of a signed integer that can be formatted
/// if you wish to adjust this, you must fork the repository
pub const max_integer_bitwidth = 64;
/// maximum bitwidth of a floating-point value that can be formatted
/// if you wish to adjust this, you must fork the repository
pub const max_float_bitwidth = 64;
/// maximum amount of arguments that can be given
/// if you wish to adjust this, you must fork the repository
pub const max_formatting_args = 32;

const FmtInteger = std.meta.Int(.signed, max_integer_bitwidth);
const FmtUnsignedInteger = std.meta.Int(.unsigned, max_float_bitwidth);
const FmtFloat = std.meta.Float(max_float_bitwidth);

/// TODO: copy description of how formats work here
/// format specifiers actually existing, args being in the right order, etc are all checked with `unreachable`.
/// so test before compiling in ReleaseFast or ReleaseSmall
pub fn format(writer: std.io.AnyWriter, fmt: []const u8, args: anytype) !void {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);
    if (args_type_info != .Struct) {
        @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
    }
    if (args_type_info.Struct.fields.len > max_integer_bitwidth) {
        @compileError("exceeded maximum amount of arguments supported per format call");
    }

    // convert tuple into a dynamically indexable format
    var args_array: [max_formatting_args]ArgsField = undefined;
    inline for (args, 0..) |arg, i| {
        const ArgType = @TypeOf(arg);
        const arg_type_info = @typeInfo(ArgType);
        switch (arg_type_info) {
            .Int, .ComptimeInt => args_array[i] = .{ .integer = @intCast(arg) },
            .Float, .ComptimeFloat => args_array[i] = .{ .float = @floatCast(arg) },
            .Bool => args_array[i] = .{ .integer = @intFromBool(arg) },
            .Pointer => |ptr| {
                // zig fmt: off
                args_array[i] =
                    if (ptr.size == .One and ptr.child == usize)                                                             .{ .usize_ptr = arg }
                    else if (ptr.size == .One and @typeInfo(ptr.child) == .Array and @typeInfo(ptr.child).Array.child == u8) .{ .string = @ptrCast(arg) }
                    else if (ptr.size == .Slice and ptr.child == u8)                                                         .{ .string = arg }
                    else                                                                                                     .{ .generic_ptr = @ptrCast(arg) };
                // zig fmt: on
            },
            else => {
                @compileError("type " ++ @typeName(ArgType) ++ " not supported by format call");
            },
        }
    }

    // actually do the formatting
    var i: usize = 0;
    var written_characters: usize = 0;
    var arguments_read: usize = 0;
    fmt_loop: while (i < fmt.len) : (i += 1) {
        // write if its a normal character
        if (fmt[i] != '%') {
            try writer.writeByte(fmt[i]);
            written_characters += 1;
            continue :fmt_loop;
        }

        // write `%` if escaping
        i += 1;
        if (fmt[i] == '%') {
            try writer.writeByte('%');
            written_characters += 1;
            continue :fmt_loop;
        }

        // parse specifier
        var specifier: Specifier = .{
            .allign = .right,
            .sign = .negative_only,
            .sign_position = .after_padding,
            .pad_char = ' ',
        };

        // flags
        flag_loop: while (true) : (i += 1) {
            switch (fmt[i]) {
                '-' => specifier.allign = .left,
                '+' => specifier.sign = .always,
                ' ' => specifier.sign = .force_space,
                '<' => specifier.sign_position = .before_padding,
                '0' => specifier.pad_char = '0',
                else => break :flag_loop,
            }
        }

        // minimum_width
        if (fmt[i] == '*') {
            std.debug.assert(arguments_read < args_array.len);
            std.debug.assert(args_array[arguments_read] == .integer);
            std.debug.assert(args_array[arguments_read].integer >= 0);
            specifier.minimum_width = @intCast(args_array[arguments_read].integer);
            arguments_read += 1;
            i += 1;
        } else if (std.ascii.isDigit(fmt[i])) {
            while (true) : (i += 1) {
                if (!std.ascii.isDigit(fmt[i])) break;
                specifier.minimum_width *= 10;
                specifier.minimum_width += fmt[i] - '0';
            }
        }

        // precision
        if (fmt[i] == '.') {
            i += 1;
            if (fmt[i] == '*') {
                std.debug.assert(arguments_read < args_array.len);
                std.debug.assert(args_array[arguments_read] == .integer);
                std.debug.assert(args_array[arguments_read].integer >= 0);
                specifier.precision = @intCast(args_array[arguments_read].integer);
                arguments_read += 1;
                i += 1;
            } else if (std.ascii.isDigit(fmt[i])) {
                specifier.precision = 0;
                while (true) : (i += 1) {
                    if (!std.ascii.isDigit(fmt[i])) break;
                    specifier.precision.? *= 10;
                    specifier.precision.? += fmt[i] - '0';
                }
            } else {
                specifier.precision = 0;
            }
        }

        // write contents
        switch (fmt[i]) {
            'i', 'd', 'u' => { // decimal integer
                std.debug.assert(arguments_read < args_array.len);
                std.debug.assert(args_array[arguments_read] == .integer);
                const value = args_array[arguments_read].integer;
                try formatInteger(writer, specifier, &written_characters, value, &[_]u8{
                    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
                });
            },
            'b' => { // binary integer
                std.debug.assert(arguments_read < args_array.len);
                std.debug.assert(args_array[arguments_read] == .integer);
                const value = args_array[arguments_read].integer;
                try formatInteger(writer, specifier, &written_characters, value, &[_]u8{
                    '0', '1',
                });
            },
            'o' => { // octal integer
                std.debug.assert(arguments_read < args_array.len);
                std.debug.assert(args_array[arguments_read] == .integer);
                const value = args_array[arguments_read].integer;
                try formatInteger(writer, specifier, &written_characters, value, &[_]u8{
                    '0', '1', '2', '3', '4', '5', '6', '7',
                });
            },
            'x' => { // hexadecimal integer (lowercase)
                std.debug.assert(arguments_read < args_array.len);
                std.debug.assert(args_array[arguments_read] == .integer);
                const value = args_array[arguments_read].integer;
                try formatInteger(writer, specifier, &written_characters, value, &[_]u8{
                    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
                });
            },
            'X' => { // hexadecimal integer (lowercase)
                std.debug.assert(arguments_read < args_array.len);
                std.debug.assert(args_array[arguments_read] == .integer);
                const value = args_array[arguments_read].integer;
                try formatInteger(writer, specifier, &written_characters, value, &[_]u8{
                    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F',
                });
            },
            's' => { // string
                std.debug.assert(arguments_read < args_array.len);
                std.debug.assert(args_array[arguments_read] == .string);
                const value = args_array[arguments_read].string;
                try formatString(writer, specifier, &written_characters, value);
            },
            'c' => { // character, the reason this isnt just a writer.writeByte() is cause of padding and precision
                std.debug.assert(arguments_read < args_array.len);
                std.debug.assert(args_array[arguments_read] == .integer);
                std.debug.assert(args_array[arguments_read].integer < 0x100);
                const value: u8 = @intCast(args_array[arguments_read].integer);
                try formatCharacter(writer, specifier, &written_characters, value);
            },
            else => unreachable,
        }
        arguments_read += 1;
    }
}

fn formatInteger(writer: std.io.AnyWriter, specifier: Specifier, written_characters: *usize, value: FmtInteger, symbols: []const u8) !void {
    const base = symbols.len;
    std.debug.assert(base > 1);
    const value_absolute = @abs(value);
    const value_digits = std.math.log(FmtUnsignedInteger, base, value_absolute) + 1;
    const sign_char = specifier.getSign(value);
    const value_length = value_digits + @intFromBool(sign_char != null);
    const padding_length = specifier.minimum_width -| value_length;

    if (sign_char != null and specifier.sign_position == .before_padding) {
        try writer.writeByte(sign_char.?);
        written_characters.* += 1;
    }
    if (specifier.allign == .right) {
        try writer.writeByteNTimes(specifier.pad_char, padding_length);
        written_characters.* += padding_length;
    }
    if (sign_char != null and specifier.sign_position == .after_padding) {
        try writer.writeByte(sign_char.?);
        written_characters.* += 1;
    }
    var digit = value_digits - 1;
    var value_left = value_absolute;
    while (true) {
        const power = @abs(std.math.pow(FmtInteger, @intCast(base), @intCast(digit)));
        const factor = @abs(@divTrunc(value_left, power));
        try writer.writeByte(symbols[factor]);
        written_characters.* += 1;
        value_left %= power;
        if (digit == 0) break;
        digit -= 1;
    }
    if (specifier.allign == .left) {
        try writer.writeByteNTimes(specifier.pad_char, padding_length);
        written_characters.* += padding_length;
    }
}
fn formatString(writer: std.io.AnyWriter, specifier: Specifier, written_characters: *usize, value: []const u8) !void {
    // zig fmt: off
    const value_length =
        if (specifier.precision) |precision| @min(value.len, precision)
        else value.len;
    // zig fmt: on
    const padding_length = specifier.minimum_width -| value_length;

    if (specifier.allign == .right) {
        try writer.writeByteNTimes(specifier.pad_char, padding_length);
        written_characters.* += padding_length;
    }
    for (0..value_length) |i| {
        try writer.writeByte(value[i]);
        written_characters.* += 1;
    }
    if (specifier.allign == .left) {
        try writer.writeByteNTimes(specifier.pad_char, padding_length);
        written_characters.* += padding_length;
    }
}
fn formatCharacter(writer: std.io.AnyWriter, specifier: Specifier, written_characters: *usize, value: u8) !void {
    const value_length = if (specifier.precision) |p| p else 1;
    const padding_length = specifier.minimum_width -| value_length;

    if (specifier.allign == .right) {
        try writer.writeByteNTimes(specifier.pad_char, padding_length);
        written_characters.* += padding_length;
    }
    try writer.writeByteNTimes(value, value_length);
    written_characters.* += value_length;
    if (specifier.allign == .left) {
        try writer.writeByteNTimes(specifier.pad_char, padding_length);
        written_characters.* += padding_length;
    }
}

const Specifier = struct {
    allign: enum { left, right },
    sign: enum { negative_only, always, force_space },
    sign_position: enum { before_padding, after_padding },
    pad_char: u8,

    /// 0 implies no minimum width set
    minimum_width: usize = 0,
    precision: ?usize = null,

    pub fn getSign(specifier: Specifier, int: FmtInteger) ?u8 {
        // zig fmt: off
        return
            if (int < 0) '-'
            else if (specifier.sign == .always) '+'
            else if (specifier.sign == .force_space) ' '
            else null;
        // zig fmt: on
    }
};
const ArgsField = union(enum) {
    integer: FmtInteger,
    float: FmtFloat,
    string: []const u8,
    usize_ptr: *usize,
    generic_ptr: *anyopaque,
};

// the below code is basically just copied from zig's standard library
pub const BufPrintError = std.fmt.BufPrintError;
/// Print a Formatter string into `buf`. Actually just a thin wrapper around `format` and `fixedBufferStream`.
/// Returns a slice of the bytes printed to.
pub fn bufPrint(buf: []u8, fmt: []const u8, args: anytype) BufPrintError![]u8 {
    var fbs = std.io.fixedBufferStream(buf);
    format(fbs.writer().any(), fmt, args) catch |err| switch (err) {
        error.NoSpaceLeft => return BufPrintError.NoSpaceLeft,
        else => unreachable,
    };
    return fbs.getWritten();
}

test "Echoing" {
    var buf: [256]u8 = undefined;

    try std.testing.expectEqualStrings("Hello World!", try bufPrint(&buf, "Hello World!", .{}));
    try std.testing.expectEqualStrings("Foxes are cute, aren't they ?:3", try bufPrint(&buf, "Foxes are cute, aren't they ?:3", .{}));
    try std.testing.expectEqualStrings("meow\n", try bufPrint(&buf, "meow\n", .{}));
}
test "% escaping" {
    var buf: [256]u8 = undefined;

    try std.testing.expectEqualStrings("%", try bufPrint(&buf, "%%", .{}));
    try std.testing.expectEqualStrings("100%", try bufPrint(&buf, "100%%", .{}));
    try std.testing.expectEqualStrings("%rax", try bufPrint(&buf, "%%rax", .{}));
}
test "Integer formatting" {
    var buf: [256]u8 = undefined;

    try std.testing.expectEqualStrings("128", try bufPrint(&buf, "%i", .{128}));
    try std.testing.expectEqualStrings("128", try bufPrint(&buf, "%d", .{128}));
    try std.testing.expectEqualStrings("128", try bufPrint(&buf, "%u", .{128}));
    try std.testing.expectEqualStrings("10000000", try bufPrint(&buf, "%b", .{128}));
    try std.testing.expectEqualStrings("200", try bufPrint(&buf, "%o", .{128}));
    try std.testing.expectEqualStrings("8a", try bufPrint(&buf, "%x", .{138}));
    try std.testing.expectEqualStrings("8A", try bufPrint(&buf, "%X", .{138}));

    try std.testing.expectEqualStrings("-184", try bufPrint(&buf, "%i", .{-184}));
    try std.testing.expectEqualStrings("-184", try bufPrint(&buf, "% i", .{-184}));
    try std.testing.expectEqualStrings("-184", try bufPrint(&buf, "%+i", .{-184}));
    try std.testing.expectEqualStrings("184", try bufPrint(&buf, "%i", .{184}));
    try std.testing.expectEqualStrings(" 184", try bufPrint(&buf, "% i", .{184}));
    try std.testing.expectEqualStrings("+184", try bufPrint(&buf, "%+i", .{184}));
}
test "Integer padding" {
    var buf: [256]u8 = undefined;

    try std.testing.expectEqualStrings("   16", try bufPrint(&buf, "%5i", .{16}));
    try std.testing.expectEqualStrings("  +16", try bufPrint(&buf, "%+5i", .{16}));
    try std.testing.expectEqualStrings("   16", try bufPrint(&buf, "% 5i", .{16}));
    try std.testing.expectEqualStrings("  -16", try bufPrint(&buf, "% 5i", .{-16}));
    try std.testing.expectEqualStrings("-  16", try bufPrint(&buf, "%< 5i", .{-16}));
    try std.testing.expectEqualStrings("16   ", try bufPrint(&buf, "%-5i", .{16}));
    try std.testing.expectEqualStrings("[   16] : [+32  ]", try bufPrint(&buf, "[%5i] : [%+-5i]", .{ 16, 32 }));
    try std.testing.expectEqualStrings("16", try bufPrint(&buf, "%1i", .{16}));
    try std.testing.expectEqualStrings("16", try bufPrint(&buf, "%2i", .{16}));
    try std.testing.expectEqualStrings("2905", try bufPrint(&buf, "%2i", .{2905}));

    try std.testing.expectEqualStrings("00256", try bufPrint(&buf, "%05i", .{256}));
    try std.testing.expectEqualStrings("0-256", try bufPrint(&buf, "%05i", .{-256}));
    try std.testing.expectEqualStrings("0+256", try bufPrint(&buf, "%0+5i", .{256}));
    try std.testing.expectEqualStrings("-0256", try bufPrint(&buf, "%0 <5i", .{-256}));
    try std.testing.expectEqualStrings(" 0256", try bufPrint(&buf, "%0 <5i", .{256}));

    try std.testing.expectEqualStrings("  33", try bufPrint(&buf, "%*i", .{ 4, 33 }));
    try std.testing.expectEqualStrings("   -33", try bufPrint(&buf, "% *i", .{ 6, -33 }));
    try std.testing.expectEqualStrings(" 0033", try bufPrint(&buf, "%<0 *i", .{ 5, 33 }));
    try std.testing.expectEqualStrings("33      ", try bufPrint(&buf, "%-*i", .{ 8, 33 }));
}
test "String formatting" {
    var buf: [256]u8 = undefined;

    try std.testing.expectEqualStrings("Hello World!", try bufPrint(&buf, "Hello %s!", .{"World"}));
    try std.testing.expectEqualStrings("do not  the cat", try bufPrint(&buf, "do not %s the cat", .{""}));

    try std.testing.expectEqualStrings("   :3", try bufPrint(&buf, "%5s", .{":3"}));
    try std.testing.expectEqualStrings("000:3", try bufPrint(&buf, "%05s", .{":3"}));
    try std.testing.expectEqualStrings(":3   ", try bufPrint(&buf, "%-5s", .{":3"}));
    try std.testing.expectEqualStrings("[uwu]", try bufPrint(&buf, "[%*s]", .{ 2, "uwu" }));

    try std.testing.expectEqualStrings("hell", try bufPrint(&buf, "%.4s", .{"hello"}));
    try std.testing.expectEqualStrings(" hello", try bufPrint(&buf, "%6.5s", .{"hello"}));
    try std.testing.expectEqualStrings("he  ", try bufPrint(&buf, "%-4.2s", .{"hello"}));
    try std.testing.expectEqualStrings("hel", try bufPrint(&buf, "%.*s", .{ 3, "hello" }));
}
test "Character formatting" {
    var buf: [256]u8 = undefined;

    try std.testing.expectEqualStrings("c", try bufPrint(&buf, "%c", .{'c'}));
    try std.testing.expectEqualStrings("4", try bufPrint(&buf, "%c", .{'4'}));

    try std.testing.expectEqualStrings("  ;3", try bufPrint(&buf, "%3c%c", .{ ';', '3' }));
    try std.testing.expectEqualStrings(";3  ", try bufPrint(&buf, "%c%-*c", .{ ';', 3, '3' }));
    try std.testing.expectEqualStrings(":0", try bufPrint(&buf, "%0-2c", .{':'}));

    try std.testing.expectEqualStrings("mmmmm", try bufPrint(&buf, "%.5c", .{'m'}));
    try std.testing.expectEqualStrings("  mmmmm", try bufPrint(&buf, "%7.5c", .{'m'}));
    try std.testing.expectEqualStrings("mmm", try bufPrint(&buf, "%*.*c", .{ 2, 3, 'm' }));
}
test "bufPrint() error.NoSpaceLeft" {
    var buf: [16]u8 = undefined;

    try std.testing.expectError(BufPrintError.NoSpaceLeft, bufPrint(&buf, "0123456789ABCDEFG", .{}));
    try std.testing.expectError(BufPrintError.NoSpaceLeft, bufPrint(&buf, "%i %i %i", .{ 12345, 67890, 12345 }));
}
