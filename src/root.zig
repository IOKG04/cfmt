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
            .pad_char = ' ',
        };

        // flags
        flag_loop: while (true) : (i += 1) {
            switch (fmt[i]) {
                '-' => specifier.allign = .left,
                '+' => specifier.sign = .always,
                ' ' => specifier.sign = .force_space,
                '0' => specifier.pad_char = '0',
                else => break :flag_loop,
            }
        }

        // minimum_width
        if (fmt[i] == '*') {
            std.debug.assert(args_array[arguments_read] == .usize_ptr);
            specifier.minimum_width = args_array[arguments_read].usize_ptr.*;
            arguments_read += 1;
        }
        else if (std.ascii.isDigit(fmt[i])) {
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
                std.debug.assert(args_array[arguments_read] == .usize_ptr);
                specifier.precision = args_array[arguments_read].usize_ptr.*;
                arguments_read += 1;
            }
            else if (std.ascii.isDigit(fmt[i])) {
                specifier.precision = 0;
                while (true) : (i += 1) {
                    if (!std.ascii.isDigit(fmt[i])) break;
                    specifier.precision.? *= 10;
                    specifier.precision.? += fmt[i] - '0';
                }
            }
            else {
                specifier.precision = 0;
            }
        }

        // write contents
        switch (fmt[i]) {
            'i', 'd', 'u' => { // decimal integer
                // TODO: add precision to this mess
                std.debug.assert(args_array[arguments_read] == .integer);
                const val = args_array[arguments_read].integer;
                const val_abs = @abs(val);
                const val_digits: usize = @intCast(std.math.log10(val_abs) + 1);
                const sign_char = specifier.getSign(val);
                const int_length: usize = val_digits + @intFromBool(sign_char != null);
                const padding_length: usize =
                    if (specifier.minimum_width == 0) 0
                    else if (int_length >= specifier.minimum_width) 0
                    else specifier.minimum_width - int_length;

                if (specifier.allign == .right) {
                    try writer.writeByteNTimes(specifier.pad_char, padding_length);
                    written_characters += padding_length;
                }
                if (sign_char) |sign| {
                    try writer.writeByte(sign);
                    written_characters += 1;
                }
                var digit = val_digits - 1;
                var val_left = val;
                while (true) {
                    const base = std.math.pow(FmtInteger, 10, @intCast(digit));
                    const multiplier: u8 = @intCast(@abs(@divTrunc(val_left, base)));
                    try writer.writeByte('0' + multiplier);
                    written_characters += 1;
                    val_left = @mod(val_left, base);
                    if (digit == 0) break;
                    digit -= 1;
                }
                if (specifier.allign == .left) {
                    try writer.writeByteNTimes(specifier.pad_char, padding_length);
                    written_characters += padding_length;
                }
            },
            else => unreachable,
        }
        arguments_read += 1;
    }
}

const Specifier = struct {
    allign: enum { left, right },
    sign: enum { negative_only, always, force_space },
    pad_char: u8,

    /// 0 implies no minimum width set
    minimum_width: usize = 0,
    precision: ?usize = null,

    pub fn getSign(specifier: Specifier, int: FmtInteger) ?u8 {
        return
            if (int < 0) '-'
            else if (specifier.sign == .always) '+'
            else if (specifier.sign == .force_space) ' '
            else null;
    }
};
const ArgsField = union (enum) {
    integer: FmtInteger,
    float: FmtFloat,
    string: []const u8,
    usize_ptr: *usize,
    generic_ptr: *anyopaque,
};
pub const FormatError = error {
};
