import Array "mo:base/Array";
import Option "mo:base/Option";
import Debug "mo:base/Debug";

import BpTreeLeaf "../BpTree/Leaf";
import T "Types";
import BpTree "../BpTree";

import Utils "../internal/Utils";
import InternalTypes "../internal/Types";
module Methods {
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

    let {Const = C } = T;

    public func update_leaf_fields<K, V>(leaf : CommonFields<K, V>, cmp_key : CmpFn<K>, cmp_val : CmpFn<V>, index : Nat, key : K, val : V) {
        switch(leaf.4[C.MAX]){
            case (null){
                leaf.4[C.MAX] := ?(key, val);
                leaf.0[C.MAX_INDEX] := index;
            };
            case (?max){
                if (cmp_val(val, max.1) == +1) {
                    leaf.4[C.MAX] := ?(key, val);
                    leaf.0[C.MAX_INDEX] := index;
                } else if (cmp_val(val, max.1) == 0) {
                    if (cmp_key(key, max.0) == -1) {
                        leaf.4[C.MAX] := ?(key, val);
                        leaf.0[C.MAX_INDEX] := index;
                    }
                };
            }
        };
    };

    public func update_leaf_with_kv_pair<K, V>(leaf : CommonFields<K, V>, cmp_key : CmpFn<K>,cmp_val : CmpFn<V>, index : Nat, kv: (K, V)) {
        switch(leaf.4[C.MAX]){
            case (null){
                leaf.4[C.MAX] := ?kv;
                leaf.0[C.MAX_INDEX] := index;
            };
            case (?max){
                if (cmp_val(kv.1, max.1) == +1) {
                    leaf.4[C.MAX] := ?kv;
                    leaf.0[C.MAX_INDEX] := index;
                } else if (cmp_val(kv.1, max.1) == 0) {
                    if (cmp_key(kv.0, max.0) == -1) {
                        leaf.4[C.MAX] := ?kv;
                        leaf.0[C.MAX_INDEX] := index;
                    };
                };
            }
        };
    };

    public func update_branch_fields<K, V>(branch : Branch<K, V>, cmp_key : CmpFn<K>, cmp_val : CmpFn<V>, index : Nat, child_node : Node<K, V>) {
        switch (child_node) {
            case (#leaf(child) or #branch(child) : CommonNodeFields<K, V>) {
                switch(child.4[C.MAX], branch.4[C.MAX]) {
                    case (null, _) Debug.trap("update_branch_fields: child max is null");
                    case (child_max, null) {
                        branch.4[C.MAX] := child_max;
                        branch.0[C.MAX_INDEX] := index;
                    };
                    case (?child_max, ?curr_max) {
                        if (cmp_val(child_max.1, curr_max.1) == +1) {
                            branch.4[C.MAX] := ?child_max;
                            branch.0[C.MAX_INDEX] := index;
                        } else if (cmp_val(child_max.1, curr_max.1) == 0) {
                            if (cmp_key(child_max.0, curr_max.0) == -1) {
                                branch.4[C.MAX] := ?child_max;
                                branch.0[C.MAX_INDEX] := index;
                            };
                        };
                    };
                };
            };
        };
    };
};
