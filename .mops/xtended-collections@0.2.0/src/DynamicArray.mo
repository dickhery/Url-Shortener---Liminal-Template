/// Dynamic Array (DynamicArray) implementation for Motoko
///
/// Originally based on the Buffer module from the DFINITY Motoko Base Library
/// (https://github.com/dfinity/motoko-base) under Apache License 2.0.
/// Copyright DFINITY Foundation.
/// Extracted and adapted for continued maintenance after deprecation.
///
/// Class `DynamicArray<X>` provides a mutable list of elements of type `X`.
/// It wraps a resizable underlying array and is comparable to `ArrayList` or `Vector` in other languages.
///
/// You can convert a dynamicArray to a fixed-size array using `DynamicArray.toArray`, which is recommended for storing data in stable variables.
///
/// Like arrays, dynamicArray elements are indexed from `0` to `size - 1`.
///
/// :::note Assumptions
///
/// Runtime and space complexity assumes that `combine`, `equal`, and other functions execute in `O(1)` time and space.
///
/// :::
///
/// :::note Size vs capacity
///
/// - `size`: Number of elements in the dynamicArray.
/// - `capacity`: Length of the underlying array.
///
/// The invariant `capacity >= size` always holds.
/// :::
///
/// :::warning Performance caveat
///
/// Operations like `add` are amortized `O(1)` but can take `O(n)` in the worst case.
/// For large dynamicArrays, these worst cases may exceed the cycle limit per message.
/// Use with care when growing dynamicArrays dynamically.
/// :::
///
/// :::info Constructor behavior
///
/// The `initCapacity` argument sets the initial capacity of the underlying array.
///
/// - When the capacity is exceeded, the array grows by a factor of 1.5.
/// - When the dynamicArray size drops below 1/4 of the capacity, it shrinks by a factor of 2.
/// :::
///
/// Example:
///
/// ```motoko name=initialize
/// import DynamicArray "mo:base/DynamicArray";
///
/// let dynamicArray = DynamicArray.DynamicArray<Nat>(3); // Creates a new DynamicArray
/// ```
///
/// | Runtime   | Space     |
/// |-----------|-----------|
/// | `O(initCapacity)` | `O(initCapacity)` |

import Prim "mo:⛔";
import Result "mo:core@1/Result";
import Order "mo:core@1/Order";
import Array "mo:core@1/Array";
import Buffer "mo:buffer@0";

module {
  type Order = Order.Order;

  // The following constants are used to manage the capacity.
  // The length of `elements` is increased by `INCREASE_FACTOR` when capacity is reached.
  // The length of `elements` is decreased by `DECREASE_FACTOR` when capacity is strictly less than
  // `DECREASE_THRESHOLD`.

  // INCREASE_FACTOR = INCREASE_FACTOR_NUME / INCREASE_FACTOR_DENOM (with floating point division)
  // Keep INCREASE_FACTOR low to minimize cycle limit problem
  private let INCREASE_FACTOR_NUME = 3;
  private let INCREASE_FACTOR_DENOM = 2;
  private let DECREASE_THRESHOLD = 4; // Don't decrease capacity too early to avoid thrashing
  private let DECREASE_FACTOR = 2;
  private let DEFAULT_CAPACITY = 8;

  private func newCapacity(oldCapacity : Nat) : Nat {
    if (oldCapacity == 0) {
      1;
    } else {
      // calculates ceil(oldCapacity * INCREASE_FACTOR) without floats
      ((oldCapacity * INCREASE_FACTOR_NUME) + INCREASE_FACTOR_DENOM - 1) / INCREASE_FACTOR_DENOM;
    };
  };

  public class DynamicArray<X>(initCapacity : Nat) = this {
    var _size : Nat = 0; // avoid name clash with `size()` method
    var elements : [var ?X] = Prim.Array_init(initCapacity, null);

    /// Returns the current number of elements in the dynamicArray.
    ///
    /// Example:
    ///
    /// ```motoko include=initialize
    /// dynamicArray.size() // => 0
    /// ```
    ///
    /// | Runtime   | Space     |
    /// |-----------|-----------|
    /// | `O(1)` | `O(1)` |
    public func size() : Nat = _size;

    /// Adds a single element to the end of the dynamicArray, doubling
    /// the size of the array if capacity is exceeded.
    ///
    /// Example:
    ///
    /// ```motoko include=initialize
    /// dynamicArray.add(0); // add 0 to dynamicArray
    /// dynamicArray.add(1);
    /// dynamicArray.add(2);
    /// dynamicArray.add(3); // causes underlying array to increase in capacity
    /// DynamicArray.toArray(dynamicArray) // => [0, 1, 2, 3]
    /// ```
    ///
    /// | Runtime (worst) | Runtime (amortized) | Space (worst) | Space (amortized) |
    /// |------------------|----------------------|----------------|---------------------|
    /// | `O(size)`           | `O(1)`               | `O(size)`         | `O(1)`              |
    public func add(element : X) {
      if (_size == elements.size()) {
        reserve(newCapacity(elements.size()));
      };
      elements[_size] := ?element;
      _size += 1;
    };

    /// Returns the element at index `index`. Traps if  `index >= size`. Indexing is zero-based.
    ///
    /// Example:
    ///
    /// ```motoko include=initialize
    /// dynamicArray.add(10);
    /// dynamicArray.add(11);
    /// dynamicArray.get(0); // => 10
    /// ```
    ///
    /// | Runtime   | Space     |
    /// |-----------|-----------|
    /// | `O(1)` | `O(1)` |
    public func get(index : Nat) : X {
      switch (elements[index]) {
        case (?element) element;
        case null Prim.trap("DynamicArray index out of bounds in get");
      };
    };

    /// Returns the element at index `index` as an option.
    /// Returns `null` when `index >= size`. Indexing is zero-based.
    ///
    /// Example:
    ///
    /// ```motoko include=initialize
    /// dynamicArray.add(10);
    /// dynamicArray.add(11);
    /// let x = dynamicArray.getOpt(0); // => ?10
    /// let y = dynamicArray.getOpt(2); // => null
    /// ```
    ///
    /// | Runtime   | Space     |
    /// |-----------|-----------|
    /// | `O(1)` | `O(1)` |

    public func getOpt(index : Nat) : ?X {
      if (index < _size) {
        elements[index];
      } else {
        null;
      };
    };
    /// ```motoko include=initialize
    /// dynamicArray.add(10);
    /// dynamicArray.put(0, 20); // overwrites 10 at index 0 with 20
    /// DynamicArray.toArray(dynamicArray) // => [20]
    /// ```
    ///
    /// | Runtime   | Space     |
    /// |-----------|-----------|
    /// | `O(1)` | `O(1)` |
    ///
    public func put(index : Nat, element : X) {
      if (index >= _size) {
        Prim.trap "DynamicArray index out of bounds in put";
      };
      elements[index] := ?element;
    };

    /// Removes and returns the last item in the dynamicArray or `null` if
    /// the dynamicArray is empty.
    ///
    /// Example:
    ///
    /// ```motoko include=initialize
    /// dynamicArray.add(10);
    /// dynamicArray.add(11);
    /// dynamicArray.removeLast(); // => ?11
    /// ```
    ///
    /// | Runtime (worst) | Runtime (amortized) | Space (worst) | Space (amortized) |
    /// |------------------|----------------------|----------------|---------------------|
    /// | `O(size)`           | `O(1)`               | `O(size)`         | `O(1)`              |
    ///
    public func removeLast() : ?X {
      if (_size == 0) {
        return null;
      };

      _size -= 1;
      let lastElement = elements[_size];
      elements[_size] := null;

      if (_size < elements.size() / DECREASE_THRESHOLD) {
        // FIXME should this new capacity be a function of _size
        // instead of the current capacity? E.g. _size * INCREASE_FACTOR
        reserve(elements.size() / DECREASE_FACTOR);
      };

      lastElement;
    };

    /// Removes and returns the element at `index` from the dynamicArray.
    /// All elements with index > `index` are shifted one position to the left.
    /// This may cause a downsizing of the array.
    ///
    /// Traps if index >= size.
    ///
    /// :::warning Inefficient pattern
    ///
    /// Repeated removal of elements using this method is inefficient and may indicate that a different data structure would better suit your use case.
    /// :::
    ///
    /// Example:
    ///
    /// ```motoko include=initialize
    /// dynamicArray.add(10);
    /// dynamicArray.add(11);
    /// dynamicArray.add(12);
    /// let x = dynamicArray.remove(1); // evaluates to 11. 11 no longer in list.
    /// DynamicArray.toArray(dynamicArray) // => [10, 12]
    /// ```
    ///
    /// | Runtime (worst) | Runtime (amortized) | Space (worst) | Space (amortized) |
    /// |------------------|----------------------|----------------|---------------------|
    /// | `O(size)`           |-               | `O(size)`         | `O(1)`              |
    public func remove(index : Nat) : X {
      if (index >= _size) {
        Prim.trap "DynamicArray index out of bounds in remove";
      };

      let element = elements[index];

      // copy elements to new array and shift over in one pass
      if ((_size - 1) : Nat < elements.size() / DECREASE_THRESHOLD) {
        let elements2 = Prim.Array_init<?X>(elements.size() / DECREASE_FACTOR, null);

        var i = 0;
        var j = 0;
        label l while (i < _size) {
          if (i == index) {
            i += 1;
            continue l;
          };

          elements2[j] := elements[i];
          i += 1;
          j += 1;
        };
        elements := elements2;
      } else {
        // just shift over elements
        var i = index;
        while (i < (_size - 1 : Nat)) {
          elements[i] := elements[i + 1];
          i += 1;
        };
        elements[_size - 1] := null;
      };

      _size -= 1;

      switch (element) {
        case (?element) {
          element;
        };
        case null {
          Prim.trap "Malformed dynamicArray in remove";
        };
      };
    };

    /// Resets the dynamicArray. Capacity is set to 8.
    ///
    /// Example:
    ///
    /// ```motoko include=initialize
    /// dynamicArray.add(10);
    /// dynamicArray.add(11);
    /// dynamicArray.add(12);
    /// dynamicArray.clear(); // dynamicArray is now empty
    /// DynamicArray.toArray(dynamicArray) // => []
    /// ```
    ///
    /// | Runtime   | Space     |
    /// |-----------|-----------|
    /// | `O(1)` | `O(1)` |
    public func clear() {
      _size := 0;
      reserve(DEFAULT_CAPACITY);
    };

    /// Removes all elements from the dynamicArray for which the predicate returns false.
    /// The predicate is given both the index of the element and the element itself.
    /// This may cause a downsizing of the array.
    ///
    /// Example:
    ///
    /// ```motoko include=initialize
    /// dynamicArray.add(10);
    /// dynamicArray.add(11);
    /// dynamicArray.add(12);
    /// dynamicArray.filterEntries(func(_, x) = x % 2 == 0); // only keep even elements
    /// DynamicArray.toArray(dynamicArray) // => [10, 12]
    /// ```
    ///
    /// | Runtime (worst) | Runtime (amortized) | Space (worst) | Space (amortized) |
    /// |------------------|----------------------|----------------|---------------------|
    /// | `O(size)`           | -               | `O(size)`         | `O(1)`              |
    ///
    public func filterEntries(predicate : (Nat, X) -> Bool) {
      var numRemoved = 0;
      let keep = Prim.Array_tabulate<Bool>(
        _size,
        func i {
          switch (elements[i]) {
            case (?element) {
              if (predicate(i, element)) {
                true;
              } else {
                numRemoved += 1;
                false;
              };
            };
            case null {
              Prim.trap "Malformed dynamicArray in filter()";
            };
          };
        },
      );

      let capacity = elements.size();

      if ((_size - numRemoved : Nat) < capacity / DECREASE_THRESHOLD) {
        let elements2 = Prim.Array_init<?X>(capacity / DECREASE_FACTOR, null);

        var i = 0;
        var j = 0;
        while (i < _size) {
          if (keep[i]) {
            elements2[j] := elements[i];
            i += 1;
            j += 1;
          } else {
            i += 1;
          };
        };

        elements := elements2;
      } else {
        var i = 0;
        var j = 0;
        while (i < _size) {
          if (keep[i]) {
            elements[j] := elements[i];
            i += 1;
            j += 1;
          } else {
            i += 1;
          };
        };

        while (j < _size) {
          elements[j] := null;
          j += 1;
        };
      };

      _size -= numRemoved;
    };

    /// Returns the capacity of the dynamicArray (the length of the underlying array).
    ///
    /// Example:
    ///
    /// ```motoko include=initialize
    /// let dynamicArray = DynamicArray.DynamicArray<Nat>(2); // underlying array has capacity 2
    /// dynamicArray.add(10);
    /// let c1 = dynamicArray.capacity(); // => 2
    /// dynamicArray.add(11);
    /// dynamicArray.add(12); // causes capacity to increase by factor of 1.5
    /// let c2 = dynamicArray.capacity(); // => 3
    /// ```
    ///
    /// | Runtime   | Space     |
    /// |-----------|-----------|
    /// | `O(1)` | `O(1)` |
    public func capacity() : Nat = elements.size();

    /// Changes the capacity to `capacity`. Traps if `capacity` < `size`.
    ///
    /// ```motoko include=initialize
    /// dynamicArray.reserve(4);
    /// dynamicArray.add(10);
    /// dynamicArray.add(11);
    /// dynamicArray.capacity(); // => 4
    /// ```
    ///
    /// | Runtime   | Space     |
    /// |-----------|-----------|
    /// | `O(capacity)` | `O(capacity)` |
    public func reserve(capacity : Nat) {
      if (capacity < _size) {
        Prim.trap "capacity must be >= size in reserve";
      };

      let elements2 = Prim.Array_init<?X>(capacity, null);

      var i = 0;
      while (i < _size) {
        elements2[i] := elements[i];
        i += 1;
      };
      elements := elements2;
    };

    /// Adds all elements in dynamicArray `b` to this dynamicArray.
    ///
    /// ```motoko include=initialize
    /// let dynamicArray1 = DynamicArray.DynamicArray<Nat>(2);
    /// let dynamicArray2 = DynamicArray.DynamicArray<Nat>(2);
    /// dynamicArray1.add(10);
    /// dynamicArray1.add(11);
    /// dynamicArray2.add(12);
    /// dynamicArray2.add(13);
    /// dynamicArray1.append(dynamicArray2); // adds elements from dynamicArray2 to dynamicArray1
    /// DynamicArray.toArray(dynamicArray1) // => [10, 11, 12, 13]
    /// ```
    ///
    /// | Runtime (worst) | Runtime (amortized) | Space (worst) | Space (amortized) |
    /// |------------------|----------------------|----------------|---------------------|
    /// | `O(size1 + size2)`           | `O(size2)`              | `O(size1 +size2)`         | `O(1)`              |

    public func append(dynamicArray2 : DynamicArray<X>) {
      let size2 = dynamicArray2.size();
      // Make sure you only allocate a new array at most once
      if (_size + size2 > elements.size()) {
        // FIXME would be nice to have a tabulate for var arrays here
        reserve(newCapacity(_size + size2));
      };
      var i = 0;
      while (i < size2) {
        elements[_size + i] := dynamicArray2.getOpt i;
        i += 1;
      };

      _size += size2;
    };

    /// Inserts `element` at `index`, shifts all elements to the right of
    /// `index` over by one index. Traps if `index` is greater than size.
    ///
    /// ```motoko include=initialize
    /// let dynamicArray1 = DynamicArray.DynamicArray<Nat>(2);
    /// let dynamicArray2 = DynamicArray.DynamicArray<Nat>(2);
    /// dynamicArray.add(10);
    /// dynamicArray.add(11);
    /// dynamicArray.insert(1, 9);
    /// DynamicArray.toArray(dynamicArray) // => [10, 9, 11]
    /// ```
    ///
    /// | Runtime (worst) | Runtime (amortized) | Space (worst) | Space (amortized) |
    /// |------------------|----------------------|----------------|---------------------|
    /// | `O(size)`           | -               | `O(size)`         | `O(1)`              |
    public func insert(index : Nat, element : X) {
      if (index > _size) {
        Prim.trap "DynamicArray index out of bounds in insert";
      };
      let capacity = elements.size();

      if (_size + 1 > capacity) {
        let capacity = elements.size();
        let elements2 = Prim.Array_init<?X>(newCapacity capacity, null);
        var i = 0;
        while (i < _size + 1) {
          if (i < index) {
            elements2[i] := elements[i];
          } else if (i == index) {
            elements2[i] := ?element;
          } else {
            elements2[i] := elements[i - 1];
          };

          i += 1;
        };
        elements := elements2;
      } else {
        var i : Nat = _size;
        while (i > index) {
          elements[i] := elements[i - 1];
          i -= 1;
        };
        elements[index] := ?element;
      };

      _size += 1;
    };

    /// Inserts `dynamicArray2` at `index`, and shifts all elements to the right of
    /// `index` over by size2. Traps if `index` is greater than size.
    ///
    /// ```motoko include=initialize
    /// let dynamicArray1 = DynamicArray.DynamicArray<Nat>(2);
    /// let dynamicArray2 = DynamicArray.DynamicArray<Nat>(2);
    /// dynamicArray1.add(10);
    /// dynamicArray1.add(11);
    /// dynamicArray2.add(12);
    /// dynamicArray2.add(13);
    /// dynamicArray1.insertDynamicArray(1, dynamicArray2);
    /// DynamicArray.toArray(dynamicArray1) // => [10, 12, 13, 11]
    /// ```
    ///
    /// | Runtime (worst) | Runtime (amortized) | Space (worst) | Space (amortized) |
    /// |------------------|----------------------|----------------|---------------------|
    /// | `O(size)`           | -             | `O(size1 +size2)`         | `O(1)`              |
    public func insertDynamicArray(index : Nat, dynamicArray2 : DynamicArray<X>) {
      if (index > _size) {
        Prim.trap "DynamicArray index out of bounds in insertDynamicArray";
      };

      let size2 = dynamicArray2.size();
      let capacity = elements.size();

      // copy elements to new array and shift over in one pass
      if (_size + size2 > capacity) {
        let elements2 = Prim.Array_init<?X>(newCapacity(_size + size2), null);
        var i = 0;
        for (element in elements.vals()) {
          if (i == index) {
            i += size2;
          };
          elements2[i] := element;
          i += 1;
        };

        i := 0;
        while (i < size2) {
          elements2[i + index] := dynamicArray2.getOpt(i);
          i += 1;
        };
        elements := elements2;
      } // just insert
      else {
        var i = index;
        while (i < index + size2) {
          if (i < _size) {
            elements[i + size2] := elements[i];
          };
          elements[i] := dynamicArray2.getOpt(i - index);

          i += 1;
        };
      };

      _size += size2;
    };

    /// Sorts the elements in the dynamicArray according to `compare`.
    /// Sort is deterministic, stable, and in-place.
    ///
    /// ```motoko include=initialize
    /// import Nat "mo:base/Nat";
    ///
    /// dynamicArray.add(11);
    /// dynamicArray.add(12);
    /// dynamicArray.add(10);
    /// dynamicArray.sort(Nat.compare);
    /// DynamicArray.toArray(dynamicArray) // => [10, 11, 12]
    /// ```
    ///
    /// | Runtime   | Space     |
    /// |-----------|-----------|
    /// | `O(size * log(size))` | `O(size)` |
    public func sort(compare : (X, X) -> Order.Order) {
      // Stable merge sort in a bottom-up iterative style
      if (_size == 0) {
        return;
      };
      let scratchSpace = Prim.Array_init<?X>(_size, null);

      let sizeDec = _size - 1 : Nat;
      var currSize = 1; // current size of the subarrays being merged
      // when the current size == size, the array has been merged into a single sorted array
      while (currSize < _size) {
        var leftStart = 0; // selects the current left subarray being merged
        while (leftStart < sizeDec) {
          let mid : Nat = if (leftStart + currSize - 1 : Nat < sizeDec) {
            leftStart + currSize - 1;
          } else { sizeDec };
          let rightEnd : Nat = if (leftStart + (2 * currSize) - 1 : Nat < sizeDec) {
            leftStart + (2 * currSize) - 1;
          } else { sizeDec };

          // Merge subarrays elements[leftStart...mid] and elements[mid+1...rightEnd]
          var left = leftStart;
          var right = mid + 1;
          var nextSorted = leftStart;
          while (left < mid + 1 and right < rightEnd + 1) {
            let leftOpt = elements[left];
            let rightOpt = elements[right];
            switch (leftOpt, rightOpt) {
              case (?leftElement, ?rightElement) {
                switch (compare(leftElement, rightElement)) {
                  case (#less or #equal) {
                    scratchSpace[nextSorted] := leftOpt;
                    left += 1;
                  };
                  case (#greater) {
                    scratchSpace[nextSorted] := rightOpt;
                    right += 1;
                  };
                };
              };
              case (_, _) {
                // only sorting non-null items
                Prim.trap "Malformed dynamicArray in sort";
              };
            };
            nextSorted += 1;
          };
          while (left < mid + 1) {
            scratchSpace[nextSorted] := elements[left];
            nextSorted += 1;
            left += 1;
          };
          while (right < rightEnd + 1) {
            scratchSpace[nextSorted] := elements[right];
            nextSorted += 1;
            right += 1;
          };

          // Copy over merged elements
          var i = leftStart;
          while (i < rightEnd + 1) {
            elements[i] := scratchSpace[i];
            i += 1;
          };

          leftStart += 2 * currSize;
        };
        currSize *= 2;
      };
    };

    /// Returns an Iterator (`Iter`) over the elements of this dynamicArray.
    /// Iterator provides a single method `next()`, which returns
    /// elements in order, or `null` when out of elements to iterate over.
    ///
    /// ```motoko include=initialize
    /// dynamicArray.add(10);
    /// dynamicArray.add(11);
    /// dynamicArray.add(12);
    ///
    /// var sum = 0;
    /// for (element in dynamicArray.vals()) {
    ///  sum += element;
    /// };
    /// sum // => 33
    /// ```
    ///
    /// | Runtime   | Space     |
    /// |-----------|-----------|
    /// | `O(1)` | `O(1)` |
    public func vals() : { next : () -> ?X } = object {
      // FIXME either handle modification to underlying list
      // or explicitly warn users in documentation
      var nextIndex = 0;
      public func next() : ?X {
        if (nextIndex >= _size) {
          return null;
        };
        let nextElement = elements[nextIndex];
        nextIndex += 1;
        nextElement;
      };
    };

    /// Returns a Buffer interface for writing to this dynamicArray.
    /// This allows the dynamicArray to be used with any function that accepts
    /// a `Buffer.Buffer<X>` interface, providing interoperability with libraries
    /// that can write to various buffer implementations (arrays, lists, etc.).
    ///
    /// Example:
    ///
    /// ```motoko include=initialize
    /// Cbor.toBytesBuffer(dynamicArray.buffer(), cborValue);
    /// let cborBytes = DynamicArray.toArray(dynamicArray) // => encoded bytes
    /// ```
    ///
    /// | Runtime   | Space     |
    /// |-----------|-----------|
    /// | `O(1)` | `O(1)` |
    public func buffer() : Buffer.Buffer<X> = object {
      public func write(item : X) {
        add(item);
      };
    };
  };

  /// Returns true if and only if the dynamicArray is empty.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// dynamicArray.add(2);
  /// dynamicArray.add(0);
  /// dynamicArray.add(3);
  /// DynamicArray.isEmpty(dynamicArray); // => false
  /// ```
  ///
  /// ```motoko include=initialize
  /// DynamicArray.isEmpty(dynamicArray); // => true
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(1)` | `O(1)` |
  public func isEmpty<X>(dynamicArray : DynamicArray<X>) : Bool = dynamicArray.size() == 0;

  /// Returns true if `dynamicArray` contains `element` with respect to equality
  /// defined by `equal`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(2);
  /// dynamicArray.add(0);
  /// dynamicArray.add(3);
  /// DynamicArray.contains<Nat>(dynamicArray, 2, Nat.equal); // => true
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(1)` |
  public func contains<X>(dynamicArray : DynamicArray<X>, element : X, equal : (X, X) -> Bool) : Bool {
    for (current in dynamicArray.vals()) {
      if (equal(current, element)) {
        return true;
      };
    };

    false;
  };

  /// Returns a copy of `dynamicArray`, with the same capacity.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// dynamicArray.add(1);
  ///
  /// let clone = DynamicArray.clone(dynamicArray);
  /// DynamicArray.toArray(clone); // => [1]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func clone<X>(dynamicArray : DynamicArray<X>) : DynamicArray<X> {
    let newDynamicArray = DynamicArray<X>(dynamicArray.capacity());
    for (element in dynamicArray.vals()) {
      newDynamicArray.add(element);
    };
    newDynamicArray;
  };

  /// Finds the greatest element in `dynamicArray` defined by `compare`.
  /// Returns `null` if `dynamicArray` is empty.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  ///
  /// DynamicArray.max(dynamicArray, Nat.compare); // => ?2
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(1)` |
  public func max<X>(dynamicArray : DynamicArray<X>, compare : (X, X) -> Order) : ?X {
    if (dynamicArray.size() == 0) {
      return null;
    };

    var maxSoFar = dynamicArray.get(0);
    for (current in dynamicArray.vals()) {
      switch (compare(current, maxSoFar)) {
        case (#greater) {
          maxSoFar := current;
        };
        case _ {};
      };
    };

    ?maxSoFar;
  };

  /// Finds the least element in `dynamicArray` defined by `compare`.
  /// Returns `null` if `dynamicArray` is empty.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  ///
  /// DynamicArray.min(dynamicArray, Nat.compare); // => ?1
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(1)` |
  public func min<X>(dynamicArray : DynamicArray<X>, compare : (X, X) -> Order) : ?X {
    if (dynamicArray.size() == 0) {
      return null;
    };

    var minSoFar = dynamicArray.get(0);
    for (current in dynamicArray.vals()) {
      switch (compare(current, minSoFar)) {
        case (#less) {
          minSoFar := current;
        };
        case _ {};
      };
    };

    ?minSoFar;
  };

  /// Defines equality for two dynamicArrays, using `equal` to recursively compare elements in the
  /// dynamicArrays. Returns true if the two dynamicArrays are of the same size, and `equal`
  /// evaluates to true for every pair of elements in the two dynamicArrays of the same
  /// index.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// let dynamicArray1 = DynamicArray.DynamicArray<Nat>(2);
  /// dynamicArray1.add(1);
  /// dynamicArray1.add(2);
  ///
  /// let dynamicArray2 = DynamicArray.DynamicArray<Nat>(5);
  /// dynamicArray2.add(1);
  /// dynamicArray2.add(2);
  ///
  /// DynamicArray.equal(dynamicArray1, dynamicArray2, Nat.equal); // => true
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(1)` |
  public func equal<X>(dynamicArray1 : DynamicArray<X>, dynamicArray2 : DynamicArray<X>, equal : (X, X) -> Bool) : Bool {
    let size1 = dynamicArray1.size();

    if (size1 != dynamicArray2.size()) {
      return false;
    };

    var i = 0;
    while (i < size1) {
      if (not equal(dynamicArray1.get(i), dynamicArray2.get(i))) {
        return false;
      };
      i += 1;
    };

    true;
  };

  /// Defines comparison for two dynamicArrays, using `compare` to recursively compare elements in the
  /// dynamicArrays. Comparison is defined lexicographically.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// let dynamicArray1 = DynamicArray.DynamicArray<Nat>(2);
  /// dynamicArray1.add(1);
  /// dynamicArray1.add(2);
  ///
  /// let dynamicArray2 = DynamicArray.DynamicArray<Nat>(3);
  /// dynamicArray2.add(3);
  /// dynamicArray2.add(4);
  ///
  /// DynamicArray.compare<Nat>(dynamicArray1, dynamicArray2, Nat.compare); // => #less
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(1)` |
  public func compare<X>(dynamicArray1 : DynamicArray<X>, dynamicArray2 : DynamicArray<X>, compare : (X, X) -> Order.Order) : Order.Order {
    let size1 = dynamicArray1.size();
    let size2 = dynamicArray2.size();
    let minSize = if (size1 < size2) { size1 } else { size2 };

    var i = 0;
    while (i < minSize) {
      switch (compare(dynamicArray1.get(i), dynamicArray2.get(i))) {
        case (#less) {
          return #less;
        };
        case (#greater) {
          return #greater;
        };
        case _ {};
      };
      i += 1;
    };

    if (size1 < size2) {
      #less;
    } else if (size1 == size2) {
      #equal;
    } else {
      #greater;
    };
  };

  /// Creates a textual representation of `dynamicArray`, using `toText` to recursively
  /// convert the elements into Text.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  /// dynamicArray.add(4);
  ///
  /// DynamicArray.toText(dynamicArray, Nat.toText); // => "[1, 2, 3, 4]"
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |

  public func toText<X>(dynamicArray : DynamicArray<X>, toText : X -> Text) : Text {
    let size : Int = dynamicArray.size();
    var i = 0;
    var text = "";
    while (i < size - 1) {
      text := text # toText(dynamicArray.get(i)) # ", "; // Text implemented as rope
      i += 1;
    };
    if (size > 0) {
      // avoid the trailing comma
      text := text # toText(dynamicArray.get(i));
    };

    "[" # text # "]";
  };

  /// Hashes `dynamicArray` using `hash` to hash the underlying elements.
  /// The deterministic hash function is a function of the elements in the `dynamicArray`, as well
  /// as their ordering.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Hash "mo:base/Hash";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  /// dynamicArray.add(1000);
  ///
  /// DynamicArray.hash<Nat>(dynamicArray, Hash.hash); // => 2_872_640_342
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(1)` |
  public func hash<X>(dynamicArray : DynamicArray<X>, hash : X -> Nat32) : Nat32 {
    let size = dynamicArray.size();
    var i = 0;
    var accHash : Nat32 = 0;

    while (i < size) {
      accHash := Prim.intToNat32Wrap(i) ^ accHash ^ hash(dynamicArray.get(i));
      i += 1;
    };

    accHash;
  };

  /// Finds the first index of `element` in `dynamicArray` using equality of elements defined
  /// by `equal`. Returns `null` if `element` is not found.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  /// dynamicArray.add(4);
  ///
  /// DynamicArray.indexOf<Nat>(3, dynamicArray, Nat.equal); // => ?2
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func indexOf<X>(element : X, dynamicArray : DynamicArray<X>, equal : (X, X) -> Bool) : ?Nat {
    let size = dynamicArray.size();
    var i = 0;
    while (i < size) {
      if (equal(dynamicArray.get(i), element)) {
        return ?i;
      };
      i += 1;
    };

    null;
  };

  /// Finds the last index of `element` in `dynamicArray` using equality of elements defined
  /// by `equal`. Returns `null` if `element` is not found.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  /// dynamicArray.add(4);
  /// dynamicArray.add(2);
  /// dynamicArray.add(2);
  ///
  /// DynamicArray.lastIndexOf<Nat>(2, dynamicArray, Nat.equal); // => ?5
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func lastIndexOf<X>(element : X, dynamicArray : DynamicArray<X>, equal : (X, X) -> Bool) : ?Nat {
    let size = dynamicArray.size();
    if (size == 0) {
      return null;
    };
    var i = size;
    while (i >= 1) {
      i -= 1;
      if (equal(dynamicArray.get(i), element)) {
        return ?i;
      };
    };

    null;
  };

  /// Searches for `subDynamicArray` in `dynamicArray`, and returns the starting index if it is found.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  /// dynamicArray.add(4);
  /// dynamicArray.add(5);
  /// dynamicArray.add(6);
  ///
  /// let sub = DynamicArray.DynamicArray<Nat>(2);
  /// sub.add(4);
  /// sub.add(5);
  /// sub.add(6);
  ///
  /// DynamicArray.indexOfDynamicArray<Nat>(sub, dynamicArray, Nat.equal); // => ?3
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size of dynamicArray + size of subDynamicArray)` | `O(size of subDynamicArray)` |
  public func indexOfDynamicArray<X>(subDynamicArray : DynamicArray<X>, dynamicArray : DynamicArray<X>, equal : (X, X) -> Bool) : ?Nat {
    // Uses the KMP substring search algorithm
    // Implementation from: https://www.educative.io/answers/what-is-the-knuth-morris-pratt-algorithm
    let size = dynamicArray.size();
    let subSize = subDynamicArray.size();
    if (subSize > size or subSize == 0) {
      return null;
    };

    // precompute lps
    let lps = Prim.Array_init<Nat>(subSize, 0);
    var i = 0;
    var j = 1;

    while (j < subSize) {
      if (equal(subDynamicArray.get(i), subDynamicArray.get(j))) {
        i += 1;
        lps[j] := i;
        j += 1;
      } else if (i == 0) {
        lps[j] := 0;
        j += 1;
      } else {
        i := lps[i - 1];
      };
    };

    // start search
    i := 0;
    j := 0;
    let subSizeDec = subSize - 1 : Nat; // hoisting loop invariant
    while (i < subSize and j < size) {
      if (equal(subDynamicArray.get(i), dynamicArray.get(j)) and i == subSizeDec) {
        return ?(j - i);
      } else if (equal(subDynamicArray.get(i), dynamicArray.get(j))) {
        i += 1;
        j += 1;
      } else {
        if (i != 0) {
          i := lps[i - 1];
        } else {
          j += 1;
        };
      };
    };

    null;
  };

  /// Similar to `indexOf`, but runs in logarithmic time. Assumes that `dynamicArray` is sorted.
  /// Behavior is undefined if `dynamicArray` is not sorted. Uses `compare` to
  /// perform the search. Returns an index of `element` if it is found.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(4);
  /// dynamicArray.add(5);
  /// dynamicArray.add(6);
  ///
  /// DynamicArray.binarySearch<Nat>(5, dynamicArray, Nat.compare); // => ?2
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(log(size))` | `O(1)` |
  public func binarySearch<X>(element : X, dynamicArray : DynamicArray<X>, compare : (X, X) -> Order.Order) : ?Nat {
    var low = 0;
    var high = dynamicArray.size();

    while (low < high) {
      let mid = (low + high) / 2;
      let current = dynamicArray.get(mid);
      switch (compare(element, current)) {
        case (#equal) {
          return ?mid;
        };
        case (#less) {
          high := mid;
        };
        case (#greater) {
          low := mid + 1;
        };
      };
    };

    null;
  };

  /// Returns the sub-dynamicArray of `dynamicArray` starting at index `start`
  /// of length `length`. Traps if `start` is out of bounds, or `start + length`
  /// is greater than the size of `dynamicArray`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  /// dynamicArray.add(4);
  /// dynamicArray.add(5);
  /// dynamicArray.add(6);
  ///
  /// let sub = DynamicArray.subDynamicArray(dynamicArray, 3, 2);
  /// DynamicArray.toText(sub, Nat.toText); // => [4, 5]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(length)` | `O(length)` |
  public func subDynamicArray<X>(dynamicArray : DynamicArray<X>, start : Nat, length : Nat) : DynamicArray<X> {
    let size = dynamicArray.size();
    let end = start + length; // exclusive
    if (start >= size or end > size) {
      Prim.trap "DynamicArray index out of bounds in subDynamicArray";
    };

    let newDynamicArray = DynamicArray<X>(newCapacity length);

    var i = start;
    while (i < end) {
      newDynamicArray.add(dynamicArray.get(i));

      i += 1;
    };

    newDynamicArray;
  };

  /// Checks if `subDynamicArray` is a sub-DynamicArray of `dynamicArray`. Uses `equal` to
  /// compare elements.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  /// dynamicArray.add(4);
  /// dynamicArray.add(5);
  /// dynamicArray.add(6);
  ///
  /// let sub = DynamicArray.DynamicArray<Nat>(2);
  /// sub.add(2);
  /// sub.add(3);
  /// DynamicArray.isSubDynamicArrayOf(sub, dynamicArray, Nat.equal); // => true
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size of subDynamicArray + size of dynamicArray)` | `O(size of subDynamicArray)` |
  public func isSubDynamicArrayOf<X>(subDynamicArray : DynamicArray<X>, dynamicArray : DynamicArray<X>, equal : (X, X) -> Bool) : Bool {
    switch (indexOfDynamicArray(subDynamicArray, dynamicArray, equal)) {
      case null subDynamicArray.size() == 0;
      case _ true;
    };
  };

  /// Checks if `subDynamicArray` is a strict subDynamicArray of `dynamicArray`, i.e. `subDynamicArray` must be
  /// strictly contained inside both the first and last indices of `dynamicArray`.
  /// Uses `equal` to compare elements.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  /// dynamicArray.add(4);
  ///
  /// let sub = DynamicArray.DynamicArray<Nat>(2);
  /// sub.add(2);
  /// sub.add(3);
  /// DynamicArray.isStrictSubDynamicArrayOf(sub, dynamicArray, Nat.equal); // => true
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size of subDynamicArray + size of dynamicArray)` | `O(size of subDynamicArray)` |
  public func isStrictSubDynamicArrayOf<X>(subDynamicArray : DynamicArray<X>, dynamicArray : DynamicArray<X>, equal : (X, X) -> Bool) : Bool {
    let subDynamicArraySize = subDynamicArray.size();

    switch (indexOfDynamicArray(subDynamicArray, dynamicArray, equal)) {
      case (?index) {
        index != 0 and index != (dynamicArray.size() - subDynamicArraySize : Nat) // enforce strictness
      };
      case null {
        subDynamicArraySize == 0 and subDynamicArraySize != dynamicArray.size()
      };
    };
  };

  /// Returns the prefix of `dynamicArray` of length `length`. Traps if `length`
  /// is greater than the size of `dynamicArray`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  /// dynamicArray.add(4);
  ///
  /// let pre = DynamicArray.prefix(dynamicArray, 3); // => [1, 2, 3]
  /// DynamicArray.toText(pre, Nat.toText);
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(length)` | `O(length)` |
  ///
  public func prefix<X>(dynamicArray : DynamicArray<X>, length : Nat) : DynamicArray<X> {
    let size = dynamicArray.size();
    if (length > size) {
      Prim.trap "DynamicArray index out of bounds in prefix";
    };

    let newDynamicArray = DynamicArray<X>(newCapacity length);

    var i = 0;
    while (i < length) {
      newDynamicArray.add(dynamicArray.get(i));
      i += 1;
    };

    newDynamicArray;
  };

  /// Checks if `prefix` is a prefix of `dynamicArray`. Uses `equal` to
  /// compare elements.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  /// dynamicArray.add(4);
  ///
  /// let pre = DynamicArray.DynamicArray<Nat>(2);
  /// pre.add(1);
  /// pre.add(2);
  /// DynamicArray.isPrefixOf(pre, dynamicArray, Nat.equal); // => true
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size of prefix)` | `O(size of prefix)` |
  public func isPrefixOf<X>(prefix : DynamicArray<X>, dynamicArray : DynamicArray<X>, equal : (X, X) -> Bool) : Bool {
    let sizePrefix = prefix.size();
    if (dynamicArray.size() < sizePrefix) {
      return false;
    };

    var i = 0;
    while (i < sizePrefix) {
      if (not equal(dynamicArray.get(i), prefix.get(i))) {
        return false;
      };

      i += 1;
    };

    return true;
  };

  /// Checks if `prefix` is a strict prefix of `dynamicArray`. Uses `equal` to
  /// compare elements.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  /// dynamicArray.add(4);
  ///
  /// let pre = DynamicArray.DynamicArray<Nat>(3);
  /// pre.add(1);
  /// pre.add(2);
  /// pre.add(3);
  /// DynamicArray.isStrictPrefixOf(pre, dynamicArray, Nat.equal); // => true
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size of prefix)` | `O(size of prefix)` |
  public func isStrictPrefixOf<X>(prefix : DynamicArray<X>, dynamicArray : DynamicArray<X>, equal : (X, X) -> Bool) : Bool {
    if (dynamicArray.size() <= prefix.size()) {
      return false;
    };
    isPrefixOf(prefix, dynamicArray, equal);
  };

  /// Returns the suffix of `dynamicArray` of length `length`.
  /// Traps if `length`is greater than the size of `dynamicArray`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  /// dynamicArray.add(4);
  ///
  /// let suf = DynamicArray.suffix(dynamicArray, 3); // => [2, 3, 4]
  /// DynamicArray.toText(suf, Nat.toText);
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(length)` | `O(length)` |
  public func suffix<X>(dynamicArray : DynamicArray<X>, length : Nat) : DynamicArray<X> {
    let size = dynamicArray.size();

    if (length > size) {
      Prim.trap "DynamicArray index out of bounds in suffix";
    };

    let newDynamicArray = DynamicArray<X>(newCapacity length);

    var i = size - length : Nat;
    while (i < size) {
      newDynamicArray.add(dynamicArray.get(i));

      i += 1;
    };

    newDynamicArray;
  };

  /// Checks if `suffix` is a suffix of `dynamicArray`. Uses `equal` to compare
  /// elements.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  /// dynamicArray.add(4);
  ///
  /// let suf = DynamicArray.DynamicArray<Nat>(3);
  /// suf.add(2);
  /// suf.add(3);
  /// suf.add(4);
  /// DynamicArray.isSuffixOf(suf, dynamicArray, Nat.equal); // => true
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(length of suffix)` | `O(length of suffix)` |
  public func isSuffixOf<X>(suffix : DynamicArray<X>, dynamicArray : DynamicArray<X>, equal : (X, X) -> Bool) : Bool {
    let suffixSize = suffix.size();
    let dynamicArraySize = dynamicArray.size();
    if (dynamicArraySize < suffixSize) {
      return false;
    };

    var i = dynamicArraySize;
    var j = suffixSize;
    while (i >= 1 and j >= 1) {
      i -= 1;
      j -= 1;
      if (not equal(dynamicArray.get(i), suffix.get(j))) {
        return false;
      };
    };

    return true;
  };

  /// Checks if `suffix` is a strict suffix of `dynamicArray`. Uses `equal` to compare
  /// elements.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  /// dynamicArray.add(4);
  ///
  /// let suf = DynamicArray.DynamicArray<Nat>(3);
  /// suf.add(2);
  /// suf.add(3);
  /// suf.add(4);
  /// DynamicArray.isStrictSuffixOf(suf, dynamicArray, Nat.equal); // => true
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(length)` | `O(length)` |
  public func isStrictSuffixOf<X>(suffix : DynamicArray<X>, dynamicArray : DynamicArray<X>, equal : (X, X) -> Bool) : Bool {
    if (dynamicArray.size() <= suffix.size()) {
      return false;
    };
    isSuffixOf(suffix, dynamicArray, equal);
  };

  /// Returns true if every element in `dynamicArray` satisfies `predicate`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  /// dynamicArray.add(4);
  ///
  /// DynamicArray.forAll<Nat>(dynamicArray, func x { x > 1 }); // => true
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(1)` |
  public func forAll<X>(dynamicArray : DynamicArray<X>, predicate : X -> Bool) : Bool {
    for (element in dynamicArray.vals()) {
      if (not predicate element) {
        return false;
      };
    };

    true;
  };

  /// Returns true if some element in `dynamicArray` satisfies `predicate`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  /// dynamicArray.add(4);
  ///
  /// DynamicArray.forSome<Nat>(dynamicArray, func x { x > 3 }); // => true
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(1)` |
  public func forSome<X>(dynamicArray : DynamicArray<X>, predicate : X -> Bool) : Bool {
    for (element in dynamicArray.vals()) {
      if (predicate element) {
        return true;
      };
    };

    false;
  };

  /// Returns true if no element in `dynamicArray` satisfies `predicate`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  /// dynamicArray.add(4);
  ///
  /// DynamicArray.forNone<Nat>(dynamicArray, func x { x == 0 }); // => true
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(1)` |
  public func forNone<X>(dynamicArray : DynamicArray<X>, predicate : X -> Bool) : Bool {
    for (element in dynamicArray.vals()) {
      if (predicate element) {
        return false;
      };
    };

    true;
  };

  /// Creates an `array` containing elements from `dynamicArray`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  ///
  /// DynamicArray.toArray<Nat>(dynamicArray); // => [1, 2, 3]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func toArray<X>(dynamicArray : DynamicArray<X>) : [X] =
  // immutable clone of array
  Prim.Array_tabulate<X>(
    dynamicArray.size(),
    func(i : Nat) : X { dynamicArray.get(i) },
  );

  /// Creates a mutable array containing elements from `dynamicArray`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  ///
  /// DynamicArray.toVarArray<Nat>(dynamicArray); // => [1, 2, 3]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func toVarArray<X>(dynamicArray : DynamicArray<X>) : [var X] {
    let size = dynamicArray.size();
    if (size == 0) { [var] } else {
      let newArray = Prim.Array_init<X>(size, dynamicArray.get(0));
      var i = 1;
      while (i < size) {
        newArray[i] := dynamicArray.get(i);
        i += 1;
      };
      newArray;
    };
  };

  /// Creates a `dynamicArray` containing elements from `array`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// let array = [2, 3];
  ///
  /// let buf = DynamicArray.fromArray<Nat>(array); // => [2, 3]
  /// DynamicArray.toText(buf, Nat.toText);
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func fromArray<X>(array : [X]) : DynamicArray<X> {
    // When returning new dynamicArray, if possible, set the capacity
    // to the capacity of the old dynamicArray. Otherwise, return them
    // at 2/3 capacity (like in this case). Alternative is to
    // calculate what the size would be if the elements were
    // sequentially added using `add`. This current strategy (2/3)
    // is the upper bound of that calculation (if the last element
    // added caused a capacity increase).
    let newDynamicArray = DynamicArray<X>(newCapacity(array.size()));

    for (element in array.vals()) {
      newDynamicArray.add(element);
    };

    newDynamicArray;
  };

  /// Creates a `dynamicArray` containing elements from `array`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// let array = [var 1, 2, 3];
  ///
  /// let buf = DynamicArray.fromVarArray<Nat>(array); // => [1, 2, 3]
  /// DynamicArray.toText(buf, Nat.toText);
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func fromVarArray<X>(array : [var X]) : DynamicArray<X> {
    let newDynamicArray = DynamicArray<X>(newCapacity(array.size()));

    for (element in array.vals()) {
      newDynamicArray.add(element);
    };

    newDynamicArray;
  };

  /// Creates a `dynamicArray` containing elements from `iter`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// let array = [1, 1, 1];
  /// let iter = array.vals();
  ///
  /// let buf = DynamicArray.fromIter<Nat>(iter); // => [1, 1, 1]
  /// DynamicArray.toText(buf, Nat.toText);
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func fromIter<X>(iter : { next : () -> ?X }) : DynamicArray<X> {
    let newDynamicArray = DynamicArray<X>(DEFAULT_CAPACITY); // can't get size from `iter`

    for (element in iter) {
      newDynamicArray.add(element);
    };

    newDynamicArray;
  };

  /// Reallocates the array underlying `dynamicArray` such that capacity == size.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// let dynamicArray = DynamicArray.DynamicArray<Nat>(10);
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  ///
  /// DynamicArray.trimToSize<Nat>(dynamicArray);
  /// dynamicArray.capacity(); // => 3
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func trimToSize<X>(dynamicArray : DynamicArray<X>) {
    let size = dynamicArray.size();
    if (size < dynamicArray.capacity()) {
      dynamicArray.reserve(size);
    };
  };

  /// Creates a new `dynamicArray` by applying `f` to each element in `dynamicArray`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  ///
  /// let newBuf = DynamicArray.map<Nat, Nat>(dynamicArray, func (x) { x + 1 });
  /// DynamicArray.toText(newBuf, Nat.toText); // => [2, 3, 4]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func map<X, Y>(dynamicArray : DynamicArray<X>, f : X -> Y) : DynamicArray<Y> {
    let newDynamicArray = DynamicArray<Y>(dynamicArray.capacity());

    for (element in dynamicArray.vals()) {
      newDynamicArray.add(f element);
    };

    newDynamicArray;
  };

  /// Applies `f` to each element in `dynamicArray`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  /// import Debug "mo:base/Debug";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  ///
  /// DynamicArray.iterate<Nat>(dynamicArray, func (x) {
  ///   Debug.print(Nat.toText(x)); // prints each element in dynamicArray
  /// });
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  ///
  public func iterate<X>(dynamicArray : DynamicArray<X>, f : X -> ()) {
    for (element in dynamicArray.vals()) {
      f element;
    };
  };

  /// Applies `f` to each element in `dynamicArray` and its index.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  ///
  /// let newBuf = DynamicArray.mapEntries<Nat, Nat>(dynamicArray, func (x, i) { x + i + 1 });
  /// DynamicArray.toText(newBuf, Nat.toText); // => [2, 4, 6]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func mapEntries<X, Y>(dynamicArray : DynamicArray<X>, f : (Nat, X) -> Y) : DynamicArray<Y> {
    let newDynamicArray = DynamicArray<Y>(dynamicArray.capacity());

    var i = 0;
    let size = dynamicArray.size();
    while (i < size) {
      newDynamicArray.add(f(i, dynamicArray.get(i)));
      i += 1;
    };

    newDynamicArray;
  };

  /// Creates a new dynamicArray by applying `f` to each element in `dynamicArray`,
  /// and keeping all non-null elements.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  ///
  /// let newBuf = DynamicArray.mapFilter<Nat, Nat>(dynamicArray, func (x) {
  ///  if (x > 1) {
  ///    ?(x * 2);
  ///  } else {
  ///    null;
  ///  }
  /// });
  /// DynamicArray.toText(newBuf, Nat.toText); // => [4, 6]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func mapFilter<X, Y>(dynamicArray : DynamicArray<X>, f : X -> ?Y) : DynamicArray<Y> {
    let newDynamicArray = DynamicArray<Y>(dynamicArray.capacity());

    for (element in dynamicArray.vals()) {
      switch (f element) {
        case (?element) {
          newDynamicArray.add(element);
        };
        case _ {};
      };
    };

    newDynamicArray;
  };

  /// Creates a new dynamicArray by applying `f` to each element in `dynamicArray`.
  /// If any invocation of `f` produces an `#err`, returns an `#err`. Otherwise
  /// Returns an `#ok` containing the new dynamicArray.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Result "mo:base/Result";
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  ///
  /// let result = DynamicArray.mapResult<Nat, Nat, Text>(dynamicArray, func (k) {
  ///  if (k > 0) {
  ///    #ok(k);
  ///  } else {
  ///    #err("One or more elements are zero.");
  ///  }
  /// });
  ///
  /// Result.mapOk<DynamicArray.DynamicArray<Nat>, [Nat], Text>(result, func dynamicArray = DynamicArray.toArray(dynamicArray)) // => #ok([1, 2, 3])
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func mapResult<X, Y, E>(dynamicArray : DynamicArray<X>, f : X -> Result.Result<Y, E>) : Result.Result<DynamicArray<Y>, E> {
    let newDynamicArray = DynamicArray<Y>(dynamicArray.capacity());

    for (element in dynamicArray.vals()) {
      switch (f element) {
        case (#ok result) {
          newDynamicArray.add(result);
        };
        case (#err e) {
          return #err e;
        };
      };
    };

    #ok newDynamicArray;
  };

  /// Creates a new `dynamicArray` by applying `k` to each element in `dynamicArray`,
  /// and concatenating the resulting dynamicArrays in order. This operation
  /// is similar to what in other functional languages is known as monadic bind.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  ///
  /// let chain = DynamicArray.chain<Nat, Nat>(dynamicArray, func (x) {
  /// let b = DynamicArray.DynamicArray<Nat>(2);
  /// b.add(x);
  /// b.add(x * 2);
  /// return b;
  /// });
  /// DynamicArray.toText(chain, Nat.toText); // => [1, 2, 2, 4, 3, 6]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func chain<X, Y>(dynamicArray : DynamicArray<X>, k : X -> DynamicArray<Y>) : DynamicArray<Y> {
    let newDynamicArray = DynamicArray<Y>(dynamicArray.size() * 4);

    for (element in dynamicArray.vals()) {
      newDynamicArray.append(k element);
    };

    newDynamicArray;
  };

  /// Collapses the elements in `dynamicArray` into a single value by starting with `base`
  /// and progessively combining elements into `base` with `combine`. Iteration runs
  /// left to right.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  ///
  /// DynamicArray.foldLeft<Text, Nat>(dynamicArray, "", func (acc, x) { acc # Nat.toText(x)}); // => "123"
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(1)` |
  public func foldLeft<A, X>(dynamicArray : DynamicArray<X>, base : A, combine : (A, X) -> A) : A {
    var accumulation = base;

    for (element in dynamicArray.vals()) {
      accumulation := combine(accumulation, element);
    };

    accumulation;
  };

  /// Collapses the elements in `dynamicArray` into a single value by starting with `base`
  /// and progessively combining elements into `base` with `combine`. Iteration runs
  /// right to left.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  ///
  /// DynamicArray.foldRight<Nat, Text>(dynamicArray, "", func (x, acc) { Nat.toText(x) # acc }); // => "123"
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(1)` |
  public func foldRight<X, A>(dynamicArray : DynamicArray<X>, base : A, combine : (X, A) -> A) : A {
    let size = dynamicArray.size();
    if (size == 0) {
      return base;
    };
    var accumulation = base;

    var i = size;
    while (i >= 1) {
      i -= 1; // to avoid Nat underflow, subtract first and stop iteration at 1
      accumulation := combine(dynamicArray.get(i), accumulation);
    };

    accumulation;
  };

  /// Returns the first element of `dynamicArray`. Traps if `dynamicArray` is empty.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  ///
  /// DynamicArray.first(dynamicArray); // => 1
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(1)` | `O(1)` |
  public func first<X>(dynamicArray : DynamicArray<X>) : X = dynamicArray.get(0);

  /// Returns the last element of `dynamicArray`. Traps if `dynamicArray` is empty.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  ///
  /// DynamicArray.last(dynamicArray); // => 3
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(1)` | `O(1)` |
  public func last<X>(dynamicArray : DynamicArray<X>) : X = dynamicArray.get(dynamicArray.size() - 1);

  /// Returns a new `dynamicArray` with capacity and size 1, containing `element`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// let dynamicArray = DynamicArray.make<Nat>(1);
  /// DynamicArray.toText(dynamicArray, Nat.toText); // => [1]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(1)` | `O(1)` |
  public func make<X>(element : X) : DynamicArray<X> {
    let newDynamicArray = DynamicArray<X>(1);
    newDynamicArray.add(element);
    newDynamicArray;
  };

  /// Reverses the order of elements in `dynamicArray`.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  ///
  /// DynamicArray.reverse(dynamicArray);
  /// DynamicArray.toText(dynamicArray, Nat.toText); // => [3, 2, 1]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(1)` |
  public func reverse<X>(dynamicArray : DynamicArray<X>) {
    let size = dynamicArray.size();
    if (size == 0) {
      return;
    };

    var i = 0;
    var j = size - 1 : Nat;
    var temp = dynamicArray.get(0);
    while (i < size / 2) {
      temp := dynamicArray.get(j);
      dynamicArray.put(j, dynamicArray.get(i));
      dynamicArray.put(i, temp);
      i += 1;
      j -= 1;
    };
  };

  /// Merges two sorted dynamicArrays into a single sorted `dynamicArray`, using `compare` to define
  /// the ordering. The final ordering is stable. Behavior is undefined if either
  /// `dynamicArray1` or `dynamicArray2` is not sorted.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// let dynamicArray1 = DynamicArray.DynamicArray<Nat>(2);
  /// dynamicArray1.add(1);
  /// dynamicArray1.add(2);
  /// dynamicArray1.add(4);
  ///
  /// let dynamicArray2 = DynamicArray.DynamicArray<Nat>(2);
  /// dynamicArray2.add(2);
  /// dynamicArray2.add(4);
  /// dynamicArray2.add(6);
  ///
  /// let merged = DynamicArray.merge<Nat>(dynamicArray1, dynamicArray2, Nat.compare);
  /// DynamicArray.toText(merged, Nat.toText); // => [1, 2, 2, 4, 4, 6]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size1 + size2)` | `O(size1 + size2)` |
  public func merge<X>(dynamicArray1 : DynamicArray<X>, dynamicArray2 : DynamicArray<X>, compare : (X, X) -> Order) : DynamicArray<X> {
    let size1 = dynamicArray1.size();
    let size2 = dynamicArray2.size();

    let newDynamicArray = DynamicArray<X>(newCapacity(size1 + size2));

    var pointer1 = 0;
    var pointer2 = 0;

    while (pointer1 < size1 and pointer2 < size2) {
      let current1 = dynamicArray1.get(pointer1);
      let current2 = dynamicArray2.get(pointer2);

      switch (compare(current1, current2)) {
        case (#less) {
          newDynamicArray.add(current1);
          pointer1 += 1;
        };
        case _ {
          newDynamicArray.add(current2);
          pointer2 += 1;
        };
      };
    };

    while (pointer1 < size1) {
      newDynamicArray.add(dynamicArray1.get(pointer1));
      pointer1 += 1;
    };

    while (pointer2 < size2) {
      newDynamicArray.add(dynamicArray2.get(pointer2));
      pointer2 += 1;
    };

    newDynamicArray;
  };

  /// Eliminates all duplicate elements in `dynamicArray` as defined by `compare`.
  /// Elimination is stable with respect to the original ordering of the elements.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  ///
  /// DynamicArray.removeDuplicates<Nat>(dynamicArray, Nat.compare);
  /// DynamicArray.toText(dynamicArray, Nat.toText); // => [1, 2, 3]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size * log(size))` | `O(size)` |
  public func removeDuplicates<X>(dynamicArray : DynamicArray<X>, compare : (X, X) -> Order) {
    let size = dynamicArray.size();
    let indices = Prim.Array_tabulate<(Nat, X)>(size, func i = (i, dynamicArray.get(i)));
    // Sort based on element, while carrying original index information
    // This groups together the duplicate elements
    let sorted = Array.sort<(Nat, X)>(indices, func(pair1, pair2) = compare(pair1.1, pair2.1));
    let uniques = DynamicArray<(Nat, X)>(size);

    // Iterate over elements
    var i = 0;
    while (i < size) {
      var j = i;
      // Iterate over duplicate elements, and find the smallest index among them (for stability)
      var minIndex = sorted[j];
      label duplicates while (j < (size - 1 : Nat)) {
        let pair1 = sorted[j];
        let pair2 = sorted[j + 1];
        switch (compare(pair1.1, pair2.1)) {
          case (#equal) {
            if (pair2.0 < pair1.0) {
              minIndex := pair2;
            };
            j += 1;
          };
          case _ {
            break duplicates;
          };
        };
      };

      uniques.add(minIndex);
      i := j + 1;
    };

    // resort based on original ordering and place back in dynamicArray
    uniques.sort(
      func(pair1, pair2) {
        if (pair1.0 < pair2.0) {
          #less;
        } else if (pair1.0 == pair2.0) {
          #equal;
        } else {
          #greater;
        };
      }
    );

    dynamicArray.clear();
    dynamicArray.reserve(uniques.size());
    for (element in uniques.vals()) {
      dynamicArray.add(element.1);
    };
  };

  /// Splits `dynamicArray` into a pair of dynamicArrays where all elements in the left
  /// `dynamicArray` satisfy `predicate` and all elements in the right `dynamicArray` do not.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  /// dynamicArray.add(4);
  /// dynamicArray.add(5);
  /// dynamicArray.add(6);
  ///
  /// let partitions = DynamicArray.partition<Nat>(dynamicArray, func (x) { x % 2 == 0 });
  /// (DynamicArray.toArray(partitions.0), DynamicArray.toArray(partitions.1)) // => ([2, 4, 6], [1, 3, 5])
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func partition<X>(dynamicArray : DynamicArray<X>, predicate : X -> Bool) : (DynamicArray<X>, DynamicArray<X>) {
    let size = dynamicArray.size();
    let trueDynamicArray = DynamicArray<X>(size);
    let falseDynamicArray = DynamicArray<X>(size);

    for (element in dynamicArray.vals()) {
      if (predicate element) {
        trueDynamicArray.add(element);
      } else {
        falseDynamicArray.add(element);
      };
    };

    (trueDynamicArray, falseDynamicArray);
  };

  /// Splits the dynamicArray into two dynamicArrays at `index`, where the left dynamicArray contains
  /// all elements with indices less than `index`, and the right dynamicArray contains all
  /// elements with indices greater than or equal to `index`. Traps if `index` is out
  /// of bounds.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  /// dynamicArray.add(4);
  /// dynamicArray.add(5);
  /// dynamicArray.add(6);
  ///
  /// let split = DynamicArray.split<Nat>(dynamicArray, 3);
  /// (DynamicArray.toArray(split.0), DynamicArray.toArray(split.1)) // => ([1, 2, 3], [4, 5, 6])
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |

  public func split<X>(dynamicArray : DynamicArray<X>, index : Nat) : (DynamicArray<X>, DynamicArray<X>) {
    let size = dynamicArray.size();

    if (index < 0 or index > size) {
      Prim.trap "Index out of bounds in split";
    };

    let dynamicArray1 = DynamicArray<X>(newCapacity index);
    let dynamicArray2 = DynamicArray<X>(newCapacity(size - index));

    var i = 0;
    while (i < index) {
      dynamicArray1.add(dynamicArray.get(i));
      i += 1;
    };
    while (i < size) {
      dynamicArray2.add(dynamicArray.get(i));
      i += 1;
    };

    (dynamicArray1, dynamicArray2);
  };

  /// Breaks up `dynamicArray` into dynamicArrays of size `size`. The last chunk may
  /// have less than `size` elements if the number of elements is not divisible
  /// by the chunk size.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  /// dynamicArray.add(4);
  /// dynamicArray.add(5);
  /// dynamicArray.add(6);
  ///
  /// let chunks = DynamicArray.chunk<Nat>(dynamicArray, 3);
  /// DynamicArray.toText<DynamicArray.DynamicArray<Nat>>(chunks, func buf = DynamicArray.toText(buf, Nat.toText)); // => [[1, 2, 3], [4, 5, 6]]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(number of elements in dynamicArray)` | `O(number of elements in dynamicArray)` |
  ///
  public func chunk<X>(dynamicArray : DynamicArray<X>, size : Nat) : DynamicArray<DynamicArray<X>> {
    if (size == 0) {
      Prim.trap "Chunk size must be non-zero in chunk";
    };

    // ceil(dynamicArray.size() / size)
    let newDynamicArray = DynamicArray<DynamicArray<X>>((dynamicArray.size() + size - 1) / size);

    var newInnerDynamicArray = DynamicArray<X>(newCapacity size);
    var innerSize = 0;
    for (element in dynamicArray.vals()) {
      if (innerSize == size) {
        newDynamicArray.add(newInnerDynamicArray);
        newInnerDynamicArray := DynamicArray<X>(newCapacity size);
        innerSize := 0;
      };
      newInnerDynamicArray.add(element);
      innerSize += 1;
    };
    if (innerSize > 0) {
      newDynamicArray.add(newInnerDynamicArray);
    };

    newDynamicArray;
  };

  /// Groups equal and adjacent elements in the list into sub lists.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(2);
  /// dynamicArray.add(4);
  /// dynamicArray.add(5);
  /// dynamicArray.add(5);
  ///
  /// let grouped = DynamicArray.groupBy<Nat>(dynamicArray, func (x, y) { x == y });
  /// DynamicArray.toText<DynamicArray.DynamicArray<Nat>>(grouped, func buf = DynamicArray.toText(buf, Nat.toText)); // => [[1], [2, 2], [4], [5, 5]]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func groupBy<X>(dynamicArray : DynamicArray<X>, equal : (X, X) -> Bool) : DynamicArray<DynamicArray<X>> {
    let size = dynamicArray.size();
    let newDynamicArray = DynamicArray<DynamicArray<X>>(size);
    if (size == 0) {
      return newDynamicArray;
    };

    var i = 0;
    var baseElement = dynamicArray.get(0);
    var newInnerDynamicArray = DynamicArray<X>(size);
    while (i < size) {
      let element = dynamicArray.get(i);

      if (equal(baseElement, element)) {
        newInnerDynamicArray.add(element);
      } else {
        newDynamicArray.add(newInnerDynamicArray);
        baseElement := element;
        newInnerDynamicArray := DynamicArray<X>(size - i);
        newInnerDynamicArray.add(element);
      };
      i += 1;
    };
    if (newInnerDynamicArray.size() > 0) {
      newDynamicArray.add(newInnerDynamicArray);
    };

    newDynamicArray;
  };

  /// Flattens the `dynamicArray` of dynamicArrays into a single `dynamicArray`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// let dynamicArray = DynamicArray.DynamicArray<DynamicArray.DynamicArray<Nat>>(1);
  ///
  /// let inner1 = DynamicArray.DynamicArray<Nat>(2);
  /// inner1.add(1);
  /// inner1.add(2);
  ///
  /// let inner2 = DynamicArray.DynamicArray<Nat>(2);
  /// inner2.add(3);
  /// inner2.add(4);
  ///
  /// dynamicArray.add(inner1);
  /// dynamicArray.add(inner2);
  /// // dynamicArray = [[1, 2], [3, 4]]
  ///
  /// let flat = DynamicArray.flatten<Nat>(dynamicArray);
  /// DynamicArray.toText<Nat>(flat, Nat.toText); // => [1, 2, 3, 4]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(number of elements in dynamicArray)` | `O(number of elements in dynamicArray)` |
  public func flatten<X>(dynamicArray : DynamicArray<DynamicArray<X>>) : DynamicArray<X> {
    let size = dynamicArray.size();
    if (size == 0) {
      return DynamicArray<X>(0);
    };

    let newDynamicArray = DynamicArray<X>(
      if (dynamicArray.get(0).size() != 0) {
        newCapacity(dynamicArray.get(0).size() * size);
      } else {
        newCapacity(size);
      }
    );

    for (innerDynamicArray in dynamicArray.vals()) {
      for (innerElement in innerDynamicArray.vals()) {
        newDynamicArray.add(innerElement);
      };
    };

    newDynamicArray;
  };

  /// Combines the two dynamicArrays into a single dynamicArray of pairs, pairing together
  /// elements with the same index. If one dynamicArray is longer than the other, the
  /// remaining elements from the longer dynamicArray are not included.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  ///
  /// let dynamicArray1 = DynamicArray.DynamicArray<Nat>(2);
  /// dynamicArray1.add(1);
  /// dynamicArray1.add(2);
  /// dynamicArray1.add(3);
  ///
  /// let dynamicArray2 = DynamicArray.DynamicArray<Nat>(2);
  /// dynamicArray2.add(4);
  /// dynamicArray2.add(5);
  ///
  /// let zipped = DynamicArray.zip(dynamicArray1, dynamicArray2);
  /// DynamicArray.toArray(zipped); // => [(1, 4), (2, 5)]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(min(size1, size2))` | `O(min(size1, size2))` |
  public func zip<X, Y>(dynamicArray1 : DynamicArray<X>, dynamicArray2 : DynamicArray<Y>) : DynamicArray<(X, Y)> {
    // compiler should pull lamda out as a static function since it is fully closed
    zipWith<X, Y, (X, Y)>(dynamicArray1, dynamicArray2, func(x, y) = (x, y));
  };

  /// Combines the two dynamicArrays into a single dynamicArray, pairing together
  /// elements with the same index and combining them using `zip`. If
  /// one dynamicArray is longer than the other, the remaining elements from
  /// the longer dynamicArray are not included.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  ///
  /// let dynamicArray1 = DynamicArray.DynamicArray<Nat>(2);
  /// dynamicArray1.add(1);
  /// dynamicArray1.add(2);
  /// dynamicArray1.add(3);
  ///
  /// let dynamicArray2 = DynamicArray.DynamicArray<Nat>(2);
  /// dynamicArray2.add(4);
  /// dynamicArray2.add(5);
  /// dynamicArray2.add(6);
  ///
  /// let zipped = DynamicArray.zipWith<Nat, Nat, Nat>(dynamicArray1, dynamicArray2, func (x, y) { x + y });
  /// DynamicArray.toArray(zipped) // => [5, 7, 9]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(min(size1, size2))` | `O(min(size1, size2))` |
  ///
  public func zipWith<X, Y, Z>(dynamicArray1 : DynamicArray<X>, dynamicArray2 : DynamicArray<Y>, zip : (X, Y) -> Z) : DynamicArray<Z> {
    let size1 = dynamicArray1.size();
    let size2 = dynamicArray2.size();
    let minSize = if (size1 < size2) { size1 } else { size2 };

    var i = 0;
    let newDynamicArray = DynamicArray<Z>(newCapacity minSize);
    while (i < minSize) {
      newDynamicArray.add(zip(dynamicArray1.get(i), dynamicArray2.get(i)));
      i += 1;
    };
    newDynamicArray;
  };

  /// Creates a new dynamicArray taking elements in order from `dynamicArray` until predicate
  /// returns false.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  ///
  /// let newBuf = DynamicArray.takeWhile<Nat>(dynamicArray, func (x) { x < 3 });
  /// DynamicArray.toText(newBuf, Nat.toText); // => [1, 2]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func takeWhile<X>(dynamicArray : DynamicArray<X>, predicate : X -> Bool) : DynamicArray<X> {
    let newDynamicArray = DynamicArray<X>(dynamicArray.size());

    for (element in dynamicArray.vals()) {
      if (not predicate element) {
        return newDynamicArray;
      };
      newDynamicArray.add(element);
    };

    newDynamicArray;
  };

  /// Creates a new dynamicArray excluding elements in order from `dynamicArray` until predicate
  /// returns false.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  ///
  /// let newBuf = DynamicArray.dropWhile<Nat>(dynamicArray, func x { x < 3 }); // => [3]
  /// DynamicArray.toText(newBuf, Nat.toText);
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func dropWhile<X>(dynamicArray : DynamicArray<X>, predicate : X -> Bool) : DynamicArray<X> {
    let size = dynamicArray.size();
    let newDynamicArray = DynamicArray<X>(size);

    var i = 0;
    var take = false;
    label iter for (element in dynamicArray.vals()) {
      if (not (take or predicate element)) {
        take := true;
      };
      if (take) {
        newDynamicArray.add(element);
      };
    };
    newDynamicArray;
  };
};
