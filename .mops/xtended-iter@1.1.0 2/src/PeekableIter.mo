import Iter "mo:core@1/Iter";

module {
  /// Represents an iterator that allows peeking at the next element without consuming it.
  /// A PeekableIter extends the standard Iter interface with a `peek` method that returns
  /// the next value without advancing the iterator position.
  ///
  /// ```motoko
  /// let numbers = [1, 2, 3].vals();
  /// let peekableIter : PeekableIter<Nat> = PeekableIter.fromIter(numbers);
  /// ```
  public type PeekableIter<T> = Iter.Iter<T> and {
    peek : () -> ?T;
  };

  /// Creates a PeekableIter from an existing iterator.
  /// The returned peekable iterator allows you to examine the next value using `peek()`
  /// without consuming it, which is useful for lookahead parsing or conditional processing.
  ///
  /// The `peek()` method caches the next value internally, so subsequent calls to `peek()`
  /// return the same value without advancing the underlying iterator. The cached value
  /// is consumed when `next()` is called.
  ///
  /// ```motoko
  /// let numbers = [10, 20, 30].vals();
  /// let peekable = PeekableIter.fromIter(numbers);
  ///
  /// let peeked1 = peekable.peek(); // ?10 (caches the value)
  /// let peeked2 = peekable.peek(); // ?10 (returns cached value)
  /// let consumed1 = peekable.next(); // ?10 (consumes cached value)
  ///
  /// let peeked3 = peekable.peek(); // ?20 (caches next value)
  /// let consumed2 = peekable.next(); // ?20 (consumes cached value)
  /// let consumed3 = peekable.next(); // ?30 (no peek, direct consumption)
  ///
  /// let end = peekable.peek(); // null (no more elements)
  /// let endNext = peekable.next(); // null (no more elements)
  /// ```
  public func fromIter<T>(iter : Iter.Iter<T>) : PeekableIter<T> {
    var peekItem : ?T = null;

    return object {
      public func peek() : ?T {
        switch (peekItem) {
          case (?val) ?val;
          case (null) {
            // If we don't have a peeked value, get the next item from the iterator
            // and store it for future calls to peek and next.
            let next = iter.next();
            peekItem := next;
            next;
          };
        };
      };

      public func next() : ?T {
        switch (peekItem) {
          case (?val) {
            // If we have a peeked value, return it and clear the cache
            peekItem := null;
            ?val;
          };
          case (null) iter.next(); // Otherwise, just call next on the underlying iterator
        };
      };
    };
  };

  /// Checks if the peekable iterator has more elements available.
  /// Returns `true` if there are more elements, `false` if the iterator is exhausted.
  /// This method uses `peek()` internally, which may advance the underlying iterator
  /// by one position if no value is currently cached.
  ///
  /// ```motoko
  /// let numbers = [1, 2].vals();
  /// let peekable = PeekableIter.fromIter(numbers);
  ///
  /// let hasMore1 = PeekableIter.hasNext(peekable); // true
  /// let first = peekable.next(); // ?1
  ///
  /// let hasMore2 = PeekableIter.hasNext(peekable); // true
  /// let second = peekable.next(); // ?2
  ///
  /// let hasMore3 = PeekableIter.hasNext(peekable); // false
  /// let end = peekable.next(); // null
  ///
  /// // Example with empty iterator
  /// let empty = [].vals();
  /// let emptyPeekable = PeekableIter.fromIter(empty);
  /// let hasAny = PeekableIter.hasNext(emptyPeekable); // false
  /// ```
  public func hasNext<T>(iter : PeekableIter<T>) : Bool {
    switch (iter.peek()) {
      case (?_) { true };
      case (null) { false };
    };
  };

  /// Checks if the next value in the peekable iterator equals the given value using the provided equality function.
  /// Returns `true` if the next value exists and equals the given value, `false` otherwise.
  /// This method does not advance the peekable iterator position, but may advance the underlying
  /// iterator by one position if no value is currently cached.
  ///
  /// ```motoko
  /// import Nat "mo:core@1/Nat";
  ///
  /// let numbers = [42, 100, 200].vals();
  /// let peekable = PeekableIter.fromIter(numbers);
  ///
  /// let isFortyTwo = PeekableIter.isNext(peekable, 42, Nat.equal); // true
  /// let isHundred = PeekableIter.isNext(peekable, 100, Nat.equal); // false (next is 42)
  ///
  /// let consumed = peekable.next(); // ?42 (consume the peeked value)
  /// let isHundredNow = PeekableIter.isNext(peekable, 100, Nat.equal); // true
  ///
  /// // Example with empty iterator
  /// let empty = [].vals();
  /// let emptyPeekable = PeekableIter.fromIter(empty);
  /// let isAnything = PeekableIter.isNext(emptyPeekable, 42, Nat.equal); // false
  ///
  /// // Example with custom equality
  /// let texts = ["hello", "world"].vals();
  /// let textPeekable = PeekableIter.fromIter(texts);
  /// let isHello = PeekableIter.isNext(textPeekable, "hello", Text.equal); // true
  /// let isHELLO = PeekableIter.isNext(textPeekable, "HELLO", Text.equal); // false (case sensitive)
  /// ```
  public func isNext<T>(iter : PeekableIter<T>, val : T, isEq : (T, T) -> Bool) : Bool {
    switch (iter.peek()) {
      case (?v) { isEq(v, val) };
      case (null) { false };
    };
  };
};
