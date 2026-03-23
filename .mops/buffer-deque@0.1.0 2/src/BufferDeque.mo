/// A Buffer that with an amortized time of O(1) additions at both ends

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

    public class BufferDeque<A>(init_capacity : Nat) {

        var start = 0;
        var count = 0;

        var elems : [var ?A] = Array.init<?A>(init_capacity, null);

        /// Returns the number of items in the buffer
        public func size() : Nat = count;

        /// Returns the capacity of the deque.
        public func capacity() : Nat = elems.size();

        // Returns the internal index of the element at the perceived index `i`.
        private func get_index(i : Nat) : Nat = (start + i) % capacity();

        /// for debugging purposes
        public func internal_array() : [?A] = Array.freeze(elems);
        public func internal_start() : Nat = start;

        /// Retrieves the element at the given index.
        /// Traps if the index is out of bounds.
        public func get(i : Nat) : A {
            if (i >= count) {
                Debug.trap("BufferDeque get(): Index " # debug_show (i) # " out of bounds");
            };

            switch (elems[get_index(i)]) {
                case (?elem) elem;
                case (null) Debug.trap("BufferDeque get(): Index " # debug_show (i) # " out of bounds");
            };
        };

        /// Retrieves an element at the given index, if it exists.
        /// If not it returns `null`.
        public func getOpt(i : Nat) : ?A {
            if (i < count) {
                elems[get_index(i)];
            } else {
                null;
            };
        };

        /// Overwrites the element at the given index.
        public func put(i : Nat, elem : A) {
            if (i >= count) {
                Debug.trap("BufferDeque put(): Index " # debug_show (i) # " out of bounds");
            };

            elems[get_index(i)] := ?elem;
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
        public func reserve(capacity : Nat) {
            if (capacity < count) {
                Debug.trap "capacity must be >= size in reserve";
            };

            let elems2 = Array.init<?A>(capacity, null);

            var i = 0;
            while (i < count) {
                elems2[i] := elems[get_index(i)];
                i += 1;
            };

            elems := elems2;
            start := 0;
        };

        /// Adds an element to the start of the buffer.
        public func addFront(elem : A) {
            if (count == capacity()) {
                reserve(newCapacity(capacity()));
            };

            start := get_index(capacity() - 1);
            elems[start] := ?elem;
            count += 1;
        };

        /// Adds an element to the end of the buffer
        public func addBack(elem : A) {
            if (count == capacity()) {
                reserve(newCapacity(capacity()));
            };

            elems[get_index(count)] := ?elem;
            count += 1;
        };

        /// Removes an element from the start of the buffer and returns it if it exists.
        /// If the buffer is empty, it returns `null`.
        public func popFront() : ?A {
            if (count == 0) {
                return null;
            };

            let elem = elems[start];
            elems[start] := null;
            start := get_index(1);
            count -= 1;
            return elem;
        };

        /// Removes an element from the end of the buffer and returns it if it exists.
        /// If the buffer is empty, it returns `null`.
        /// Runtime: `O(1)` amortized
        public func popBack() : ?A {
            if (count == 0) {
                return null;
            };

            let elem = elems[get_index(count - 1)];
            elems[get_index(count - 1)] := null;
            count -= 1;
            return elem;
        };

        /// Removes all elements from the buffer and resizes it to the default capacity.
        public func clear() {
            start := 0;
            count := 0;
            elems := Array.init<?A>(DEFAULT_CAPACITY, null);
        };

        /// Adds all the elements in the given buffer to the end of this buffer.
        /// The `BufferInterface<A>` type is used to allow for any type that has a `size` and `get` method.
        public func append(other : BufferInterface<A>) {
            for (i in Iter.range(1, other.size())) {
                addBack(other.get(i - 1));
            };
        };

        /// Adds all the elements in the given buffer to the start of this buffer.
        public func prepend(other : BufferInterface<A>) {
            for (i in Iter.range(1, other.size())) {
                let end_index = (other.size() - i) : Nat;
                addFront(other.get(end_index));
            };
        };

        func subToMinZero(x : Nat, y : Nat) : Nat = if (x > y) x - y else 0;

        /// Removes an element at the given index and returns it. Traps if the index is out of bounds.
        /// Runtime: `O(min(i, size - i))`
        public func remove(i : Nat) : A {
            if (i >= count) {
                Debug.trap("BufferDeque remove(): Index " # debug_show (i) # " out of bounds");
            };

            let elem = get(i);

            let shift_left = i >= (count / 2);

            if (shift_left) {
                var dist = 0;

                while (dist < (count - i - 1 : Nat)) {
                    let j = dist + i;
                    elems[get_index(j)] := elems[get_index(j + 1)];
                    dist += 1;
                };

                elems[get_index(count - 1)] := null;

            } else {
                var dist = 0;

                while (dist < i) {
                    let j = (i - dist) : Nat;
                    elems[get_index(j)] := elems[get_index(j - 1)];
                    dist += 1;
                };

                elems[start] := null;
                start := get_index(1);
            };

            count -= 1;
            elem;
        };

        /// Removes a range of elements from the buffer and returns them as an array.
        /// Traps if the range is out of bounds.
        public func removeRange(_start : Nat, end : Nat) : [A] {
            if (_start > end) {
                Debug.trap("BufferDeque removeRange(): start " # debug_show (_start) # " > end " # debug_show (end));
            };

            if (end > count) {
                Debug.trap("BufferDeque removeRange(): end " # debug_show (end) # " > count " # debug_show (count));
            };

            let remove_size = (end - _start) : Nat;

            let items = Array.tabulate(
                remove_size,
                func(i : Nat) : A {
                    let j = _start + i;
                    let val = get(j);
                    elems[get_index(j)] := null;
                    val;
                },
            );

            let shift_from_end = (count - end) : Nat <= _start;

            if (shift_from_end) {
                var dist = 0;

                while (dist < (count - end : Nat)) {
                    let curr = dist + end;
                    let next = (curr - remove_size) : Nat;

                    elems[get_index(next)] := elems[get_index(curr)];
                    elems[get_index(curr)] := null;
                    dist += 1;
                };
            } else {

                var dist = 0;

                while (dist < _start) {
                    let curr = (_start - dist - 1) : Nat;
                    let next = curr + remove_size;

                    elems[get_index(next)] := elems[get_index(curr)];
                    elems[get_index(curr)] := null;

                    dist += 1;
                };

                start := get_index(remove_size);

            };

            count -= remove_size;

            items;
        };

        /// Returns an iterator over the elements of the buffer.
        /// Note: The values in the iterator will change if the buffer is modified before the iterator is consumed.
        public func range(start : Nat, end : Nat) : Iter.Iter<A> {
            if (start > end) {
                Debug.trap("BufferDeque range(): start " # debug_show (start) # " > end " # debug_show (end));
            };

            if (end > count) {
                Debug.trap("BufferDeque range(): end " # debug_show (end) # " > count " # debug_show (count));
            };

            let len = (end - start) : Nat;

            if (len == 0) {
                return [].vals();
            };

            Iter.map(
                Iter.range(start, end - 1),
                func(i : Nat) : A = get(i),
            );
        };

        func swap_unchecked(i : Nat, j : Nat) {
            let tmp = elems[i];
            elems[i] := elems[j];
            elems[j] := tmp;
        };

        /// Swaps the elements at the given indices.
        public func swap(i : Nat, j : Nat) {
            if (i >= count) {
                Debug.trap("BufferDeque swap(): Index " # debug_show (i) # " out of bounds");
            };

            if (j >= count) {
                Debug.trap("BufferDeque swap(): Index " # debug_show (j) # " out of bounds");
            };

            swap_unchecked(get_index(i), get_index(j));
        };

        /// Rotates the buffer to the left by the given amount.
        /// Runtime: `O(min(n, size - n))`
        public func rotateLeft(n : Nat) {
            let rotate_n = n % count;

            if (rotate_n == 0) {
                return;
            };

            if (size() == capacity()) {
                start := get_index(rotate_n);
                return;
            };

            let shift_from_end = (count - rotate_n) : Nat <= rotate_n;

            if (shift_from_end) {
                var dist = 0;
                while (dist < (count - rotate_n : Nat)) {
                    let curr = rotate_n + dist;
                    let next = (curr + count) % capacity();
                    let i = get_index(curr);
                    let j = get_index(next);

                    swap_unchecked(i, j);
                    dist += 1;
                };

                start := get_index((capacity() - (count - rotate_n)) : Nat);

            } else {
                var dist = 0;

                while (dist < rotate_n) {
                    let curr = dist;
                    let next = (curr + count) % capacity();
                    let i = get_index(curr);
                    let j = get_index(next);

                    swap_unchecked(i, j);
                    dist += 1;
                };

                start := get_index(rotate_n);
            };
        };

        /// Rotates the buffer to the right by the given amount.
        /// Runtime: `O(min(n, size - n))`
        public func rotateRight(n : Nat) = rotateLeft(count - (n % count));

        /// Returns an iterator over the elements of the buffer.
        public func vals() : Iter.Iter<A> {
            Iter.map(
                Iter.range(1, count),
                func(i : Nat) : A = get(i - 1),
            );
        };
    };

    /// Creates an empty buffer.
    public func new<A>() : BufferDeque<A> {
        BufferDeque<A>(0);
    };

    /// Creates a buffer with the given capacity and initializes all elements to the given value.
    public func init<A>(capacity : Nat, val : A) : BufferDeque<A> {
        let buffer = BufferDeque<A>(capacity);

        for (_ in Iter.range(1, capacity)) {
            buffer.addBack(val);
        };

        buffer;
    };

    /// Creates a buffer with the given capacity and initializes all elements using the given function.
    public func tabulate<A>(capacity : Nat, f : Nat -> A) : BufferDeque<A> {
        let buffer = BufferDeque<A>(capacity);

        for (i in Iter.range(1, capacity)) {
            buffer.addBack(f(i - 1));
        };

        buffer;
    };

    /// Returns the element at the front of the buffer, or `null` if the buffer is empty.
    public func peekFront<A>(buffer : BufferDeque<A>) : ?A {
        buffer.getOpt(0);
    };

    /// Returns the element at the back of the buffer, or `null` if the buffer is empty.
    public func peekBack<A>(buffer : BufferDeque<A>) : ?A {
        let size = buffer.size();
        if (size == 0) { return null };

        buffer.getOpt(size - 1);
    };

    /// Checks if the buffer is empty.
    public func isEmpty<A>(buffer : BufferDeque<A>) : Bool {
        buffer.size() == 0;
    };

    /// Creates a buffer from the given array.
    public func fromArray<A>(arr : [A]) : BufferDeque<A> {
        let buffer = BufferDeque<A>(arr.size());

        for (i in Iter.range(1, arr.size())) {
            buffer.addBack(arr[i - 1]);
        };

        buffer;
    };

    /// Returns the buffer as an array.
    public func toArray<A>(buffer : BufferDeque<A>) : [A] {
        Array.tabulate(buffer.size(), func(i : Nat) : A = buffer.get(i));
    };
};
