import Order "mo:base/Order";
import InternalTypes "../internal/Types";

module {
    type Order = Order.Order;

    public type CmpFn<K> = InternalTypes.CmpFn<K>;

    public type BpTree<K, V> = {
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
    /// The data in each node is grouped together into mutable arrays of similar types stored in a tuple instead of a record.
    /// This is done to reduce the heap allocations and improve cache locality.
    ///
    /// #### Fields
    /// - `nats`: [id, index, count, subtree_size]
    ///     - `id`: Unique id representing the branch as a node.
    ///     - `index`: The index of this branch node in the parent branch node.
    ///     - `count`: The number of child nodes in this branch node.
    ///     - `subtree_size`: The total number of nodes in the subtree rooted at this branch node.
    /// - `parent`: The parent branch node.
    /// - `keys`: The keys in this branch node.
    /// - `children`: The child nodes in this branch node.

    public type Branch<K, V> = (
        nats : [var Nat], // [id, index, count, subtree_size]
        parent : [var ?Branch<K, V>], // parent
        keys : [var ?K], // [...keys]
        children : [var ?Node<K, V>], // [...children]
    );

    /// Leaf nodes are doubly linked lists of key-value pairs.
    ///
    /// #### Fields
    /// - `nats`: [id, index, count]
    ///     - `id`: Unique id representing the leaf as a node.
    ///     - `index`: The index of this leaf node in the parent branch node.
    ///     - `count`: The number of key-value pairs in this leaf node.
    /// - `parent`: The parent branch node.
    /// - `adjacent_nodes`: [prev, next]
    ///     - `prev`: The previous leaf node in the linked list.
    ///     - `next`: The next leaf node in the linked list.
    /// - `kvs`: The key-value pairs in this leaf node.

    public type Leaf<K, V> = (
        nats : [var Nat], // [id, index, count]
        parent : [var ?Branch<K, V>], // parent
        adjacent_nodes : [var ?Leaf<K, V>], // [prev, next]
        kvs : [var ?(K, V)], // [...kvs]
    );

    public module Const = {
        public let ID = 0;
        public let INDEX = 1;
        public let COUNT = 2;
        public let SUBTREE_SIZE = 3;

        public let PARENT = 0;

        public let PREV = 0;
        public let NEXT = 1;

    };

    public type CommonFields<K, V> = Leaf<K, V> or Branch<K, V>;

    public type CommonNodeFields<K, V> = {
        #leaf : CommonFields<K, V>;
        #branch : CommonFields<K, V>;
    };

    public type ExpectedIndex = {
        #NotFound : Nat;
        #Found : Nat;
    }

};
