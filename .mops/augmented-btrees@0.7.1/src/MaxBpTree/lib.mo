import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Debug "mo:base/Debug";
import Order "mo:base/Order";
import Option "mo:base/Option";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";

import BufferDeque "mo:buffer-deque/BufferDeque";
import T "Types";
import InternalTypes "../internal/Types";
import Methods "Methods";
import BpTree "../BpTree";
import ArrayMut "../internal/ArrayMut";

import Leaf "Leaf";
import Branch "Branch";
import RevIter "mo:itertools/RevIter";
import Common "Common";
import Utils "../internal/Utils";

module MaxBpTree {

    public type MaxBpTree<K, V> = T.MaxBpTree<K, V>;
    public type Node<K, V> = T.Node<K, V>;
    public type BufferDeque<T> = BufferDeque.BufferDeque<T>;
    public type Leaf<K, V> = T.Leaf<K, V>;
    public type Branch<K, V> = T.Branch<K, V>;
    public type CommonFields<K, V> = T.CommonFields<K, V>;
    public type CommonNodeFields<K, V> = T.CommonNodeFields<K, V>;
    type MultiCmpFn<A, B> = T.MultiCmpFn<A, B>;
    type CmpFn<A> = T.CmpFn<A>;
    type LeafEntry<K, V> = T.LeafEntry<K, V>;

    type Iter<A> = Iter.Iter<A>;
    type Order = Order.Order;
    public type RevIter<A> = RevIter.RevIter<A>;

    let { Const = C } = T;

    let ALLOWED_ORDERS : [Nat] = [4, 8, 16, 32, 64, 128, 256, 512];

    /// Create a new Max B+ tree with the given order.
    /// The order is the maximum number of children a node can have.
    /// The order must be one of 4, 8, 16, 32, 64, 128, 256 and 512.
    ///
    /// #### Examples
    /// ```motoko
    /// let bptree = MaxBpTree.new<Char, Nat>(?32);
    /// ```
    public func new<K, V>(_order : ?Nat) : MaxBpTree<K, V> {
        let order = Option.get(_order, 32);

        assert Option.isSome(
            Array.find(ALLOWED_ORDERS, func(n : Nat) : Bool = n == order)
        );

        let leaf_node = Leaf.new<K, V>(order, 0, null, func() : Nat = 0, func(_ : V, _ : V) : Int8 = 0);

        {
            order;
            var root = #leaf(leaf_node);
            var size = 0;
            var next_id = 1;
        };
    };

    /// Returns the value associated with the given key.
    /// If the key is not in the tree, it returns null.
    ///
    /// #### Examples
    /// ```motoko
    ///     let arr = [('A', 1), ('B', 2), ('C', 3)];
    ///     let max_bp_tree = MaxBpTree.fromArray<Char, Nat>(arr, Cmp.Char, Cmp.Nat, null);
    ///
    ///     assert MaxBpTree.get(max_bp_tree, Cmp.Char, 'A') == 1;
    ///     assert MaxBpTree.get(max_bp_tree, Cmp.Char, 'D') == null;
    /// ```
    public func get<K, V>(self : MaxBpTree<K, V>, cmp : CmpFn<K>, key : K) : ?V {
        Methods.get(self, cmp, key);
    };

    /// Returns the stored key-value pair associated with the given key and the comparison function.
    ///
    /// #### Examples
    /// ```motoko
    ///     let arr = [('A', 1), ('B', 2), ('C', 3)];
    ///     let max_bp_tree = MaxBpTree.fromArray<Char, Nat>(arr, Cmp.Char, Cmp.Nat, null);
    ///
    ///     assert MaxBpTree.getEntry(max_bp_tree, Cmp.Char, 'A') == ?('A', 1);
    ///     assert MaxBpTree.getEntry(max_bp_tree, Cmp.Char, 'D') == null;
    /// ```
    public func getEntry<K, V>(self : MaxBpTree<K, V>, cmp : CmpFn<K>, key : K) : ?(K, V) {
        Methods.get_entry(self, cmp, key);
    };

    /// Checks if the given key exists in the tree.
    public func has<K, V>(self : MaxBpTree<K, V>, cmp : CmpFn<K>, key : K) : Bool {
        Option.isSome(get(self, cmp, key));
    };

    /// Returns the largest key in the tree that is less than or equal to the given key.
    public func getFloor<K, V>(self : MaxBpTree<K, V>, cmp : CmpFn<K>, key : K) : ?(K, V) {
        Methods.get_floor<K, V>(self, cmp, key);
    };

    /// Returns the smallest key in the tree that is greater than or equal to the given key.
    public func getCeiling<K, V>(self : MaxBpTree<K, V>, cmp : CmpFn<K>, key : K) : ?(K, V) {
        Methods.get_ceiling<K, V>(self, cmp, key);
    };

    /// Inserts the given key-value pair into the tree.
    /// If the key already exists in the tree, it replaces the value and returns the old value.
    /// Otherwise, it returns null.
    ///
    /// #### Examples
    /// ```motoko
    ///     let max_bp_tree = MaxBpTree.new<Text, Nat>(?32);
    ///
    ///     assert MaxBpTree.insert(max_bp_tree, Cmp.Text, "id", 1) == null;
    ///     assert MaxBpTree.insert(max_bp_tree, Cmp.Text, "id", 2) == ?1;
    /// ```
    // add max-value update during replace
    public func insert<K, V>(max_bp_tree : MaxBpTree<K, V>, cmp_key : CmpFn<K>, cmp_val : CmpFn<V>, key : K, val : V) : ?V {
        let leaf_node = Methods.get_leaf_node(max_bp_tree, cmp_key, key);

        _insert_in_leaf(max_bp_tree, cmp_key, cmp_val, leaf_node, key, val);
    };

    public func _insert_in_leaf<K, V>(max_bp_tree : MaxBpTree<K, V>, cmp_key : CmpFn<K>, cmp_val : CmpFn<V>, leaf_node : Leaf<K, V>, key : K, val : V) : ?V {
        let int_elem_index = ArrayMut.binary_search(leaf_node.3, Utils.adapt_cmp(cmp_key), key, leaf_node.0 [C.COUNT]);
        let elem_index = if (int_elem_index >= 0) Int.abs(int_elem_index) else Int.abs(int_elem_index + 1);

        if (int_elem_index >= 0 and int_elem_index < leaf_node.0 [C.COUNT]) {
            _replace_at_leaf_index(max_bp_tree, cmp_key, cmp_val, leaf_node, elem_index, key, val);
        } else {
            _insert_at_leaf_index(max_bp_tree, cmp_key, cmp_val, leaf_node, elem_index, key, val);
            null;
        };
    };

    // Replaces the value associated with the given key with the new value.
    // Can also replace the key with a new key, if its inserted position is the same as the old key's position.
    // Meaning that the key is greater than the key to its left and less than the key to its right.
    // Note that this function does not check if the newly inserted key is in its correct position.
    public func _replace_at_leaf_index<K, V>(max_bp_tree : MaxBpTree<K, V>, cmp_key : CmpFn<K>, cmp_val : CmpFn<V>, leaf_node : Leaf<K, V>, elem_index : Nat, key : K, val : V) : ?V {
        // Debug.print("replace");

        let ?prev = leaf_node.3 [elem_index] else Debug.trap("1. insert: accessed a null value while replacing a key-value pair");

        let elem = (key, val);
        leaf_node.3 [elem_index] := ?elem;

        if (cmp_key(key, prev.0) != 0) {
            // update the median key of the parent node if necessary
            switch (leaf_node.1 [C.PARENT]) {
                case (?parent) if (elem_index == 0) {
                    Branch.update_median_key<K, V>(parent, leaf_node.0 [C.INDEX], key);
                };
                case (null) {};
            };
        };

        let ?max = leaf_node.4 [C.MAX] else Debug.trap("1: insert (replace entry): should have a max value");

        if (cmp_key(max.0, prev.0) == 0 and cmp_val(val, max.1) == -1) {
            leaf_node.4 [C.MAX] := null;

            var i = 0;
            while (i < leaf_node.0 [C.COUNT]) {
                // if (i == max_index) continue _loop;

                let ?kv = leaf_node.3 [i] else Debug.trap("insert (replace entry): accessed a null value");
                Common.update_leaf_with_kv_pair(leaf_node, cmp_key, cmp_val, i, kv);
                i += 1;
            };

        } else if (cmp_val(val, max.1) == 1 or (cmp_key(max.0, prev.0) == 0 and cmp_key(prev.0, key) != 0)) {
            leaf_node.4 [C.MAX] := ?elem;
            leaf_node.0 [C.MAX_INDEX] := elem_index;
        } else {
            Common.update_leaf_with_kv_pair(leaf_node, cmp_key, cmp_val, elem_index, elem);
        };

        func update_path_upstream(branch : Branch<K, V>, child_index : Nat) {
            // need not increase the subtree size as it is replacing an existing key-value pair
            // ~~branch.0[C.SUBTREE_SIZE] += 1;~~

            // update the max value of the branch node if necessary
            // note:    this function selects the max value by comparing all the max values in the children
            //          of the branch node. However, since the max value of the child node storing the key-value
            //          pair we are removing has not yet computed its new max value, the value stored here is just
            //          a placeholder (or best possible option) until the new max value is computed.
            let ?branch_max = branch.4 [C.MAX] else Debug.trap("replace(update_path_upstream): should have a max value");
            let max_index = branch.0 [C.MAX_INDEX];

            let ?child_max = switch (branch.3 [child_index]) {
                case (?#branch(node) or ?#leaf(node) : ?CommonNodeFields<K, V>) {
                    node.4 [C.MAX];
                };
                case (_) null;
            } else Debug.trap("replace(update_path_upstream): accessed a null value");

            if (cmp_key(branch_max.0, prev.0) == 0 and cmp_val(val, branch_max.1) == -1) {
                branch.4 [C.MAX] := ?child_max;

                var i = 0;
                while (i < branch.0 [C.COUNT]) {
                    let ?child = branch.3 [i] else Debug.trap("replace(update_path_upstream): accessed a null value");

                    if (i == max_index) {
                        let #branch(node) or #leaf(node) : CommonNodeFields<K, V> = child;
                        assert i == node.0 [C.INDEX];
                    } else {
                        Common.update_branch_fields(branch, cmp_key, cmp_val, i, child);
                    };

                    i += 1;
                };

            } else if (cmp_val(child_max.1, branch_max.1) == 1 or (cmp_key(branch_max.0, prev.0) == 0 and cmp_key(prev.0, key) != 0)) {
                branch.4 [C.MAX] := ?child_max;
                branch.0 [C.MAX_INDEX] := child_index;
            };
        };

        Methods.update_leaf_to_root(max_bp_tree, leaf_node, update_path_upstream);

        return ?prev.1;

    };

    public func _insert_at_leaf_index<K, V>(max_bp_tree : MaxBpTree<K, V>, cmp_key : CmpFn<K>, cmp_val : CmpFn<V>, leaf_node : Leaf<K, V>, elem_index : Nat, key : K, val : V) {

        let entry = (key, val);

        if (leaf_node.0 [C.COUNT] < max_bp_tree.order) {
            Leaf.insert(leaf_node, cmp_key, cmp_val, elem_index, entry);
            max_bp_tree.size += 1;

            func update_path_upstream(branch : Branch<K, V>, child_index : Nat) {
                branch.0 [C.SUBTREE_SIZE] += 1;

                let ?child = branch.3 [child_index] else Debug.trap("insert: accessed a null value");
                Common.update_branch_fields(branch, cmp_key, cmp_val, child_index, child);
            };

            Methods.update_leaf_to_root(max_bp_tree, leaf_node, update_path_upstream);

            return;
        };

        func gen_id() : Nat = Methods.gen_id(max_bp_tree);

        // split leaf node
        // Debug.print("before split leaf node: " # debug_show (leaf_node.4[C.MAX], leaf_node.3));
        let right_leaf_node = Leaf.split(leaf_node, elem_index, entry, gen_id, cmp_key, cmp_val);
        // Debug.print("after split left node: " # debug_show (leaf_node.4[C.MAX], leaf_node.3));
        // Debug.print("after split right node: " # debug_show (right_leaf_node.4[C.MAX], right_leaf_node.3));

        var opt_parent : ?Branch<K, V> = leaf_node.1 [C.PARENT];
        var left_node : Node<K, V> = #leaf(leaf_node);
        var left_index = leaf_node.0 [C.INDEX];

        var right_index = right_leaf_node.0 [C.INDEX];
        let ?right_leaf_first_entry = right_leaf_node.3 [0] else Debug.trap("2. insert: accessed a null value");
        var right_key = right_leaf_first_entry.0;
        var right_node : Node<K, V> = #leaf(right_leaf_node);

        // insert split leaf nodes into parent nodes if there is space
        // or iteratively split parent (internal) nodes to make space
        label index_split_loop while (Option.isSome(opt_parent)) {

            var subtree_diff : Nat = 0;
            let ?parent = opt_parent else Debug.trap("3. insert: accessed a null parent value");

            parent.0 [C.SUBTREE_SIZE] -= subtree_diff;

            parent.0 [C.SUBTREE_SIZE] += 1;

            if (parent.0 [C.COUNT] < max_bp_tree.order) {
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

                            if (j == right_index) {
                                let ?parent_max = parent.4 [C.MAX] else Debug.trap("3. insert: accessed a null value");
                                let ?node_max = node.4 [C.MAX] else Debug.trap("3. insert: accessed a null value");

                                let cmp_result = cmp_val(node_max.1, parent_max.1);
                                if (cmp_result == +1) {
                                    parent.4 [C.MAX] := ?(node_max.0, node_max.1);
                                    parent.0 [C.MAX_INDEX] := j;
                                    // Debug.print("update max index: Match");

                                } else if (parent.0 [C.MAX_INDEX] >= right_index) {
                                    parent.0 [C.MAX_INDEX] += 1;
                                    // Debug.print("update max index: to the right");

                                };
                            };
                        };
                        case (_) {};
                    };

                    j -= 1;
                };

                parent.0 [C.COUNT] += 1;
                max_bp_tree.size += 1;

                func update_path_upstream(branch : Branch<K, V>, child_index : Nat) {
                    branch.0 [C.SUBTREE_SIZE] += 1;

                    let ?child = branch.3 [child_index] else Debug.trap("insert: accessed a null value");
                    Common.update_branch_fields(branch, cmp_key, cmp_val, child_index, child);
                };

                Methods.update_branch_to_root(parent, update_path_upstream);

                return;

            } else {

                let median = (parent.0 [C.COUNT] / 2) + 1; // include inserted key-value pair
                let prev_subtree_size = parent.0 [C.SUBTREE_SIZE];

                // Debug.print("before split branch node: " # debug_show (parent.4[C.MAX], Methods.children_max(parent)));
                let split_node = Branch.split(parent, right_node, right_index, right_key, gen_id, cmp_key, cmp_val);
                // Debug.print("after split left node: " # debug_show (parent.4[C.MAX], Methods.children_max(parent)));
                // Debug.print("after split right node: " # debug_show (split_node.4[C.MAX], Methods.children_max(split_node)));

                let ?first_key = ArrayMut.extract(split_node.2, split_node.2.size() - 1 : Nat) else Debug.trap("4. insert: accessed a null value in first key of branch");
                right_key := first_key;

                left_node := #branch(parent);
                right_node := #branch(split_node);

                right_index := split_node.0 [C.INDEX];
                opt_parent := split_node.1 [C.PARENT];

                subtree_diff := prev_subtree_size - parent.0 [C.SUBTREE_SIZE];
            };
        };

        let root_node = Branch.new<K, V>(max_bp_tree.order, null, null, gen_id, cmp_val);
        root_node.2 [0] := ?right_key;

        Branch.add_child(root_node, cmp_key, cmp_val, left_node);
        Branch.add_child(root_node, cmp_key, cmp_val, right_node);

        max_bp_tree.root := #branch(root_node);
        max_bp_tree.size += 1;

    };

    public func toLeafNodes<K, V>(self : MaxBpTree<K, V>) : [(?(K, V, Nat), [?(K, V)])] {
        Methods.to_leaf_nodes(self);
    };

    public func toNodeKeys<K, V>(self : MaxBpTree<K, V>) : [[(Nat, ?(K, V, Nat), [?K])]] {
        Methods.to_node_keys(self);
    };

    /// Removes the key-value pair from the tree.
    /// If the key is not in the tree, it returns null.
    /// Otherwise, it returns the value associated with the key.
    ///
    /// #### Examples
    /// ```motoko
    ///     let arr = [('A', 1), ('B', 2), ('C', 3)];
    ///     let bptree = MaxBpTree.fromArray<Char, Nat>(arr, Cmp.Char, Cmp.Nat, null);
    ///
    ///     assert MaxBpTree.remove(bptree, Cmp.Char, Cmp.Nat, 'A') == ?1;
    ///     assert MaxBpTree.remove(bptree, Cmp.Char, Cmp.Nat, 'D') == null;
    /// ```
    public func remove<K, V>(self : MaxBpTree<K, V>, cmp_key : CmpFn<K>, cmp_val : CmpFn<V>, key : K) : ?V {
        if (self.size == 0) return null;

        let leaf_node = Methods.get_leaf_node(self, cmp_key, key);

        let int_elem_index = ArrayMut.binary_search(leaf_node.3, Utils.adapt_cmp(cmp_key), key, leaf_node.0 [C.COUNT]);

        let elem_index = if (int_elem_index >= 0) Int.abs(int_elem_index) else {
            func inc_branch_subtree_size(branch : Branch<K, V>, child_index : Nat) {
                branch.0 [C.SUBTREE_SIZE] += 1;
            };

            Methods.update_leaf_to_root(self, leaf_node, inc_branch_subtree_size);

            return null;
        };

        _remove_from_leaf(self, cmp_key, cmp_val, leaf_node, elem_index);
    };

    public func _remove_from_leaf<K, V>(self : MaxBpTree<K, V>, cmp_key : CmpFn<K>, cmp_val : CmpFn<V>, leaf_node : Leaf<K, V>, elem_index : Nat) : ?V {

        // remove elem
        let ?entry = ArrayMut.remove(leaf_node.3, elem_index, leaf_node.0 [C.COUNT]) else Debug.trap("1. remove: accessed a null value");
        // Debug.print("removing key: " # debug_show entry);

        let key = entry.0;
        let val = entry.1;
        let deleted = entry.1;
        self.size -= 1;
        leaf_node.0 [C.COUNT] -= 1;

        if (leaf_node.0 [C.MAX_INDEX] == elem_index) {
            leaf_node.4 [C.MAX] := null;

            var i = 0;

            while (i < leaf_node.0 [C.COUNT]) {
                let ?kv = leaf_node.3 [i] else Debug.trap("2. remove: accessed a null value");
                Common.update_leaf_with_kv_pair(leaf_node, cmp_key, cmp_val, i, kv);
                i += 1;
            };
        } else if (leaf_node.0 [C.MAX_INDEX] > elem_index) {
            leaf_node.0 [C.MAX_INDEX] -= 1;
        };

        if (self.size == 0) return ?deleted;

        let ?_new_max = leaf_node.4 [C.MAX] else Debug.trap("4: insert (replace entry): should have a max value");
        var new_max = _new_max;
        var prev_child_index = leaf_node.0 [C.INDEX];

        func update_path_upstream(branch : Branch<K, V>, child_index : Nat) {
            // Debug.print("branch index before: " # debug_show branch.0 [C.MAX_INDEX]);
            // reduce the subtree size of every branch on the path to the leaf node
            branch.0 [C.SUBTREE_SIZE] -= 1;

            // update the max value of the branch node if necessary
            let ?max = branch.4 [C.MAX] else Debug.trap("insert(update_path_downstream): should have a max value");

            if (cmp_val(max.1, val) != 0) return;

            branch.4 [C.MAX] := null;

            var i = 0;
            while (i < branch.0 [C.COUNT]) {
                let ?child = branch.3 [i] else Debug.trap("insert(update_path_downstream): accessed a null value");
                Common.update_branch_fields(branch, cmp_key, cmp_val, i, child);

                i += 1;
            };

        };

        Methods.update_leaf_to_root(self, leaf_node, update_path_upstream);

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
        // Debug.print("branch index before redistribute: " # debug_show (do?{leaf_node.1[C.PARENT]!.0[C.MAX_INDEX]}));

        Leaf.redistribute_keys(leaf_node, cmp_key, cmp_val);

        // Debug.print("branch index after redistribute: " # debug_show (do?{let p = leaf_node.1[C.PARENT]!; (p.0[C.MAX_INDEX])}));

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

        Leaf.merge(left_node, right_node, cmp_key, cmp_val);

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
            Branch.redistribute_keys(branch_node, cmp_key, cmp_val);
            if (branch_node.0 [C.COUNT] >= min_count) return ?deleted;

            let ?#branch(adj_branch_node) = (
                if (branch_node.0 [C.INDEX] == 0) {
                    parent.3 [1];
                } else {
                    parent.3 [branch_node.0 [C.INDEX] - 1];
                }
            ) else {
                // if the adjacent node is null then the branch node is the only child of the parent
                // this only happens if the branch node is the root node

                // update root node if necessary
                assert parent.0 [C.COUNT] == 1;
                let ?child = parent.3 [0] else Debug.trap("3. remove: accessed a null value");
                self.root := child;

                return ?deleted;
            };

            let left_node = if (adj_branch_node.0 [C.INDEX] < branch_node.0 [C.INDEX]) adj_branch_node else branch_node;
            let right_node = if (adj_branch_node.0 [C.INDEX] < branch_node.0 [C.INDEX]) branch_node else adj_branch_node;

            // Debug.print("parent before merge: " # debug_show Branch.toText(parent, Nat.toText, Nat.toText));
            Branch.merge(left_node, right_node, cmp_key, cmp_val);
            // Debug.print("parent after merge: " # debug_show Branch.toText(parent, Nat.toText, Nat.toText));

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

    /// Create a new Max Value B+ tree from the given entries.
    ///
    /// #### Inputs
    /// - `order` - the maximum number of children a node can have.
    /// - `entries` - an iterator over the entries to insert into the tree.
    /// - `cmp` - the comparison function to use for ordering the keys.
    ///
    /// #### Examples
    /// ```motoko
    ///     let entries = [('A', 1), ('B', 2), ('C', 3)].vals();
    ///     let max_bp_tree = Methods.fromEntries<Char, Nat>(null, entries, Cmp.Char);
    /// ```
    public func fromEntries<K, V>(entries : Iter<(K, V)>, cmp_key : CmpFn<K>, cmp_val : CmpFn<V>, order : ?Nat) : MaxBpTree<K, V> {
        let max_bp_tree = MaxBpTree.new<K, V>(order);

        for ((k, v) in entries) {
            ignore insert(max_bp_tree, cmp_key, cmp_val, k, v);
        };

        max_bp_tree;
    };

    /// Create a new Max Value B+ tree from the given array of key-value pairs.
    ///
    /// #### Inputs
    /// - `order` - the maximum number of children a node can have.
    /// - `arr` - the array of key-value pairs to insert into the tree.
    /// - `cmp` - the comparison function to use for ordering the keys.
    ///
    /// #### Examples
    /// ```motoko
    ///    let arr = [('A', 1), ('B', 2), ('C', 3)];
    ///    let max_bp_tree = MaxBpTree.fromArray<Char, Nat>(arr, Cmp.Char, Cmp.Nat, null);
    /// ```
    public func fromArray<K, V>(order : ?Nat, arr : [(K, V)], cmp_key : CmpFn<K>, cmp_val : CmpFn<V>) : MaxBpTree<K, V> {
        let max_bp_tree = MaxBpTree.new<K, V>(order);

        for (kv in arr.vals()) {
            let (k, v) = kv;
            ignore MaxBpTree.insert(max_bp_tree, cmp_key, cmp_val, k, v);
        };

        max_bp_tree;
    };

    /// Returns a sorted array of the key-value pairs in the tree.
    ///
    /// #### Examples
    /// ```motoko
    ///     let arr = [('A', 1), ('B', 2), ('C', 3)];
    ///     let max_bp_tree = MaxBpTree.fromArray<Char, Nat>(arr, Cmp.Char, Cmp.Nat, null);
    ///     assert MaxBpTree.toArray(max_bp_tree) == arr;
    /// ```
    public func toArray<K, V>(self : MaxBpTree<K, V>) : [(K, V)] {
        Methods.to_array<K, V>(self);
    };

    /// Returns the size of the Max Value B+ tree.
    ///
    /// #### Examples
    /// ```motoko
    ///     let arr = [('A', 1), ('B', 2), ('C', 3)];
    ///     let max_bp_tree = MaxBpTree.fromArray<Char, Nat>(arr, Cmp.Char, Cmp.Nat, null);
    ///
    ///     assert MaxBpTree.size(max_bp_tree) == 3;
    /// ```
    public func size<K, V>(self : MaxBpTree<K, V>) : Nat {
        self.size;
    };

    /// Returns the entry with the max value in the tree.
    /// If the tree is empty, it returns null.
    ///
    /// #### Examples
    /// ```motoko
    ///     let arr = [('A', 1), ('B', 2), ('C', 3)];
    ///     let max_bp_tree = MaxBpTree.fromArray<Char, Nat>(arr, Cmp.Char, Cmp.Nat, null);
    ///
    ///     assert MaxBpTree.maxValue(max_bp_tree) == ?('C', 3);
    /// ```
    public func maxValue<K, V>(self : MaxBpTree<K, V>) : ?(K, V) {
        switch (self.root) {
            case (#leaf(node) or #branch(node) : CommonNodeFields<K, V>) {
                node.4 [C.MAX];
            };
        };
    };

    /// Returns the minimum key-value pair in the tree.
    /// If the tree is empty, it returns null.
    ///
    /// #### Examples
    /// ```motoko
    ///     let arr = [('A', 1), ('B', 2), ('C', 3)];
    ///     let max_bp_tree = MaxBpTree.fromArray<Char, Nat>(arr, Cmp.Char, Cmp.Nat, null);
    ///
    ///     assert MaxBpTree.min(max_bp_tree) == ?('A', 1);
    /// ```
    public func min<K, V>(self : MaxBpTree<K, V>) : ?(K, V) {
        Methods.min(self);
    };

    /// Returns the maximum key-value pair in the tree.
    /// If the tree is empty, it returns null.
    ///
    /// #### Examples
    /// ```motoko
    ///     let arr = [('A', 1), ('B', 2), ('C', 3)];
    ///     let max_bp_tree = MaxBpTree.fromArray<Char, Nat>(arr, Cmp.Char, Cmp.Nat, null);
    ///
    ///     assert MaxBpTree.max(max_bp_tree) == ?('C', 3);
    /// ```
    public func max<K, V>(self : MaxBpTree<K, V>) : ?(K, V) {
        Methods.max(self);
    };

    /// Removes the minimum key-value pair in the tree and returns it.
    /// If the tree is empty, it returns null.
    ///
    /// #### Examples
    /// ```motoko
    ///     let arr = [('A', 1), ('B', 2), ('C', 3)];
    ///     let bptree = MaxBpTree.fromArray<Char, Nat>(arr, Cmp.Char, Cmp.Nat, null);
    ///
    ///     assert MaxBpTree.removeMin(bptree, Cmp.Char) == ?('A', 1);
    /// ```
    public func removeMin<K, V>(self : MaxBpTree<K, V>, cmp_key : CmpFn<K>, cmp_val : CmpFn<V>) : ?(K, V) {
        if (self.size == 0) return null;

        let leaf_node = Methods.get_min_leaf_node(self);
        let ?min = leaf_node.3 [0] else Debug.trap("removeMin: should have a min value");

        let ?v = _remove_from_leaf(self, cmp_key, cmp_val, leaf_node, 0) else return null;

        assert cmp_val(min.1, v) == 0;

        return ?min;
    };

    /// Removes the maximum key-value pair in the tree and returns it.
    /// If the tree is empty, it returns null.
    ///
    /// #### Examples
    /// ```motoko
    ///     let arr = [('A', 1), ('B', 2), ('C', 3)];
    ///     let bptree = MaxBpTree.fromArray<Char, Nat>(arr, Cmp.Char, Cmp.Nat, null);
    ///
    ///     assert MaxBpTree.removeMax(bptree, Cmp.Char, Cmp.Nat) == ?('C', 3);
    /// ```
    public func removeMax<K, V>(self : MaxBpTree<K, V>, cmp_key : CmpFn<K>, cmp_val : CmpFn<V>) : ?(K, V) {
        if (self.size == 0) return null;

        let leaf = Methods.get_max_leaf_node(self);
        let index = leaf.0 [C.COUNT] - 1 : Nat;
        let ?max = leaf.3 [index] else Debug.trap("removeMax: should have a max value");

        let ?v = _remove_from_leaf(self, cmp_key, cmp_val, leaf, index) else return null;

        assert cmp_val(max.1, v) == 0;

        return ?(max.0, v);
    };

    /// Removes the entry with the max value in the tree.
    /// If the tree is empty, it returns null.
    ///
    /// #### Examples
    /// ```motoko
    ///     let arr = [('A', 1), ('B', 3), ('C', 2)];
    ///     let max_bp_tree = MaxBpTree.fromArray<Char, Nat>(arr, Cmp.Char, Cmp.Nat, null);
    ///
    ///     assert MaxBpTree.removeMaxValue(max_bp_tree, Cmp.Char, Cmp.Nat) == ?('B', 3);
    /// ```
    public func removeMaxValue<K, V>(self : MaxBpTree<K, V>, cmp_key : CmpFn<K>, cmp_val : CmpFn<V>) : ?(K, V) {
        if (self.size == 0) return null;

        let leaf = Methods.get_max_value_leaf_node(self);
        let ?max = leaf.4 [C.MAX] else Debug.trap("removeMaxValue: should have a max value");
        let max_index = leaf.0 [C.MAX_INDEX];

        let ?v = _remove_from_leaf(self, cmp_key, cmp_val, leaf, max_index) else return null;
        assert cmp_val(max.1, v) == 0;
        return ?max;
    };

    /// Replaces the value of the entry with the max value in the tree.
    /// It returns the old value associated with the key.
    /// If the tree is empty, it returns null.
    /// Note that if there are duplicates of the max value, the key of the entry is not
    /// guaranteed to match the result from `maxValue`.
    public func replaceMaxValue<K, V>(self : MaxBpTree<K, V>, cmp_key : CmpFn<K>, cmp_val : CmpFn<V>, new_val : V) : ?(K, V) {
        if (self.size == 0) return null;

        let leaf = Methods.get_max_value_leaf_node(self);
        let max_index = leaf.0 [C.MAX_INDEX];
        let ?max = leaf.4 [C.MAX] else Debug.trap("replaceMaxValue: should have a max value");

        let old_val = max.1;

        let ?v = _replace_at_leaf_index(self, cmp_key, cmp_val, leaf, max_index, max.0, new_val) else return null;
        assert cmp_val(old_val, v) == 0;

        return ?max;
    };

    /// Returns a reversible iterator over the entries of the tree.
    public func entries<K, V>(max_bp_tree : MaxBpTree<K, V>) : RevIter<(K, V)> {
        Methods.entries(max_bp_tree);
    };

    /// Returns a reversible iterator over the keys of the tree.
    public func keys<K, V>(self : MaxBpTree<K, V>) : RevIter<K> {
        Methods.keys(self);
    };

    /// Returns a reversible iterator over the values of the tree.
    public func vals<K, V>(self : MaxBpTree<K, V>) : RevIter<V> {
        Methods.vals(self);
    };

    /// Returns a reversible iterator over the tree's entries, attached with their sorted index and leaf references.
    public func leafEntries<K, V>(self : MaxBpTree<K, V>) : RevIter<LeafEntry<K, V>> {
        Methods.leaf_entries(self);
    };

    /// Returns the rank of the given key in the tree.
    /// The rank is 0 indexed so the first element in the tree has rank 0.
    ///
    /// If the key does not exist in the tree, then the fn returns the rank.
    /// of the key if it were to be inserted.
    ///
    /// #### Examples
    /// ```motoko
    ///     let arr = [('A', 1), ('B', 2), ('C', 3)];
    ///     let max_bp_tree = MaxBpTree.fromArray<Char, Nat>(arr, Cmp.Char, Cmp.Nat, null);
    ///
    ///     assert MaxBpTree.getIndex(max_bp_tree, Cmp.Char, 'B') == 1;
    ///     assert MaxBpTree.getIndex(max_bp_tree, Cmp.Char, 'D') == 3;
    /// ```
    public func getIndex<K, V>(self : MaxBpTree<K, V>, cmp : CmpFn<K>, key : K) : Nat {
        Methods.get_index(self, cmp, key);
    };

    /// Returns the key-value pair at the given rank.
    /// Returns null if the rank is greater than the size of the tree.
    ///
    /// #### Examples
    /// ```motoko
    ///     let arr = [('A', 1), ('B', 2), ('C', 3)];
    ///     let max_bp_tree = MaxBpTree.fromArray<Char, Nat>(arr, Cmp.Char, Cmp.Nat, null);
    ///
    ///     assert MaxBpTree.getFromIndex(max_bp_tree, 0) == ('A', 1);
    ///     assert MaxBpTree.getFromIndex(max_bp_tree, 1) == ('B', 2);
    /// ```
    public func getFromIndex<K, V>(self : MaxBpTree<K, V>, rank : Nat) : (K, V) {
        Methods.get_from_index(self, rank);
    };

    /// Returns an iterator over the entries of the tree in the range [start, end].
    /// The range is defined by the ranks of the start and end keys
    public func range<K, V>(self : MaxBpTree<K, V>, start : Nat, end : Nat) : RevIter<(K, V)> {
        Methods.range(self, start, end);
    };

    /// Returns an iterator over the entries of the tree in the range [start, end].
    /// The iterator is inclusive of start and end.
    ///
    /// If the start key does not exist in the tree then the iterator will start from next key greater than start.
    /// If the end key does not exist in the tree then the iterator will end at the last key less than end.
    public func scan<K, V>(self : MaxBpTree<K, V>, cmp : CmpFn<K>, start : K, end : K) : RevIter<(K, V)> {
        Methods.scan(self, cmp, start, end);
    };

    /// Removes all the entries from the tree.
    public func clear<K, V>(self : MaxBpTree<K, V>) {

        let leaf = switch (self.root) {
            case (#leaf(leaf)) leaf;
            case (#branch(branch)) Methods.get_min_leaf_node(self);
        };

        var cnt = leaf.0 [C.COUNT];

        leaf.0 [C.ID] := 0;
        leaf.0 [C.COUNT] := 0;
        leaf.0 [C.INDEX] := 0;
        leaf.0 [C.MAX_INDEX] := 0;

        leaf.1 [C.PARENT] := null;

        leaf.2 [C.PREV] := null;
        leaf.2 [C.NEXT] := null;

        while (cnt > 0) {
            leaf.3 [cnt - 1] := null;
            cnt -= 1;
        };

        leaf.4 [C.MAX] := null;

        self.root := #leaf(leaf);
        self.size := 0;

        self.next_id := 1;
    };

};
