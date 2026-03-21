# Motoko Buffer Interface

[![MOPS](https://img.shields.io/badge/MOPS-buffer-blue)](https://mops.one/buffer)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/edjCase/motoko_buffer/blob/main/LICENSE)

A Motoko library that provides a simple, universal buffer interface for writing data to different underlying storage types. This lightweight abstraction allows you to write generic code that can work with lists, arrays, or any other writable data structure through a unified interface.

## Package

### MOPS

```bash
mops add buffer
```

To set up MOPS package manager, follow the instructions from the [MOPS Site](https://mops.one)

## Quick Start

### Example 1: Writing to a List

```motoko
import Buffer "mo:buffer";
import List "mo:core/List";
import Debug "mo:core/Debug";

// Create a list-backed buffer
let list = List.empty<Nat>();
let buffer = Buffer.fromList(list);

// Write individual items
buffer.write(1);
buffer.write(2);
buffer.write(3);

// The list now contains [1, 2, 3]
Debug.print("List size: " # debug_show(List.size(list))); // Output: "List size: 3"
```

### Example 2: Writing to an Array

```motoko
import Buffer "mo:buffer";
import Debug "mo:core/Debug";

// Create an array-backed buffer
let array : [var Nat] = [var 0, 0, 0, 0, 0];
let buffer = Buffer.fromArray(array, 0); // Start writing at index 0

// Write some data
buffer.write(10);
buffer.write(20);
buffer.write(30);

// Array now contains [10, 20, 30, 0, 0]
Debug.print("Array: " # debug_show(array)); // Output: "Array: [10, 20, 30, 0, 0]"

// Create another buffer starting at a different index
let buffer2 = Buffer.fromArray(array, 3); // Start writing at index 3
buffer2.write(40);
buffer2.write(50);

// Array now contains [10, 20, 30, 40, 50]
Debug.print("Array: " # debug_show(array)); // Output: "Array: [10, 20, 30, 40, 50]"
```

### Example 3: Writing Multiple Items

```motoko
import Buffer "mo:buffer";
import List "mo:core/List";
import Iter "mo:core/Iter";
import Debug "mo:core/Debug";

// Create a buffer
let list = List.empty<Text>();
let buffer = Buffer.fromList(list);

// Write multiple items at once
let items = ["hello", "world", "from", "motoko"];
Buffer.writeMany(buffer, Iter.fromArray(items));

// List now contains all the items
Debug.print("List size: " # debug_show(List.size(list))); // Output: "List size: 4"
```

### Example 4: Working with Legacy Buffer

```motoko
import Buffer "mo:buffer";
import OldBuffer "mo:base/Buffer";
import Debug "mo:core/Debug";

// Create a legacy buffer and wrap it
let oldBuffer = OldBuffer.Buffer<Nat>(5);
let buffer = Buffer.fromDeprecatedBuffer(oldBuffer);

// Write using the new interface
buffer.write(100);
buffer.write(200);

// The old buffer now contains the data
Debug.print("Buffer size: " # debug_show(oldBuffer.size())); // Output: "Buffer size: 2"
Debug.print("First item: " # debug_show(oldBuffer.get(0))); // Output: "First item: 100"
```

### Example 5: Generic Function Using Buffer

```motoko
import Buffer "mo:buffer";
import List "mo:core/List";
import Iter "mo:core/Iter";

// A generic function that works with any buffer implementation
func processNumbers<T>(buffer : Buffer.Buffer<Nat>, count : Nat) {
  for (i in Iter.range(0, count - 1)) {
    buffer.write(i * i); // Write squares
  };
};

// Use with different storage types
let list = List.empty<Nat>();
let listBuffer = Buffer.fromList(list);
processNumbers(listBuffer, 5); // Writes 0, 1, 4, 9, 16 to the list

let array : [var Nat] = [var 0, 0, 0, 0, 0];
let arrayBuffer = Buffer.fromArray(array, 0);
processNumbers(arrayBuffer, 5); // Writes 0, 1, 4, 9, 16 to the array
```

## API Reference

### Types

```motoko
public type Buffer<T> = {
    write : (T) -> ();
};
```

The core `Buffer<T>` type represents a write-only interface for any data structure that can accept items of type `T`.

### Functions

#### `writeMany<T>(buffer : Buffer<T>, items : Iter.Iter<T>)`

Writes multiple items to a buffer in sequence.

**Parameters:**

-   `buffer`: The buffer to write to
-   `items`: An iterator of items to write

#### `fromList<T>(list : List.List<T>) : Buffer<T>`

Creates a buffer that writes to a `List`. Items are appended to the end of the list.

**Parameters:**

-   `list`: The list to write to

**Returns:** A buffer interface for the list

#### `fromArray<T>(array : [var T], startIndex : Nat) : Buffer<T>`

Creates a buffer that writes to a mutable array starting at a specific index.

**Parameters:**

-   `array`: The mutable array to write to
-   `startIndex`: The index to start writing at

**Returns:** A buffer interface for the array

**Note:** The buffer will write sequentially starting from `startIndex`. Make sure the array has enough capacity.

#### `fromDeprecatedBuffer<T>(buffer : OldBuffer.Buffer<T>) : Buffer<T>`

Creates a buffer interface for the legacy `mo:base/Buffer` type, allowing you to use the old buffer with the new interface.

**Parameters:**

-   `buffer`: The legacy buffer to wrap

**Returns:** A buffer interface for the legacy buffer

## Use Cases

This library is particularly useful when:

1. **Building generic data processing functions** that don't need to know about the underlying storage
2. **Creating adapters** between different data structure libraries
3. **Writing streaming or pipeline code** where you want to decouple data generation from storage
4. **Migrating from legacy buffer implementations** while maintaining compatibility
5. **Building libraries** that need to work with different storage backends

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
