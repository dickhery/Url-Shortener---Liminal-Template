# Hex

[![mops-test](https://github.com/f0i/hex/actions/workflows/mops-test.yml/badge.svg)](https://github.com/f0i/hex/actions/workflows/mops-test.yml)

A Motoko library to convert between `Nat8` values/arrays and hexadecimal string representations.

## Installation

Install the library from mops:

```bash
mops add hex
```

## Usage

Here are some basic examples of how to use the `Hex` library:

```motoko
import Hex "mo:hex";

// Convert a byte array to a hex string
let hexString = Hex.toText([0x12, 0x34, 0x56]);
// hexString == "123456"

// Convert a hex string to a byte array
let byteArray = Hex.toArray("123456");
// byteArray == #ok([0x12, 0x34, 0x56])
```

### Usage with other types (Nat16, Int32, Float, ...)

To convert other types like `Nat` to hexadecimal strings, you can first convert them to a `Nat8` array using a library like [`byte-utils`](https://mops.one/byte-utils), and then use `Hex.toText`.

First, install `byte-utils`:

```bash
mops add byte-utils
```

Then, in your Motoko code:

```motoko
import Hex "mo:hex";
import ByteUtils "mo:byte-utils";

let bytes = ByteUtils.BE.fromNat16(0x1234); // Convert Nat16 to Big Endian byte array
let hex = Hex.toText(bytes);
// hex == "1234"
```

## API

### toText

Converts a byte array to a hex string.

```motoko
import Hex "mo:hex";

let hex = Hex.toText([0x12, 0x34, 0x56]);
// hex == "123456"
```

### toTextFormat

Converts a byte array to a hex string with custom formatting. For more details on formatting options, see [Format](#format).

```motoko
import Hex "mo:hex";

let hex = Hex.toTextFormat([1, 2], Hex.VERBOSE);
// hex == "[ 0x01, 0x02 ]"
```

### toArray

Converts a hex string to a byte array.

```motoko
import Hex "mo:hex";

let bytes = Hex.toArray("123456");
// bytes == #ok([0x12, 0x34, 0x56])
```

### toArrayFormat

Converts a hex string with custom formatting to a byte array. For more details on formatting options, see [Format](#format).

```motoko
import Hex "mo:hex";

let bytes = Hex.toArrayFormat("[ 0x01, 0x02 ]", Hex.VERBOSE);
// bytes == #ok([1, 2])
```

### toArrayUnsafe

Converts a hex string to a byte array, trapping on invalid input.

```motoko
import Hex "mo:hex";

let bytes = Hex.toArrayUnsafe("123456");
// bytes == [0x12, 0x34, 0x56]
```

### toArrayFormatUnsafe

Converts a hex string with custom formatting to a byte array, trapping on invalid input. For more details on formatting options, see [Format](#format).

```motoko
import Hex "mo:hex";

let bytes = Hex.toArrayFormatUnsafe("[ 0x01, 0x02 ]", Hex.VERBOSE);
// bytes == [1, 2]
```

### toText2D

Converts a 2D byte array to a hex string.

```motoko
import Hex "mo:hex";

let hex = Hex.toText2D([[0x12, 0x34], [0x56, 0x78]]);
// hex == "[1234, 5678]"
```

### toText2DFormat

Converts a 2D byte array to a hex string with custom formatting. For more details on formatting options, see [Format2D](#format2d).

```motoko
import Hex "mo:hex";

let hex = Hex.toText2DFormat([[1,2], []], Hex.COMPACT_2D);
// hex == "[12, 0]"
```

## Constants

### Type: Format

`Format` is a record type used to define custom formatting options for hexadecimal strings.

```motoko
import Hex "mo:hex";

let customFormat = {
  pre = "<";
  post = ">";
  sep = "-";
  preItem = "";
  empty = "";
};
print(Hex.toTextFormat([0x12, 0x34], customFormat));
/*
<12-34>
*/
```

**COMPACT**

A `Format` constant for compact hexadecimal representation (no prefixes, postfixes, or separators).

```motoko
import Hex "mo:hex";

print(Hex.toTextFormat([0x12, 0x34, 0x56], Hex.COMPACT));
/*
123456
*/
```

**COMPACT_UPPER**

A `Format` constant for compact hexadecimal representation with upper case hex values.

```motoko
import Hex "mo:hex";

print(Hex.toTextFormat([0xab, 0xcd, 0xef], Hex.COMPACT_UPPER));
/*
ABCDEF
*/
```

**COMPACT_PREFIX**

A `Format` constant for compact hexadecimal representation with a "0x" prefix for the entire string.

```motoko
import Hex "mo:hex";

print(Hex.toTextFormat([0x12, 0x34, 0x56], Hex.COMPACT_PREFIX));
/*
0x123456
*/
```

**VERBOSE**

A `Format` constant for verbose hexadecimal representation, including brackets, "0x" prefixes for items, and comma separators.

```motoko
import Hex "mo:hex";

print(Hex.toTextFormat([0x12, 0x34, 0x56], Hex.VERBOSE));
/*
[ 0x12, 0x34, 0x56 ]
*/
```

**VERBOSE_UPPER**

A `Format` constant for verbose hexadecimal representation with upper case hex values, including brackets, "0x" prefixes for items, and comma separators.

```motoko
import Hex "mo:hex";

print(Hex.toTextFormat([0xab, 0xcd, 0xef], Hex.VERBOSE_UPPER));
/*
[ 0xAB, 0xCD, 0xEF ]
*/
```

### Type: Format2D

`Format2D` is a record type used to define custom formatting options for two-dimensional hexadecimal strings. It contains two `Format` records: `inner` for the inner arrays and `outer` for the outer array.

```motoko
import Hex "mo:hex";

let customFormat2D = {
  inner = { pre = "("; post = ")"; sep = ","; preItem = ""; empty = "" };
  outer = { pre = "{"; post = "}"; sep = ";"; preItem = ""; empty = "" };
};
print(Hex.toText2DFormat([[0x01, 0x02], [0x03]], customFormat2D));
/*
{(01,02);(03)}
*/
```

**COMPACT_2D**

A `Format2D` constant for compact two-dimensional hexadecimal representation.

```motoko
import Hex "mo:hex";

print(Hex.toText2DFormat([[0x12, 0x34], [0x56, 0x78]], Hex.COMPACT_2D));
/*
[1234, 5678]
*/
```

**VERBOSE_2D**

A `Format2D` constant for verbose two-dimensional hexadecimal representation.

```motoko
import Hex "mo:hex";

print(Hex.toText2DFormat([[0x12, 0x34], [0x56, 0x78]], Hex.VERBOSE_2D));
/*
[ [ 0x12, 0x34 ], [ 0x56, 0x78 ] ]
*/
```

Example:
```motoko
import Hex "mo:hex";

print(Hex.toText2DFormat([[0x01, 0x02], [0x03, 0x04]], Hex.VERBOSE_2D));
/*
[ 0x01, 0x02 ], [ 0x03, 0x04 ]
*/
```

**MATRIX_2D**

A `Format2D` constant for a matrix-like representation of two-dimensional hexadecimal arrays.

```motoko
import Hex "mo:hex";

print(Hex.toText2DFormat([[0x01, 0x02], [0x03, 0x04]], Hex.MATRIX_2D));
/*
[ [ 0x01, 0x02 ],
  [ 0x03, 0x04 ] ]
*/
```

## License

This project is licensed under the MIT License.
