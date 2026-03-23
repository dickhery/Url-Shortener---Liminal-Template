import Array "mo:base/Array";
import Debug "mo:base/Debug";
import Iter "mo:base/Iter";
import Option "mo:base/Option";
import Int "mo:base/Int";

import BpTreeLeaf "../BpTree/Leaf";
import T "Types";
import BpTree "../BpTree";
import ArrayMut "../internal/ArrayMut";

import Utils "../internal/Utils";
import InternalTypes "../internal/Types";
import Common "Common";

module Leaf {
    type Iter<A> = Iter.Iter<A>;

    public type MaxBpTree<K, V> = T.MaxBpTree<K, V>;
    public type Node<K, V> = T.Node<K, V>;
    public type Leaf<K, V> = T.Leaf<K, V>;
    public type Branch<K, V> = T.Branch<K, V>;
    type CommonFields<K, V> = T.CommonFields<K, V>;
    type CommonNodeFields<K, V> = T.CommonNodeFields<K, V>;
    type CmpFn<A> = T.CmpFn<A>;
    type MultiCmpFn<A, B> = T.MultiCmpFn<A, B>;
    type UpdateLeafMaxFn<K, V> = T.UpdateLeafMaxFn<K, V>;
    type UpdateBranchMaxFn<K, V> = T.UpdateBranchMaxFn<K, V>;
    type ResetMaxFn<K, V> = T.ResetMaxFn<K, V>;

    let { Const =  C} = T;
    
    public func new<K, V>(order : Nat, count : Nat, opt_kvs : ?[var ?(K, V)], gen_id : () -> Nat, cmp_val : CmpFn<V>) : Leaf<K, V> {

        let leaf_node : Leaf<K, V> = (
            Array.init<Nat>(5, 0),
            Array.init<?Branch<K, V>>(1, null),
            Array.init(2, null),
            switch (opt_kvs) {
                case (?kvs) kvs;
                case (_) Array.init<?(K, V)>(order, null);
            },
            Array.init(1, null),
        );

        leaf_node.0[C.ID] := gen_id();
        leaf_node.0[C.COUNT] := count;

        leaf_node;
    };

    public func insert<K, V>(
        leaf: Leaf<K, V>,
        cmp_key: CmpFn<K>,
        cmp_val: CmpFn<V>,
        index: Nat,
        kv: (K, V),
    ){
        var i = leaf.0[C.COUNT];

        if (leaf.0[C.COUNT] > 0 and leaf.0[C.MAX_INDEX] >= index){
            leaf.0[C.MAX_INDEX] += 1;
        };

        label while_loop while (i > index) {
            leaf.3[i] := leaf.3[i - 1];
            i -= 1;
        };

        Common.update_leaf_with_kv_pair(leaf, cmp_key, cmp_val, index, kv);

        leaf.3[i] := ?kv;
        leaf.0[C.COUNT] += 1;
    };

    public func split<K, V>(
        leaf : Leaf<K, V>,
        elem_index : Nat,
        elem : (K, V),
        gen_id : () -> Nat,
        cmp_key : CmpFn<K>,
        cmp_val : CmpFn<V>,
    ) : Leaf<K, V> {

        let arr_len = leaf.0[C.COUNT];
        let median = (arr_len / 2) + 1;

        let is_elem_added_to_right = elem_index >= median;

        // if elem is added to the left
        // this variable allows us to retrieve the last element on the left
        // that gets shifted by the inserted elemeent
        let initial_offset = if (is_elem_added_to_right) 0 else 1;
        var offset = initial_offset;
        let right_cnt = arr_len + 1 - median : Nat;
        let right_node = Leaf.new<K, V>(leaf.3.size(), 0, null, gen_id, cmp_val);

        var already_inserted = false;

        var i = 0;
        while (i < right_cnt) {
            let j = i + median - offset : Nat;

            let ?kv = if (j >= median and j == elem_index and not already_inserted) {
                offset += 1;
                already_inserted := true;
                ?elem;
            } else {
                ArrayMut.extract(leaf.3, j);
            } else Debug.trap("Leaf.split: kv is null");

            right_node.3[i] := ?kv;
            Common.update_leaf_with_kv_pair(right_node, cmp_key, cmp_val, i, kv);

            i += 1;
        };

        right_node.0[C.COUNT] := right_cnt;

        let moved_left_max : Bool = if (leaf.0[C.MAX_INDEX] >= (arr_len - right_cnt - initial_offset : Nat)){
            leaf.4[C.MAX] := null;
            true
        } else if (leaf.0[C.MAX_INDEX] >= elem_index ) {
            leaf.0[C.MAX_INDEX] := leaf.0[C.MAX_INDEX] + 1;
            false;
        } else false;
        
        var j = median - 1 : Nat;

        label while_loop while (moved_left_max or j >= elem_index) {
            if (j > elem_index) {
                leaf.3[j] := leaf.3[j - 1];
            } else if (j == elem_index) {
                leaf.3[j] := ?elem;
            };

            if (moved_left_max) {
                let ?kv = leaf.3[j] else Debug.trap("Leaf.split: kv is null");
                Common.update_leaf_with_kv_pair(leaf, cmp_key, cmp_val, j, kv);
            }else if (j == elem_index) {
                Common.update_leaf_with_kv_pair(leaf, cmp_key, cmp_val, j, elem);
            };

            if (j == 0) break while_loop else j -= 1;
        };

        //update parent max to left node because the right node is a new node
        switch (leaf.1[C.PARENT]) {
            case (?parent) {
                let ?leaf_max = leaf.4[C.MAX] else Debug.trap("Leaf.split: max is null");
                let ?parent_max = parent.4[C.MAX] else Debug.trap("Leaf.split: max is null");
                if (parent.0[C.MAX_INDEX] == leaf.0[C.INDEX] or cmp_val(leaf_max.1, parent_max.1) == +1){
                    parent.4[C.MAX] := leaf.4[C.MAX];
                    parent.0[C.MAX_INDEX] := leaf.0[C.INDEX];
                };
            };
            case (_) {};
        };

        leaf.0[C.COUNT] := median;

        right_node.0[C.INDEX] := leaf.0[C.INDEX] + 1;
        right_node.1[C.PARENT] := leaf.1[C.PARENT];

        // update leaf pointers
        right_node.2[C.NEXT] := leaf.2[C.NEXT];
        leaf.2[C.NEXT] := ?right_node;

        right_node.2[C.PREV] := ?leaf;

        switch (right_node.2[C.NEXT]) {
            case (?next) next.2[C.PREV] := ?right_node;
            case (_) {};
        };

        right_node;
    };

    public func shift_by<K, V>(
        leaf : Leaf<K, V>,
        start : Nat,
        end : Nat,
        offset : Int,
    ) {
        ArrayMut.shift_by(leaf.3, start, end, offset);
        
        leaf.0[C.MAX_INDEX] := Int.abs(leaf.0[C.MAX_INDEX] + offset);
    };

    public func put<K, V>(leaf : Leaf<K, V>, index : Nat, kv : (K, V)) {
        leaf.3[index] := ?kv;
    };

    public func remove_and_calc_max<K, V>(
        leaf : Leaf<K, V>,
        index : Nat,
        count : Nat,
        cmp_key : CmpFn<K>,
        cmp_val : CmpFn<V>,
    ) : ?(K, V) {
        let removed = leaf.3[index];
        
        var i = 0;

        let is_max_removed = leaf.0[C.MAX_INDEX] == index;
        if (is_max_removed) {
            leaf.4[C.MAX] := null;

            while ( i < index){
                let ?kv = leaf.3[i] else Debug.trap("Leaf.remove: accessed a null value");
                Common.update_leaf_with_kv_pair(leaf, cmp_key, cmp_val, i, kv);
                i += 1;
            };
        } else if (leaf.0[C.MAX_INDEX] > index) {
            leaf.0[C.MAX_INDEX] -= 1;
        };

        // assert i == index;

        while (i < (count - 1 : Nat)) {
            leaf.3[i] := leaf.3[i + 1];

            let ?kv = leaf.3[i] else Debug.trap("Leaf.remove: accessed a null value");

            if (is_max_removed){
                // update with the prev index as it will be updated after the loop
                Common.update_leaf_with_kv_pair(leaf, cmp_key, cmp_val, i, kv);
            };

            i += 1;
        };

        leaf.3[count - 1] := null;

        // self.0[C.COUNT] -=1;

        removed;
    };

    public func redistribute_keys<K, V>(
        leaf_node : Leaf<K, V>,
        cmp_key : CmpFn<K>,
        cmp_val : CmpFn<V>,
    ) {

        let ?parent = leaf_node.1[C.PARENT] else return;

        var adj_node = leaf_node;
        if (parent.0[C.COUNT] > 1) {
            if (leaf_node.0[C.INDEX] != 0) {
                let ? #leaf(left_adj_node) = parent.3[leaf_node.0[C.INDEX] - 1] else Debug.trap("1. redistribute_leaf_keys: accessed a null value");
                adj_node := left_adj_node;
            };

            if (leaf_node.0[C.INDEX] != (parent.0[C.COUNT] - 1 : Nat)) {
                let ? #leaf(right_adj_node) = parent.3[leaf_node.0[C.INDEX] + 1] else Debug.trap("2. redistribute_leaf_keys: accessed a null value");
                if (right_adj_node.0[C.COUNT] > adj_node.0[C.COUNT]) {
                    adj_node := right_adj_node;
                };
            };
        };

        if (adj_node.0[C.INDEX] == leaf_node.0[C.INDEX]) return; // no adjacent node to distribute data to

        let sum_count = leaf_node.0[C.COUNT] + adj_node.0[C.COUNT];
        let min_count_for_both_nodes = leaf_node.3.size();

        if (sum_count < min_count_for_both_nodes) return; // not enough entries to distribute

        let data_to_move = (sum_count / 2) - leaf_node.0[C.COUNT] : Nat;

        let is_adj_node_equal_to_parent_max = parent.0[C.MAX_INDEX] == adj_node.0[C.INDEX];
        
        // switch (parent.4[C.MAX], adj_node.4[C.MAX]) {
        //     case (?parent_max, ?adj_max) cmp_key(parent_max.0, adj_max.0) == 0;
        //     case (_, _) false;
        // };

        // distribute data between adjacent nodes
        if (adj_node.0[C.INDEX] < leaf_node.0[C.INDEX]) {
            // adj_node is before leaf_node

            var i = 0;
            Leaf.shift_by(leaf_node, 0, leaf_node.0[C.COUNT], data_to_move);
            while (i < data_to_move) {
                let opt_kv = ArrayMut.remove(adj_node.3, adj_node.0[C.COUNT] - i - 1 : Nat, adj_node.0[C.COUNT]);
                let ?kv = opt_kv else Debug.trap("Leaf.redistribute_keys: kv is null");

                // no need to call update_fields as the adjacent node is before the leaf node
                // which means that all its keys are less than the leaf node's keys
                leaf_node.3[data_to_move - i - 1] := opt_kv;

                // update max if a greater value was inserted
                let ?leaf_max = leaf_node.4[C.MAX] else Debug.trap("Leaf.redistribute_keys: max is null");
                if (cmp_val(kv.1, leaf_max.1) == +1) {
                    leaf_node.4[C.MAX] := ?(kv.0, kv.1);
                    leaf_node.0[C.MAX_INDEX] := data_to_move - i - 1;
                };

                // remove max from adj_node if it was moved

                if (adj_node.0[C.MAX_INDEX] == (adj_node.0[C.COUNT] - i - 1 : Nat)){
                    adj_node.4[C.MAX] := null;
                };
                
                // switch(adj_node.4[C.MAX]){
                //     case (?adj_max) if (cmp_key(kv.0, adj_max.0) == 0) ;
                //     case (_) {};
                // };

                i += 1;
            };
        } else {
            // adj_node is after leaf_node

            var i = 0;
            while (i < data_to_move) {
                let opt_kv = adj_node.3[i];
                ArrayMut.insert(leaf_node.3, leaf_node.0[C.COUNT] + i, opt_kv, leaf_node.0[C.COUNT]);

                let ?kv = opt_kv else Debug.trap("Leaf.redistribute_keys: kv is null");

                // update max if a greater value was inserted
                let ?leaf_max = leaf_node.4[C.MAX] else Debug.trap("Leaf.redistribute_keys: max is null");
                if (cmp_val(kv.1, leaf_max.1) == +1) {
                    leaf_node.4[C.MAX] := ?(kv.0, kv.1);
                    leaf_node.0[C.MAX_INDEX] := leaf_node.0[C.COUNT] + i;
                };

                // remove max from adj_node if it was moved
                if (adj_node.0[C.MAX_INDEX] == i){
                    adj_node.4[C.MAX] := null;
                };

                // switch(adj_node.4[C.MAX]){
                //     case (?adj_max) if (cmp_key(kv.0, adj_max.0) == 0) adj_node.4[C.MAX] := null;
                //     case (_) {};
                // };

                i += 1;
            };

            Leaf.shift_by(adj_node, i, adj_node.0[C.COUNT], -i);
        };

        adj_node.0[C.COUNT] -= data_to_move;
        leaf_node.0[C.COUNT] += data_to_move;

        if (Option.isNull(adj_node.4[C.MAX])) {
            var i = 0;

            while (i < adj_node.0[C.COUNT]) {
                let ?kv = adj_node.3[i] else Debug.trap("Leaf.redistribute_keys: kv is null");
                Common.update_leaf_with_kv_pair(adj_node, cmp_key, cmp_val, i, kv);
                i += 1;
            };

        };

        // update parent keys
        if (adj_node.0[C.INDEX] < leaf_node.0[C.INDEX]) {
            // no need to worry about leaf_node.0[C.INDEX] - 1 being out of bounds because
            // the adj_node is before the leaf_node, meaning the leaf_node is not the first child
            let ?leaf_2nd_entry = leaf_node.3[0] else Debug.trap("3. redistribute_leaf_keys: accessed a null value");
            let leaf_node_key = leaf_2nd_entry.0;

            let key_index = leaf_node.0[C.INDEX] - 1 : Nat;
            parent.2[key_index] := ?leaf_node_key;
        } else {
            // and vice versa
            let ?adj_2nd_entry = adj_node.3[0] else Debug.trap("4. redistribute_leaf_keys: accessed a null value");
            let adj_node_key = adj_2nd_entry.0;

            let key_index = adj_node.0[C.INDEX] - 1 : Nat;
            parent.2[key_index] := ?adj_node_key;
        };

        // update parent max
        if (is_adj_node_equal_to_parent_max) {
            switch(parent.4[C.MAX], adj_node.4[C.MAX]){
                case (?parent_max, ?adj_max) {
                    if (cmp_val(parent_max.1, adj_max.1) != 0) {
                        parent.4[C.MAX] := ?(parent_max.0, parent_max.1);
                        parent.0[C.MAX_INDEX] := leaf_node.0[C.INDEX];
                    };
                };
                case (_, _) {};
            };
        };

    };

    // merges two leaf nodes into the left node
    public func merge<K, V>(
        left : Leaf<K, V>,
        right : Leaf<K, V>,
        cmp_key : CmpFn<K>,
        cmp_val : CmpFn<V>,
    ) {
        var i = 0;
        var is_updated = false;

        // merge right into left
        while (i < right.0[C.COUNT]) {
            let opt_kv = right.3[i];
            ArrayMut.insert(left.3, left.0[C.COUNT] + i, opt_kv, left.0[C.COUNT]);

            let ?kv = opt_kv else Debug.trap("Leaf.merge: kv is null");
            Common.update_leaf_with_kv_pair(left, cmp_key, cmp_val, left.0[C.COUNT] + i, kv);

            i += 1;
        };

        left.0[C.COUNT] += right.0[C.COUNT];

        // update leaf pointers
        left.2[C.NEXT] := right.2[C.NEXT];
        switch (left.2[C.NEXT]) {
            case (?next) next.2[C.PREV] := ?left;
            case (_) {};
        };

        let ?parent = left.1[C.PARENT] else Debug.trap("Leaf.merge: parent is null");

        // if the max value was in the right node,
        // after the merge fn it will be in the left node
        // so we need to update the parent key with the new max value in the left node
        if (parent.0[C.MAX_INDEX] == right.0[C.INDEX]) {
            parent.0[C.MAX_INDEX] := left.0[C.INDEX];
        };

        // update parent keys
        ignore ArrayMut.remove(parent.2, right.0[C.INDEX] - 1 : Nat, parent.0[C.COUNT] - 1 : Nat);

        // remove right from parent
        do {
            var i = right.0[C.INDEX];
            while (i < (parent.0[C.COUNT] - 1 : Nat)) {
                parent.3[i] := parent.3[i + 1];

                let ?child = parent.3[i] else Debug.trap("Leaf.merge: accessed a null value");

                switch (child) {
                    case (#leaf(node) or #branch(node) : CommonNodeFields<K, V>) {
                        node.0[C.INDEX] := i;
                    };
                };

                // update max with prev index
                Common.update_branch_fields(parent, cmp_key, cmp_val, i + 1, child);

                i += 1;
            };

            parent.3[parent.0[C.COUNT] - 1] := null;
            parent.0[C.COUNT] -= 1;

            // update the max field index
            if (parent.0[C.MAX_INDEX] > right.0[C.INDEX]) {
                parent.0[C.MAX_INDEX] -= 1;
            };
        };
    };

    public func toText<K, V>(self : Leaf<K, V>, key_to_text : (K) -> Text, val_to_text : (V) -> Text) : Text {
        var t = "leaf { index: " # debug_show self.0[C.INDEX] # ", count: " # debug_show self.0[C.COUNT] # ", kvs: ";

        t #= debug_show Array.map(
            Array.freeze(self.3),
            func(opt_kv : ?(K, V)) : Text {
                switch (opt_kv) {
                    case (?kv) "(" # key_to_text(kv.0) # ", " # val_to_text(kv.1) # ")";
                    case (_) "null";
                };
            },
        );

        t #= " }";

        t;
    };
};
