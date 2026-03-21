/// A Stable Heap Buffer Deque

import Array "mo:base/Array";
import Debug "mo:base/Debug";
import Iter "mo:base/Iter";

import Common "internal/Common";

module {
    let {
        newCapacity;
        INCREASE_FACTOR_NUME;
        INCREASE_FACTOR_DENOM;
        DECREASE_THRESHOLD;
        DECREASE_FACTOR;
        DEFAULT_CAPACITY;
    } = Common;

    type BufferInterface<A> = Common.BufferInterface<A>;

    public type StableBufferDeque<A> = {
        var elems : [var ?A];
        var start : Nat;
        var count : Nat;
    };

    public func new<A>() : StableBufferDeque<A> = {
        var elems = [var];
        var start = 0;
        var count = 0;
    };

    public func withCapacity<A>(init_capacity : Nat) : StableBufferDeque<A> = {
        var elems = Array.init<?A>(init_capacity, null);
        var start = 0;
        var count = 0;
    };

    public func init<A>(capacity : Nat, val : A) : StableBufferDeque<A> = {
        var elems = Array.init<?A>(capacity, ?val);
        var start = 0;
        var count = capacity;
    };

    public func size<A>(self : StableBufferDeque<A>) : Nat = self.count;

    public func capacity<A>(self : StableBufferDeque<A>) : Nat = self.elems.size();

    // Returns the internal index of the element at the perceived index `i`.
    func get_index<A>(self : StableBufferDeque<A>, i : Nat) : Nat = (self.start + i) % self.elems.size();

    public func get<A>(self : StableBufferDeque<A>, i : Nat) : A {
        if (i >= self.count) {
            Debug.trap("BufferDeque self, ): Index " # debug_show (i) # " out of bounds");
        };

        let ?elem = self.elems[get_index(self, i)] else Debug.trap("BufferDeque get(): Index " # debug_show (i) # " out of bounds");
        return elem;
    };

    public func getOpt<A>(self: StableBufferDeque<A>, i : Nat) : ?A {
        if (i >= self.count) {
            return null;
        };

        return self.elems[get_index(self, i)];
    };

    public func put<A>(self : StableBufferDeque<A>, i : Nat, val : A) {
        if (i >= self.count) {
            Debug.trap("BufferDeque put(): Index " # debug_show (i) # " out of bounds");
        };

        self.elems[get_index(self, i)] := ?val;
    };

    /// Changes the capacity to `capacity`. Traps if `capacity` < `size`.
    ///
    /// ```motoko include=initialize
    ///
    /// buffer.reserve(4);
    /// buffer.add(10);
    /// buffer.add(11);
    /// buffer.capacity(); // => 4
    /// ```
    ///
    /// Runtime: O(capacity)
    ///
    /// Space: O(capacity)
    ///
    /// > *Adapted from the base implementation of the `Buffer` class*
    public func reserve<A>(self : StableBufferDeque<A>, capacity : Nat) {
        if (capacity < self.count) {
            Debug.trap "capacity must be >= size in reserve";
        };

        let elems2 = Array.init<?A>(capacity, null);

        var i = 0;
        while (i < self.count) {
            elems2[i] := self.elems[get_index(self, i)];
            i += 1;
        };

        self.elems := elems2;
        self.start := 0;
    };

    /// Adds an element to the start of the buffer.
    public func addFront<A>(self : StableBufferDeque<A>, elem : A) {
        if (self.count == capacity(self)) {
            reserve(self, newCapacity(capacity(self)));
        };

        self.start := get_index(self, capacity(self) - 1);
        self.elems[self.start] := ?elem;
        self.count += 1;
    };

    /// Adds an element to the end of the buffer
    public func addBack<A>(self : StableBufferDeque<A>, elem : A) {
        if (self.count == capacity(self)) {
            reserve(self, newCapacity(capacity(self)));
        };

        self.elems[get_index(self, self.count)] := ?elem;
        self.count += 1;
    };

    /// Removes an element from the start of the buffer and returns it if it exists.
    /// If the buffer is empty, it returns `null`.
    public func popFront<A>(self : StableBufferDeque<A>) : ?A {
        if (self.count == 0) {
            return null;
        };

        let elem = self.elems[self.start];
        self.elems[self.start] := null;
        self.start := get_index(self, 1);
        self.count -= 1;

        return elem;
    };

    /// Removes an element from the end of the buffer and returns it if it exists.
    /// If the buffer is empty, it returns `null`.
    /// Runtime: `O(1)` amortized
    public func popBack<A>(self : StableBufferDeque<A>) : ?A {
        if (self.count == 0) {
            return null;
        };

        let elem = self.elems[get_index(self, self.count - 1)];
        self.elems[get_index(self, self.count - 1)] := null;
        self.count -= 1;
        return elem;
    };

    /// Removes all elements from the buffer and resizes it to the default capacity.
    public func clear<A>(self : StableBufferDeque<A>) {
        self.start := 0;
        self.count := 0;
        self.elems := Array.init<?A>(DEFAULT_CAPACITY, null);
    };

    /// Adds all the elements in the given buffer to the end of this buffer.
    public func append<A>(self : StableBufferDeque<A>, other : StableBufferDeque<A>) {
        for (i in Iter.range(1, size(other))) {
            addBack(self, get(other, i - 1));
        };
    };

    /// Adds all the elements in the given buffer to the start of this buffer.
    public func prepend<A>(self: StableBufferDeque<A>, other : StableBufferDeque<A>) {
        let other_size = size(other);
        for (i in Iter.range(1, other_size)) {
            let end_index = (other_size - i) : Nat;
            let other_item = get(other, end_index);
            addFront(self, other_item);
        };
    };

    /// Removes an element at the given index and returns it. Traps if the index is out of bounds.
    /// Runtime: `O(min(i, size - i))`
    public func remove<A>(self: StableBufferDeque<A>, i : Nat) : A {
        if (i >= self.count) {
            Debug.trap("BufferDeque remove(): Index " # debug_show (i) # " out of bounds");
        };

        let elem = get(self, i);

        let shift_left = i >= (self.count / 2);

        if (shift_left) {
            var dist = 0;

            while (dist < (self.count - i - 1 : Nat)) {
                let j = dist + i;
                self.elems[get_index(self, j)] := self.elems[get_index(self, j + 1)];
                dist += 1;
            };

            self.elems[get_index(self, self.count - 1)] := null;

        } else {
            var dist = 0;

            while (dist < i) {
                let j = (i - dist) : Nat;
                self.elems[get_index(self, j)] := self.elems[get_index(self, j - 1)];
                dist += 1;
            };

            self.elems[self.start] := null;
            self.start := get_index(self, 1);
        };

        self.count -= 1;
        elem;
    };

    /// Removes a range of elements from the buffer and returns them as an array.
    /// Traps if the range is out of bounds.
    public func removeRange<A>(self: StableBufferDeque<A>, _start : Nat, end : Nat) : [A] {
        if (_start > end) {
            Debug.trap("BufferDeque removeRange(): start " # debug_show (_start) # " > end " # debug_show (end));
        };

        if (end > self.count) {
            Debug.trap("BufferDeque removeRange(): end " # debug_show (end) # " > self.count " # debug_show (self.count));
        };

        let remove_size = (end - _start) : Nat;

        let items = Array.tabulate(
            remove_size,
            func(i : Nat) : A {
                let j = _start + i;
                let val = get(self, j);
                self.elems[get_index(self, j)] := null;
                val;
            },
        );

        let shift_from_end = (self.count - end) : Nat <= _start;

        if (shift_from_end) {
            var dist = 0;

            while (dist < (self.count - end : Nat)) {
                let curr = dist + end;
                let next = (curr - remove_size) : Nat;

                self.elems[get_index(self, next)] := self.elems[get_index(self, curr)];
                self.elems[get_index(self, curr)] := null;
                dist += 1;
            };
        } else {

            var dist = 0;

            while (dist < _start) {
                let curr = (_start - dist - 1) : Nat;
                let next = curr + remove_size;

                self.elems[get_index(self, next)] := self.elems[get_index(self, curr)];
                self.elems[get_index(self, curr)] := null;

                dist += 1;
            };

            self.start := get_index(self, remove_size);

        };

        self.count -= remove_size;

        items;
    };

    /// Returns an iterator over the elements of the buffer.
    /// Note: The values in the iterator will change if the buffer is modified before the iterator is consumed.
    public func range<A>(self : StableBufferDeque<A>, start : Nat, end : Nat) : Iter.Iter<A> {
        if (self.start > end) {
            Debug.trap("BufferDeque range(): start " # debug_show (start) # " > end " # debug_show (end));
        };

        if (end > self.count) {
            Debug.trap("BufferDeque range(): end " # debug_show (end) # " > count " # debug_show (self.count));
        };

        let len = (end - self.start) : Nat;

        if (len == 0) {
            return [].vals();
        };

        Iter.map(
            Iter.range(self.start, end - 1),
            func(i : Nat) : A = get(self, i),
        );
    };


    func swap_unchecked<A>(self: StableBufferDeque<A>, i : Nat, j : Nat) {
        let tmp = self.elems[i];
        self.elems[i] := self.elems[j];
        self.elems[j] := tmp;
    };

    /// Swaps the elements at the given indices.
    public func swap<A>(self: StableBufferDeque<A>, i : Nat, j : Nat) {
        if (i >= self.count) {
            Debug.trap("BufferDeque swap(): Index " # debug_show (i) # " out of bounds");
        };

        if (j >= self.count) {
            Debug.trap("BufferDeque swap(): Index " # debug_show (j) # " out of bounds");
        };

        swap_unchecked(self, get_index(self, i), get_index(self, j));
    };

     /// Rotates the buffer to the left by the given amount.
    /// Runtime: `O(min(n, size - n))`
    public func rotateLeft<A>(self: StableBufferDeque<A>, n : Nat) {
        let rotate_n = n % self.count;

        if (rotate_n == 0) {
            return;
        };

        if (size(self) == capacity(self)) {
            self.start := get_index(self, rotate_n);
            return;
        };

        let shift_from_end = (self.count - rotate_n) : Nat <= rotate_n;

        if (shift_from_end) {
            var dist = 0;
            while (dist < (self.count - rotate_n : Nat)) {
                let curr = rotate_n + dist;
                let next = (curr + self.count) % capacity(self);
                let i = get_index(self, curr);
                let j = get_index(self, next);

                swap_unchecked(self, i, j);
                dist += 1;
            };

            self.start := get_index(self, (capacity(self) - (self.count - rotate_n)) : Nat);

        } else {
            var dist = 0;

            while (dist < rotate_n) {
                let curr = dist;
                let next = (curr + self.count) % capacity(self);
                let i = get_index(self, curr);
                let j = get_index(self, next);

                swap_unchecked(self, i, j);
                dist += 1;
            };

            self.start := get_index(self, rotate_n);
        };
    };

    /// Rotates the buffer to the right by the given amount.
    /// Runtime: `O(min(n, size - n))`
    public func rotateRight<A>(self: StableBufferDeque<A>, n : Nat) = rotateLeft(self, self.count - (n % self.count));


    /// Returns an iterator over the elements of the buffer.
    public func vals<A>(self: StableBufferDeque<A>) : Iter.Iter<A> {
        Iter.map(
            Iter.range(1, self.count),
            func(i : Nat) : A = get(self, i - 1),
        );
    };

    /// Returns the element at the front of the buffer, or `null` if the buffer is empty.
    public func peekFront<A>(self : StableBufferDeque<A>) : ?A {
        getOpt(self, 0);
    };

    /// Returns the element at the back of the buffer, or `null` if the buffer is empty.
    public func peekBack<A>(self : StableBufferDeque<A>) : ?A {
        let buffer_size = size(self);
        if (buffer_size == 0) { return null };

        getOpt(self, buffer_size - 1);
    };

    /// Checks if the buffer is empty.
    public func isEmpty<A>(self : StableBufferDeque<A>) : Bool {
        size(self) == 0;
    };

    /// Creates a buffer from the given array.
    public func fromArray<A>(arr : [A]) : StableBufferDeque<A> {
        let buffer = withCapacity<A>(arr.size());

        for (i in Iter.range(1, arr.size())) {
            addBack(buffer, arr[i - 1]);
        };

        buffer;
    };

    /// Returns the buffer as an array.
    public func toArray<A>(self : StableBufferDeque<A>) : [A] {
        Array.tabulate(size(self), func(i : Nat) : A = get(self, i));
    };
};
