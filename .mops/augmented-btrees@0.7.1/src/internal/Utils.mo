import Array "mo:base/Array";
import Debug "mo:base/Debug";
import Order "mo:base/Order";
import T "Types";

module {
    type Order = Order.Order;

    public func tabulate_var<T>(capacity : Nat, size: Nat, fn : (Nat) -> ?T) : [var ?T] {
        assert size <= capacity;
        var arr = Array.init<?T>(capacity, null);

        var i = 0;

        while (i < size) {
            arr[i] := fn(i);
            i += 1;
        };

        arr;
    };

    public func unwrap<T>(optional: ?T, trap_msg: Text) : T {
        switch(optional) {
            case (?v) return v;
            case (_) return Debug.trap(trap_msg);
        };
    };

    public func validate_array_equal_count<T>(arr : [var ?T], count : Nat) : Bool {
        var i = 0;

        for (opt_elem in arr.vals()) {
            let ?elem = opt_elem else return i == count;
            i += 1;
        };

        i == count;
    };

    public func validate_indexes<K, V>(arr : [var ?{#leaf:{var index : Nat};#branch:{var index : Nat};}], count : Nat) : Bool {

        var i = 0;

        while (i < count) {
            switch (arr[i]) {
                case (? #branch(node) or ? #leaf(node)) {
                    if (node.index != i) return false;
                };
                case (_) Debug.trap("validate_indexes: accessed a null value");
            };
            i += 1;
        };

        true;
    };

    public func is_sorted<T>(arr: [var ?T], cmp: T.CmpFn<T>): Bool {
        var i = 0;

        while (i < ((arr.size() - 1) : Nat)) {
            let ?a = arr[i] else return true;
            let ?b = arr[i + 1] else return true;

            if (cmp(a, b) == +1) return false;
            i += 1;
        };

        true;
    };

    public func adapt_cmp<K, V>(cmp : T.CmpFn<K>) : T.MultiCmpFn<K, (K, V)> {
        func(a : K, b : (K, V)) : Int8 {
            cmp(a, b.0);
        };
    };

    public func tuple_cmp_key<K>(cmp: T.CmpFn<K>) : ((K, Any), (K, Any)) -> Int8 {
        func ((a, _) : (K, Any), (b, _) : (K, Any)): Int8 {
            cmp(a, b)
        };
    };

    public func tuple_cmp_val<V>(cmp: T.CmpFn<V>) : ((Any, V), (Any, V)) -> Int8 {
        func ((_, a) : (Any, V), (_, b) : (Any, V)): Int8 {
            cmp(a, b)
        };
    };

    public func tuple_cmp<K, V>( cmp_key: T.CmpFn<K>, cmp_val: T.CmpFn<V>) : ((K, V), (K, V)) -> Int8 {
        func ((a_key, a_val) : (K, V), (b_key, b_val) : (K, V)): Int8 {
            let val_result = cmp_val(a_val, b_val);
            if (val_result == 0) return cmp_key(a_key, b_key);
            val_result;
        };
    };

    public func tuple_order_cmp_key<K>(cmp: (K, K) -> Order) : ((K, Any), (K, Any)) -> Order {
        func ((a, _) : (K, Any), (b, _) : (K, Any)): Order {
            cmp(a, b)
        };
    };

    public func tuple_order_cmp_val<V>(cmp: (V, V) -> Order) : ((Any, V), (Any, V)) -> Order {
        func ((_, a) : (Any, V), (_, b) : (Any, V)): Order {
            cmp(a, b)
        };
    };

    public func tuple_order_cmp<K, V>(cmp_key: (K, K) -> Order, cmp_val: (V, V) -> Order) : ((K, V), (K, V)) -> Order {
        func ((a_key, a_val) : (K, V), (b_key, b_val) : (K, V)): Order {
            let val_result = cmp_val(a_val, b_val);
            if (val_result == #equal) return cmp_key(a_key, b_key);
            val_result;
        };
    };


}