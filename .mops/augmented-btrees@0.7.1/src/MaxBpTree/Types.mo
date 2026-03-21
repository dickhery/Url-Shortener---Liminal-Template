import Order "mo:base/Order";
import InternalTypes "../internal/Types";
import MaxHeap "../internal/MaxHeap";

module {
    type Order = Order.Order;

    public type CmpFn<A> = (A, A) -> Int8;
    public type MultiCmpFn<A, B> = (A, B) -> Int8;
    public type LeafEntry<K, V> = (Leaf<K, V>, Nat, (K, V));
    public type MaxHeap<A> = MaxHeap.MaxHeap<A>;

    public type MaxBpTree<K, V> = {
        order : Nat;
        var root : Node<K, V>;
        var size : Nat;
        var next_id : Nat;
    };

    public type Node<K, V> = {
        #leaf : Leaf<K, V>;
        #branch : Branch<K, V>;
    };

    /// Branch nodes store keys and pointers to child nodes.
    public type Branch<K, V> = (
        nats: [var Nat], // [id, index, count, subtree_size, max_index]
        parent: [var ?Branch<K, V>], // parent
        keys: [var ?K], // [...keys]
        children: [var ?Node<K, V>], // [...child nodes]
        max: [var ?(K, V)], // (max_key, max_val)
        // max_heap: MaxHeap<(K, V)>
    );

    /// Leaf nodes are doubly linked lists of key-value pairs.
    public type Leaf<K, V> = (
        nats: [var Nat], // [id, index, count, ----,  max_index]
        parent: [var ?Branch<K, V>], // parent
        adjacent_nodes: [var ?Leaf<K, V>], // [prev, next]
        kvs: [var ?(K, V)], // [...key-value pairs]
        max: [var ?(K, V)],// (max_key, max_val)
        // max_heap: MaxHeap<(K, V)>
    );

    public module Const = {
        public let ID = 0;
        public let INDEX = 1;
        public let COUNT = 2;
        public let SUBTREE_SIZE = 3;
        public let MAX_INDEX = 4;

        public let PARENT = 0;

        public let PREV = 0;
        public let NEXT = 1;

        public let MAX = 0;
    };

    public type CommonFields<K, V> = Leaf<K, V> or Branch<K, V>;

    public type CommonNodeFields<K, V> = {
        #leaf : CommonFields<K, V>;
        #branch : CommonFields<K, V>;
    };

    public type UpdateLeafMaxFn<K, V> = (CommonFields<K, V>, Nat, K, V) -> ();
    public type UpdateBranchMaxFn<K, V> = (Branch<K, V>, Nat, Node<K, V>) -> ();

    public type ResetMaxFn<K, V> = (CommonFields<K, V>) -> ();


};
