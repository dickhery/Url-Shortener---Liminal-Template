import Array "mo:base/Array";
import Debug "mo:base/Debug";

import InternalTypes "Types";
import ArrayMut "ArrayMut";
import Cmp "../Cmp";

module MaxHeap {
    type CmpFn<A> = InternalTypes.CmpFn<A>;

    public type MaxHeap<A> = [var ?A];

    public func new<A>(capacity : Nat) : MaxHeap<A> {
        Array.init<?A>(capacity, null);
    };

    public func fromArray<A>(arr: [A], cmp: CmpFn<A>): MaxHeap<A> {
        let heap = MaxHeap.new<A>(arr.size());
        var i = 0;

        for (val in arr.vals()){
            MaxHeap.put(heap, cmp, val, i);
            i += 1;
        };

        heap;
    };

    func trickle_down<A>(heap : MaxHeap<A>, cmp : CmpFn<A>, index : Nat, count : Nat) {
        if (index >= count) Debug.trap("index (" # debug_show index # ") is greater than count (" # debug_show count # ")");
        if (count > heap.size()) Debug.trap("count (" # debug_show count # ") is greater than heap size (" # debug_show heap.size() # ")");

        var curr = index;

        label loop1 loop {
            var largest = curr;

            let left = (curr * 2) + 1;
            let right = (curr * 2) + 2;

            if (left < count) switch (heap[left], heap[largest]) {
                case (?left_val, ?largest_val) if (cmp(left_val, largest_val) == 1) largest := left;
                case (_) {};
            };

            if (right < count) switch(heap[right], heap[largest]) {
                case (?right_val, ?largest_val) if (cmp(right_val, largest_val) == 1)  largest := right;
                case (_) {};
            };

            if (largest != curr) {
                ArrayMut.swap(heap, curr, largest);
                trickle_down(heap, cmp, largest, count);
                curr := largest;
            } else break loop1;
        };
    };

    func trickle_up<A>(heap : MaxHeap<A>, cmp : CmpFn<A>, child_index : Nat, count : Nat) {
        if (child_index >= count) Debug.trap("child_index (" # debug_show child_index # ") is greater than count (" # debug_show count # ")");
        if (count > heap.size()) Debug.trap("count (" # debug_show count # ") is greater than heap size (" # debug_show heap.size() # ")");

        if (child_index == 0) return;

        var child = child_index;

        label loop1 while (child > 0) {
            let parent = (child - 1 : Nat) / 2;
            let left = (parent * 2 ) + 1;
            let right = (parent * 2) + 2;

            var largest = parent;

            // left is always included because it is either the given index or to the left of the given index
            switch (heap[left], heap[largest]) {
                case (?left_val, ?largest_val) if (cmp(left_val, largest_val) == 1) largest := left;
                case (_) {};
            };

            if (right < count) switch(heap[right], heap[largest]) {
                case (?right_val, ?largest_val) if (cmp(right_val, largest_val) == 1)  largest := right;
                case (_) {};
            };
            
            if (largest != parent){
                ArrayMut.swap(heap, parent, child);
                child := parent;
            } else break loop1;
        };
        
    };

    // Convert an arbitrary array into a heap
    public func heapify<A>(arr: [var ?A], cmp: CmpFn<A>, count: Nat) {
        var start = (count - 1 : Nat) / 2;

        start += 1;

        while (start > 0) {
            trickle_down(arr, cmp, start - 1 : Nat, count);
            start -= 1;
        };
    };

    public func put<A>(heap : MaxHeap<A>, cmp : CmpFn<A>, value : A, count : Nat) {
        heap[count] := ?value;
        trickle_up(heap, cmp, count, count + 1 : Nat);
    };

    public func peekMax<A>(heap : MaxHeap<A>) : ?A {
        heap[0];
    };

    public func removeMax<A>(heap : MaxHeap<A>, cmp : CmpFn<A>, count : Nat) : ?A {
        if (count == 0) return null;

        let max = heap[0];

        heap[0] := heap[count - 1];
        heap[count - 1] := null;

        if (count == 1) return max;

        trickle_down(heap, cmp, 0, count - 1 : Nat);
        max;
    };

    public func removeIf<A>(
        heap: MaxHeap<A>, 
        cmp: CmpFn<A>, 
        size: Nat, 
        pred: (val: A) -> Bool
    ) : Nat {
        let new_size = ArrayMut.removeIf(heap, size, func (val: A, i: Nat) : Bool = pred(val));
        heapify(heap, cmp, new_size);
        return new_size;
    };

    // remove the first value that returns true from the predicate
    // requires Utils.tuple_cmp()
    public func remove<A>(heap: MaxHeap<A>, cmp: CmpFn<A>, count: Nat, prev: A) : ?A {
        
        let is_equal = func(a: A, b: A) : Bool = cmp(a, b) == 0;

        let i = switch(ArrayMut.index_of(heap, count, is_equal, prev)){
            case (?i) i;
            case (_) return null;
        };

        let removed = heap[i];
        ArrayMut.swap(heap, i, count - 1 : Nat);
        heap[count - 1] := null;

        trickle_up(heap, cmp, i, count);
        trickle_down(heap, cmp, i, count);

        removed
    };

    // replaces the first value that returns true from the predicate with the given value
    // requires Utils.tuple_cmp()
    public func replace<A>(heap: MaxHeap<A>, cmp: CmpFn<A>, count: Nat, prev: A, new: A) {
        let is_equal = func(a: A, b: A) : Bool = cmp(a, b) == 0;

        let i = switch(ArrayMut.index_of(heap, count, is_equal, prev)){
            case (?i) i;
            case (_) return;
        };

        heap[i] := ?new;

        trickle_up(heap, cmp, i, count);
        trickle_down(heap, cmp, i, count); 
    };

};
