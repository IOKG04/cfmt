# cfmt

Zig's `@import("std").fmt` may be good, but in some cases you just need a little bit more functionality.

Now why not just link in `libc` and use `sprintf()` and such? <br/>
Either because you are on some device where there isn't (yet) a `libc` to link against,
because you just don't *want* to link against `libc`,
or lastly because you're using some types c doesn't understand (`u19`, `f128`, etc.) and want a native zig solution.

That being said, this is not a drop in replacement, the format specifiers are a little different from c's.
I did design them to be as close as possible though, requiring little rethinking if you're already used to c.

## Format specifier

Format specifiers in `cfmt` look something like this:
```zig
"%s"     // a string
"%.4f"   // a floating-point value rounded to 4 digits after the period
"%-4.8i" // a left alligned integer of at least 4 and at most 8 digits
```

They can be split into five parts in this exact order:
A `%` character,
[flags](#flags),
[minimum width](#minimum-width),
[precision](#precision) and lastly
the [specifier](#specifiers). <br/>
All besides the specifier are optional.

The only exception to this is the specifier for writing a `%` character, which is `%%`.

### Specifiers

Specifiers tell `cfmt` what kind of type you're formatting and how you want it formatted.

The following specifiers exist:

**Integers:**
- `i`: Decimal integer
- `b`: Binary integer
- `o`: Octal integer
- `x`: Hexadecimal integer (lowercase)
- `X`: Hexadecimal integer (uppercase)

**Floating-point:**
- `f`: Decimal floating-point
<!-- `e`: Decimal scientific notation (lowercase) -->
<!-- `E`: Decimal scientific notation (uppercase) -->
<!-- `a`: Hexadecimal floating-point (lowercase)  -->
<!-- `A`: Hexadecimal floating-point (uppercase)  -->

**Other:**
- `s`: String
- `c`: Character
- `p`: Pointer

**Special:**
<br/> \*cricket noises\*
<!-- - `n`: Writes characters written so far to a `*usize` -->

For better compatibility with c's format specifiers, `d` and `u` work the same as `i`.

### Minimum width

If a minimum width is specified and the formatted string isn't that long, the string will be padded with space characters.

The minimum width can either be a decimal number, such as `4`, `9` or `142`,
or a `*`, in which case an unsigned integer is read from the arguments and its value is used as the minimum width. <br/>
If a `*` is used, the dynamic minimum width must be given before the value to be formatted (and the dynamic precision if used). <br/>
Please note that the decimal number may not have a leading zero as that could interfere with the [`0` flag](#flags).

By default, the formatted contents will be right alligned (space characters on the left),
though this behavior can be changed with the [`-` flag](#flags).

### Precision

What exactly *precision* means depends on the type to be formatted:

If it's a floating point value, precision is the amount of digits after the decimal separator.

If it's a string, precision defines the maximum amount of digits written.
If more would be written, an error is returned.

If it's a string, precision also defines the maximum amount of characters written,
though in this case the string is truncated, no error is returned.
When truncation happens, the last characters are cut off.
<!-- maybe making precision negative could make it truncate the first characters instead? -->
<!-- maybe add a way to make it throw an error instead, maybe by putting a `!` after the `.` -->

For any other type, precision doesn't do anything.

To set the precision, a `.` followed by a number or a `*` is used, similar to [minimum width](#minimum-width) except with a `.` character. <br/>
Here however, the precision is put *between* the dynamic minimum width and value to be formatted.

### Flags

Flags change some parts of formatting.

The following flags exist:
- `-`: Allign to the left instead of right (space characters on the right)
- `+`: Always write `+` and `-` sign for numeric types
- ` `: (space) Write a space character at start of positive numeric values
- `0`: Pad with `0` characters instead of space characters
<!-- `#`: Always write decimal separator for floating-point values -->
