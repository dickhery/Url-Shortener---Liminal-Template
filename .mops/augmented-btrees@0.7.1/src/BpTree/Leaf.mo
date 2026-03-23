import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";
import Option "mo:base/Option";
import Nat "mo:base/Nat";
import Order "mo:base/Order";

import T "Types";
import InternalTypes "../internal/Types";
import ArrayMut "../internal/ArrayMut";

import Utils "../internal/Utils";

module Leaf {
    type Order = Order.Order;
    public type Leaf<K, V> = T.Leaf<K, V>;
    type Node<K, V> = T.Node<K, V>;
    type BpTree<K, V> = T.BpTree<K, V>;
    type CmpFn<K> = InternalTypes.CmpFn<K>;
    type CommonNodeFields<K, V> = T.CommonNodeFields<K, V>;
    
    let { Const = C } = T;

    public func new<K, V>(order : Nat, count : Nat, opt_kvs : ?[var ?(K, V)], gen_id : () -> Nat) : Leaf<K, V> {
        let kvs : [var ?(K, V)] = switch (opt_kvs){
            case (?kvs) kvs;
            case (_) Array.init(order, null);
        };

        let leaf_node : Leaf<K, V> = (
            Array.init<Nat>(3, 0),
            Array.init(1, null),
            Array.init(2, null),
            kvs,
        );

        leaf_node.0[C.ID] := gen_id();
        leaf_node.0[C.COUNT] := count;

        leaf_node;
    };

    public func split<K, V>(leaf : Leaf<K, V>, elem_index : Nat, elem : (K, V), gen_id : () -> Nat) : Leaf<K, V> {
        let arr_len = leaf.0[C.COUNT];
        let median = (arr_len / 2) + 1;

        let is_elem_added_to_right = elem_index >= median;

        // if elem is added to the left
        // this variable allows us to retrieve the last element on the left
        // that gets shifted by the inserted elemeent
        var offset = if (is_elem_added_to_right) 0 else 1;

        let right_cnt = arr_len + 1 - median : Nat;
        let right_node = Leaf.new<K, V>(leaf.3.size(), 0, null, gen_id);

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

            i += 1;
        };

        right_node.0[C.COUNT] := right_cnt;


        var j = median - 1 : Nat;

        while (j > elem_index) {
            leaf.3[j] := leaf.3[j - 1];
            j -= 1;
        };

        if (j == elem_index) {
            leaf.3[j] := ?elem;
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

    public func redistribute_keys<K, V>(leaf_node : Leaf<K, V>) {
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

        // distribute data between adjacent nodes
        if (adj_node.0[C.INDEX] < leaf_node.0[C.INDEX]) {
            // adj_node is before leaf_node

            var i = 0;
            ArrayMut.shift_by(leaf_node.3, 0, leaf_node.0[C.COUNT], data_to_move);
            while (i < data_to_move) {
                let opt_kv = ArrayMut.remove(adj_node.3, adj_node.0[C.COUNT] - i - 1 : Nat, adj_node.0[C.COUNT]);

                // no need to call update_fields as we are the adjacent node is before the leaf node 
                // which means that all its keys are less than the leaf node's keys
                leaf_node.3[data_to_move - i - 1] := opt_kv;
                
                i += 1;
            };
        } else {
            // adj_node is after leaf_node

            var i = 0;
            while (i < data_to_move ) {
                let opt_kv = adj_node.3[i];
                ArrayMut.insert(leaf_node.3, leaf_node.0[C.COUNT] + i, opt_kv, leaf_node.0[C.COUNT]);

                i += 1;
            };

            ArrayMut.shift_by(adj_node.3, i, adj_node.0[C.COUNT], -i);
        };

        adj_node.0[C.COUNT] -= data_to_move;
        leaf_node.0[C.COUNT] += data_to_move;

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
    };

    // merges two leaf nodes into the left node
    public func merge<K, V>(left : Leaf<K, V>, right : Leaf<K, V>) {
        var i = 0;

        // merge right into left
        while (i < right.0[C.COUNT]) {
            let opt_kv = right.3[i];
            ArrayMut.insert(left.3, left.0[C.COUNT] + i, opt_kv, left.0[C.COUNT]);

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

                i += 1;
            };

            parent.3[parent.0[C.COUNT] - 1] := null;

            parent.0[C.COUNT] -= 1;
        }
    };

    public func remove<K, V>(leaf : Leaf<K, V>, index : Nat) : ?(K, V) {
        let removed = ArrayMut.remove(leaf.3, index, leaf.0[C.COUNT]);

        // leaf.0[C.COUNT] -= 1;
        removed;
    };

    public func equal<K, V>(a : Leaf<K, V>, b : Leaf<K, V>, cmp : CmpFn<K>) : Bool {
        for (i in Iter.range(0, a.3.size() - 1)) {
            let res = switch (a.3[i], b.3[i]) {
                case (?v1, ?v2) {
                    cmp(v1.0, v2.0) == 0;
                };
                case (_) false;
            };

            if (not res) return false;
        };

        true;
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
