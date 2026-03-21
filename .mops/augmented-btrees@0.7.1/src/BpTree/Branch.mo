import Iter "mo:base/Iter";
import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Order "mo:base/Order";

import T "Types";
import InternalTypes "../internal/Types";
import Leaf "Leaf";
import Utils "../internal/Utils";
import ArrayMut "../internal/ArrayMut";
module Branch {
    type Order = Order.Order;
    public type Branch<K, V> = T.Branch<K, V>;
    type Node<K, V> = T.Node<K, V>;
    type BpTree<K, V> = T.BpTree<K, V>;
    type CmpFn<K> = InternalTypes.CmpFn<K>;
    type CommonNodeFields<K, V> = T.CommonNodeFields<K, V>;
    let { Const = C } = T;

    public func new<K, V>(
        order : Nat,
        opt_keys : ?[var ?K],
        opt_children : ?[var ?Node<K, V>],
        gen_id : () -> Nat,
    ) : Branch<K, V> {

        let self : Branch<K, V> = (
            Array.init(4, 0),
            Array.init(1, null),
            Array.init(order - 1 : Nat, null),
            Array.init(order, null)
        );

        self;
    };

    public func update_median_key<K, V>(_parent: Branch<K, V>, leaf_index: Nat, new_key: K){
        var parent = _parent;
        var i = leaf_index;

        while (i == 0){
            i:= parent.0[C.INDEX];
            let ?__parent = parent.1[C.PARENT] else return; // occurs when key is the first key in the tree
            parent := __parent;
        };

        parent.2[i - 1] := ?new_key;
    };

    public func add_child<K, V>(branch: Branch<K,V>, child: Node<K,V>) {
        let i = branch.0[C.COUNT] : Nat;
        branch.3[i] := ?child;

        switch (child) {
            case (#branch(node)) {
                node.1[C.PARENT] := ?branch;
                node.0[C.INDEX] := i;
                branch.0[C.SUBTREE_SIZE] += node.0[C.SUBTREE_SIZE];
            };
            case(#leaf(node)) {
                node.1[C.PARENT] := ?branch;
                node.0[C.INDEX] := i;
                branch.0[C.SUBTREE_SIZE] += node.0[C.COUNT];
            };
        };
        
        branch.0[C.COUNT] += 1;
    };

    public func add_children<K, V>(branch: Branch<K,V>, children: [Node<K,V>]) {
        var i = 0;
        while (i < children.size()) {
            add_child(branch, children[i]);
        };
    };

    public func split<K, V>(node : Branch<K, V>, child : Node<K, V>, child_index : Nat, first_child_key : K, gen_id: () -> Nat) : Branch<K, V> {
        let arr_len = node.0[C.COUNT];
        let median = (arr_len / 2) + 1;

        let is_elem_added_to_right = child_index >= median;

        var median_key = ?first_child_key;

        var offset = if (is_elem_added_to_right) 0 else 1;
        var already_inserted = false;

        let right_cnt = arr_len + 1 - median : Nat;
        let right_node = Branch.new<K, V>(node.3.size(), null, null, gen_id);
        
        var i = 0;
        
        while (i < right_cnt) {
            let j = i + median - offset : Nat;

            let ?child_node = if (j >= median and j == child_index and not already_inserted) {
                offset += 1;
                already_inserted := true;
                if (i > 0) right_node.2[i - 1] := ?first_child_key;
                ?child;
            } else {
                if (i == 0) {
                    median_key := node.2[j - 1];
                } else {
                    right_node.2[i - 1] := node.2[j - 1];
                };
                node.2[j - 1] := null;
                ArrayMut.extract(node.3, j);
            } else Debug.trap("Branch.split: accessed a null value");

            Branch.add_child<K, V>(right_node, child_node);
            i += 1;
        };

        node.0[C.SUBTREE_SIZE] -= right_node.0[C.SUBTREE_SIZE];


        var j = median - 1 : Nat;

        while (j > child_index) {
            if (j >= 2) {
                node.2[j - 1] := node.2[j - 2];
            };

            node.3[j] := node.3[j - 1];

            switch (node.3[j]) {
                case (? #branch(node) or ? #leaf(node) : ?CommonNodeFields<K, V>) {
                    node.0[C.INDEX] := j;
                };
                case (_) {};
            };

            j -= 1;
        };

        if (j == child_index) {
            if (j > 0) {
                node.2[j - 1] := ?first_child_key;
                node.3[j] := ?child;
            } else {
                // elements inserted are always nodes created as a result of split
                // so their index is always greater than one as new nodes created from
                // a split operation are always inserted at the right
                // update_median_key(node, child_index, first_child_key);
                // node.3[0] := ?child;
            };
        };

        node.0[C.COUNT] := median;

        right_node.0[C.INDEX] := node.0[C.INDEX] + 1;

        right_node.0[C.COUNT] := right_cnt;
        right_node.1[C.PARENT] := node.1[C.PARENT];

        // store the first key of the right node at the end of the keys in left node
        // no need to delete as the value will get overwritten because it exceeds the count position
        right_node.2[right_node.2.size() - 1] := median_key;

        right_node;
    };

    public func shift_by<K, V>(self : Branch<K, V>, start : Nat, end : Nat, shift : Int) {
        if (shift == 0) return;

        if (shift > 0) {
            var i = end; // exclusive

            while (i > start) {
                let child = self.3[i - 1];
                self.3[i - 1] := null;

                let j = Int.abs(shift) + i - 1 : Nat;
                self.3[j] := child;

                switch (child) {
                    case (? #branch(node) or ? #leaf(node) : ?CommonNodeFields<K, V>) {
                        node.0[C.INDEX] := j;
                    };
                    case (_) {};
                };

                i -= 1;
            };

            return;
        };

        var i = start;
        while (i < end) {
            let child = self.3[i];
            self.3[i] := null;

            let j = Int.abs(i + shift);
            self.3[j] := child;

            switch (child) {
                case (? #branch(node) or ? #leaf(node) : ?CommonNodeFields<K, V>) {
                    node.0[C.INDEX] := j;
                };
                case (_) {};
            };

            i += 1;
        };
    };


    public func put<K, V>(branch : Branch<K, V>, i : Nat, child : Node<K, V>) {
        branch.3[i] := ?child;

        switch (child) {
            case (#branch(node) or #leaf(node) : CommonNodeFields<K, V>) {
                node.1[C.PARENT] := ?branch;
                node.0[C.INDEX] := i;
            };
        };
    };

    public func insert<K, V>(branch : Branch<K, V>, i : Nat, child : Node<K, V>) {

        var j = i;

        while (j < branch.0[C.COUNT]) {
            branch.3[j + 1] := branch.3[j];

            switch (branch.3[j + 1]) {
                case (? #branch(node) or ? #leaf(node) : ?CommonNodeFields<K, V>) {
                    node.1[C.PARENT] := ?branch;
                    node.0[C.INDEX] := j + 1;
                };
                case (_) {};
            };
            j += 1;
        };

        branch.3[i] := ?child;

        switch (child) {
            case (#branch(node) or #leaf(node) : CommonNodeFields<K, V>) {
                node.1[C.PARENT] := ?branch;
                node.0[C.INDEX] := i;
            };
        };

    };

    public func remove<K, V>(
        self : Branch<K, V>, 
        index : Nat, 
        count : Nat,
    ) : ?Node<K, V> {
        let removed = self.3[index];

        var i = index;
        while (i < (count - 1 : Nat)) {
            self.3[i] := self.3[i + 1];

            let ?child = self.3[i] else Debug.trap("Branch.remove: accessed a null value");

            switch (child) {
                case (#leaf(node) or #branch(node) : CommonNodeFields<K, V>) {
                    node.0[C.INDEX] := i;
                };
            };

            i += 1;
        };

        self.3[count - 1] := null;
        // self.0[C.COUNT] -=1;

        removed;
    };

    public func redistribute_keys<K, V>(branch_node: Branch<K, V>){
        var adj_node = branch_node;

        // retrieve adjacent node
        switch (branch_node.1[C.PARENT]) {
            case (null) {};
            case (?parent) {
                if (parent.0[C.COUNT] > 1) {
                    if (branch_node.0[C.INDEX] != 0) {
                        let ? #branch(left_adj_node) = parent.3[branch_node.0[C.INDEX] - 1] else Debug.trap("1. redistribute_branch_keys: accessed a null value");
                        adj_node := left_adj_node;
                    };

                    if (branch_node.0[C.INDEX] + 1 != parent.0[C.COUNT]) {
                        let ? #branch(right_adj_node) = parent.3[branch_node.0[C.INDEX] + 1] else Debug.trap("2. redistribute_branch_keys: accessed a null value");
                        if (right_adj_node.0[C.COUNT] > adj_node.0[C.COUNT]) {
                            adj_node := right_adj_node;
                        };
                    };
                };
            };
        };

        if (adj_node.0[C.INDEX] == branch_node.0[C.INDEX]) return; // no adjacent node to distribute data to

        let sum_count = branch_node.0[C.COUNT] + adj_node.0[C.COUNT];
        let min_count_for_both_nodes = branch_node.3.size();

        if (sum_count < min_count_for_both_nodes) return; // not enough entries to distribute

        let data_to_move = (sum_count / 2) - branch_node.0[C.COUNT] : Nat;

        // every node from this point on has a parent because an adjacent node was found
        let ?parent = branch_node.1[C.PARENT] else Debug.trap("3. redistribute_branch_keys: accessed a null value");
        // assert Utils.is_sorted<Nat>(branch_node.2, Nat.compare);

        var moved_subtree_size = 0;

        // distribute data between adjacent nodes
        if (adj_node.0[C.INDEX] < branch_node.0[C.INDEX]) {
            // adj_node is before branch_node
            var median_key = parent.2[adj_node.0[C.INDEX]];

            ArrayMut.shift_by(branch_node.2, 0, branch_node.0[C.COUNT] - 1 : Nat, data_to_move : Nat);
            Branch.shift_by(branch_node, 0, branch_node.0[C.COUNT] : Nat, data_to_move : Nat);
            var i = 0;
            while (i < data_to_move) {
                let j = adj_node.0[C.COUNT] - i - 1 : Nat;
                branch_node.2[data_to_move - i - 1] := median_key;
                let ?mk = ArrayMut.remove(adj_node.2, j - 1 : Nat, adj_node.0[C.COUNT] - 1 : Nat) else Debug.trap("4. redistribute_branch_keys: accessed a null value");
                median_key := ?mk;

                let new_node_index = data_to_move - i - 1 : Nat;
                let ?val = Branch.remove(adj_node, j, adj_node.0[C.COUNT] - i : Nat) else Debug.trap("4. redistribute_branch_keys: accessed a null value");
                
                // no need to call update_fields as we are the adjacent node is before the leaf node 
                // which means that all its keys are less than the leaf node's keys
                Branch.put(branch_node, new_node_index, val);

                switch (val) {
                    case (#branch(node)) {
                        moved_subtree_size += node.0[C.SUBTREE_SIZE];
                    };
                    case (#leaf(node)) {
                        moved_subtree_size += node.0[C.COUNT];
                    };
                };

                i += 1;
            };

            parent.2[adj_node.0[C.INDEX]] := median_key;

        } else {
            // adj_node is after branch_node
            var median_key = parent.2[branch_node.0[C.INDEX]];
            var i = 0;

            while (i < data_to_move) {
                ArrayMut.insert(branch_node.2, branch_node.0[C.COUNT] + i - 1 : Nat, median_key, branch_node.0[C.COUNT] - 1 : Nat);
                median_key := adj_node.2[i];

                let ?val = adj_node.3[i] else Debug.trap("5. redistribute_branch_keys: accessed a null value");
                Branch.insert(branch_node, branch_node.0[C.COUNT] + i, val);

                switch (val) {
                    case (#branch(node)) {
                        moved_subtree_size += node.0[C.SUBTREE_SIZE];
                    };
                    case (#leaf(node)) {
                        moved_subtree_size += node.0[C.COUNT];
                    };
                };

                i += 1;
            };

            ArrayMut.shift_by(adj_node.2, i, adj_node.0[C.COUNT] - 1 : Nat, -data_to_move : Int);
            Branch.shift_by(adj_node, i, adj_node.0[C.COUNT] : Nat, -data_to_move : Int);

            parent.2[branch_node.0[C.INDEX]] := median_key;

        };

        adj_node.0[C.COUNT] -= data_to_move;
        branch_node.0[C.COUNT] += data_to_move;

        adj_node.0[C.SUBTREE_SIZE] -= moved_subtree_size;
        branch_node.0[C.SUBTREE_SIZE] += moved_subtree_size;

    };

    public func merge<K, V>(left: Branch<K, V>, right: Branch<K, V>){
        //  assert left.0[C.INDEX] + 1 == right.0[C.INDEX];

        // if there are two adjacent nodes then there must be a parent
        let ?parent = left.1[C.PARENT] else Debug.trap("1. merge_branch_nodes: accessed a null value");

        var median_key = parent.2[right.0[C.INDEX] - 1];
        let right_subtree_size = right.0[C.SUBTREE_SIZE];
        // merge right into left
        var i = 0;
        
        while (i < right.0[C.COUNT]){
            ArrayMut.insert(left.2, left.0[C.COUNT] + i - 1 : Nat, median_key, left.0[C.COUNT] - 1 : Nat);
            median_key := right.2[i];

            let ?child = right.3[i] else Debug.trap("2. merge_branch_nodes: accessed a null value");
            Branch.insert(left, left.0[C.COUNT] + i, child);
            i += 1;
        };

        left.0[C.COUNT] += right.0[C.COUNT];
        left.0[C.SUBTREE_SIZE] += right_subtree_size;

        // update parent keys
        ignore ArrayMut.remove(parent.2, right.0[C.INDEX] - 1 : Nat, parent.0[C.COUNT] - 1 : Nat);
        ignore Branch.remove(parent, right.0[C.INDEX], parent.0[C.COUNT]);
        parent.0[C.COUNT] -= 1;

    };

    public func equal<K, V>(a : Branch<K, V>, b : Branch<K, V>, cmp : CmpFn<K>) : Bool {
        for (i in Iter.range(0, a.2.size() - 2)) {
            let res = switch (a.2[i], b.2[i]) {
                case (?v1, ?v2) {
                    cmp(v1, v2) == 0;
                };
                case (null, null) true;
                case (_) false;
            };

            if (not res) return false;
        };

        for (i in Iter.range(0, a.3.size() - 1)) {
            let res = switch (a.3[i], b.3[i]) {
                case (? #leaf(v1), ? #leaf(v2)) {
                    Leaf.equal(v1, v2, cmp);
                };
                case (? #branch(v1), ? #branch(v2)) {
                    equal(v1, v2, cmp);
                };
                case (null, null) true;
                case (_) false;
            };
        };

        true;
    };

    public func subtrees<K, V>(node : Branch<K, V>) : [Nat] {
        Array.tabulate(
            node.0[C.COUNT],
            func(i : Nat) : Nat {
                let ?child = node.3[i] else Debug.trap("subtrees: accessed a null value");
                switch (child) {
                    case (#branch(node)) node.0[C.SUBTREE_SIZE];
                    case (#leaf(node)) node.0[C.COUNT];
                };
            },
        );
    };

    public func toText<K, V>(self : Branch<K, V>, key_to_text : (K) -> Text, val_to_text : (V) -> Text) : Text {
        var t = "branch { index: " # debug_show self.0[C.INDEX] # ", count: " # debug_show self.0[C.COUNT] # ", subtree: " # debug_show self.0[C.SUBTREE_SIZE] # ", keys: ";
        t #= debug_show Array.map(
            Array.freeze(self.2),
            func(opt_key : ?K) : Text {
                switch (opt_key) {
                    case (?key) key_to_text(key);
                    case (_) "null";
                };
            },
        );

        t #= ", children: " # debug_show Array.map(
            Array.freeze(self.3),
            func(opt_node : ?Node<K, V>) : Text {
                switch (opt_node) {
                    case (? #leaf(node)) Leaf.toText<K, V>(node, key_to_text, val_to_text);
                    case (? #branch(node)) Branch.toText(node, key_to_text, val_to_text);
                    case (_) "null";
                };
            },
        );

        t #= " }";

        t;
    };
};
