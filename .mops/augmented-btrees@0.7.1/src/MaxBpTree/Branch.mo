import Iter "mo:base/Iter";
import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Order "mo:base/Order";
import Option "mo:base/Option";

import T "Types";
import InternalTypes "../internal/Types";
import Leaf "Leaf";
import Utils "../internal/Utils";
import ArrayMut "../internal/ArrayMut";

import Common "Common";

module Branch {
    type Order = Order.Order;
    public type Branch<K, V> = T.Branch<K, V>;
    type Node<K, V> = T.Node<K, V>;
    type Leaf<K, V> = T.Leaf<K, V>;
    type CmpFn<A> = T.CmpFn<A>;
    type MultiCmpFn<A, B> = T.MultiCmpFn<A, B>;
    type CommonNodeFields<K, V> = T.CommonNodeFields<K, V>;
    type MaxBpTree<K, V> = T.MaxBpTree<K, V>;
    type UpdateBranchMaxFn<K, V> = T.UpdateBranchMaxFn<K, V>;
    type ResetMaxFn<K, V> = T.ResetMaxFn<K, V>;
    let {Const = C } = T;

    public func new<K, V>(
        order : Nat,
        opt_keys : ?[var ?K],
        opt_children : ?[var ?Node<K, V>],
        gen_id : () -> Nat,
        cmp_val : CmpFn<V>,
    ) : Branch<K, V> {

        let self : Branch<K, V> = (
            Array.init(5, 0),
            Array.init(1, null),
            Array.init(order - 1 : Nat, null),
            Array.init(order, null),
            Array.init(1, null),
        );

        self;
    };

    public func update_median_key<K, V>(_parent : Branch<K, V>, leaf_index : Nat, new_key : K) {
        var parent = _parent;
        var i = leaf_index;

        while (i == 0) {
            i := parent.0[C.INDEX];
            let ?__parent = parent.1[C.PARENT] else return; // occurs when key is the first key in the tree
            parent := __parent;
        };

        parent.2[i - 1] := ?new_key;
    };

    public func add_child<K, V>(branch: Branch<K,V>, cmp_key: CmpFn<K>, cmp_val: CmpFn<V>, child: Node<K,V>) {
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
        
        Common.update_branch_fields(branch, cmp_key, cmp_val, i, child);
        branch.0[C.COUNT] += 1;
    };

    public func split<K, V>(
        node : Branch<K, V>,
        child : Node<K, V>,
        child_index : Nat,
        first_child_key : K,
        gen_id : () -> Nat,
        cmp_key : CmpFn<K>,
        cmp_val : CmpFn<V>,
    ) : Branch<K, V> {

        let arr_len = node.0[C.COUNT];
        let median = (arr_len / 2) + 1;

        let is_elem_added_to_right = child_index >= median;

        var median_key = ?first_child_key;

        let initial_offset = if (is_elem_added_to_right) 0 else 1;
        var offset = initial_offset;
        var already_inserted = false;

        let right_cnt = arr_len + 1 - median : Nat;
        let right_node = Branch.new<K, V>(node.3.size(), null, null, gen_id, cmp_val);
        
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

            Branch.add_child<K, V>(right_node, cmp_key, cmp_val, child_node);
            i += 1;
        };

        node.0[C.SUBTREE_SIZE] -= right_node.0[C.SUBTREE_SIZE];

        var j = median - 1 : Nat;

        let moved_left_max = if (node.0[C.MAX_INDEX] >= (arr_len - right_cnt - initial_offset : Nat)){
            node.4[C.MAX] := null;
            true;
        }else {
            if (node.0[C.MAX_INDEX] >= child_index){
                node.0[C.MAX_INDEX] += 1;
            };
            false;
        };

        label while_loop while (moved_left_max or j >= child_index) {

            if (j > child_index){
                if (j >= 2) {
                    node.2[j - 1] := node.2[j - 2];
                };

                node.3[j] := node.3[j - 1];

            } else if (j == child_index){
                if (j > 0) {
                    node.2[j - 1] := ?first_child_key;
                } else {
                    // elements inserted are always nodes created as a result of split
                    // so their index is always greater than one as new nodes created from
                    // a split operation are always inserted at the right
                    
                    // update_median_key(node, 0, first_child_key);
                };

                node.3[j] := ?child;
            };
            
            let ?child_node = node.3[j] else Debug.trap("Branch.split: accessed a null value");

            switch (child_node) {
                case (#branch(node) or #leaf(node) : CommonNodeFields<K, V>) {
                    node.0[C.INDEX] := j;
                };
            };

            if (moved_left_max){
                Common.update_branch_fields(node, cmp_key, cmp_val, j, child_node);
            } else if (j == child_index){
                Common.update_branch_fields(node, cmp_key, cmp_val, j, child);
            };

            if (j > 0) j -= 1 else break while_loop;
        };

        //update parent max to left branch because the right branch is a new branch
        switch (node.1[C.PARENT]) {
            case (?parent) {
                let ?node_max = node.4[C.MAX] else Debug.trap("Branch.split: accessed a null value");
                let ?parent_max = parent.4[C.MAX] else Debug.trap("Branch.split: accessed a null value");
                // Debug.print("Parent max index: " # debug_show parent.0[C.MAX_INDEX]);
                if (parent.0[C.MAX_INDEX] == node.0[C.INDEX] or cmp_val(node_max.1, parent_max.1) == +1){
                    parent.4[C.MAX] := node.4[C.MAX];
                    parent.0[C.MAX_INDEX] := node.0[C.INDEX];
                };
                // Debug.print("Parent max index: " # debug_show parent.0[C.MAX_INDEX]);

            };
            case (_) {};
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

    public func shift_by<K, V>(branch : Branch<K, V>, start : Nat, end : Nat, offset : Int) {
        if (offset == 0) return;

        if (offset > 0) {
            var i = end; // exclusive

            while (i > start) {
                let child = branch.3[i - 1];
                branch.3[i - 1] := null;

                let j = Int.abs(offset) + i - 1 : Nat;
                branch.3[j] := child;

                switch (child) {
                    case (? #branch(node) or ? #leaf(node) : ?CommonNodeFields<K, V>) {
                        node.0[C.INDEX] := j;
                    };
                    case (_) {};
                };

                i -= 1;
            };
        } else {
            var i = start;
            while (i < end) {
                let child = branch.3[i];
                branch.3[i] := null;

                let j = Int.abs(i + offset);
                branch.3[j] := child;

                switch (child) {
                    case (? #branch(node) or ? #leaf(node) : ?CommonNodeFields<K, V>) {
                        node.0[C.INDEX] := j;
                    };
                    case (_) {};
                };

                i += 1;
            };
        };

       branch.0[C.MAX_INDEX] := Int.abs(branch.0[C.MAX_INDEX] + offset);

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
        cmp_key: CmpFn<K>,
        cmp_val : CmpFn<V>,
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

            // update with the prev index as it will be updated after the loop
            Common.update_branch_fields(self, cmp_key, cmp_val, i + 1, child);

            i += 1;
        };

        // update the max field index
        if (self.0[C.MAX_INDEX] > index and self.0[C.MAX_INDEX] > 0) {
            self.0[C.MAX_INDEX] -= 1;
        };

        self.3[count - 1] := null;
        // self.0[C.COUNT] -=1;

        removed;
    };

    public func redistribute_keys<K, V>(
        branch_node : Branch<K, V>,
        cmp_key : CmpFn<K>,
        cmp_val : CmpFn<V>,
    ) {

        // every node from this point on has a parent because an adjacent node was found
        let ?parent = branch_node.1[C.PARENT] else return;
        
        // retrieve adjacent node
        var adj_node = branch_node;
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

        if (adj_node.0[C.INDEX] == branch_node.0[C.INDEX]) return; // no adjacent node to distribute data to

        let sum_count = branch_node.0[C.COUNT] + adj_node.0[C.COUNT];
        let min_count_for_both_nodes = branch_node.3.size();

        if (sum_count < min_count_for_both_nodes) return; // not enough entries to distribute

        let data_to_move = (sum_count / 2) - branch_node.0[C.COUNT] : Nat;

        var moved_subtree_size = 0;

        let is_adj_node_equal_to_parent_max = parent.0[C.MAX_INDEX] == adj_node.0[C.INDEX];
        //  switch (parent.4[C.MAX], adj_node.4[C.MAX]) {
        //     case (?parent_max, ?adj_max) cmp_key(parent_max.0, adj_max.0) == 0;
        //     case (_, _) false;
        // };

        // distribute data between adjacent nodes
        if (adj_node.0[C.INDEX] < branch_node.0[C.INDEX]) {
            // adj_node is before branch_node
            var median_key = parent.2[adj_node.0[C.INDEX]];

            ArrayMut.shift_by(branch_node.2, 0, branch_node.0[C.COUNT] - 1 : Nat, data_to_move : Nat);
            Branch.shift_by(branch_node, 0, branch_node.0[C.COUNT] : Nat, data_to_move : Nat);
            var i = 0;
            while (i < data_to_move ) {
                let j = adj_node.0[C.COUNT] - i - 1 : Nat;
                branch_node.2[data_to_move - i - 1] := median_key;
                let ?mk = ArrayMut.remove(adj_node.2, j - 1 : Nat, adj_node.0[C.COUNT] - 1 : Nat) else Debug.trap("4. redistribute_branch_keys: accessed a null value");
                median_key := ?mk;

                let new_node_index = data_to_move - i - 1 : Nat;
                assert j < adj_node.3.size();

                let ?val = ArrayMut.extract(adj_node.3, j) else Debug.trap("4. redistribute_branch_keys: accessed a null value");
                
                let #leaf(new_child_node) or #branch(new_child_node) : CommonNodeFields<K, V> = val;

                // remove the adj_node max if it was removed
                if (adj_node.0[C.MAX_INDEX] <= j){
                    adj_node.4[C.MAX] := null;
                };

                // no need to call update_fields as we are the adjacent node is before the leaf node
                // which means that all its keys are less than the leaf node's keys
                Branch.put(branch_node, new_node_index, val);

                // update the branch node max if the inserted value's max is greater than the current max
                switch(branch_node.4[C.MAX], new_child_node.4[C.MAX]){
                    case (?branch_max, ?child_max) {
                        if (cmp_val(child_max.1, branch_max.1) == +1) {
                            branch_node.4[C.MAX] := ?(child_max.0, child_max.1);
                            branch_node.0[C.MAX_INDEX] := new_node_index;
                        };
                    };
                    case (_) Debug.trap("Branch.redistribute_keys: branch max is null");
                };

                // update the subtree size
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
            var j = branch_node.0[C.COUNT] : Nat;
            var median_key = parent.2[branch_node.0[C.INDEX]];
            
            var i = 0;
            while (i < data_to_move) {
                ArrayMut.insert(branch_node.2, branch_node.0[C.COUNT] + i - 1 : Nat, median_key, branch_node.0[C.COUNT] - 1 : Nat);
                median_key := adj_node.2[i];

                let ?val = adj_node.3[i] else Debug.trap("5. redistribute_branch_keys: accessed a null value");
                Branch.insert(branch_node, branch_node.0[C.COUNT] + i, val);

                // remove the adj_node max if it was removed
                if (adj_node.0[C.MAX_INDEX] <= i){
                    adj_node.4[C.MAX] := null;
                };

                let #branch(child_node) or #leaf(child_node) : CommonNodeFields<K, V> = val;

                // update the branch node max if the inserted value's max is greater than the current max
                switch(branch_node.4[C.MAX], child_node.4[C.MAX]){
                    case (?branch_max, ?child_max) {
                        if (cmp_val(child_max.1, branch_max.1) == +1) {
                            branch_node.4[C.MAX] := ?(child_max.0, child_max.1);
                            branch_node.0[C.MAX_INDEX] := branch_node.0[C.COUNT] + i;
                        };
                    };
                    case (_) Debug.trap("Branch.redistribute_keys: branch max is null");
                };

                // update subtree size
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

        if (Option.isNull(adj_node.4[C.MAX])){

            var i = 0;
            while (i < adj_node.0[C.COUNT]) {
                let ?node = adj_node.3[i] else Debug.trap("Leaf.redistribute_keys: kv is null");
                Common.update_branch_fields(adj_node, cmp_key, cmp_val, i, node);
                i += 1;
            };
        };

        // update parent max
        if (is_adj_node_equal_to_parent_max) {
            switch(parent.4[C.MAX], adj_node.4[C.MAX]) {
                case (?parent_max, ?adj_max) {
                    if (cmp_val(parent_max.1, adj_max.1) != 0) {
                        parent.4[C.MAX] := ?(parent_max.0, parent_max.1);
                        parent.0[C.MAX_INDEX] := branch_node.0[C.INDEX];
                    };
                };
                case (_, _) {};
            };
        };
    };

    public func merge<K, V>(
        left : Branch<K, V>,
        right : Branch<K, V>,
        cmp_key : CmpFn<K>,
        cmp_val : CmpFn<V>,
    ) {
        // assert left.0[C.INDEX] + 1 == right.0[C.INDEX];

        // if there are two adjacent nodes then there must be a parent
        let ?parent = left.1[C.PARENT] else Debug.trap("1. merge_branch_nodes: accessed a null value");

        var median_key = parent.2[right.0[C.INDEX] - 1];
        let right_subtree_size = right.0[C.SUBTREE_SIZE];
        // merge right into left
        var i = 0;
        while (i < right.0[C.COUNT]) {
            ArrayMut.insert(left.2, left.0[C.COUNT] + i - 1 : Nat, median_key, left.0[C.COUNT] - 1 : Nat);
            median_key := right.2[i];

            let ?child = right.3[i] else Debug.trap("2. merge_branch_nodes: accessed a null value");
            Branch.insert(left, left.0[C.COUNT] + i, child);

            Common.update_branch_fields(left, cmp_key, cmp_val, left.0[C.COUNT] + i, child);
            i += 1;
        };

        left.0[C.COUNT] += right.0[C.COUNT];
        left.0[C.SUBTREE_SIZE] += right_subtree_size;

        // update the parent fields with the updated left node
        if (parent.0[C.MAX_INDEX] == right.0[C.INDEX]) {
            parent.0[C.MAX_INDEX] := left.0[C.INDEX];
        };


        // update parent keys
        ignore ArrayMut.remove(parent.2, right.0[C.INDEX] - 1 : Nat, parent.0[C.COUNT] - 1 : Nat);
        ignore Branch.remove(parent, right.0[C.INDEX], parent.0[C.COUNT], cmp_key, cmp_val);
        parent.0[C.COUNT] -= 1;

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
