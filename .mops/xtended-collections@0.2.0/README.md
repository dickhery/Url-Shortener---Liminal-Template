# Motoko Extended Collections Library

[![MOPS](https://img.shields.io/badge/MOPS-xtended--collections-blue)](https://mops.one/xtended-collections)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](https://github.com/edjCase/motoko_xtended_collections/blob/main/LICENSE)

A Motoko library that provides extended collections including `DynamicArray` (fork of deprecated `mo:base/Buffer`) and `StableDynamicArray` (fork of `canscale/StableBuffer`)

## MOPS

```bash
mops add xtended-collections
```

To set up MOPS package manager, follow the instructions from the [MOPS Site](https://mops.one)

## DynamicArray Module

The `DynamicArray<X>` class provides a mutable list of elements of type `X` with automatic resizing capabilities. It's comparable to `ArrayList` or `Vector` in other programming languages.

### Example Usage

```motoko
import DynamicArray "mo:xtended-collections/DynamicArray";
import Nat "mo:core/Nat";

// Create a new dynamic array
let dynamicArray = DynamicArray.DynamicArray<Nat>(3);

// Add elements
dynamicArray.add(1);
dynamicArray.add(2);
dynamicArray.add(3);

// Access elements
let first = dynamicArray.get(0); // => 1
let size = dynamicArray.size(); // => 3

// Transform elements
let doubled = DynamicArray.map(dynamicArray, func(x) { x * 2 });

// Convert to array
let array = DynamicArray.toArray(dynamicArray); // => [1, 2, 3]

// Sort elements
dynamicArray.sort(Nat.compare);

// Find elements
let index = DynamicArray.indexOf(2, dynamicArray, Nat.equal); // => ?1
```

### Constructor

```motoko
let dynamicArray = DynamicArray.DynamicArray<Nat>(8); // Initial capacity of 8
```

The constructor takes an initial capacity parameter that determines the size of the underlying array. When capacity is exceeded, the array grows by a factor of 1.5. When the size drops below 1/4 of capacity, it shrinks by a factor of 2.

### Core Operations

#### Basic Operations

-   `add(element)`: Add element to the end
-   `get(index)`: Get element at index (traps if out of bounds)
-   `getOpt(index)`: Get element at index as option
-   `put(index, element)`: Replace element at index
-   `remove(index)`: Remove element at index
-   `removeLast()`: Remove and return last element
-   `size()`: Get current number of elements
-   `capacity()`: Get current capacity

#### Bulk Operations

-   `append(dynamicArray2)`: Add all elements from another DynamicArray
-   `insert(index, element)`: Insert element at specific index
-   `insertDynamicArray(index, dynamicArray2)`: Insert another DynamicArray at index
-   `clear()`: Remove all elements
-   `reserve(capacity)`: Set minimum capacity

#### Search and Query

-   `contains(element, equal)`: Check if element exists
-   `indexOf(element, equal)`: Find first index of element
-   `lastIndexOf(element, equal)`: Find last index of element
-   `binarySearch(element, compare)`: Binary search in sorted array
-   `isEmpty()`: Check if array is empty

#### Transformation and Iteration

-   `map(f)`: Transform elements with function
-   `mapEntries(f)`: Transform elements with index
-   `mapFilter(f)`: Transform and filter elements
-   `mapResult(f)`: Transform with error handling
-   `filter(predicate)`: Keep elements matching predicate
-   `sort(compare)`: Sort elements in-place
-   `reverse()`: Reverse element order

#### Conversion

-   `toArray()`: Convert to immutable array
-   `toVarArray()`: Convert to mutable array
-   `vals()`: Get iterator over elements
-   `buffer()`: Get Buffer interface

### Advanced Operations

#### Array Manipulation

-   `subDynamicArray(start, length)`: Extract sub-array
-   `prefix(length)`: Get first n elements
-   `suffix(length)`: Get last n elements
-   `split(index)`: Split into two arrays at index

#### Functional Operations

-   `foldLeft(base, combine)`: Reduce from left
-   `foldRight(base, combine)`: Reduce from right
-   `chain(k)`: Monadic bind operation
-   `partition(predicate)`: Split based on predicate
-   `zip(dynamicArray2)`: Combine with another array
-   `zipWith(dynamicArray2, f)`: Combine with transformation

#### Grouping and Chunking

-   `chunk(size)`: Break into fixed-size chunks
-   `groupBy(equal)`: Group adjacent equal elements
-   `flatten()`: Flatten array of arrays
-   `takeWhile(predicate)`: Take elements while condition holds
-   `dropWhile(predicate)`: Skip elements while condition holds

#### Comparison and Analysis

-   `equal(dynamicArray2, equal)`: Compare arrays for equality
-   `compare(dynamicArray2, compare)`: Lexicographic comparison
-   `max(compare)`: Find maximum element
-   `min(compare)`: Find minimum element
-   `forAll(predicate)`: Check if all elements satisfy condition
-   `forSome(predicate)`: Check if any element satisfies condition
-   `forNone(predicate)`: Check if no element satisfies condition

### Static Functions

```motoko
// Utility functions
public func isEmpty<X>(dynamicArray : DynamicArray<X>) : Bool
public func contains<X>(dynamicArray : DynamicArray<X>, element : X, equal : (X, X) -> Bool) : Bool
public func clone<X>(dynamicArray : DynamicArray<X>) : DynamicArray<X>

// Conversion functions
public func fromArray<X>(array : [X]) : DynamicArray<X>
public func fromVarArray<X>(array : [var X]) : DynamicArray<X>
public func fromIter<X>(iter : { next : () -> ?X }) : DynamicArray<X>
public func toArray<X>(dynamicArray : DynamicArray<X>) : [X]
public func toVarArray<X>(dynamicArray : DynamicArray<X>) : [var X]

// Analysis functions
public func max<X>(dynamicArray : DynamicArray<X>, compare : (X, X) -> Order) : ?X
public func min<X>(dynamicArray : DynamicArray<X>, compare : (X, X) -> Order) : ?X
public func equal<X>(dynamicArray1 : DynamicArray<X>, dynamicArray2 : DynamicArray<X>, equal : (X, X) -> Bool) : Bool
public func compare<X>(dynamicArray1 : DynamicArray<X>, dynamicArray2 : DynamicArray<X>, compare : (X, X) -> Order.Order) : Order.Order

// Text and hashing
public func toText<X>(dynamicArray : DynamicArray<X>, toText : X -> Text) : Text
public func hash<X>(dynamicArray : DynamicArray<X>, hash : X -> Nat32) : Nat32

// Advanced operations
public func merge<X>(dynamicArray1 : DynamicArray<X>, dynamicArray2 : DynamicArray<X>, compare : (X, X) -> Order) : DynamicArray<X>
public func removeDuplicates<X>(dynamicArray : DynamicArray<X>, compare : (X, X) -> Order)
```

### Performance Characteristics

Most operations have the following complexity:

| Operation    | Time Complexity                                  | Space Complexity |
| ------------ | ------------------------------------------------ | ---------------- |
| `add`        | O(1) amortized, O(n) worst case                  | O(1) amortized   |
| `get/put`    | O(1)                                             | O(1)             |
| `remove`     | O(n)                                             | O(1) amortized   |
| `append`     | O(m) amortized where m is size of appended array | O(1) amortized   |
| `sort`       | O(n log n)                                       | O(n)             |
| `map/filter` | O(n)                                             | O(n)             |

### Notes

-   Operations like `add` are amortized O(1) but can take O(n) in the worst case due to resizing
-   For large arrays, worst-case operations may exceed cycle limits in some environments
-   The array maintains the invariant that `capacity >= size`
-   Recommended for storing data in stable variables by converting to arrays first

## StableDynamicArray Module

The `StableDynamicArray<X>` module provides persistent, stable dynamic arrays that maintain their state across canister upgrades. Unlike the class-based `DynamicArray`, this is a module with functions that operate on a stable data structure.

### Key Features

-   **Upgrade-safe**: Maintains state across canister upgrades when declared as `stable`
-   **Functional interface**: Uses module functions instead of class methods
-   **Same performance characteristics**: Similar O(1) amortized operations as DynamicArray
-   **Compatible API**: Most operations mirror the DynamicArray interface

### Example Usage

```motoko
import StableDynamicArray "mo:xtended-collections/StableDynamicArray";

// Declare as stable to persist across upgrades
stable let stableArray = StableDynamicArray.init<Nat>();

// Add elements
StableDynamicArray.add(stableArray, 42);
StableDynamicArray.add(stableArray, 100);

// Access elements
let size = StableDynamicArray.size(stableArray);
let firstElement = StableDynamicArray.get(stableArray, 0);
```

See the module documentation for the complete API reference.

## Attribution

**DynamicArray Module**: This module contains code originally from the [DFINITY Motoko Base Library](https://github.com/dfinity/motoko-base), specifically the `Buffer` module. The original code is licensed under Apache License 2.0.

-   Original Copyright: DFINITY Foundation
-   Original Repository: https://github.com/dfinity/motoko-base
-   Original License: Apache License 2.0

**StableDynamicArray Module**: This module contains code originally from the [canscale StableBuffer](https://github.com/canscale/StableBuffer) repository. The original code is licensed under Apache License 2.0.

-   Original Copyright: canscale organization and contributors
-   Original Repository: https://github.com/canscale/StableBuffer
-   Original License: Apache License 2.0

All other components in this library are original work unless otherwise noted.
