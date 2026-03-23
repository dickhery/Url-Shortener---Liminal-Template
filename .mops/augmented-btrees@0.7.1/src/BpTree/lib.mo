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

import LeafModule "Leaf";
import BranchModule "Branch";

import ArrayMut "../internal/ArrayMut";
import Utils "../internal/Utils";
import T "Types";
import Methods "Methods";
import InternalTypes "../internal/Types";
import RevIter "mo:itertools/RevIter";

module BpTree {
    type Iter<A> = Iter.Iter<A>;
    type Order = Order.Order;
    type CmpFn<A> = T.CmpFn<A>;
    type Result<A, B> = Result.Result<A, B>;
    type BufferDeque<A> = BufferDeque.BufferDeque<A>;
    public type RevIter<A> = RevIter.RevIter<A>;

    public let Leaf = LeafModule;
    public let Branch = BranchModule;

    public type BpTree<K, V> = T.BpTree<K, V>;
    public type Node<K, V> = T.Node<K, V>;
    public type Leaf<K, V> = T.Leaf<K, V>;
    public type Branch<K, V> = T.Branch<K, V>;
    type CommonFields<K, V> = T.CommonFields<K, V>;
    type CommonNodeFields<K, V> = T.CommonNodeFields<K, V>;
    type MultiCmpFn<A, B> = InternalTypes.MultiCmpFn<A, B>;

    let { Const = C } = T;
    // public func new2<K, V>(): T.BpTreeV2<K, V> {
    //     new<K, V>();
    // };

    let ALLOWED_ORDERS : [Nat] = [4, 8, 16, 32, 64, 128, 256, 512];

    /// Create a new B+ tree with the given order.
    /// The order is the maximum number of children a node can have.
    /// The order must be one of 4, 8, 16, 32, 64, 128, 256 and 512.
    ///
    /// #### Examples
    /// ```motoko
    /// let bptree = BpTree.new<Char, Nat>(?32);
    /// ```
    public func new<K, V>(_order : ?Nat) : BpTree<K, V> {
        let order = Option.get(_order, 32);

        assert Option.isSome(
            Array.find(ALLOWED_ORDERS, func(n : Nat) : Bool = n == order)
        );

        {
            order;
            var root = #leaf(Leaf.new<K, V>(order, 0, null, func() : Nat = 0));
            var size = 0;
            var next_id = 1;
        };
    };

    /// Create a new B+ tree from the given entries.
    ///
    /// #### Inputs
    /// - `order` - the maximum number of children a node can have.
    /// - `entries` - an iterator over the entries to insert into the tree.
    /// - `cmp` - the comparison function to use for ordering the keys.
    ///
    /// #### Examples
    /// ```motoko
    ///     let entries = [('A', 1), ('B', 2), ('C', 3)].vals();
    ///     let bptree = BpTree.fromEntries<Char, Nat>(entries, Cmp.Char, null);
    /// ```

    public func fromEntries<K, V>(entries : Iter<(K, V)>, cmp : CmpFn<K>, order : ?Nat) : BpTree<K, V> {
        let bptree = BpTree.new<K, V>(order);

        for ((k, v) in entries) {
            ignore insert<K, V>(bptree, cmp, k, v);
        };

        bptree;
    };

    /// Create a new B+ tree from the given array of key-value pairs.
    ///
    /// #### Inputs
    /// - `order` - the maximum number of children a node can have.
    /// - `arr` - the array of key-value pairs to insert into the tree.
    /// - `cmp` - the comparison function to use for ordering the keys.
    ///
    /// #### Examples
    /// ```motoko
    ///    let arr = [('A', 1), ('B', 2), ('C', 3)];
    ///    let bptree = BpTree.fromArray<Char, Nat>(arr, Cmp.Char, null);
    /// ```
    public func fromArray<K, V>(arr : [(K, V)], cmp : CmpFn<K>, order : ?Nat) : BpTree<K, V> {
        fromEntries(arr.vals(), cmp, order);
    };

    /// Returns a sorted array of the key-value pairs in the tree.
    ///
    /// #### Examples
    /// ```motoko
    ///     let arr = [('A', 1), ('B', 2), ('C', 3)];
    ///     let bptree = BpTree.fromArray<Char, Nat>(arr, Cmp.Char, null);
    ///     assert BpTree.toArray(bptree) == arr;
    /// ```
    public func toArray<K, V>(self : BpTree<K, V>) : [(K, V)] {
        Methods.to_array(self);
    };

    /// Returns the size of the B+ tree.
    ///
    /// #### Examples
    /// ```motoko
    ///     let arr = [('A', 1), ('B', 2), ('C', 3)];
    ///     let bptree = BpTree.fromArray<Char, Nat>(arr, Cmp.Char, null);
    ///
    ///     assert BpTree.size(bptree) == 3;
    /// ```
    public func size<K, V>(self : BpTree<K, V>) : Nat {
        self.size;
    };

    /// Returns the value associated with the given key.
    /// If the key is not in the tree, it returns null.
    ///
    /// #### Examples
    /// ```motoko
    ///     let arr = [('A', 1), ('B', 2), ('C', 3)];
    ///     let bptree = BpTree.fromArray<Char, Nat>(arr, Cmp.Char, null);
    ///
    ///     assert BpTree.get(bptree, Cmp.Char, 'A') == 1;
    ///     assert BpTree.get(bptree, Cmp.Char, 'D') == null;
    /// ```
    public func get<K, V>(self : BpTree<K, V>, cmp : CmpFn<K>, key : K) : ?V {
        Methods.get(self, cmp, key);
    };

    public func getEntry<K, V>(self : BpTree<K, V>, cmp : CmpFn<K>, key : K) : ?(K, V) {
        Methods.get_entry(self, cmp, key);
    };

    /// Checks if the given key exists in the tree.
    public func has<K, V>(self : BpTree<K, V>, cmp : CmpFn<K>, key : K) : Bool {
        Option.isSome(get(self, cmp, key));
    };

    /// Returns the largest element in the B+Tree that is less than or equal to a given key.
    public func getFloor<K, V>(self : BpTree<K, V>, cmp : CmpFn<K>, key : K) : ?(K, V) {
        Methods.get_floor(self, cmp, key);
    };

    /// Returns the smallest element in the B+Tree that is greater than or equal to a given key.
    public func getCeiling<K, V>(self : BpTree<K, V>, cmp : CmpFn<K>, key : K) : ?(K, V) {
        Methods.get_ceiling(self, cmp, key);
    };

    public func toText<K, V>(self : BpTree<K, V>, key_to_text : (K) -> Text, val_to_text : (V) -> Text) : Text {
        var t = "BpTree { order: " # debug_show self.order # ", size: " # debug_show self.size # ", root: ";

        t #= switch (self.root) {
            case (#leaf(node)) "leaf { " # Leaf.toText<K, V>(node, key_to_text, val_to_text) # " }";
            case (#branch(node)) "branch {" # Branch.toText<K, V>(node, key_to_text, val_to_text) # "}";
        };

        t #= "}";

        t;
    };

    /// Inserts the given key-value pair into the tree.
    /// If the key already exists in the tree, it replaces the value and returns the old value.
    /// Otherwise, it returns null.
    ///
    /// #### Examples
    /// ```motoko
    ///     let bptree = BpTree.new<Text, Nat>(?32);
    ///
    ///     assert BpTree.insert(bptree, Cmp.Text, "id", 1) == null;
    ///     assert BpTree.insert(bptree, Cmp.Text, "id", 2) == ?1;
    /// ```
    public func insert<K, V>(self : BpTree<K, V>, cmp : CmpFn<K>, key : K, val : V) : ?V {
        func inc_branch_subtree_size(branch : Branch<K, V>, index : Nat) {
            branch.0 [C.SUBTREE_SIZE] += 1;
        };

        func decrement_branch_subtree_size(branch : Branch<K, V>) {
            branch.0 [C.SUBTREE_SIZE] -= 1;
        };

        func gen_id() : Nat = Methods.gen_id(self);

        let leaf_node = Methods.get_leaf_node_and_update_branch_path(self, cmp, key, inc_branch_subtree_size);
        let entry = (key, val);

        let int_elem_index = ArrayMut.binary_search<K, (K, V)>(leaf_node.3, Utils.adapt_cmp(cmp), key, leaf_node.0 [C.COUNT]);
        let elem_index = if (int_elem_index >= 0) Int.abs(int_elem_index) else Int.abs(int_elem_index + 1);

        let prev_value = if (int_elem_index >= 0) {
            let ?kv = leaf_node.3 [elem_index] else Debug.trap("1. insert: accessed a null value while replacing a key-value pair");
            leaf_node.3 [elem_index] := ?entry;

            // undoes the update to subtree count for the nodes on the path to the root when replacing a key-value pair
            Methods.update_branch_path_from_leaf_to_root(self, leaf_node, decrement_branch_subtree_size);

            return ?kv.1;
        } else {
            null;
        };

        if (leaf_node.0 [C.COUNT] < self.order) {
            // shift elems to the right and insert the new key-value pair
            var j = leaf_node.0 [C.COUNT];

            while (j > elem_index) {
                leaf_node.3 [j] := leaf_node.3 [j - 1];
                j -= 1;
            };

            leaf_node.3 [elem_index] := ?entry;
            leaf_node.0 [C.COUNT] += 1;

            self.size += 1;
            return prev_value;
        };

        // split leaf node
        let right_leaf_node = Leaf.split(leaf_node, elem_index, entry, gen_id);

        var opt_parent : ?Branch<K, V> = leaf_node.1 [C.PARENT];
        var left_node : Node<K, V> = #leaf(leaf_node);
        var left_index = leaf_node.0 [C.INDEX];

        var right_index = right_leaf_node.0 [C.INDEX];
        let ?right_leaf_first_entry = right_leaf_node.3 [0] else Debug.trap("2. insert: accessed a null value");
        var right_key = right_leaf_first_entry.0;
        var right_node : Node<K, V> = #leaf(right_leaf_node);

        // insert split leaf nodes into parent nodes if there is space
        // or iteratively split parent (internal) nodes to make space
        while (Option.isSome(opt_parent)) {
            let ?parent = opt_parent else Debug.trap("3. insert: accessed a null parent value");

            if (parent.0 [C.COUNT] < self.order) {
                var j = parent.0 [C.COUNT];

                while (j >= right_index) {
                    if (j == right_index) {
                        parent.2 [j - 1] := ?right_key;
                        parent.3 [j] := ?right_node;
                    } else {
                        parent.2 [j - 1] := parent.2 [j - 2];
                        parent.3 [j] := parent.3 [j - 1];
                    };

                    switch (parent.3 [j]) {
                        case ((?#branch(node) or ?#leaf(node)) : ?CommonNodeFields<K, V>) {
                            node.0 [C.INDEX] := j;
                        };
                        case (_) {};
                    };

                    j -= 1;
                };

                parent.0 [C.COUNT] += 1;

                self.size += 1;
                return prev_value;

            } else {

                let split_node = Branch.split(parent, right_node, right_index, right_key, gen_id);

                let ?first_key = ArrayMut.extract(split_node.2, split_node.2.size() - 1 : Nat) else Debug.trap("4. insert: accessed a null value in first key of branch");
                right_key := first_key;

                left_node := #branch(parent);
                right_node := #branch(split_node);

                right_index := split_node.0 [C.INDEX];
                opt_parent := split_node.1 [C.PARENT];
            };
        };

        let root_node = Branch.new<K, V>(self.order, null, null, gen_id);
        root_node.2 [0] := ?right_key;

        Branch.add_child(root_node, left_node);
        Branch.add_child(root_node, right_node);

        self.root := #branch(root_node);
        self.size += 1;

        prev_value;
    };

    /// Removes the key-value pair from the tree.
    /// If the key is not in the tree, it returns null.
    /// Otherwise, it returns the value associated with the key.
    ///
    /// #### Examples
    /// ```motoko
    ///     let arr = [('A', 1), ('B', 2), ('C', 3)];
    ///     let bptree = BpTree.fromArray<Char, Nat>(arr, Cmp.Char, null);
    ///
    ///     assert BpTree.remove(bptree, Cmp.Char, 'A') == ?1;
    ///     assert BpTree.remove(bptree, Cmp.Char, 'D') == null;
    /// ```
    public func remove<K, V>(self : BpTree<K, V>, cmp : CmpFn<K>, key : K) : ?V {
        func inc_branch_subtree_size(branch : Branch<K, V>) {
            branch.0 [C.SUBTREE_SIZE] += 1;
        };

        func decrement_branch_subtree_size(branch : Branch<K, V>, index : Nat) {
            branch.0 [C.SUBTREE_SIZE] -= 1;
        };

        let leaf_node = Methods.get_leaf_node_and_update_branch_path(self, cmp, key, decrement_branch_subtree_size);

        let int_elem_index = ArrayMut.binary_search<K, (K, V)>(leaf_node.3, Utils.adapt_cmp(cmp), key, leaf_node.0 [C.COUNT]);
        let elem_index = if (int_elem_index >= 0) Int.abs(int_elem_index) else {
            Methods.update_branch_path_from_leaf_to_root(self, leaf_node, inc_branch_subtree_size);
            return null;
        };
        // remove parent key as well
        let ?entry : ?(K, V) = ArrayMut.remove(leaf_node.3, elem_index, leaf_node.0 [C.COUNT]) else Debug.trap("1. remove: accessed a null value");

        let deleted = entry.1;
        self.size -= 1;
        leaf_node.0 [C.COUNT] -= 1;

        let min_count = self.order / 2;

        let ?_parent = leaf_node.1 [C.PARENT] else return ?deleted; // if parent is null then leaf_node is the root
        var parent = _parent;

        func update_deleted_median_key(_parent : Branch<K, V>, index : Nat, deleted_key : K, next_key : K) {
            var parent = _parent;
            var i = index;

            while (i == 0) {
                i := parent.0 [C.INDEX];
                let ?__parent = parent.1 [C.PARENT] else return; // occurs when key is the first key in the tree
                parent := __parent;
            };

            parent.2 [i - 1] := ?next_key;
        };

        if (elem_index == 0) {
            let next = leaf_node.3 [elem_index]; // same as entry index because we removed the entry from the array
            let ?next_key = do ? { next!.0 } else Debug.trap("update_deleted_median_key: accessed a null value");
            update_deleted_median_key(parent, leaf_node.0 [C.INDEX], key, next_key);
        };

        if (leaf_node.0 [C.COUNT] >= min_count) return ?deleted;

        Leaf.redistribute_keys(leaf_node);

        if (leaf_node.0 [C.COUNT] >= min_count) return ?deleted;

        // the parent will always have (self.order / 2) children
        let opt_adj_node = if (leaf_node.0 [C.INDEX] == 0) {
            parent.3 [1];
        } else {
            parent.3 [leaf_node.0 [C.INDEX] - 1];
        };

        let ?#leaf(adj_node) = opt_adj_node else return ?deleted;

        let left_node = if (adj_node.0 [C.INDEX] < leaf_node.0 [C.INDEX]) adj_node else leaf_node;
        let right_node = if (adj_node.0 [C.INDEX] < leaf_node.0 [C.INDEX]) leaf_node else adj_node;

        Leaf.merge(left_node, right_node);

        var branch_node = parent;
        let ?__parent = branch_node.1 [C.PARENT] else {

            // update root node as this node does not have a parent
            // which means it is the root node
            if (branch_node.0 [C.COUNT] == 1) {
                let ?child = branch_node.3 [0] else Debug.trap("3. remove: accessed a null value");
                switch (child) {
                    case (#branch(node) or #leaf(node) : CommonNodeFields<K, V>) {
                        node.1 [C.PARENT] := null;
                    };
                };
                self.root := child;
            };

            return ?deleted;
        };

        parent := __parent;

        while (branch_node.0 [C.COUNT] < min_count) {
            Branch.redistribute_keys(branch_node);

            if (branch_node.0 [C.COUNT] >= min_count) return ?deleted;

            let ?#branch(adj_branch_node) = if (branch_node.0 [C.INDEX] == 0) {
                parent.3 [1];
            } else {
                parent.3 [branch_node.0 [C.INDEX] - 1];
            } else {
                // if the adjacent node is null then the branch node is the only child of the parent
                // this only happens if the branch node is the root node

                // update root node if necessary
                // assert parent.0[C.COUNT] == 1;
                let ?child = parent.3 [0] else Debug.trap("3. remove: accessed a null value");
                self.root := child;

                return ?deleted;
            };

            let left_node = if (adj_branch_node.0 [C.INDEX] < branch_node.0 [C.INDEX]) adj_branch_node else branch_node;
            let right_node = if (adj_branch_node.0 [C.INDEX] < branch_node.0 [C.INDEX]) branch_node else adj_branch_node;

            Branch.merge(left_node, right_node);

            branch_node := parent;
            let ?_parent = branch_node.1 [C.PARENT] else {
                // update root node if necessary
                if (branch_node.0 [C.COUNT] == 1) {
                    let ?child = branch_node.3 [0] else Debug.trap("3. remove: accessed a null value");
                    switch (child) {
                        case (#branch(node) or #leaf(node) : CommonNodeFields<K, V>) {
                            node.1 [C.PARENT] := null;
                        };
                    };
                    self.root := child;
                };

                return ?deleted;
            };

            parent := _parent;
        };

        ?deleted;
    };

    /// Returns the minimum key-value pair in the tree.
    /// If the tree is empty, it returns null.
    ///
    /// #### Examples
    /// ```motoko
    ///     let arr = [('A', 1), ('B', 2), ('C', 3)];
    ///     let bptree = BpTree.fromArray<Char, Nat>(arr, Cmp.Char, null);
    ///
    ///     assert BpTree.min(bptree) == ?('A', 1);
    /// ```
    public func min<K, V>(self : BpTree<K, V>) : ?(K, V) {
        Methods.min(self);
    };

    /// Returns the maximum key-value pair in the tree.
    /// If the tree is empty, it returns null.
    ///
    /// #### Examples
    /// ```motoko
    ///     let arr = [('A', 1), ('B', 2), ('C', 3)];
    ///     let bptree = BpTree.fromArray<Char, Nat>(arr, Cmp.Char, null);
    ///
    ///     assert BpTree.max(bptree) == ?('C', 3);
    /// ```
    public func max<K, V>(self : BpTree<K, V>) : ?(K, V) {
        Methods.max(self);
    };

    /// Removes the minimum key-value pair in the tree and returns it.
    /// If the tree is empty, it returns null.
    ///
    /// #### Examples
    /// ```motoko
    ///     let arr = [('A', 1), ('B', 2), ('C', 3)];
    ///     let bptree = BpTree.fromArray<Char, Nat>(arr, Cmp.Char, null);
    ///
    ///     assert BpTree.removeMin(bptree, Cmp.Char) == ?('A', 1);
    /// ```
    public func removeMin<K, V>(self : BpTree<K, V>, cmp : CmpFn<K>) : ?(K, V) {
        let ?min = Methods.min(self) else return null;

        let ?v = remove(self, cmp, min.0) else return null;

        return ?min;
    };

    /// Removes the maximum key-value pair in the tree and returns it.
    /// If the tree is empty, it returns null.
    ///
    /// #### Examples
    /// ```motoko
    ///     let arr = [('A', 1), ('B', 2), ('C', 3)];
    ///     let bptree = BpTree.fromArray<Char, Nat>(arr, Cmp.Char, null);
    ///
    ///     assert BpTree.removeMax(bptree, Cmp.Char) == ?('C', 3);
    /// ```
    public func removeMax<K, V>(self : BpTree<K, V>, cmp : CmpFn<K>) : ?(K, V) {
        let ?max = Methods.max(self) else return null;

        let ?v = remove(self, cmp, max.0) else return null;

        return ?max;
    };

    /// Returns a reversible iterator over the entries of the tree.
    public func entries<K, V>(bptree : BpTree<K, V>) : RevIter<(K, V)> {
        Methods.entries(bptree);
    };

    /// Returns a reversible iterator over the keys of the tree.
    public func keys<K, V>(self : BpTree<K, V>) : RevIter<K> {
        Methods.keys(self);
    };

    /// Returns a reversible iterator over the values of the tree.
    public func vals<K, V>(self : BpTree<K, V>) : RevIter<V> {
        Methods.vals(self);
    };

    /// Returns the index of the given key in the tree.
    ///
    /// If the key does not exist in the tree, the function
    /// returns the index as if the key was inserted into the tree.
    ///
    /// #### Examples
    /// ```motoko
    ///     let arr = [('A', 1), ('B', 2), ('C', 3)];
    ///     let bptree = BpTree.fromArray<Char, Nat>(arr, Cmp.Char, null);
    ///
    ///     assert BpTree.getIndex(bptree, Cmp.Char, 'B') == 1;
    ///     assert BpTree.getIndex(bptree, Cmp.Char, 'D') == 3;
    /// ```
    public func getIndex<K, V>(self : BpTree<K, V>, cmp : CmpFn<K>, key : K) : Nat {
        Methods.get_index(self, cmp, key);
    };

    /// Get the index (sorted position) of the given key in the btree
    /// Returns a `ExpectedIndex` variant that returns `#Found(index)` if the key exists or `#NotFound(index)` if it does not.
    public func getExpectedIndex<K, V>(self : BpTree<K, V>, cmp : CmpFn<K>, key : K) : T.ExpectedIndex {
        Methods.get_expected_index(self, cmp, key);
    };

    /// Returns the key-value pair at the given index.
    /// Returns null if the index is greater than the size of the tree.
    ///
    /// #### Examples
    /// ```motoko
    ///     let arr = [('A', 1), ('B', 2), ('C', 3)];
    ///     let bptree = BpTree.fromArray<Char, Nat>(arr, Cmp.Char, null);
    ///
    ///     assert BpTree.getFromIndex(bptree, 0) == ('A', 1);
    ///     assert BpTree.getFromIndex(bptree, 1) == ('B', 2);
    /// ```
    public func getFromIndex<K, V>(self : BpTree<K, V>, i : Nat) : (K, V) {
        Methods.get_from_index(self, i);
    };

    /// Returns an iterator over the entries of the tree in the range [start, end).
    /// The iterator is inclusive of start and exclusive of end.
    public func range<K, V>(self : BpTree<K, V>, start : Nat, end : Nat) : RevIter<(K, V)> {
        Methods.range(self, start, end);
    };

    public func rangeKeys<K, V>(self : BpTree<K, V>, start : Nat, end : Nat) : RevIter<K> {
        RevIter.map<(K, V), K>(range(self, start, end), func(kv : (K, V)) : K = kv.0);
    };

    public func rangeVals<K, V>(self : BpTree<K, V>, start : Nat, end : Nat) : RevIter<V> {
        RevIter.map<(K, V), V>(range(self, start, end), func(kv : (K, V)) : V = kv.1);
    };

    /// Returns an iterator over the entries of the tree in the range [start, end].
    /// The iterator is inclusive of start and end.
    ///
    /// If the start key does not exist in the tree then the iterator will start from the next key greater than start.
    /// If the end key does not exist in the tree then the iterator will end at the last key less than end.
    ///
    /// If either start or end is null then the iterator will start from the first key or end at the last key respectively.
    ///
    public func scan<K, V>(self : BpTree<K, V>, cmp : CmpFn<K>, start : ?K, end : ?K) : RevIter<(K, V)> {
        Methods.scan(self, cmp, start, end);
    };

    public func clear<K, V>(self : BpTree<K, V>) {

        let leaf = switch (self.root) {
            case (#leaf(leaf)) leaf;
            case (#branch(branch)) Methods.get_min_leaf_node(self);
        };

        var cnt = leaf.0 [C.COUNT];

        leaf.0 [C.ID] := 0;
        leaf.0 [C.INDEX] := 0;
        leaf.0 [C.COUNT] := 0;

        leaf.1 [C.PARENT] := null;

        leaf.2 [C.PREV] := null;
        leaf.2 [C.NEXT] := null;

        while (cnt > 0) {
            leaf.3 [cnt - 1] := null;
            cnt -= 1;
        };

        self.root := #leaf(leaf);
        self.size := 0;

        self.next_id := 1;
    };

    public func toLeafNodes<K, V>(self : BpTree<K, V>) : [[?(K, V)]] {
        var node = ?self.root;
        let buffer = Buffer.Buffer<[?(K, V)]>(self.size);

        var leaf_node : ?Leaf<K, V> = ?Methods.get_min_leaf_node(self);

        label _loop loop {
            switch (leaf_node) {
                case (?leaf) {
                    buffer.add(Array.freeze<?(K, V)>(leaf.3));
                    leaf_node := leaf.2 [C.NEXT];
                };
                case (_) break _loop;
            };
        };

        Buffer.toArray(buffer);
    };

    public func toNodeKeys<K, V>(self : BpTree<K, V>) : [[(Nat, [?K])]] {
        var nodes = BufferDeque.fromArray<?Node<K, V>>([?self.root]);
        let buffer = Buffer.Buffer<[(Nat, [?K])]>(self.size / 2);

        while (nodes.size() > 0) {
            let row = Buffer.Buffer<(Nat, [?K])>(nodes.size());

            for (_ in Iter.range(1, nodes.size())) {
                let ?node = nodes.popFront() else Debug.trap("toNodeKeys: accessed a null value");

                switch (node) {
                    case (?#branch(node)) {
                        let node_buffer = Buffer.Buffer<?K>(node.2.size());
                        for (key in node.2.vals()) {
                            node_buffer.add(key);
                        };

                        for (child in node.3.vals()) {
                            nodes.addBack(child);
                        };

                        row.add((node.0 [C.INDEX], Buffer.toArray(node_buffer)));
                    };
                    case (_) {};
                };
            };

            buffer.add(Buffer.toArray(row));
        };

        Buffer.toArray(buffer);
    };

};
