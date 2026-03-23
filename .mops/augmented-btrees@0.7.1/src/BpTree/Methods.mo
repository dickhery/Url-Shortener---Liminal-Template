import Prim "mo:prim";

import Option "mo:base/Option";
import Array "mo:base/Array";
import Debug "mo:base/Debug";
import Order "mo:base/Order";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Result "mo:base/Result";
import Buffer "mo:base/Buffer";
import BufferDeque "mo:buffer-deque/BufferDeque";

import ArrayMut "../internal/ArrayMut";
import Utils "../internal/Utils";
import T "Types";
import InternalTypes "../internal/Types";
import RevIter "mo:itertools/RevIter";

module Methods {

    let { Const = C } = T;
    type Iter<A> = Iter.Iter<A>;
    type Order = Order.Order;
    type CmpFn<A> = T.CmpFn<A>;
    type Result<A, B> = Result.Result<A, B>;
    type BufferDeque<A> = BufferDeque.BufferDeque<A>;
    public type RevIter<A> = RevIter.RevIter<A>;

    public type BpTree<K, V> = T.BpTree<K, V>;
    public type Node<K, V> = T.Node<K, V>;
    public type Leaf<K, V> = T.Leaf<K, V>;
    public type Branch<K, V> = T.Branch<K, V>;
    type CommonFields<K, V> = T.CommonFields<K, V>;
    type CommonNodeFields<K, V> = T.CommonNodeFields<K, V>;
    type MultiCmpFn<A, B> = InternalTypes.MultiCmpFn<A, B>;

    public func depth<K, V>(bptree : BpTree<K, V>) : Nat {
        var node = ?bptree.root;
        var depth = 0;

        label while_loop loop {
            switch (node) {
                case (?#branch(n)) {
                    node := n.3 [0];
                    depth += 1;
                };
                case (?#leaf(_)) {
                    return depth + 1;
                };
                case (_) Debug.trap("depth: accessed a null value");
            };
        };

        depth;
    };

    public func get_leaf_node<K, V>(self : BpTree<K, V>, cmp : CmpFn<K>, key : K) : Leaf<K, V> {
        var curr = ?self.root;

        loop {
            switch (curr) {
                case (?#branch(node)) {
                    let int_index = ArrayMut.binary_search<K, K>(node.2, cmp, key, node.0 [C.COUNT] - 1);
                    let node_index = if (int_index >= 0) Int.abs(int_index) + 1 else Int.abs(int_index + 1);
                    curr := node.3 [node_index];
                };
                case (?#leaf(leaf_node)) {
                    return leaf_node;
                };
                case (_) Debug.trap("get_leaf_node: accessed a null value");
            };
        };
    };

    public func update_branch_path_from_leaf_to_root<K, V>(self : BpTree<K, V>, leaf : Leaf<K, V>, update : (Branch<K, V>) -> ()) {
        var parent = leaf.1 [C.PARENT];

        loop {
            switch (parent) {
                case (?node) {
                    update(node);
                    parent := node.1 [C.PARENT];
                };

                case (_) return;
            };
        };
    };

    public func update_partial_branch_path_from_leaf_to_root<K, V>(self : BpTree<K, V>, leaf : Leaf<K, V>, update : (Branch<K, V>) -> (_continue : Bool)) {
        var parent = leaf.1 [C.PARENT];

        loop {
            switch (parent) {
                case (?node) {
                    if (not update(node)) return;
                    parent := node.1 [C.PARENT];
                };

                case (_) return;
            };
        };
    };

    public func get_leaf_node_and_update_branch_path<K, V>(self : BpTree<K, V>, cmp : CmpFn<K>, key : K, update : (parent : Branch<K, V>, child_index : Nat) -> ()) : Leaf<K, V> {
        var curr = ?self.root;

        loop {
            switch (curr) {
                case (?#branch(node)) {
                    let int_index = ArrayMut.binary_search<K, K>(node.2, cmp, key, node.0 [C.COUNT] - 1);
                    let node_index = if (int_index >= 0) Int.abs(int_index) + 1 else Int.abs(int_index + 1);
                    update(node, node_index);

                    curr := node.3 [node_index];
                };
                case (?#leaf(leaf_node)) {
                    return leaf_node;
                };
                case (_) Debug.trap("get_leaf_node: accessed a null value");
            };
        };
    };

    public func get_min_leaf_node<K, V>(self : BpTree<K, V>) : Leaf<K, V> {
        var node = ?self.root;

        loop {
            switch (node) {
                case (?#branch(branch)) {
                    node := branch.3 [0];
                };
                case (?#leaf(leaf_node)) {
                    return leaf_node;
                };
                case (_) Debug.trap("get_min_leaf_node: accessed a null value");
            };
        };
    };

    public func get_max_leaf_node<K, V>(self : BpTree<K, V>) : Leaf<K, V> {
        var node = ?self.root;

        loop {
            switch (node) {
                case (?#branch(branch)) {
                    node := branch.3 [branch.0 [C.COUNT] - 1];
                };
                case (?#leaf(leaf_node)) {
                    return leaf_node;
                };
                case (_) Debug.trap("get_max_leaf_node: accessed a null value");
            };
        };
    };

    public func gen_id<K, V>(bptree : BpTree<K, V>) : Nat {
        let id = bptree.next_id;
        bptree.next_id += 1;
        id;
    };

    public func inc_branch_subtree_size<K, V>(branch : Branch<K, V>) {
        branch.0 [C.SUBTREE_SIZE] += 1;
    };

    public func decrement_branch_subtree_size<K, V>(branch : Branch<K, V>) {
        branch.0 [C.SUBTREE_SIZE] -= 1;
    };

    public func subtree_size<K, V>(node : Node<K, V>) : Nat {
        switch (node) {
            case (#branch(node)) node.0 [C.SUBTREE_SIZE];
            case (#leaf(node)) node.0 [C.COUNT];
        };
    };

    public func new_iterator<K, V>(
        start_leaf : Leaf<K, V>,
        start_index : Nat,
        end_leaf : Leaf<K, V>,
        end_index : Nat // exclusive
    ) : RevIter<(K, V)> {

        var _start_leaf = ?start_leaf;
        var i = start_index;

        var _end_leaf = ?end_leaf;
        var j = end_index;

        func next() : ?(K, V) {
            let ?start = _start_leaf else return null;
            let ?end = _end_leaf else return null;

            if (start.0 [C.ID] == end.0 [C.ID] and i >= j) {
                _start_leaf := null;
                return null;
            };

            if (i >= start.0 [C.COUNT]) {
                _start_leaf := start.2 [C.NEXT];
                i := 0;
                return next();
            };

            let entry = start.3 [i];
            i += 1;
            return entry;
        };

        func nextFromEnd() : ?(K, V) {
            let ?start = _start_leaf else return null;
            let ?end = _end_leaf else return null;

            if (start.0 [C.ID] == end.0 [C.ID] and i >= j) {
                _end_leaf := null;
                return null;
            };

            if (j == 0) {
                _end_leaf := end.2 [C.PREV];
                switch (_end_leaf) {
                    case (?leaf) j := leaf.0 [C.COUNT];
                    case (_) { return null };
                };

                return nextFromEnd();
            };

            let entry = end.3 [j - 1];
            j -= 1;
            return entry;
        };

        RevIter.new(next, nextFromEnd);
    };

    // Returns the leaf node and rank of the first element in the leaf node
    public func get_leaf_node_and_index<K, V>(self : BpTree<K, V>, cmp : CmpFn<K>, key : K) : (Leaf<K, V>, Nat) {

        let root = switch (self.root) {
            case (#branch(node)) node;
            case (#leaf(node)) return (node, 0);
        };

        var rank = root.0 [C.SUBTREE_SIZE];

        func get_node(parent : Branch<K, V>, key : K) : Leaf<K, V> {
            var i = parent.0 [C.COUNT] - 1 : Nat;

            label get_node_loop while (i >= 1) {
                let child = parent.3 [i];

                let ?search_key = parent.2 [i - 1] else Debug.trap("get_leaf_node_and_index 1: accessed a null value");

                switch (child) {
                    case (?#branch(node)) {
                        if (cmp(key, search_key) != -1) {
                            return get_node(node, key);
                        };

                        rank -= node.0 [C.SUBTREE_SIZE];
                    };
                    case (?#leaf(node)) {
                        // subtract before comparison because we want the rank of the first element in the leaf node
                        rank -= node.0 [C.COUNT];

                        if (cmp(key, search_key) != -1) {
                            return node;
                        };
                    };
                    case (_) Debug.trap("get_leaf_node_and_index 2: accessed a null value");
                };

                i -= 1;
            };

            switch (parent.3 [0]) {
                case (?#branch(node)) {
                    return get_node(node, key);
                };
                case (?#leaf(node)) {
                    rank -= node.0 [C.COUNT];
                    return node;
                };
                case (_) Debug.trap("get_leaf_node_and_index 3: accessed a null value");
            };
        };

        (get_node(root, key), rank);
    };

    public func get_leaf_node_by_index<K, V>(self : BpTree<K, V>, rank : Nat) : (Leaf<K, V>, Nat) {
        let root = switch (self.root) {
            case (#branch(node)) node;
            case (#leaf(leaf)) return (leaf, rank);
        };

        var search_index = rank;

        func get_node(parent : Branch<K, V>) : Leaf<K, V> {
            var i = parent.0 [C.COUNT] - 1 : Nat;
            var curr = ?parent;
            var node_index = parent.0 [C.SUBTREE_SIZE];

            label get_node_loop loop {
                let child = parent.3 [i];

                switch (child) {
                    case (?#branch(node)) {
                        let subtree = node.0 [C.SUBTREE_SIZE];

                        node_index -= subtree;
                        if (node_index <= search_index) {
                            search_index -= node_index;
                            return get_node(node);
                        };

                    };
                    case (?#leaf(node)) {
                        let subtree = node.0 [C.COUNT];
                        node_index -= subtree;

                        if (node_index <= search_index) {
                            search_index -= node_index;
                            return node;
                        };

                    };
                    case (_) Debug.trap("get_leaf_node_by_index 1: accessed a null value");
                };

                // assert i > 0;

                i -= 1;
            };

            Debug.trap("get_leaf_node_by_index 3: reached unreachable code");
        };

        (get_node(root), search_index);
    };

    // // merges two leaf nodes into the left node
    // public func merge_leaf_nodes<K, V>(left : Leaf<K, V>, right : Leaf<K, V>) {
    //     let min_count = left.3.size() / 2;

    //     var i = 0;

    //     // merge right into left
    //     for (_ in Iter.range(0, right.0[C.COUNT] - 1)) {
    //         let val = right.3[i];
    //         ArrayMut.insert(left.3, left.0[C.COUNT] + i, val, left.0[C.COUNT]);

    //         i += 1;
    //     };

    //     left.0[C.COUNT] += right.0[C.COUNT];

    //     // update leaf pointers
    //     left.2[C.NEXT] := right.2[C.NEXT];
    //     switch (left.2[C.NEXT]) {
    //         case (?next) next.2[C.PREV] := ?left;
    //         case (_) {};
    //     };

    //     // update parent keys
    //     switch (left.1[C.PARENT]) {
    //         case (null) {};
    //         case (?parent) {
    //             ignore ArrayMut.remove(parent.2, right.index - 1 : Nat, parent.0[C.COUNT] - 1 : Nat);
    //             ignore Branch.remove(parent, right.index : Nat, parent.0[C.COUNT]);

    //             parent.0[C.COUNT] -= 1;
    //         };
    //     };

    // };

    public func get<K, V>(self : BpTree<K, V>, cmp : CmpFn<K>, key : K) : ?V {
        let leaf_node = get_leaf_node<K, V>(self, cmp, key);

        let i = ArrayMut.binary_search<K, (K, V)>(leaf_node.3, Utils.adapt_cmp(cmp), key, leaf_node.0 [C.COUNT]);

        if (i >= 0) {
            let ?kv = leaf_node.3 [Int.abs(i)] else Debug.trap("1. get: accessed a null value");
            return ?kv.1;
        };

        null;
    };

    public func get_entry<K, V>(self : BpTree<K, V>, cmp : CmpFn<K>, key : K) : ?(K, V) {
        let leaf_node = get_leaf_node<K, V>(self, cmp, key);

        let i = ArrayMut.binary_search<K, (K, V)>(leaf_node.3, Utils.adapt_cmp(cmp), key, leaf_node.0 [C.COUNT]);

        if (i >= 0) {
            return leaf_node.3 [Int.abs(i)];
        };

        null;
    };

    public func get_ceiling<K, V>(self : BpTree<K, V>, cmp : CmpFn<K>, key : K) : ?(K, V) {
        let leaf_node = get_leaf_node<K, V>(self, cmp, key);

        let i = ArrayMut.binary_search<K, (K, V)>(leaf_node.3, Utils.adapt_cmp(cmp), key, leaf_node.0 [C.COUNT]);

        if (i >= 0) {
            return leaf_node.3 [Int.abs(i)];
        };

        let expected_index = Int.abs(i) - 1 : Nat;

        if (expected_index == leaf_node.0 [C.COUNT]) {
            let ?next_node = leaf_node.2 [C.NEXT] else return null;
            return next_node.3 [0];
        };

        return leaf_node.3 [expected_index];
    };

    public func get_floor<K, V>(self : BpTree<K, V>, cmp : CmpFn<K>, key : K) : ?(K, V) {
        let leaf_node = get_leaf_node<K, V>(self, cmp, key);

        let i = ArrayMut.binary_search<K, (K, V)>(leaf_node.3, Utils.adapt_cmp(cmp), key, leaf_node.0 [C.COUNT]);

        if (i >= 0) return leaf_node.3 [Int.abs(i)];

        let expected_index = Int.abs(i) - 1 : Nat;

        if (expected_index == 0) {
            let ?prev_node = leaf_node.2 [C.PREV] else return null;
            return prev_node.3 [prev_node.0 [C.COUNT] - 1];
        };

        return leaf_node.3 [expected_index - 1];
    };

    public func to_array<K, V>(self : BpTree<K, V>) : [(K, V)] {
        var node = ?self.root;
        let buffer = Buffer.Buffer<(K, V)>(self.size);

        var leaf_node : ?Leaf<K, V> = ?get_min_leaf_node(self);

        label _loop loop {
            switch (leaf_node) {
                case (?leaf) {
                    label _for_loop for (opt in leaf.3.vals()) {
                        let ?kv = opt else break _for_loop;
                        buffer.add(kv);
                    };

                    leaf_node := leaf.2 [C.NEXT];
                };
                case (_) break _loop;
            };
        };

        Buffer.toArray(buffer);
    };

    public func min<K, V>(self : BpTree<K, V>) : ?(K, V) {
        let leaf_node = get_min_leaf_node(self) else return null;
        leaf_node.3 [0];
    };

    // Returns the maximum key-value pair in the tree.
    public func max<K, V>(self : BpTree<K, V>) : ?(K, V) {
        let leaf_node = get_max_leaf_node(self) else return null;
        leaf_node.3 [leaf_node.0 [C.COUNT] - 1];
    };

    // Returns a reversible iterator over the entries of the tree.
    public func entries<K, V>(bptree : BpTree<K, V>) : RevIter<(K, V)> {
        let min_leaf = get_min_leaf_node(bptree);
        let max_leaf = get_max_leaf_node(bptree);
        new_iterator(min_leaf, 0, max_leaf, max_leaf.0 [C.COUNT]);
    };

    // Returns a reversible iterator over the keys of the tree.
    public func keys<K, V>(self : BpTree<K, V>) : RevIter<K> {
        RevIter.map(
            entries(self),
            func(kv : (K, V)) : K {
                kv.0;
            },
        );
    };

    // Returns a reversible iterator over the values of the tree.
    public func vals<K, V>(self : BpTree<K, V>) : RevIter<V> {
        RevIter.map(
            entries(self),
            func(kv : (K, V)) : V {
                kv.1;
            },
        );
    };

    // Returns the rank of the given key in the tree.
    public func get_index<K, V>(self : BpTree<K, V>, cmp : CmpFn<K>, key : K) : Nat {
        let (leaf_node, rank) = get_leaf_node_and_index(self, cmp, key);
        let i = ArrayMut.binary_search<K, (K, V)>(leaf_node.3, Utils.adapt_cmp(cmp), key, leaf_node.0 [C.COUNT]);

        if (i < 0) {
            return rank + (Int.abs(i) - 1 : Nat);
        };

        rank + Int.abs(i);
    };

    public func get_expected_index<K, V>(self : BpTree<K, V>, cmp : CmpFn<K>, key : K) : T.ExpectedIndex {
        let (leaf_node, rank) = get_leaf_node_and_index(self, cmp, key);
        let i = ArrayMut.binary_search<K, (K, V)>(leaf_node.3, Utils.adapt_cmp(cmp), key, leaf_node.0 [C.COUNT]);

        if (i < 0) {
            #NotFound(rank + (Int.abs(i) - 1 : Nat));
        } else {
            #Found(rank + Int.abs(i));
        };

    };

    // Returns the key-value pair at the given rank.
    // Returns null if the rank is greater than the size of the tree.
    public func get_from_index<K, V>(self : BpTree<K, V>, rank : Nat) : (K, V) {
        if (rank >= self.size) return Debug.trap("getFromIndex: rank is greater than the size of the tree");
        let (leaf_node, i) = get_leaf_node_by_index(self, rank);

        // assert i < leaf_node.0[C.COUNT];

        let ?entry = leaf_node.3 [i] else Debug.trap("getFromIndex: accessed a null value");
        entry;
    };

    // Returns an iterator over the entries of the tree in the range [start, end).
    // The range is defined by the ranks of the start and end keys
    public func range<K, V>(self : BpTree<K, V>, start : Nat, end : Nat) : RevIter<(K, V)> {
        let (start_node, start_node_index) = get_leaf_node_by_index(self, start);
        let (end_node, end_node_index) = get_leaf_node_by_index(self, end);

        let start_index = start_node_index : Nat;
        let end_index = end_node_index : Nat;

        new_iterator(start_node, start_index, end_node, end_index);
    };

    // Returns an iterator over the entries of the tree in the range [start, end].
    // The iterator is inclusive of start and end.
    //
    // If the start key does not exist in the tree then the iterator will start from next key greater than start.
    // If the end key does not exist in the tree then the iterator will end at the last key less than end.
    public func scan<K, V>(self : BpTree<K, V>, cmp : CmpFn<K>, start : ?K, end : ?K) : RevIter<(K, V)> {
        let left_node = switch (start) {
            case (?key) get_leaf_node(self, cmp, key);
            case (null) get_min_leaf_node(self);
        };

        let start_index = switch (start) {
            case (?key) ArrayMut.binary_search<K, (K, V)>(left_node.3, Utils.adapt_cmp(cmp), key, left_node.0 [C.COUNT]);
            case (null) 0;
        };

        // if start_index is negative then the element was not found
        // moreover if start_index is negative then abs(i) - 1 is the index of the first element greater than start
        var i = if (start_index >= 0) Int.abs(start_index) else Int.abs(start_index) - 1 : Nat;

        let right_node = switch (end) {
            case (?key) get_leaf_node(self, cmp, key);
            case (null) get_max_leaf_node(self);
        };

        let end_index = switch (end) {
            case (?key) ArrayMut.binary_search<K, (K, V)>(right_node.3, Utils.adapt_cmp(cmp), key, right_node.0 [C.COUNT]);
            case (null) right_node.0 [C.COUNT];
        };

        var j = if (end_index >= 0) Int.abs(end_index) + 1 else Int.abs(end_index) - 1 : Nat;

        new_iterator(left_node, i, right_node, j);
    };

};
