/// Stable Dynamic Array (StableDynamicArray) implementation for Motoko
///
/// Originally based on the StableBuffer module from the canscale organization
/// (https://github.com/canscale/StableBuffer) under Apache License 2.0.
/// Copyright canscale organization and contributors.
/// Extracted and adapted with modifications for this library.
///
/// Generic, extensible dynamic arrays
///
/// `StableDynamicArray<X>` is adapted directly from https://github.com/dfinity/motoko-base/blob/master/src/DynamicArray.mo,
/// ripping all functions and instance variables out of the `DynamicArray` class in order to make a stable, persistent
/// dynamicArray.
///
/// Generic, mutable sequences that grow to accommodate arbitrary numbers of elements.
///
/// `StableDynamicArray<X>` provides extensible, mutable sequences of elements of type `X`.
/// that can be efficiently produced and consumed with imperative code.
/// A dynamicArray object can be extended by a single element or the contents of another dynamicArray object.
///
/// When required, the current state of a dynamicArray object can be converted to a fixed-size array of its elements.
///
/// DynamicArrays complement Motoko's non-extensible array types
/// (arrays do not support efficient extension, because the size of an array is
/// determined at construction and cannot be changed).

import Prim "mo:⛔";
import Result "mo:core@1/Result";
import Order "mo:core@1/Order";
import Array "mo:core@1/Array";

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

  public type StableDynamicArray<X> = {
    initCapacity : Nat;
    var count : Nat;
    var elems : [var ?X];
  };

  /// Initializes a dynamicArray of given initial capacity. Note that this capacity is not realized until an element
  /// is added to the dynamicArray.
  public func initPresized<X>(initCapacity : Nat) : StableDynamicArray<X> = {
    initCapacity = initCapacity;
    var count = 0;
    var elems = Prim.Array_init(initCapacity, null);
  };

  /// Initializes a dynamicArray of initial capacity 0. When the first element is added the size will grow to one
  public func init<X>() : StableDynamicArray<X> = {
    initCapacity = 0;
    var count = 0;
    var elems = [var];
  };

  /// Adds a single element to the end of the dynamicArray, doubling
  /// the size of the array if capacity is exceeded.
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// StableDynamicArray.add(dynamicArray, 0); // add 0 to dynamicArray
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3); // causes underlying array to increase in capacity
  /// StableDynamicArray.toArray(dynamicArray) // => [0, 1, 2, 3]
  /// ```
  ///
  /// Amortized Runtime: O(1), Worst Case Runtime: O(size)
  ///
  /// Amortized Space: O(1), Worst Case Space: O(size)
  public func add<X>(dynamicArray : StableDynamicArray<X>, element : X) {
    if (dynamicArray.count == dynamicArray.elems.size()) {
      reserve(dynamicArray, newCapacity(dynamicArray.elems.size()));
    };
    dynamicArray.elems[dynamicArray.count] := ?element;
    dynamicArray.count += 1;
  };

  /// Removes and returns the element at `index` from the dynamicArray.
  /// All elements with index > `index` are shifted one position to the left.
  /// This may cause a downsizing of the array.
  ///
  /// Traps if index >= size.
  ///
  /// WARNING: Repeated removal of elements using this method is ineffecient
  /// and might be a sign that you should consider a different data-structure
  /// for your use case.
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// StableDynamicArray.add(dynamicArray, 10);
  /// StableDynamicArray.add(dynamicArray, 11);
  /// StableDynamicArray.add(dynamicArray, 12);
  /// let x = StableDynamicArray.remove(dynamicArray, 1); // evaluates to 11. 11 no longer in list.
  /// StableDynamicArray.toArray(dynamicArray) // => [10, 12]
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Amortized Space: O(1), Worst Case Space: O(size)
  public func remove<X>(dynamicArray : StableDynamicArray<X>, index : Nat) : X {
    if (index >= dynamicArray.count) {
      Prim.trap "DynamicArray index out of bounds in remove";
    };

    let element = dynamicArray.elems[index];

    // copy elements to new array and shift over in one pass
    if ((dynamicArray.count - 1) : Nat < dynamicArray.elems.size() / DECREASE_THRESHOLD) {
      let elements2 = Prim.Array_init<?X>(dynamicArray.elems.size() / DECREASE_FACTOR, null);

      var i = 0;
      var j = 0;
      label l while (i < dynamicArray.count) {
        if (i == index) {
          i += 1;
          continue l;
        };

        elements2[j] := dynamicArray.elems[i];
        i += 1;
        j += 1;
      };
      dynamicArray.elems := elements2;
    } else {
      // just shift over elements
      var i = index;
      while (i < (dynamicArray.count - 1 : Nat)) {
        dynamicArray.elems[i] := dynamicArray.elems[i + 1];
        i += 1;
      };
      dynamicArray.elems[dynamicArray.count - 1] := null;
    };

    dynamicArray.count -= 1;

    switch (element) {
      case (?element) {
        element;
      };
      case null {
        Prim.trap "Malformed dynamicArray in remove";
      };
    };
  };

  /// Removes and returns the last item in the dynamicArray or `null` if
  /// the dynamicArray is empty.
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// StableDynamicArray.add(dynamicArray, 10);
  /// StableDynamicArray.add(dynamicArray, 11);
  /// StableDynamicArray.removeLast(dynamicArray); // => ?11
  /// ```
  ///
  /// Amortized Runtime: O(1), Worst Case Runtime: O(size)
  ///
  /// Amortized Space: O(1), Worst Case Space: O(size)
  public func removeLast<X>(dynamicArray : StableDynamicArray<X>) : ?X {
    if (dynamicArray.count == 0) {
      return null;
    };

    dynamicArray.count -= 1;
    let lastElement = dynamicArray.elems[dynamicArray.count];
    dynamicArray.elems[dynamicArray.count] := null;

    if (dynamicArray.count < dynamicArray.elems.size() / DECREASE_THRESHOLD) {
      // FIXME should this new capacity be a function of count
      // instead of the current capacity? E.g. count * INCREASE_FACTOR
      reserve(dynamicArray, dynamicArray.elems.size() / DECREASE_FACTOR);
    };

    lastElement;
  };

  /// Adds all elements in dynamicArray `b` to this dynamicArray.
  ///
  /// ```motoko include=initialize
  /// let dynamicArray1 = StableDynamicArray.initPresized<Nat>(2);
  /// let dynamicArray2 = StableDynamicArray.initPresized<Nat>(2);
  /// StableDynamicArray.add(dynamicArray1, 10);
  /// StableDynamicArray.add(dynamicArray1, 11);
  /// StableDynamicArray.add(dynamicArray2, 12);
  /// StableDynamicArray.add(dynamicArray2, 13);
  /// StableDynamicArray.append(dynamicArray1, dynamicArray2); // adds elements from dynamicArray2 to dynamicArray1
  /// StableDynamicArray.toArray(dynamicArray1) // => [10, 11, 12, 13]
  /// ```
  ///
  /// Amortized Runtime: O(size2), Worst Case Runtime: O(size1 + size2)
  ///
  /// Amortized Space: O(1), Worst Case Space: O(size1 + size2)
  public func append<X>(dynamicArray : StableDynamicArray<X>, dynamicArray2 : StableDynamicArray<X>) {
    let size2 = size(dynamicArray2);

    // Make sure you only allocate a new array at most once
    if (dynamicArray.count + size2 > dynamicArray.elems.size()) {
      // FIXME would be nice to have a tabulate for var arrays here
      reserve(dynamicArray, newCapacity(dynamicArray.count + size2));
    };
    var i = 0;
    while (i < size2) {
      dynamicArray.elems[dynamicArray.count + i] := getOpt(dynamicArray2, i);
      i += 1;
    };

    dynamicArray.count += size2;
  };

  /// Returns the current number of elements in the dynamicArray.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// size(dynamicArray) // => 0
  /// ```
  ///
  /// Runtime: O(1)
  ///
  /// Space: O(1)
  public func size<X>(dynamicArray : StableDynamicArray<X>) : Nat = dynamicArray.count;

  /// Returns the capacity of the dynamicArray (the length of the underlying array).
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// let dynamicArray = StableDynamicArray.initPresized<Nat>(2); // underlying array has capacity 2
  /// StableDynamicArray.add(dynamicArray, 10);
  /// let c1 = StableDynamicArray.capacity(dynamicArray); // => 2
  /// StableDynamicArray.add(dynamicArray, 11);
  /// StableDynamicArray.add(dynamicArray, 12); // causes capacity to increase by factor of 1.5
  /// let c2 = StableDynamicArray.capacity(dynamicArray); // => 3
  /// ```
  ///
  /// Runtime: O(1)
  ///
  /// Space: O(1)
  public func capacity<X>(dynamicArray : StableDynamicArray<X>) : Nat = dynamicArray.elems.size();

  /// Changes the capacity to `capacity`. Traps if `capacity` < `size`.
  ///
  /// ```motoko include=initialize
  ///
  /// StableDynamicArray.reserve(dynamicArray, 4);
  /// StableDynamicArray.add(dynamicArray, 10);
  /// StableDynamicArray.add(dynamicArray, 11);
  /// StableDynamicArray.capacity(dynamicArray); // => 4
  /// ```
  ///
  /// Runtime: O(capacity)
  ///
  /// Space: O(capacity)
  public func reserve<X>(dynamicArray : StableDynamicArray<X>, capacity : Nat) {
    if (capacity < dynamicArray.count) {
      Prim.trap "capacity must be >= size in reserve";
    };

    let elements2 = Prim.Array_init<?X>(capacity, null);

    var i = 0;
    while (i < dynamicArray.count) {
      elements2[i] := dynamicArray.elems[i];
      i += 1;
    };
    dynamicArray.elems := elements2;
  };

  /// Resets the dynamicArray. Capacity is set to 8.
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// StableDynamicArray.add(dynamicArray, 10);
  /// StableDynamicArray.add(dynamicArray, 11);
  /// StableDynamicArray.add(dynamicArray, 12);
  /// StableDynamicArray.clear(dynamicArray, ); // dynamicArray is now empty
  /// StableDynamicArray.toArray(dynamicArray) // => []
  /// ```
  ///
  /// Runtime: O(1)
  ///
  /// Space: O(1)
  public func clear<X>(dynamicArray : StableDynamicArray<X>) {
    dynamicArray.count := 0;
    reserve(dynamicArray, DEFAULT_CAPACITY);
  };

  /// Returns a copy of `dynamicArray`, with the same capacity.
  ///
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  ///
  /// let clone = StableDynamicArray.clone(dynamicArray);
  /// StableDynamicArray.toArray(clone); // => [1]
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(size)
  public func clone<X>(dynamicArray : StableDynamicArray<X>) : StableDynamicArray<X> {
    let newDynamicArray = initPresized<X>(capacity(dynamicArray));
    for (element in vals(dynamicArray)) {
      add(newDynamicArray, element);
    };
    newDynamicArray;
  };

  /// Returns an Iterator (`Iter`) over the elements of this dynamicArray.
  /// Iterator provides a single method `next()`, which returns
  /// elements in order, or `null` when out of elements to iterate over.
  ///
  /// ```motoko include=initialize
  ///
  /// StableDynamicArray.add(dynamicArray, 10);
  /// StableDynamicArray.add(dynamicArray, 11);
  /// StableDynamicArray.add(dynamicArray, 12);
  ///
  /// var sum = 0;
  /// for (element in StableDynamicArray.vals(dynamicArray, )) {
  ///   sum += element;
  /// };
  /// sum // => 33
  /// ```
  ///
  /// Runtime: O(1)
  ///
  /// Space: O(1)
  public func vals<X>(dynamicArray : StableDynamicArray<X>) : {
    next : () -> ?X;
  } = object {
    // FIXME either handle modification to underlying list
    // or explicitly warn users in documentation
    var nextIndex = 0;
    public func next() : ?X {
      if (nextIndex >= dynamicArray.count) {
        return null;
      };
      let nextElement = dynamicArray.elems[nextIndex];
      nextIndex += 1;
      nextElement;
    };
  };

  /// Creates a dynamicArray containing elements from `array`.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// let array = [2, 3];
  ///
  /// let buf = StableDynamicArray.fromArray<Nat>(array); // => [2, 3]
  /// StableDynamicArray.toText(buf, Nat.toText);
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(size)
  public func fromArray<X>(array : [X]) : StableDynamicArray<X> {
    // When returning new dynamicArray, if possible, set the capacity
    // to the capacity of the old dynamicArray. Otherwise, return them
    // at 2/3 capacity (like in this case). Alternative is to
    // calculate what the size would be if the elements were
    // sequentially added using `add`. This current strategy (2/3)
    // is the upper bound of that calculation (if the last element
    // added caused a capacity increase).
    let newDynamicArray = initPresized<X>(newCapacity(array.size()));

    for (element in array.vals()) {
      add(newDynamicArray, element);
    };

    newDynamicArray;
  };

  /// Creates an array containing elements from `dynamicArray`.
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  ///
  /// StableDynamicArray.toArray<Nat>(dynamicArray); // => [1, 2, 3]
  ///
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(size)
  public func toArray<X>(dynamicArray : StableDynamicArray<X>) : [X] =
  // immutable clone of array
  Prim.Array_tabulate<X>(
    size(dynamicArray),
    func(i : Nat) : X { get(dynamicArray, i) },
  );

  /// Creates a mutable array containing elements from `dynamicArray`.
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  ///
  /// StableDynamicArray.toVarArray<Nat>(dynamicArray); // => [1, 2, 3]
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(size)
  public func toVarArray<X>(dynamicArray : StableDynamicArray<X>) : [var X] {
    let count = size(dynamicArray);
    if (count == 0) { [var] } else {
      let newArray = Prim.Array_init<X>(count, get(dynamicArray, 0));
      var i = 1;
      while (i < count) {
        newArray[i] := get(dynamicArray, i);
        i += 1;
      };
      newArray;
    };
  };

  /// Returns the element at index `index`. Traps if  `index >= size`. Indexing is zero-based.
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// StableDynamicArray.add(dynamicArray,10);
  /// StableDynamicArray.add(dynamicArray,11);
  /// StableDynamicArray.get(dynamicArray,0); // => 10
  /// ```
  ///
  /// Runtime: O(1)
  ///
  /// Space: O(1)
  public func get<X>(dynamicArray : StableDynamicArray<X>, index : Nat) : X {
    switch (dynamicArray.elems[index]) {
      case (?element) element;
      case null Prim.trap("DynamicArray index out of bounds in get");
    };
  };

  /// Returns the element at index `index` as an option.
  /// Returns `null` when `index >= size`. Indexing is zero-based.
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// StableDynamicArray.add(dynamicArray, 10);
  /// StableDynamicArray.add(dynamicArray, 11);
  /// let x = StableDynamicArray.getOpt(dynamicArray, 0); // => ?10
  /// let y = StableDynamicArray.getOpt(dynamicArray, 2); // => null
  /// ```
  ///
  /// Runtime: O(1)
  ///
  /// Space: O(1)
  public func getOpt<X>(dynamicArray : StableDynamicArray<X>, index : Nat) : ?X {
    if (index < dynamicArray.count) {
      dynamicArray.elems[index];
    } else {
      null;
    };
  };

  /// Overwrites the current element at `index` with `element`. Traps if
  /// `index` >= size. Indexing is zero-based.
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// StableDynamicArray.add(dynamicArray, 10);
  /// StableDynamicArray.put(dynamicArray, 0, 20); // overwrites 10 at index 0 with 20
  /// StableDynamicArray.toArray(DynamicArray, dynamicArray) // => [20]
  /// ```
  ///
  /// Runtime: O(1)
  ///
  /// Space: O(1)
  public func put<X>(dynamicArray : StableDynamicArray<X>, index : Nat, element : X) {
    if (index >= dynamicArray.count) {
      Prim.trap "DynamicArray index out of bounds in put";
    };
    dynamicArray.elems[index] := ?element;
  };

  /// Returns true iff `dynamicArray` contains `element` with respect to equality
  /// defined by `equal`.
  ///
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 0);
  /// StableDynamicArray.add(dynamicArray, 3);
  /// StableDynamicArray.contains<Nat>(dynamicArray, 2, Nat.equal); // => true
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(1)
  ///
  /// *Runtime and space assumes that `equal` runs in O(1) time and space.
  public func contains<X>(dynamicArray : StableDynamicArray<X>, element : X, equal : (X, X) -> Bool) : Bool {
    for (current in vals(dynamicArray)) {
      if (equal(current, element)) {
        return true;
      };
    };

    false;
  };

  /// Finds the first index of `element` in `dynamicArray` using equality of elements defined
  /// by `equal`. Returns `null` if `element` is not found.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  /// StableDynamicArray.add(dynamicArray, 4);
  ///
  /// StableDynamicArray.indexOf<Nat>(3, dynamicArray, Nat.equal); // => ?2
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(size)
  ///
  /// *Runtime and space assumes that `equal` runs in O(1) time and space.
  public func indexOf<X>(element : X, dynamicArray : StableDynamicArray<X>, equal : (X, X) -> Bool) : ?Nat {
    let count = size(dynamicArray);
    var i = 0;
    while (i < count) {
      if (equal(get(dynamicArray, i), element)) {
        return ?i;
      };
      i += 1;
    };

    null;
  };

  /// Removes all elements from the dynamicArray for which the predicate returns false.
  /// The predicate is given both the index of the element and the element itself.
  /// This may cause a downsizing of the array.
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// StableDynamicArray.add(dynamicArray, 10);
  /// StableDynamicArray.add(dynamicArray, 11);
  /// StableDynamicArray.add(dynamicArray, 12);
  /// StableDynamicArray.filterEntries(dynamicArray, func(_, x) = x % 2 == 0); // only keep even elements
  /// StableDynamicArray.toArray(dynamicArray) // => [10, 12]
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Amortized Space: O(1), Worst Case Space: O(size)
  public func filterEntries<X>(dynamicArray : StableDynamicArray<X>, predicate : (Nat, X) -> Bool) {
    var numRemoved = 0;
    let keep = Prim.Array_tabulate<Bool>(
      dynamicArray.count,
      func i {
        switch (dynamicArray.elems[i]) {
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

    let capacity = dynamicArray.elems.size();

    if ((dynamicArray.count - numRemoved : Nat) < capacity / DECREASE_THRESHOLD) {
      let elements2 = Prim.Array_init<?X>(capacity / DECREASE_FACTOR, null);

      var i = 0;
      var j = 0;
      while (i < dynamicArray.count) {
        if (keep[i]) {
          elements2[j] := dynamicArray.elems[i];
          i += 1;
          j += 1;
        } else {
          i += 1;
        };
      };

      dynamicArray.elems := elements2;
    } else {
      var i = 0;
      var j = 0;
      while (i < dynamicArray.count) {
        if (keep[i]) {
          dynamicArray.elems[j] := dynamicArray.elems[i];
          i += 1;
          j += 1;
        } else {
          i += 1;
        };
      };

      while (j < dynamicArray.count) {
        dynamicArray.elems[j] := null;
        j += 1;
      };
    };

    dynamicArray.count -= numRemoved;
  };

  /// Inserts `element` at `index`, shifts all elements to the right of
  /// `index` over by one index. Traps if `index` is greater than size.
  ///
  /// ```motoko include=initialize
  /// let dynamicArray1 = StableDynamicArray.initPresized<Nat>(2);
  /// let dynamicArray2 = StableDynamicArray.initPresized<Nat>(2);
  /// StableDynamicArray.add(dynamicArray, 10);
  /// StableDynamicArray.add(dynamicArray, 11);
  /// StableDynamicArray.insert(dynamicArray, 1, 9);
  /// StableDynamicArray.toArray(dynamicArray) // => [10, 9, 11]
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Amortized Space: O(1), Worst Case Space: O(size)
  public func insert<X>(dynamicArray : StableDynamicArray<X>, index : Nat, element : X) {
    if (index > dynamicArray.count) {
      Prim.trap "DynamicArray index out of bounds in insert";
    };
    let capacity = dynamicArray.elems.size();

    if (dynamicArray.count + 1 > capacity) {
      let capacity = dynamicArray.elems.size();
      let elements2 = Prim.Array_init<?X>(newCapacity capacity, null);
      var i = 0;
      while (i < dynamicArray.count + 1) {
        if (i < index) {
          elements2[i] := dynamicArray.elems[i];
        } else if (i == index) {
          elements2[i] := ?element;
        } else {
          elements2[i] := dynamicArray.elems[i - 1];
        };

        i += 1;
      };
      dynamicArray.elems := elements2;
    } else {
      var i : Nat = dynamicArray.count;
      while (i > index) {
        dynamicArray.elems[i] := dynamicArray.elems[i - 1];
        i -= 1;
      };
      dynamicArray.elems[index] := ?element;
    };

    dynamicArray.count += 1;
  };

  /// Inserts `dynamicArray2` at `index`, and shifts all elements to the right of
  /// `index` over by size2. Traps if `index` is greater than size.
  ///
  /// ```motoko include=initialize
  /// let dynamicArray1 = StableDynamicArray.initPresized<Nat>(2);
  /// let dynamicArray2 = StableDynamicArray.initPresized<Nat>(2);
  /// StableDynamicArray.add(dynamicArray1, 10);
  /// StableDynamicArray.add(dynamicArray1, 11);
  /// StableDynamicArray.add(dynamicArray2, 12);
  /// StableDynamicArray.add(dynamicArray2, 13);
  /// StableDynamicArray.insertDynamicArray(dynamicArray1, 1, dynamicArray2);
  /// StableDynamicArray.toArray(dynamicArray1) // => [10, 12, 13, 11]
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Amortized Space: O(1), Worst Case Space: O(size1 + size2)
  public func insertDynamicArray<X>(dynamicArray : StableDynamicArray<X>, index : Nat, dynamicArray2 : StableDynamicArray<X>) {
    if (index > dynamicArray.count) {
      Prim.trap "DynamicArray index out of bounds in insertDynamicArray";
    };

    let size2 = size(dynamicArray2);
    let capacity = dynamicArray.elems.size();

    // copy elements to new array and shift over in one pass
    if (dynamicArray.count + size2 > capacity) {
      let elements2 = Prim.Array_init<?X>(newCapacity(dynamicArray.count + size2), null);
      var i = 0;
      for (element in dynamicArray.elems.vals()) {
        if (i == index) {
          i += size2;
        };
        elements2[i] := element;
        i += 1;
      };

      i := 0;
      while (i < size2) {
        elements2[i + index] := getOpt(dynamicArray2, i);
        i += 1;
      };
      dynamicArray.elems := elements2;
    } // just insert
    else {
      var i = index;
      while (i < index + size2) {
        if (i < dynamicArray.count) {
          dynamicArray.elems[i + size2] := dynamicArray.elems[i];
        };
        dynamicArray.elems[i] := getOpt(dynamicArray2, (i - index : Nat));

        i += 1;
      };
    };

    dynamicArray.count += size2;
  };

  /// Sorts the elements in the dynamicArray according to `compare`.
  /// Sort is deterministic, stable, and in-place.
  ///
  /// ```motoko include=initialize
  ///
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 11);
  /// StableDynamicArray.add(dynamicArray, 12);
  /// StableDynamicArray.add(dynamicArray, 10);
  /// StableDynamicArray.sort(dynamicArray, Nat.compare);
  /// StableDynamicArray.toArray(dynamicArray) // => [10, 11, 12]
  /// ```
  ///
  /// Runtime: O(size * log(size))
  ///
  /// Space: O(size)
  public func sort<X>(dynamicArray : StableDynamicArray<X>, compare : (X, X) -> Order.Order) {
    // Stable merge sort in a bottom-up iterative style
    if (dynamicArray.count == 0) {
      return;
    };
    let scratchSpace = Prim.Array_init<?X>(dynamicArray.count, null);

    let sizeDec = dynamicArray.count - 1 : Nat;
    var currSize = 1; // current size of the subarrays being merged
    // when the current size == size, the array has been merged into a single sorted array
    while (currSize < dynamicArray.count) {
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
          let leftOpt = dynamicArray.elems[left];
          let rightOpt = dynamicArray.elems[right];
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
          scratchSpace[nextSorted] := dynamicArray.elems[left];
          nextSorted += 1;
          left += 1;
        };
        while (right < rightEnd + 1) {
          scratchSpace[nextSorted] := dynamicArray.elems[right];
          nextSorted += 1;
          right += 1;
        };

        // Copy over merged elements
        var i = leftStart;
        while (i < rightEnd + 1) {
          dynamicArray.elems[i] := scratchSpace[i];
          i += 1;
        };

        leftStart += 2 * currSize;
      };
      currSize *= 2;
    };
  };

  /// Returns true if and only if the dynamicArray is empty.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 0);
  /// StableDynamicArray.add(dynamicArray, 3);
  /// StableDynamicArray.isEmpty(dynamicArray); // => false
  /// ```
  ///
  /// ```motoko include=initialize
  /// DynamicArray.isEmpty(dynamicArray); // => true
  /// ```
  ///
  /// Runtime: O(1)
  ///
  /// Space: O(1)
  public func isEmpty<X>(dynamicArray : StableDynamicArray<X>) : Bool = size(dynamicArray) == 0;

  /// Finds the greatest element in `dynamicArray` defined by `compare`.
  /// Returns `null` if `dynamicArray` is empty.
  ///
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  ///
  /// StableDynamicArray.max(dynamicArray, Nat.compare); // => ?2
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(1)
  ///
  /// *Runtime and space assumes that `compare` runs in O(1) time and space.
  public func max<X>(dynamicArray : StableDynamicArray<X>, compare : (X, X) -> Order) : ?X {
    if (size(dynamicArray) == 0) {
      return null;
    };

    var maxSoFar = get(dynamicArray, 0);
    for (current in vals(dynamicArray)) {
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
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  ///
  /// StableDynamicArray.min(dynamicArray, Nat.compare); // => ?1
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(1)
  ///
  /// *Runtime and space assumes that `compare` runs in O(1) time and space.
  public func min<X>(dynamicArray : StableDynamicArray<X>, compare : (X, X) -> Order) : ?X {
    if (size(dynamicArray) == 0) {
      return null;
    };

    var minSoFar = get(dynamicArray, 0);
    for (current in vals(dynamicArray)) {
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
  /// dynamicArrays. Returns true iff the two dynamicArrays are of the same size, and `equal`
  /// evaluates to true for every pair of elements in the two dynamicArrays of the same
  /// index.
  ///
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// let dynamicArray1 = StableDynamicArray.initPresized<Nat>(2);
  /// StableDynamicArray.add(dynamicArray1, 1);
  /// StableDynamicArray.add(dynamicArray1, 2);
  ///
  /// let dynamicArray2 = StableDynamicArray.initPresized<Nat>(5);
  /// StableDynamicArray.add(dynamicArray2, 1);
  /// StableDynamicArray.add(dynamicArray2, 2);
  ///
  /// StableDynamicArray.equal(dynamicArray1, dynamicArray2, Nat.equal); // => true
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(1)
  ///
  /// *Runtime and space assumes that `equal` runs in O(1) time and space.
  public func equal<X>(dynamicArray1 : StableDynamicArray<X>, dynamicArray2 : StableDynamicArray<X>, equal : (X, X) -> Bool) : Bool {
    let size1 = size(dynamicArray1);

    if (size1 != size(dynamicArray2)) {
      return false;
    };

    var i = 0;
    while (i < size1) {
      if (not equal(get(dynamicArray1, i), get(dynamicArray2, i))) {
        return false;
      };
      i += 1;
    };

    true;
  };

  /// Defines comparison for two dynamicArrays, using `compare` to recursively compare elements in the
  /// dynamicArrays. Comparison is defined lexicographically.
  ///
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// let dynamicArray1 = StableDynamicArray.initPresized<Nat>(2);
  /// StableDynamicArray.add(dynamicArray1, 1);
  /// StableDynamicArray.add(dynamicArray1, 2);
  ///
  /// let dynamicArray2 = StableDynamicArray.initPresized<Nat>(3);
  /// StableDynamicArray.add(dynamicArray2, 3);
  /// StableDynamicArray.add(dynamicArray2, 4);
  ///
  /// StableDynamicArray.compare<Nat>(dynamicArray1, dynamicArray2, Nat.compare); // => #less
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(1)
  ///
  /// *Runtime and space assumes that `compare` runs in O(1) time and space.
  public func compare<X>(dynamicArray1 : StableDynamicArray<X>, dynamicArray2 : StableDynamicArray<X>, compare : (X, X) -> Order.Order) : Order.Order {
    let size1 = size(dynamicArray1);
    let size2 = size(dynamicArray2);
    let minSize = if (size1 < size2) { size1 } else { size2 };

    var i = 0;
    while (i < minSize) {
      switch (compare(get(dynamicArray1, i), get(dynamicArray2, i))) {
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
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  /// StableDynamicArray.add(dynamicArray, 4);
  ///
  /// StableDynamicArray.toText(dynamicArray, Nat.toText); // => "[1, 2, 3, 4]"
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(size)
  ///
  /// *Runtime and space assumes that `toText` runs in O(1) time and space.
  public func toText<X>(dynamicArray : StableDynamicArray<X>, toText : X -> Text) : Text {
    let count : Int = size(dynamicArray);
    var i = 0;
    var text = "";
    while (i < count - 1) {
      text := text # toText(get(dynamicArray, i)) # ", "; // Text implemented as rope
      i += 1;
    };
    if (count > 0) {
      // avoid the trailing comma
      text := text # toText(get(dynamicArray, i));
    };

    "[" # text # "]";
  };

  /// Hashes `dynamicArray` using `hash` to hash the underlying elements.
  /// The deterministic hash function is a function of the elements in the DynamicArray, as well
  /// as their ordering.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Hash "mo:base/Hash";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  /// StableDynamicArray.add(dynamicArray, 1000);
  ///
  /// StableDynamicArray.hash<Nat>(dynamicArray, Hash.hash); // => 2_872_640_342
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(1)
  ///
  /// *Runtime and space assumes that `hash` runs in O(1) time and space.
  public func hash<X>(dynamicArray : StableDynamicArray<X>, hash : X -> Nat32) : Nat32 {
    let count = size(dynamicArray);
    var i = 0;
    var accHash : Nat32 = 0;

    while (i < count) {
      accHash := Prim.intToNat32Wrap(i) ^ accHash ^ hash(get(dynamicArray, i));
      i += 1;
    };

    accHash;
  };

  /// Finds the last index of `element` in `dynamicArray` using equality of elements defined
  /// by `equal`. Returns `null` if `element` is not found.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  /// StableDynamicArray.add(dynamicArray, 4);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 2);
  ///
  /// StableDynamicArray.lastIndexOf<Nat>(2, dynamicArray, Nat.equal); // => ?5
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(size)
  ///
  /// *Runtime and space assumes that `equal` runs in O(1) time and space.
  public func lastIndexOf<X>(element : X, dynamicArray : StableDynamicArray<X>, equal : (X, X) -> Bool) : ?Nat {
    let count = size(dynamicArray);
    if (count == 0) {
      return null;
    };
    var i = count;
    while (i >= 1) {
      i -= 1;
      if (equal(get(dynamicArray, i), element)) {
        return ?i;
      };
    };

    null;
  };

  /// Searches for `subDynamicArray` in `dynamicArray`, and returns the starting index if it is found.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  /// StableDynamicArray.add(dynamicArray, 4);
  /// StableDynamicArray.add(dynamicArray, 5);
  /// StableDynamicArray.add(dynamicArray, 6);
  ///
  /// let sub = StableDynamicArray.initPresized<Nat>(2);
  /// StableDynamicArray.add(sub, 4);
  /// StableDynamicArray.add(sub, 5);
  /// StableDynamicArray.add(sub, 6);
  ///
  /// StableDynamicArray.indexOfDynamicArray<Nat>(sub, dynamicArray, Nat.equal); // => ?3
  /// ```
  ///
  /// Runtime: O(size of dynamicArray + size of subDynamicArray)
  ///
  /// Space: O(size of subDynamicArray)
  ///
  /// *Runtime and space assumes that `equal` runs in O(1) time and space.
  public func indexOfDynamicArray<X>(subDynamicArray : StableDynamicArray<X>, dynamicArray : StableDynamicArray<X>, equal : (X, X) -> Bool) : ?Nat {
    // Uses the KMP substring search algorithm
    // Implementation from: https://www.educative.io/answers/what-is-the-knuth-morris-pratt-algorithm
    let count = size(dynamicArray);
    let subSize = size(subDynamicArray);
    if (subSize > count or subSize == 0) {
      return null;
    };

    // precompute lps
    let lps = Prim.Array_init<Nat>(subSize, 0);
    var i = 0;
    var j = 1;

    while (j < subSize) {
      if (equal(get(subDynamicArray, i), get(subDynamicArray, j))) {
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
    while (i < subSize and j < count) {
      if (equal(get(subDynamicArray, i), get(dynamicArray, j)) and i == subSizeDec) {
        return ?(j - i);
      } else if (equal(get(subDynamicArray, i), get(dynamicArray, j))) {
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

  /// Similar to indexOf, but runs in logarithmic time. Assumes that `dynamicArray` is sorted.
  /// Behavior is undefined if `dynamicArray` is not sorted. Uses `compare` to
  /// perform the search. Returns an index of `element` if it is found.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 4);
  /// StableDynamicArray.add(dynamicArray, 5);
  /// StableDynamicArray.add(dynamicArray, 6);
  ///
  /// StableDynamicArray.binarySearch<Nat>(5, dynamicArray, Nat.compare); // => ?2
  /// ```
  ///
  /// Runtime: O(log(size))
  ///
  /// Space: O(1)
  ///
  /// *Runtime and space assumes that `compare` runs in O(1) time and space.
  public func binarySearch<X>(element : X, dynamicArray : StableDynamicArray<X>, compare : (X, X) -> Order.Order) : ?Nat {
    var low = 0;
    var high = size(dynamicArray);

    while (low < high) {
      let mid = (low + high) / 2;
      let current = get(dynamicArray, mid);
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
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  /// StableDynamicArray.add(dynamicArray, 4);
  /// StableDynamicArray.add(dynamicArray, 5);
  /// StableDynamicArray.add(dynamicArray, 6);
  ///
  /// let sub = StableDynamicArray.subDynamicArray(dynamicArray, 3, 2);
  /// StableDynamicArray.toText(sub, Nat.toText); // => [4, 5]
  /// ```
  ///
  /// Runtime: O(length)
  ///
  /// Space: O(length)
  public func subDynamicArray<X>(dynamicArray : StableDynamicArray<X>, start : Nat, length : Nat) : StableDynamicArray<X> {
    let count = size(dynamicArray);
    let end = start + length; // exclusive
    if (start >= count or end > count) {
      Prim.trap "DynamicArray index out of bounds in subDynamicArray";
    };

    let newDynamicArray = initPresized<X>(newCapacity length);

    var i = start;
    while (i < end) {
      add(newDynamicArray, get(dynamicArray, i));

      i += 1;
    };

    newDynamicArray;
  };

  /// Checks if `subDynamicArray` is a sub-DynamicArray of `dynamicArray`. Uses `equal` to
  /// compare elements.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  /// StableDynamicArray.add(dynamicArray, 4);
  /// StableDynamicArray.add(dynamicArray, 5);
  /// StableDynamicArray.add(dynamicArray, 6);
  ///
  /// let sub = StableDynamicArray.initPresized<Nat>(2);
  /// StableDynamicArray.add(sub, 2);
  /// StableDynamicArray.add(sub, 3);
  /// StableDynamicArray.isSubDynamicArrayOf(sub, dynamicArray, Nat.equal); // => true
  /// ```
  ///
  /// Runtime: O(size of subDynamicArray + size of dynamicArray)
  ///
  /// Space: O(size of subDynamicArray)
  ///
  /// *Runtime and space assumes that `equal` runs in O(1) time and space.
  public func isSubDynamicArrayOf<X>(subDynamicArray : StableDynamicArray<X>, dynamicArray : StableDynamicArray<X>, equal : (X, X) -> Bool) : Bool {
    switch (indexOfDynamicArray(subDynamicArray, dynamicArray, equal)) {
      case null size(subDynamicArray) == 0;
      case _ true;
    };
  };

  /// Checks if `subDynamicArray` is a strict subDynamicArray of `dynamicArray`, i.e. `subDynamicArray` must be
  /// strictly contained inside both the first and last indices of `dynamicArray`.
  /// Uses `equal` to compare elements.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  /// StableDynamicArray.add(dynamicArray, 4);
  ///
  /// let sub = StableDynamicArray.initPresized<Nat>(2);
  /// StableDynamicArray.add(sub, 2);
  /// StableDynamicArray.add(sub, 3);
  /// StableDynamicArray.isStrictSubDynamicArrayOf(sub, dynamicArray, Nat.equal); // => true
  /// ```
  ///
  /// Runtime: O(size of subDynamicArray + size of dynamicArray)
  ///
  /// Space: O(size of subDynamicArray)
  ///
  /// *Runtime and space assumes that `equal` runs in O(1) time and space.
  public func isStrictSubDynamicArrayOf<X>(subDynamicArray : StableDynamicArray<X>, dynamicArray : StableDynamicArray<X>, equal : (X, X) -> Bool) : Bool {
    let subDynamicArraySize = size(subDynamicArray);

    switch (indexOfDynamicArray(subDynamicArray, dynamicArray, equal)) {
      case (?index) {
        index != 0 and index != (size(dynamicArray) - subDynamicArraySize : Nat) // enforce strictness
      };
      case null {
        subDynamicArraySize == 0 and subDynamicArraySize != size(dynamicArray)
      };
    };
  };

  /// Returns the prefix of `dynamicArray` of length `length`. Traps if `length`
  /// is greater than the size of `dynamicArray`.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  /// StableDynamicArray.add(dynamicArray, 4);
  ///
  /// let pre = StableDynamicArray.prefix(dynamicArray, 3); // => [1, 2, 3]
  /// StableDynamicArray.toText(pre, Nat.toText);
  /// ```
  ///
  /// Runtime: O(length)
  ///
  /// Space: O(length)
  public func prefix<X>(dynamicArray : StableDynamicArray<X>, length : Nat) : StableDynamicArray<X> {
    let count = size(dynamicArray);
    if (length > count) {
      Prim.trap "DynamicArray index out of bounds in prefix";
    };

    let newDynamicArray = initPresized<X>(newCapacity length);

    var i = 0;
    while (i < length) {
      add(newDynamicArray, get(dynamicArray, i));
      i += 1;
    };

    newDynamicArray;
  };

  /// Checks if `prefix` is a prefix of `dynamicArray`. Uses `equal` to
  /// compare elements.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  /// StableDynamicArray.add(dynamicArray, 4);
  ///
  /// let pre = StableDynamicArray.initPresized<Nat>(2);
  /// StableDynamicArray.add(pre, 1);
  /// StableDynamicArray.add(pre, 2);
  /// StableDynamicArray.isPrefixOf(pre, dynamicArray, Nat.equal); // => true
  /// ```
  ///
  /// Runtime: O(size of prefix)
  ///
  /// Space: O(size of prefix)
  ///
  /// *Runtime and space assumes that `equal` runs in O(1) time and space.
  public func isPrefixOf<X>(prefix : StableDynamicArray<X>, dynamicArray : StableDynamicArray<X>, equal : (X, X) -> Bool) : Bool {
    let sizePrefix = size(prefix);
    if (size(dynamicArray) < sizePrefix) {
      return false;
    };

    var i = 0;
    while (i < sizePrefix) {
      if (not equal(get(dynamicArray, i), get(prefix, i))) {
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
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  /// StableDynamicArray.add(dynamicArray, 4);
  ///
  /// let pre = StableDynamicArray.initPresized<Nat>(3);
  /// StableDynamicArray.add(pre, 1);
  /// StableDynamicArray.add(pre, 2);
  /// StableDynamicArray.add(pre, 3);
  /// StableDynamicArray.isStrictPrefixOf(pre, dynamicArray, Nat.equal); // => true
  /// ```
  ///
  /// Runtime: O(size of prefix)
  ///
  /// Space: O(size of prefix)
  ///
  /// *Runtime and space assumes that `equal` runs in O(1) time and space.
  public func isStrictPrefixOf<X>(prefix : StableDynamicArray<X>, dynamicArray : StableDynamicArray<X>, equal : (X, X) -> Bool) : Bool {
    if (size(dynamicArray) <= size(prefix)) {
      return false;
    };
    isPrefixOf(prefix, dynamicArray, equal);
  };

  /// Returns the suffix of `dynamicArray` of length `length`.
  /// Traps if `length`is greater than the size of `dynamicArray`.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  /// StableDynamicArray.add(dynamicArray, 4);
  ///
  /// let suf = StableDynamicArray.suffix(dynamicArray, 3); // => [2, 3, 4]
  /// StableDynamicArray.toText(suf, Nat.toText);
  /// ```
  ///
  /// Runtime: O(length)
  ///
  /// Space: O(length)
  public func suffix<X>(dynamicArray : StableDynamicArray<X>, length : Nat) : StableDynamicArray<X> {
    let count = size(dynamicArray);

    if (length > count) {
      Prim.trap "DynamicArray index out of bounds in suffix";
    };

    let newDynamicArray = initPresized<X>(newCapacity length);

    var i = count - length : Nat;
    while (i < count) {
      add(newDynamicArray, get(dynamicArray, i));

      i += 1;
    };

    newDynamicArray;
  };

  /// Checks if `suffix` is a suffix of `dynamicArray`. Uses `equal` to compare
  /// elements.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  /// StableDynamicArray.add(dynamicArray, 4);
  ///
  /// let suf = StableDynamicArray.initPresized<Nat>(3);
  /// StableDynamicArray.add(suf, 2);
  /// StableDynamicArray.add(suf, 3);
  /// StableDynamicArray.add(suf, 4);
  /// StableDynamicArray.isSuffixOf(suf, dynamicArray, Nat.equal); // => true
  /// ```
  ///
  /// Runtime: O(length of suffix)
  ///
  /// Space: O(length of suffix)
  ///
  /// *Runtime and space assumes that `equal` runs in O(1) time and space.
  public func isSuffixOf<X>(suffix : StableDynamicArray<X>, dynamicArray : StableDynamicArray<X>, equal : (X, X) -> Bool) : Bool {
    let suffixSize = size(suffix);
    let dynamicArraySize = size(dynamicArray);
    if (dynamicArraySize < suffixSize) {
      return false;
    };

    var i = dynamicArraySize;
    var j = suffixSize;
    while (i >= 1 and j >= 1) {
      i -= 1;
      j -= 1;
      if (not equal(get(dynamicArray, i), get(suffix, j))) {
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
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  /// StableDynamicArray.add(dynamicArray, 4);
  ///
  /// let suf = StableDynamicArray.initPresized<Nat>(3);
  /// StableDynamicArray.add(suf, 2);
  /// StableDynamicArray.add(suf, 3);
  /// StableDynamicArray.add(suf, 4);
  /// StableDynamicArray.isStrictSuffixOf(suf, dynamicArray, Nat.equal); // => true
  /// ```
  ///
  /// Runtime: O(length of suffix)
  ///
  /// Space: O(length of suffix)
  ///
  /// *Runtime and space assumes that `equal` runs in O(1) time and space.
  public func isStrictSuffixOf<X>(suffix : StableDynamicArray<X>, dynamicArray : StableDynamicArray<X>, equal : (X, X) -> Bool) : Bool {
    if (size(dynamicArray) <= size(suffix)) {
      return false;
    };
    isSuffixOf(suffix, dynamicArray, equal);
  };

  /// Returns true iff every element in `dynamicArray` satisfies `predicate`.
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  /// StableDynamicArray.add(dynamicArray, 4);
  ///
  /// StableDynamicArray.forAll<Nat>(dynamicArray, func x { x > 1 }); // => true
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(1)
  ///
  /// *Runtime and space assumes that `predicate` runs in O(1) time and space.
  public func forAll<X>(dynamicArray : StableDynamicArray<X>, predicate : X -> Bool) : Bool {
    for (element in vals(dynamicArray)) {
      if (not predicate element) {
        return false;
      };
    };

    true;
  };

  /// Returns true iff some element in `dynamicArray` satisfies `predicate`.
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  /// StableDynamicArray.add(dynamicArray, 4);
  ///
  /// StableDynamicArray.forSome<Nat>(dynamicArray, func x { x > 3 }); // => true
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(1)
  ///
  /// *Runtime and space assumes that `predicate` runs in O(1) time and space.
  public func forSome<X>(dynamicArray : StableDynamicArray<X>, predicate : X -> Bool) : Bool {
    for (element in vals(dynamicArray)) {
      if (predicate element) {
        return true;
      };
    };

    false;
  };

  /// Returns true iff no element in `dynamicArray` satisfies `predicate`.
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  /// StableDynamicArray.add(dynamicArray, 4);
  ///
  /// StableDynamicArray.forNone<Nat>(dynamicArray, func x { x == 0 }); // => true
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(1)
  ///
  /// *Runtime and space assumes that `predicate` runs in O(1) time and space.
  public func forNone<X>(dynamicArray : StableDynamicArray<X>, predicate : X -> Bool) : Bool {
    for (element in vals(dynamicArray)) {
      if (predicate element) {
        return false;
      };
    };

    true;
  };

  /// Creates a dynamicArray containing elements from `array`.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// let array = [var 1, 2, 3];
  ///
  /// let buf = StableDynamicArray.fromVarArray<Nat>(array); // => [1, 2, 3]
  /// StableDynamicArray.toText(buf, Nat.toText);
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(size)
  public func fromVarArray<X>(array : [var X]) : StableDynamicArray<X> {
    let newDynamicArray = initPresized<X>(newCapacity(array.size()));

    for (element in array.vals()) {
      add(newDynamicArray, element);
    };

    newDynamicArray;
  };

  /// Creates a dynamicArray containing elements from `iter`.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// let array = [1, 1, 1];
  /// let iter = array.vals();
  ///
  /// let buf = StableDynamicArray.fromIter<Nat>(iter); // => [1, 1, 1]
  /// StableDynamicArray.toText(buf, Nat.toText);
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(size)
  public func fromIter<X>(iter : { next : () -> ?X }) : StableDynamicArray<X> {
    let newDynamicArray = initPresized<X>(DEFAULT_CAPACITY); // can't get size from `iter`

    for (element in iter) {
      add(newDynamicArray, element);
    };

    newDynamicArray;
  };

  /// Reallocates the array underlying `dynamicArray` such that capacity == size.
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// let dynamicArray = StableDynamicArray.initPresized<Nat>(10);
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  ///
  /// StableDynamicArray.trimToSize<Nat>(dynamicArray);
  /// StableDynamicArray.capacity(dynamicArray); // => 3
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(size)
  public func trimToSize<X>(dynamicArray : StableDynamicArray<X>) {
    let count = size<X>(dynamicArray);
    if (count < capacity(dynamicArray)) {
      reserve(dynamicArray, count);
    };
  };

  /// Creates a new dynamicArray by applying `f` to each element in `dynamicArray`.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  ///
  /// let newBuf = StableDynamicArray.map<Nat, Nat>(dynamicArray, func (x) { x + 1 });
  /// StableDynamicArray.toText(newBuf, Nat.toText); // => [2, 3, 4]
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(size)
  ///
  /// *Runtime and space assumes that `f` runs in O(1) time and space.
  public func map<X, Y>(dynamicArray : StableDynamicArray<X>, f : X -> Y) : StableDynamicArray<Y> {
    let newDynamicArray = initPresized<Y>(capacity(dynamicArray));

    for (element in vals(dynamicArray)) {
      add(newDynamicArray, f element);
    };

    newDynamicArray;
  };

  /// Applies `f` to each element in `dynamicArray`.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  /// import Debug "mo:base/Debug";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  ///
  /// StableDynamicArray.iterate<Nat>(dynamicArray, func (x) {
  ///   Debug.print(Nat.toText(x)); // prints each element in dynamicArray
  /// });
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(size)
  ///
  /// *Runtime and space assumes that `f` runs in O(1) time and space.
  public func iterate<X>(dynamicArray : StableDynamicArray<X>, f : X -> ()) {
    for (element in vals(dynamicArray)) {
      f element;
    };
  };

  /// Applies `f` to each element in `dynamicArray` and its index.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  ///
  /// let newBuf = StableDynamicArray.mapEntries<Nat, Nat>(dynamicArray, func (x, i) { x + i + 1 });
  /// StableDynamicArray.toText(newBuf, Nat.toText); // => [2, 4, 6]
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(size)
  ///
  /// *Runtime and space assumes that `f` runs in O(1) time and space.
  public func mapEntries<X, Y>(dynamicArray : StableDynamicArray<X>, f : (Nat, X) -> Y) : StableDynamicArray<Y> {
    let newDynamicArray = initPresized<Y>(capacity(dynamicArray));

    var i = 0;
    let count = size(dynamicArray);
    while (i < count) {
      add(newDynamicArray, f(i, get(dynamicArray, i)));
      i += 1;
    };

    newDynamicArray;
  };

  /// Creates a new dynamicArray by applying `f` to each element in `dynamicArray`,
  /// and keeping all non-null elements.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  ///
  /// let newBuf = StableDynamicArray.mapFilter<Nat, Nat>(dynamicArray, func (x) {
  ///   if (x > 1) {
  ///     ?(x * 2);
  ///   } else {
  ///     null;
  ///   }
  /// });
  /// StableDynamicArray.toText(newBuf, Nat.toText); // => [4, 6]
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(size)
  ///
  /// *Runtime and space assumes that `f` runs in O(1) time and space.
  public func mapFilter<X, Y>(dynamicArray : StableDynamicArray<X>, f : X -> ?Y) : StableDynamicArray<Y> {
    let newDynamicArray = initPresized<Y>(capacity(dynamicArray));

    for (element in vals(dynamicArray)) {
      switch (f element) {
        case (?element) {
          add(newDynamicArray, element);
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
  /// ```motoko include=initialize
  /// import Result "mo:base/Result";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  ///
  /// let result = StableDynamicArray.mapResult<Nat, Nat, Text>(dynamicArray, func (k) {
  ///   if (k > 0) {
  ///     #ok(k);
  ///   } else {
  ///     #err("One or more elements are zero.");
  ///   }
  /// });
  ///
  /// Result.mapOk<StableDynamicArray.StableDynamicArray<Nat>, [Nat], Text>(result, func dynamicArray = StableDynamicArray.toArray(dynamicArray)) // => #ok([1, 2, 3])
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(size)
  ///
  /// *Runtime and space assumes that `f` runs in O(1) time and space.
  public func mapResult<X, Y, E>(dynamicArray : StableDynamicArray<X>, f : X -> Result.Result<Y, E>) : Result.Result<StableDynamicArray<Y>, E> {
    let newDynamicArray = initPresized<Y>(capacity(dynamicArray));

    for (element in vals(dynamicArray)) {
      switch (f element) {
        case (#ok result) {
          add(newDynamicArray, result);
        };
        case (#err e) {
          return #err e;
        };
      };
    };

    #ok newDynamicArray;
  };

  /// Creates a new dynamicArray by applying `k` to each element in `dynamicArray`,
  /// and concatenating the resulting dynamicArrays in order. This operation
  /// is similar to what in other functional languages is known as monadic bind.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  ///
  /// let chain = StableDynamicArray.chain<Nat, Nat>(dynamicArray, func (x) {
  ///   let b = StableDynamicArray.initPresized<Nat>(2);
  ///   b.add(x);
  ///   b.add(x * 2);
  ///   return b;
  /// });
  /// DynamicArray.toText(chain, Nat.toText); // => [1, 2, 2, 4, 3, 6]
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(size)
  ///
  /// *Runtime and space assumes that `k` runs in O(1) time and space.
  public func chain<X, Y>(dynamicArray : StableDynamicArray<X>, k : X -> StableDynamicArray<Y>) : StableDynamicArray<Y> {
    let newDynamicArray = initPresized<Y>(size(dynamicArray) * 4);

    for (element in vals(dynamicArray)) {
      append(newDynamicArray, k element);
    };

    newDynamicArray;
  };

  /// Collapses the elements in `dynamicArray` into a single value by starting with `base`
  /// and progessively combining elements into `base` with `combine`. Iteration runs
  /// left to right.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  ///
  /// DynamicArray.foldLeft<Text, Nat>(dynamicArray, "", func (acc, x) { acc # Nat.toText(x)}); // => "123"
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(1)
  ///
  /// *Runtime and space assumes that `combine` runs in O(1) time and space.
  public func foldLeft<A, X>(dynamicArray : StableDynamicArray<X>, base : A, combine : (A, X) -> A) : A {
    var accumulation = base;

    for (element in vals(dynamicArray)) {
      accumulation := combine(accumulation, element);
    };

    accumulation;
  };

  /// Collapses the elements in `dynamicArray` into a single value by starting with `base`
  /// and progessively combining elements into `base` with `combine`. Iteration runs
  /// right to left.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  ///
  /// DynamicArray.foldRight<Nat, Text>(dynamicArray, "", func (x, acc) { Nat.toText(x) # acc }); // => "123"
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(1)
  ///
  /// *Runtime and space assumes that `combine` runs in O(1) time and space.
  public func foldRight<X, A>(dynamicArray : StableDynamicArray<X>, base : A, combine : (X, A) -> A) : A {
    let count = size(dynamicArray);
    if (count == 0) {
      return base;
    };
    var accumulation = base;

    var i = count;
    while (i >= 1) {
      i -= 1; // to avoid Nat underflow, subtract first and stop iteration at 1
      accumulation := combine(get(dynamicArray, i), accumulation);
    };

    accumulation;
  };

  /// Returns the first element of `dynamicArray`. Traps if `dynamicArray` is empty.
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  ///
  /// DynamicArray.first(dynamicArray); // => 1
  /// ```
  ///
  /// Runtime: O(1)
  ///
  /// Space: O(1)
  public func first<X>(dynamicArray : StableDynamicArray<X>) : X = get(dynamicArray, 0);

  /// Returns the last element of `dynamicArray`. Traps if `dynamicArray` is empty.
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// dynamicArray.add(1);
  /// dynamicArray.add(2);
  /// dynamicArray.add(3);
  ///
  /// DynamicArray.last(dynamicArray); // => 3
  /// ```
  ///
  /// Runtime: O(1)
  ///
  /// Space: O(1)
  public func last<X>(dynamicArray : StableDynamicArray<X>) : X = get(dynamicArray, size(dynamicArray) - 1 : Nat);

  /// Returns a new dynamicArray with capacity and size 1, containing `element`.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// let dynamicArray = DynamicArray.make<Nat>(1);
  /// DynamicArray.toText(dynamicArray, Nat.toText); // => [1]
  /// ```
  ///
  /// Runtime: O(1)
  ///
  /// Space: O(1)
  public func make<X>(element : X) : StableDynamicArray<X> {
    let newDynamicArray = initPresized<X>(1);
    add(newDynamicArray, element);
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
  /// Runtime: O(size)
  ///
  /// Space: O(1)
  public func reverse<X>(dynamicArray : StableDynamicArray<X>) {
    let count = size(dynamicArray);
    if (count == 0) {
      return;
    };

    var i = 0;
    var j = count - 1 : Nat;
    var temp = get(dynamicArray, 0);
    while (i < count / 2) {
      temp := get(dynamicArray, j);
      put(dynamicArray, j, get(dynamicArray, i));
      put(dynamicArray, i, temp);
      i += 1;
      j -= 1;
    };
  };

  /// Merges two sorted dynamicArrays into a single sorted dynamicArray, using `compare` to define
  /// the ordering. The final ordering is stable. Behavior is undefined if either
  /// `dynamicArray1` or `dynamicArray2` is not sorted.
  ///
  /// Example:
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
  /// Runtime: O(size1 + size2)
  ///
  /// Space: O(size1 + size2)
  ///
  /// *Runtime and space assumes that `compare` runs in O(1) time and space.
  public func merge<X>(dynamicArray1 : StableDynamicArray<X>, dynamicArray2 : StableDynamicArray<X>, compare : (X, X) -> Order) : StableDynamicArray<X> {
    let size1 = size(dynamicArray1);
    let size2 = size(dynamicArray2);

    let newDynamicArray = initPresized<X>(newCapacity(size1 + size2));

    var pointer1 = 0;
    var pointer2 = 0;

    while (pointer1 < size1 and pointer2 < size2) {
      let current1 = get(dynamicArray1, pointer1);
      let current2 = get(dynamicArray2, pointer2);

      switch (compare(current1, current2)) {
        case (#less) {
          add(newDynamicArray, current1);
          pointer1 += 1;
        };
        case _ {
          add(newDynamicArray, current2);
          pointer2 += 1;
        };
      };
    };

    while (pointer1 < size1) {
      add(newDynamicArray, get(dynamicArray1, pointer1));
      pointer1 += 1;
    };

    while (pointer2 < size2) {
      add(newDynamicArray, get(dynamicArray2, pointer2));
      pointer2 += 1;
    };

    newDynamicArray;
  };

  /// Eliminates all duplicate elements in `dynamicArray` as defined by `compare`.
  /// Elimination is stable with respect to the original ordering of the elements.
  ///
  /// Example:
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
  /// Runtime: O(size * log(size))
  ///
  /// Space: O(size)
  public func removeDuplicates<X>(dynamicArray : StableDynamicArray<X>, compare : (X, X) -> Order) {
    let count = size(dynamicArray);
    let indices = Prim.Array_tabulate<(Nat, X)>(count, func i = (i, get(dynamicArray, i)));
    // Sort based on element, while carrying original index information
    // This groups together the duplicate elements
    let sorted = Array.sort<(Nat, X)>(indices, func(pair1, pair2) = compare(pair1.1, pair2.1));
    let uniques = initPresized<(Nat, X)>(count);

    // Iterate over elements
    var i = 0;
    while (i < count) {
      var j = i;
      // Iterate over duplicate elements, and find the smallest index among them (for stability)
      var minIndex = sorted[j];
      label duplicates while (j < (count - 1 : Nat)) {
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

      add(uniques, minIndex);
      i := j + 1;
    };

    // resort based on original ordering and place back in dynamicArray
    sort<(Nat, X)>(
      uniques,
      func(pair1, pair2) {
        if (pair1.0 < pair2.0) {
          #less;
        } else if (pair1.0 == pair2.0) {
          #equal;
        } else {
          #greater;
        };
      },
    );

    clear(dynamicArray);
    reserve(dynamicArray, size(uniques));
    for (element in vals(uniques)) {
      add(dynamicArray, element.1);
    };
  };

  /// Splits `dynamicArray` into a pair of dynamicArrays where all elements in the left
  /// dynamicArray satisfy `predicate` and all elements in the right dynamicArray do not.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  /// StableDynamicArray.add(dynamicArray, 4);
  /// StableDynamicArray.add(dynamicArray, 5);
  /// StableDynamicArray.add(dynamicArray, 6);
  ///
  /// let partitions = StableDynamicArray.partition<Nat>(dynamicArray, func (x) { x % 2 == 0 });
  /// (StableDynamicArray.toArray(partitions.0), StableDynamicArray.toArray(partitions.1)) // => ([2, 4, 6], [1, 3, 5])
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(size)
  ///
  /// *Runtime and space assumes that `predicate` runs in O(1) time and space.
  public func partition<X>(dynamicArray : StableDynamicArray<X>, predicate : X -> Bool) : (StableDynamicArray<X>, StableDynamicArray<X>) {
    let count = size(dynamicArray);
    let trueDynamicArray = initPresized<X>(count);
    let falseDynamicArray = initPresized<X>(count);

    for (element in vals(dynamicArray)) {
      if (predicate element) {
        add(trueDynamicArray, element);
      } else {
        add(falseDynamicArray, element);
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
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  /// StableDynamicArray.add(dynamicArray, 4);
  /// StableDynamicArray.add(dynamicArray, 5);
  /// StableDynamicArray.add(dynamicArray, 6);
  ///
  /// let split = DynamicArray.split<Nat>(dynamicArray, 3);
  /// (DynamicArray.toArray(split.0), DynamicArray.toArray(split.1)) // => ([1, 2, 3], [4, 5, 6])
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(size)
  ///
  /// *Runtime and space assumes that `compare` runs in O(1) time and space.
  public func split<X>(dynamicArray : StableDynamicArray<X>, index : Nat) : (StableDynamicArray<X>, StableDynamicArray<X>) {
    let count = size(dynamicArray);

    if (index < 0 or index > count) {
      Prim.trap "Index out of bounds in split";
    };

    let dynamicArray1 = initPresized<X>(newCapacity index);
    let dynamicArray2 = initPresized<X>(newCapacity(count - index));

    var i = 0;
    while (i < index) {
      add(dynamicArray1, get(dynamicArray, i));
      i += 1;
    };
    while (i < count) {
      add(dynamicArray2, get(dynamicArray, i));
      i += 1;
    };

    (dynamicArray1, dynamicArray2);
  };

  /// Breaks up `dynamicArray` into dynamicArrays of size `size`. The last chunk may
  /// have less than `size` elements if the number of elements is not divisible
  /// by the chunk size.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  /// StableDynamicArray.add(dynamicArray, 4);
  /// StableDynamicArray.add(dynamicArray, 5);
  /// StableDynamicArray.add(dynamicArray, 6);
  ///
  /// let chunks = StableDynamicArray.chunk<Nat>(dynamicArray, 3);
  /// StableDynamicArray.toText<StableDynamicArray.StableDynamicArray<Nat>>(chunks, func buf = StableDynamicArray.toText(buf, Nat.toText)); // => [[1, 2, 3], [4, 5, 6]]
  /// ```
  ///
  /// Runtime: O(number of elements in dynamicArray)
  ///
  /// Space: O(number of elements in dynamicArray)
  public func chunk<X>(dynamicArray : StableDynamicArray<X>, count : Nat) : StableDynamicArray<StableDynamicArray<X>> {
    if (count == 0) {
      Prim.trap "Chunk size must be non-zero in chunk";
    };

    // ceil(dynamicArray.size() / size)
    let newDynamicArray = initPresized<StableDynamicArray<X>>((size(dynamicArray) + count - 1) / count);

    var newInnerDynamicArray = initPresized<X>(newCapacity count);
    var innerSize = 0;
    for (element in vals(dynamicArray)) {
      if (innerSize == count) {
        add(newDynamicArray, newInnerDynamicArray);
        newInnerDynamicArray := initPresized<X>(newCapacity count);
        innerSize := 0;
      };
      add(newInnerDynamicArray, element);
      innerSize += 1;
    };
    if (innerSize > 0) {
      add(newDynamicArray, newInnerDynamicArray);
    };

    newDynamicArray;
  };

  /// Groups equal and adjacent elements in the list into sub lists.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 4);
  /// StableDynamicArray.add(dynamicArray, 5);
  /// StableDynamicArray.add(dynamicArray, 5);
  ///
  /// let grouped = StableDynamicArray.groupBy<Nat>(dynamicArray, func (x, y) { x == y });
  /// StableDynamicArray.toText<StableDynamicArray.StableDynamicArray<Nat>>(grouped, func buf = StableDynamicArray.toText(buf, Nat.toText)); // => [[1], [2, 2], [4], [5, 5]]
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(size)
  ///
  /// *Runtime and space assumes that `equal` runs in O(1) time and space.
  public func groupBy<X>(dynamicArray : StableDynamicArray<X>, equal : (X, X) -> Bool) : StableDynamicArray<StableDynamicArray<X>> {
    let count = size(dynamicArray);
    let newDynamicArray = initPresized<StableDynamicArray<X>>(count);
    if (count == 0) {
      return newDynamicArray;
    };

    var i = 0;
    var baseElement = get(dynamicArray, 0);
    var newInnerDynamicArray = initPresized<X>(count);
    while (i < count) {
      let element = get(dynamicArray, i);

      if (equal(baseElement, element)) {
        add(newInnerDynamicArray, element);
      } else {
        add(newDynamicArray, newInnerDynamicArray);
        baseElement := element;
        newInnerDynamicArray := initPresized<X>(count - i);
        add(newInnerDynamicArray, element);
      };
      i += 1;
    };
    if (size(newInnerDynamicArray) > 0) {
      add(newDynamicArray, newInnerDynamicArray);
    };

    newDynamicArray;
  };

  /// Flattens the dynamicArray of dynamicArrays into a single dynamicArray.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// let dynamicArray = StableDynamicArray.initPresized<StableDynamicArray.StableDynamicArray<Nat>>(1);
  ///
  /// let inner1 = StableDynamicArray.initPresized<Nat>(2);
  /// StableDynamicArray.add(inner1, 1);
  /// StableDynamicArray.add(inner1, 2);
  ///
  /// let inner2 = StableDynamicArray.initPresized<Nat>(2);
  /// StableDynamicArray.add(inner2, 3);
  /// StableDynamicArray.add(inner2, 4);
  ///
  /// StableDynamicArray.add(dynamicArray, inner1);
  /// StableDynamicArray.add(dynamicArray, inner2);
  /// // dynamicArray = [[1, 2], [3, 4]]
  ///
  /// let flat = StableDynamicArray.flatten<Nat>(dynamicArray);
  /// StableDynamicArray.toText<Nat>(flat, Nat.toText); // => [1, 2, 3, 4]
  /// ```
  ///
  /// Runtime: O(number of elements in dynamicArray)
  ///
  /// Space: O(number of elements in dynamicArray)
  public func flatten<X>(dynamicArray : StableDynamicArray<StableDynamicArray<X>>) : StableDynamicArray<X> {
    let count = size(dynamicArray);
    if (count == 0) {
      return initPresized<X>(0);
    };

    let newDynamicArray = initPresized<X>(
      if (size(get(dynamicArray, 0)) != 0) {
        newCapacity(size(get(dynamicArray, 0)) * count);
      } else {
        newCapacity(count);
      }
    );

    for (innerDynamicArray in vals(dynamicArray)) {
      for (innerElement in vals(innerDynamicArray)) {
        add(newDynamicArray, innerElement);
      };
    };

    newDynamicArray;
  };

  /// Combines the two dynamicArrays into a single dynamicArray of pairs, pairing together
  /// elements with the same index. If one dynamicArray is longer than the other, the
  /// remaining elements from the longer dynamicArray are not included.
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// let dynamicArray1 = StableDynamicArray.initPresized<Nat>(2);
  /// StableDynamicArray.add(dynamicArray1, 1);
  /// StableDynamicArray.add(dynamicArray1, 2);
  /// StableDynamicArray.add(dynamicArray1, 3);
  ///
  /// let dynamicArray2 = StableDynamicArray.initPresized<Nat>(2);
  /// StableDynamicArray.add(dynamicArray2, 4);
  /// StableDynamicArray.add(dynamicArray2, 5);
  ///
  /// let zipped = StableDynamicArray.zip(dynamicArray1, dynamicArray2);
  /// StableDynamicArray.toArray(zipped); // => [(1, 4), (2, 5)]
  /// ```
  ///
  /// Runtime: O(min(size1, size2))
  ///
  /// Space: O(min(size1, size2))
  public func zip<X, Y>(dynamicArray1 : StableDynamicArray<X>, dynamicArray2 : StableDynamicArray<Y>) : StableDynamicArray<(X, Y)> {
    // compiler should pull lamda out as a static function since it is fully closed
    zipWith<X, Y, (X, Y)>(dynamicArray1, dynamicArray2, func(x, y) = (x, y));
  };

  /// Combines the two dynamicArrays into a single dynamicArray, pairing together
  /// elements with the same index and combining them using `zip`. If
  /// one dynamicArray is longer than the other, the remaining elements from
  /// the longer dynamicArray are not included.
  ///
  /// Example:
  /// ```motoko include=initialize
  ///
  /// let dynamicArray1 = StableDynamicArray.initPresized<Nat>(2);
  /// StableDynamicArray.add(dynamicArray1, 1);
  /// StableDynamicArray.add(dynamicArray1, 2);
  /// StableDynamicArray.add(dynamicArray1, 3);
  ///
  /// let dynamicArray2 = StableDynamicArray.initPresized<Nat>(2);
  /// StableDynamicArray.add(dynamicArray2, 4);
  /// StableDynamicArray.add(dynamicArray2, 5);
  /// StableDynamicArray.add(dynamicArray2, 6);
  ///
  /// let zipped = StableDynamicArray.zipWith<Nat, Nat, Nat>(dynamicArray1, dynamicArray2, func (x, y) { x + y });
  /// StableDynamicArray.toArray(zipped) // => [5, 7, 9]
  /// ```
  ///
  /// Runtime: O(min(size1, size2))
  ///
  /// Space: O(min(size1, size2))
  ///
  /// *Runtime and space assumes that `zip` runs in O(1) time and space.
  public func zipWith<X, Y, Z>(dynamicArray1 : StableDynamicArray<X>, dynamicArray2 : StableDynamicArray<Y>, zip : (X, Y) -> Z) : StableDynamicArray<Z> {
    let size1 = size(dynamicArray1);
    let size2 = size(dynamicArray2);
    let minSize = if (size1 < size2) { size1 } else { size2 };

    var i = 0;
    let newDynamicArray = initPresized<Z>(newCapacity minSize);
    while (i < minSize) {
      add(newDynamicArray, zip(get(dynamicArray1, i), get(dynamicArray2, i)));
      i += 1;
    };
    newDynamicArray;
  };

  /// Creates a new dynamicArray taking elements in order from `dynamicArray` until predicate
  /// returns false.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  ///
  /// let newBuf = StableDynamicArray.takeWhile<Nat>(dynamicArray, func (x) { x < 3 });
  /// StableDynamicArray.toText(newBuf, Nat.toText); // => [1, 2]
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(size)
  ///
  /// *Runtime and space assumes that `predicate` runs in O(1) time and space.
  public func takeWhile<X>(dynamicArray : StableDynamicArray<X>, predicate : X -> Bool) : StableDynamicArray<X> {
    let newDynamicArray = initPresized<X>(size(dynamicArray));

    for (element in vals(dynamicArray)) {
      if (not predicate element) {
        return newDynamicArray;
      };
      add(newDynamicArray, element);
    };

    newDynamicArray;
  };

  /// Creates a new dynamicArray excluding elements in order from `dynamicArray` until predicate
  /// returns false.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// StableDynamicArray.add(dynamicArray, 1);
  /// StableDynamicArray.add(dynamicArray, 2);
  /// StableDynamicArray.add(dynamicArray, 3);
  ///
  /// let newBuf = StableDynamicArray.dropWhile<Nat>(dynamicArray, func x { x < 3 }); // => [3]
  /// StableDynamicArray.toText(newBuf, Nat.toText);
  /// ```
  ///
  /// Runtime: O(size)
  ///
  /// Space: O(size)
  ///
  /// *Runtime and space assumes that `predicate` runs in O(1) time and space.
  public func dropWhile<X>(dynamicArray : StableDynamicArray<X>, predicate : X -> Bool) : StableDynamicArray<X> {
    let newDynamicArray = initPresized<X>(dynamicArray.count);

    var i = 0;
    var take = false;
    label iter for (element in vals(dynamicArray)) {
      if (not (take or predicate element)) {
        take := true;
      };
      if (take) {
        add(newDynamicArray, element);
      };
    };
    newDynamicArray;
  };

};
