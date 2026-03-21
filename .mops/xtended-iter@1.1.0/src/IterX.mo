import Order "mo:core@1/Order";
import Nat "mo:core@1/Nat";
import Iter "mo:core@1/Iter";
import List "mo:core@1/List";
import Runtime "mo:core@1/Runtime";
import PeekableIter "PeekableIter";

module {

  /// Returns an iterator that accumulates elements into arrays with a size less than or equal to the given `size`.
  /// Each chunk will contain exactly `chunkSize` elements except for the last chunk which may contain fewer elements.
  /// This function will trap if `size` is 0.
  ///
  /// ```motoko
  /// let vals = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10].vals();
  /// let chunkedIter = IterX.chunk(vals, 3);
  ///
  /// let chunk1 = chunkedIter.next(); // ?[1, 2, 3]
  /// let chunk2 = chunkedIter.next(); // ?[4, 5, 6]
  /// let chunk3 = chunkedIter.next(); // ?[7, 8, 9]
  /// let chunk4 = chunkedIter.next(); // ?[10]
  /// let chunk5 = chunkedIter.next(); // null
  /// ```
  public func chunk<A>(iter : Iter.Iter<A>, chunkSize : Nat) : Iter.Iter<[A]> {
    if (chunkSize == 0) {
      return Runtime.trap("Size must be greater than 0");
    };
    let list = List.empty<A>();

    object {
      public func next() : ?[A] {
        var i = 0;

        label l while (i < chunkSize) {
          let ?val = iter.next() else break l;
          List.add(list, val);
          i := i + 1;
        };

        if (List.size(list) == 0) {
          null;
        } else {
          let tmp = ?List.toArray(list);
          List.clear(list);
          tmp;
        };
      };
    };
  };

  /// Checks if two iterators are equal by comparing each element using the provided equality function.
  /// Returns `true` if both iterators contain the same sequence of elements, `false` otherwise.
  /// The iterators are consumed during comparison.
  ///
  /// ```motoko
  /// import Nat "mo:core@1/Nat";
  ///
  /// let iter1 = [1, 2, 3, 4, 5].vals();
  /// let iter2 = [1, 2, 3, 4, 5].vals();
  /// let result = IterX.equal(iter1, iter2, Nat.equal);
  /// // Returns: true
  ///
  /// let iter3 = [1, 2, 3].vals();
  /// let iter4 = [1, 2, 3, 4].vals();
  /// let result2 = IterX.equal(iter3, iter4, Nat.equal);
  /// // Returns: false
  /// ```
  public func equal<A>(
    iter1 : Iter.Iter<A>,
    iter2 : Iter.Iter<A>,
    isEq : (A, A) -> Bool,
  ) : Bool {

    switch ((iter1.next(), iter2.next())) {
      case ((?a, ?b)) {
        if (isEq(a, b)) {
          equal<A>(iter1, iter2, isEq);
        } else {
          false;
        };
      };
      case ((null, ?_)) false;
      case ((?_, null)) false;
      case ((null, null)) true;
    };

  };

  /// Returns the index of the first element in an iterator that matches the given predicate.
  /// If no element matches the predicate, returns `null`.
  /// The iterator is consumed up to and including the first matching element.
  ///
  /// ```motoko
  /// let numbers = [1, 3, 5, 8, 9, 12].vals();
  /// let isEven = func(x : Nat) : Bool { x % 2 == 0 };
  /// let result = IterX.findIndex(numbers, isEven);
  /// // Returns: ?3 (index of first even number: 8)
  ///
  /// let oddNumbers = [1, 3, 5, 7].vals();
  /// let result2 = IterX.findIndex(oddNumbers, isEven);
  /// // Returns: null (no even numbers found)
  /// ```
  public func findIndex<A>(iter : Iter.Iter<A>, predicate : (A) -> Bool) : ?Nat {
    var i = 0;
    for (val in iter) {
      if (predicate(val)) {
        return ?i;
      };
      i += 1;
    };
    return null;
  };

  /// Returns an iterator containing the indices of all elements that match the given predicate.
  /// The original iterator is fully consumed, and the returned iterator yields indices in order.
  ///
  /// ```motoko
  /// let numbers = [1, 2, 3, 4, 5, 6].vals();
  /// let isEven = func(x : Nat) : Bool { x % 2 == 0 };
  /// let indices = IterX.findIndices(numbers, isEven);
  /// let result = Iter.toArray(indices);
  /// // Returns: [1, 3, 5] (indices of even numbers: 2, 4, 6)
  /// ```
  public func findIndices<A>(iter : Iter.Iter<A>, predicate : (A) -> Bool) : Iter.Iter<Nat> {
    var i = 0;
    return object {
      public func next() : ?Nat {
        for (val in iter) {
          i += 1;

          if (predicate(val)) {
            return ?(i - 1);
          };

        };

        return null;
      };
    };
  };

  /// Returns a flattened iterator that yields all elements from nested arrays in sequence.
  /// Each array in the input iterator is expanded, and its elements are yielded individually.
  ///
  /// ```motoko
  /// let nestedArrays = [[1], [2, 3], [4, 5, 6]].vals();
  /// let flattenedIter = IterX.flattenArray(nestedArrays);
  /// let result = Iter.toArray(flattenedIter);
  /// // Returns: [1, 2, 3, 4, 5, 6]
  ///
  /// let emptyAndFilled = [[], [1, 2], []].vals();
  /// let result2 = Iter.toArray(IterX.flattenArray(emptyAndFilled));
  /// // Returns: [1, 2]
  /// ```
  public func flattenArray<A>(nestedArray : Iter.Iter<[A]>) : Iter.Iter<A> {
    Iter.flatten(
      Iter.map(
        nestedArray,
        func(arr : [A]) : Iter.Iter<A> {
          arr.vals();
        },
      )
    );
  };

  /// Groups consecutive elements into arrays based on the result of the given predicate function.
  /// Returns an iterator of tuples where each tuple contains an array of consecutive elements
  /// and a boolean indicating the predicate result for that group.
  ///
  /// ```motoko
  /// let numbers = [1, 3, 5, 2, 4, 7, 9].vals();
  /// let isEven = func(x : Nat) : Bool { x % 2 == 0 };
  /// let groups = IterX.groupBy(numbers, isEven);
  /// let result = Iter.toArray(groups);
  /// // Returns: [([1, 3, 5], false), ([2, 4], true), ([7, 9], false)]
  /// ```
  public func groupBy<A>(iter : Iter.Iter<A>, pred : (A) -> Bool) : Iter.Iter<([A], Bool)> {
    let groupItemList = List.empty<A>();

    func nextGroup() : ?([A], Bool) {
      switch (iter.next()) {
        case (?val) {
          if (List.size(groupItemList) == 0) {
            List.add(groupItemList, val);
            return nextGroup();
          };

          let firstItem = List.at(groupItemList, 0);

          if (pred(firstItem) == pred(val)) {
            List.add(groupItemList, val);
            nextGroup();
          } else {
            let arr = List.toArray(groupItemList);

            List.clear(groupItemList);
            List.add(groupItemList, val);

            ?(arr, pred(arr[0]));
          };
        };
        case (_) {
          if (List.size(groupItemList) == 0) {
            null;
          } else {
            let arr = List.toArray(groupItemList);

            List.clear(groupItemList);

            ?(arr, pred(arr[0]));
          };
        };
      };
    };

    return object {
      public func next() : ?([A], Bool) {
        nextGroup();
      };
    };
  };

  /// Checks if all elements in an iterator are sorted in ascending order using the provided comparison function.
  /// Returns `true` if for every consecutive pair of elements `a` and `b`, `compare(a, b) != #greater`.
  /// Returns `true` for empty iterators.
  ///
  /// ```motoko
  /// import Nat "mo:core@1/Nat";
  ///
  /// let ascending = [1, 2, 3, 4, 5].vals();
  /// let result1 = IterX.isSorted(ascending, Nat.compare);
  /// // Returns: true
  ///
  /// let unsorted = [1, 4, 2, 3].vals();
  /// let result2 = IterX.isSorted(unsorted, Nat.compare);
  /// // Returns: false
  ///
  /// let empty = [].vals();
  /// let result3 = IterX.isSorted(empty, Nat.compare);
  /// // Returns: true
  /// ```
  public func isSorted<A>(iter : Iter.Iter<A>, cmp : (A, A) -> Order.Order) : Bool {
    var prev = switch (iter.next()) {
      case (?n) { n };
      case (null) return true;
    };

    for (item in iter) {
      if (cmp(prev, item) == #greater) {
        return false;
      };
      prev := item;
    };

    true;
  };

  /// Checks if all elements in an iterator are sorted in descending order using the provided comparison function.
  /// Returns `true` if for every consecutive pair of elements `a` and `b`, `compare(a, b) != #less`.
  /// Returns `true` for empty iterators.
  ///
  /// ```motoko
  /// import Nat "mo:core@1/Nat";
  ///
  /// let descending = [5, 4, 3, 2, 1].vals();
  /// let result1 = IterX.isSortedDesc(descending, Nat.compare);
  /// // Returns: true
  ///
  /// let ascending = [1, 2, 3, 4].vals();
  /// let result2 = IterX.isSortedDesc(ascending, Nat.compare);
  /// // Returns: false
  ///
  /// let empty = [].vals();
  /// let result3 = IterX.isSortedDesc(empty, Nat.compare);
  /// // Returns: true
  /// ```
  public func isSortedDesc<A>(iter : Iter.Iter<A>, cmp : (A, A) -> Order.Order) : Bool {
    var prev = switch (iter.next()) {
      case (?n) { n };
      case (null) return true;
    };

    for (item in iter) {
      if (cmp(prev, item) == #less) {
        return false;
      };
      prev := item;
    };

    true;
  };

  /// Returns a tuple containing the minimum and maximum values from an iterator.
  /// The first element of the tuple is the minimum value, the second is the maximum value.
  /// Returns `null` if the iterator is empty.
  /// If the iterator contains only one element, it is returned as both minimum and maximum.
  ///
  /// ```motoko
  /// import Nat "mo:core@1/Nat";
  ///
  /// let numbers = [8, 4, 6, 9, 2].vals();
  /// let result = IterX.minmax(numbers, Nat.compare);
  /// // Returns: ?(2, 9)
  ///
  /// let empty = [].vals();
  /// let result2 = IterX.minmax(empty, Nat.compare);
  /// // Returns: null
  ///
  /// let single = [42].vals();
  /// let result3 = IterX.minmax(single, Nat.compare);
  /// // Returns: ?(42, 42)
  /// ```
  public func minmax<A>(iter : Iter.Iter<A>, cmp : (A, A) -> Order.Order) : ?(A, A) {
    let (_min, _max) = switch (iter.next()) {
      case (?a) {
        switch (iter.next()) {
          case (?b) {
            switch (cmp(a, b)) {
              case (#less) { (a, b) };
              case (_) { (b, a) };
            };
          };
          case (_) { (a, a) };
        };
      };
      case (_) {
        return null;
      };
    };

    var min = _min;
    var max = _max;

    for (val in iter) {
      if (cmp(val, min) == #less) {
        min := val;
      };

      if (cmp(val, max) == #greater) {
        max := val;
      };
    };

    ?(min, max)

  };

  /// Returns the nth element of an iterator (0-indexed).
  /// Consumes the first n elements of the iterator and returns the element at position n.
  /// Returns `null` if the iterator has fewer than n+1 elements.
  ///
  /// ```motoko
  /// let numbers = [10, 20, 30, 40, 50].vals();
  /// let result = IterX.nth(numbers, 2);
  /// // Returns: ?30 (element at index 2)
  ///
  /// let shortList = [1, 2].vals();
  /// let result2 = IterX.nth(shortList, 5);
  /// // Returns: null (index 5 doesn't exist)
  ///
  /// let result3 = IterX.nth([100].vals(), 0);
  /// // Returns: ?100 (first element)
  /// ```
  public func nth<A>(iter : Iter.Iter<A>, n : Nat) : ?A {
    let skippedIter = Iter.drop<A>(iter, n);
    return skippedIter.next();
  };

  /// Partitions an iterator into two arrays based on a predicate function.
  /// Returns a tuple where the first array contains all elements for which the predicate returns `true`,
  /// and the second array contains all elements for which the predicate returns `false`.
  /// The relative order of elements within each partition is preserved.
  ///
  /// ```motoko
  /// let numbers = [1, 2, 3, 4, 5, 6].vals();
  /// let isEven = func(n : Nat) : Bool { n % 2 == 0 };
  /// let (evenIter, oddIter) = IterX.partition(numbers, isEven);
  /// let evens = Iter.toArray(evenIter);
  /// let odds = Iter.toArray(oddIter);
  /// // evens = [2, 4, 6], odds = [1, 3, 5]
  ///
  /// let empty = [].vals();
  /// let (emptyTrue, emptyFalse) = IterX.partition(empty, isEven);
  /// // Both iterators will be empty
  /// ```
  public func partition<A>(iter : Iter.Iter<A>, f : (A) -> Bool) : (Iter.Iter<A>, Iter.Iter<A>) {
    let firstGroup = List.empty<A>();
    let secondGroup = List.empty<A>();

    for (val in iter) {
      if (f(val)) {
        List.add(firstGroup, val);
      } else {
        List.add(secondGroup, val);
      };
    };

    (List.values(firstGroup), List.values(secondGroup));
  };

  /// Splits an iterator into two iterators at the specified position.
  /// Returns a tuple where the first iterator contains the first `n` elements,
  /// and the second iterator contains the remaining elements.
  /// The original iterator is consumed during this operation.
  ///
  /// ```motoko
  /// let numbers = [1, 2, 3, 4, 5, 6].vals();
  /// let (leftIter, rightIter) = IterX.splitAt(numbers, 3);
  ///
  /// let left = Iter.toArray(leftIter);   // [1, 2, 3]
  /// let right = Iter.toArray(rightIter); // [4, 5, 6]
  ///
  /// let shortList = [1, 2].vals();
  /// let (left2, right2) = IterX.splitAt(shortList, 5);
  /// // left2 contains [1, 2], right2 is empty
  /// ```
  public func splitAt<A>(iter : Iter.Iter<A>, n : Nat) : (Iter.Iter<A>, Iter.Iter<A>) {
    let left = Iter.toArray(Iter.take(iter, n)).vals();
    (left, iter);
  };

  /// Unzips an iterator of tuples into a tuple of two arrays.
  /// The first array contains all the first elements from the tuples,
  /// and the second array contains all the second elements from the tuples.
  /// The order of elements is preserved.
  ///
  /// ```motoko
  /// let pairs = [(1, 'a'), (2, 'b'), (3, 'c')].vals();
  /// let (numbers, letters) = IterX.unzip(pairs);
  /// // numbers = [1, 2, 3], letters = ['a', 'b', 'c']
  ///
  /// let empty = [].vals();
  /// let (emptyNums, emptyChars) = IterX.unzip(empty);
  /// // Both arrays will be empty: [], []
  /// ```
  public func unzip<A, B>(iter : Iter.Iter<(A, B)>) : ([A], [B]) {
    var list1 = List.empty<A>();
    var list2 = List.empty<B>();

    for ((a, b) in iter) {
      List.add(list1, a);
      List.add(list2, b);
    };

    (List.toArray(list1), List.toArray(list2));
  };

  /// Converts a regular iterator into a peekable iterator.
  /// A peekable iterator allows you to look at the next value without consuming it
  /// by calling the `peek()` method. This is useful when you need to examine
  /// the next element before deciding whether to consume it.
  ///
  /// ```motoko
  /// let numbers = [10, 20, 30].vals();
  /// let peekableIter = IterX.toPeekable(numbers);
  ///
  /// let nextValue = peekableIter.peek(); // ?10 (doesn't consume)
  /// let nextValue2 = peekableIter.peek(); // ?10 (still doesn't consume)
  /// let consumed = peekableIter.next();   // ?10 (consumes the value)
  /// let afterPeek = peekableIter.peek();  // ?20 (next value)
  /// let consumed2 = peekableIter.next();  // ?20
  /// let consumed3 = peekableIter.next();  // ?30
  /// let end = peekableIter.peek();        // null (no more values)
  /// ```
  public func toPeekable<T>(iter : Iter.Iter<T>) : PeekableIter.PeekableIter<T> {
    PeekableIter.fromIter<T>(iter);
  };

};
